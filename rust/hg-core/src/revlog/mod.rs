// Copyright 2018-2023 Georges Racinet <georges.racinet@octobus.net>
//           and Mercurial contributors
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.
//! Mercurial concepts for handling revision history

pub mod node;
pub mod nodemap;
mod nodemap_docket;
pub mod path_encode;
pub use node::{FromHexError, Node, NodePrefix};
pub mod changelog;
pub mod filelog;
pub mod index;
pub mod manifest;
pub mod patch;

use std::borrow::Cow;
use std::io::Read;
use std::ops::Deref;
use std::path::Path;

use flate2::read::ZlibDecoder;
use sha1::{Digest, Sha1};
use std::cell::RefCell;
use zstd;

use self::node::{NODE_BYTES_LENGTH, NULL_NODE};
use self::nodemap_docket::NodeMapDocket;
use super::index::Index;
use super::index::INDEX_ENTRY_SIZE;
use super::nodemap::{NodeMap, NodeMapError};
use crate::errors::HgError;
use crate::vfs::Vfs;

/// As noted in revlog.c, revision numbers are actually encoded in
/// 4 bytes, and are liberally converted to ints, whence the i32
pub type BaseRevision = i32;

/// Mercurial revision numbers
/// In contrast to the more general [`UncheckedRevision`], these are "checked"
/// in the sense that they should only be used for revisions that are
/// valid for a given index (i.e. in bounds).
#[derive(
    Debug,
    derive_more::Display,
    Clone,
    Copy,
    Hash,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
)]
pub struct Revision(pub BaseRevision);

impl format_bytes::DisplayBytes for Revision {
    fn display_bytes(
        &self,
        output: &mut dyn std::io::Write,
    ) -> std::io::Result<()> {
        self.0.display_bytes(output)
    }
}

/// Unchecked Mercurial revision numbers.
///
/// Values of this type have no guarantee of being a valid revision number
/// in any context. Use method `check_revision` to get a valid revision within
/// the appropriate index object.
#[derive(
    Debug,
    derive_more::Display,
    Clone,
    Copy,
    Hash,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
)]
pub struct UncheckedRevision(pub BaseRevision);

impl format_bytes::DisplayBytes for UncheckedRevision {
    fn display_bytes(
        &self,
        output: &mut dyn std::io::Write,
    ) -> std::io::Result<()> {
        self.0.display_bytes(output)
    }
}

impl From<Revision> for UncheckedRevision {
    fn from(value: Revision) -> Self {
        Self(value.0)
    }
}

impl From<BaseRevision> for UncheckedRevision {
    fn from(value: BaseRevision) -> Self {
        Self(value)
    }
}

/// Marker expressing the absence of a parent
///
/// Independently of the actual representation, `NULL_REVISION` is guaranteed
/// to be smaller than all existing revisions.
pub const NULL_REVISION: Revision = Revision(-1);

/// Same as `mercurial.node.wdirrev`
///
/// This is also equal to `i32::max_value()`, but it's better to spell
/// it out explicitely, same as in `mercurial.node`
#[allow(clippy::unreadable_literal)]
pub const WORKING_DIRECTORY_REVISION: UncheckedRevision =
    UncheckedRevision(0x7fffffff);

pub const WORKING_DIRECTORY_HEX: &str =
    "ffffffffffffffffffffffffffffffffffffffff";

/// The simplest expression of what we need of Mercurial DAGs.
pub trait Graph {
    /// Return the two parents of the given `Revision`.
    ///
    /// Each of the parents can be independently `NULL_REVISION`
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError>;
}

#[derive(Clone, Debug, PartialEq)]
pub enum GraphError {
    ParentOutOfRange(Revision),
}

impl<T: Graph> Graph for &T {
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError> {
        (*self).parents(rev)
    }
}

/// The Mercurial Revlog Index
///
/// This is currently limited to the minimal interface that is needed for
/// the [`nodemap`](nodemap/index.html) module
pub trait RevlogIndex {
    /// Total number of Revisions referenced in this index
    fn len(&self) -> usize;

    fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Return a reference to the Node or `None` for `NULL_REVISION`
    fn node(&self, rev: Revision) -> Option<&Node>;

    /// Return a [`Revision`] if `rev` is a valid revision number for this
    /// index.
    ///
    /// [`NULL_REVISION`] is considered to be valid.
    #[inline(always)]
    fn check_revision(&self, rev: UncheckedRevision) -> Option<Revision> {
        let rev = rev.0;

        if rev == NULL_REVISION.0 || (rev >= 0 && (rev as usize) < self.len())
        {
            Some(Revision(rev))
        } else {
            None
        }
    }
}

const REVISION_FLAG_CENSORED: u16 = 1 << 15;
const REVISION_FLAG_ELLIPSIS: u16 = 1 << 14;
const REVISION_FLAG_EXTSTORED: u16 = 1 << 13;
const REVISION_FLAG_HASCOPIESINFO: u16 = 1 << 12;

// Keep this in sync with REVIDX_KNOWN_FLAGS in
// mercurial/revlogutils/flagutil.py
const REVIDX_KNOWN_FLAGS: u16 = REVISION_FLAG_CENSORED
    | REVISION_FLAG_ELLIPSIS
    | REVISION_FLAG_EXTSTORED
    | REVISION_FLAG_HASCOPIESINFO;

const NULL_REVLOG_ENTRY_FLAGS: u16 = 0;

#[derive(Debug, derive_more::From, derive_more::Display)]
pub enum RevlogError {
    InvalidRevision,
    /// Working directory is not supported
    WDirUnsupported,
    /// Found more than one entry whose ID match the requested prefix
    AmbiguousPrefix,
    #[from]
    Other(HgError),
}

impl From<NodeMapError> for RevlogError {
    fn from(error: NodeMapError) -> Self {
        match error {
            NodeMapError::MultipleResults => RevlogError::AmbiguousPrefix,
            NodeMapError::RevisionNotInIndex(rev) => RevlogError::corrupted(
                format!("nodemap point to revision {} not in index", rev),
            ),
        }
    }
}

fn corrupted<S: AsRef<str>>(context: S) -> HgError {
    HgError::corrupted(format!("corrupted revlog, {}", context.as_ref()))
}

impl RevlogError {
    fn corrupted<S: AsRef<str>>(context: S) -> Self {
        RevlogError::Other(corrupted(context))
    }
}

/// Read only implementation of revlog.
pub struct Revlog {
    /// When index and data are not interleaved: bytes of the revlog index.
    /// When index and data are interleaved: bytes of the revlog index and
    /// data.
    index: Index,
    /// When index and data are not interleaved: bytes of the revlog data
    data_bytes: Option<Box<dyn Deref<Target = [u8]> + Send>>,
    /// When present on disk: the persistent nodemap for this revlog
    nodemap: Option<nodemap::NodeTree>,
}

impl Graph for Revlog {
    fn parents(&self, rev: Revision) -> Result<[Revision; 2], GraphError> {
        self.index.parents(rev)
    }
}

#[derive(Debug, Copy, Clone)]
pub enum RevlogVersionOptions {
    V0,
    V1 { generaldelta: bool },
    V2,
    ChangelogV2 { compute_rank: bool },
}

/// Options to govern how a revlog should be opened, usually from the
/// repository configuration or requirements.
#[derive(Debug, Copy, Clone)]
pub struct RevlogOpenOptions {
    /// The revlog version, along with any option specific to this version
    pub version: RevlogVersionOptions,
    /// Whether the revlog uses a persistent nodemap.
    pub use_nodemap: bool,
    // TODO other non-header/version options,
}

impl RevlogOpenOptions {
    pub fn new() -> Self {
        Self {
            version: RevlogVersionOptions::V1 { generaldelta: true },
            use_nodemap: false,
        }
    }

    fn default_index_header(&self) -> index::IndexHeader {
        index::IndexHeader {
            header_bytes: match self.version {
                RevlogVersionOptions::V0 => [0, 0, 0, 0],
                RevlogVersionOptions::V1 { generaldelta } => {
                    [0, if generaldelta { 3 } else { 1 }, 0, 1]
                }
                RevlogVersionOptions::V2 => 0xDEADu32.to_be_bytes(),
                RevlogVersionOptions::ChangelogV2 { compute_rank: _ } => {
                    0xD34Du32.to_be_bytes()
                }
            },
        }
    }
}

impl Default for RevlogOpenOptions {
    fn default() -> Self {
        Self::new()
    }
}

impl Revlog {
    /// Open a revlog index file.
    ///
    /// It will also open the associated data file if index and data are not
    /// interleaved.
    pub fn open(
        store_vfs: &Vfs,
        index_path: impl AsRef<Path>,
        data_path: Option<&Path>,
        options: RevlogOpenOptions,
    ) -> Result<Self, HgError> {
        Self::open_gen(store_vfs, index_path, data_path, options, None)
    }

    fn open_gen(
        store_vfs: &Vfs,
        index_path: impl AsRef<Path>,
        data_path: Option<&Path>,
        options: RevlogOpenOptions,
        nodemap_for_test: Option<nodemap::NodeTree>,
    ) -> Result<Self, HgError> {
        let index_path = index_path.as_ref();
        let index = {
            match store_vfs.mmap_open_opt(index_path)? {
                None => Index::new(
                    Box::<Vec<_>>::default(),
                    options.default_index_header(),
                ),
                Some(index_mmap) => {
                    let index = Index::new(
                        Box::new(index_mmap),
                        options.default_index_header(),
                    )?;
                    Ok(index)
                }
            }
        }?;

        let default_data_path = index_path.with_extension("d");

        // type annotation required
        // won't recognize Mmap as Deref<Target = [u8]>
        let data_bytes: Option<Box<dyn Deref<Target = [u8]> + Send>> =
            if index.is_inline() {
                None
            } else {
                let data_path = data_path.unwrap_or(&default_data_path);
                let data_mmap = store_vfs.mmap_open(data_path)?;
                Some(Box::new(data_mmap))
            };

        let nodemap = if index.is_inline() || !options.use_nodemap {
            None
        } else {
            NodeMapDocket::read_from_file(store_vfs, index_path)?.map(
                |(docket, data)| {
                    nodemap::NodeTree::load_bytes(
                        Box::new(data),
                        docket.data_length,
                    )
                },
            )
        };

        let nodemap = nodemap_for_test.or(nodemap);

        Ok(Revlog {
            index,
            data_bytes,
            nodemap,
        })
    }

    /// Return number of entries of the `Revlog`.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns `true` if the `Revlog` has zero `entries`.
    pub fn is_empty(&self) -> bool {
        self.index.is_empty()
    }

    /// Returns the node ID for the given revision number, if it exists in this
    /// revlog
    pub fn node_from_rev(&self, rev: UncheckedRevision) -> Option<&Node> {
        if rev == NULL_REVISION.into() {
            return Some(&NULL_NODE);
        }
        let rev = self.index.check_revision(rev)?;
        Some(self.index.get_entry(rev)?.hash())
    }

    /// Return the revision number for the given node ID, if it exists in this
    /// revlog
    pub fn rev_from_node(
        &self,
        node: NodePrefix,
    ) -> Result<Revision, RevlogError> {
        if let Some(nodemap) = &self.nodemap {
            nodemap
                .find_bin(&self.index, node)?
                .ok_or(RevlogError::InvalidRevision)
        } else {
            self.rev_from_node_no_persistent_nodemap(node)
        }
    }

    /// Same as `rev_from_node`, without using a persistent nodemap
    ///
    /// This is used as fallback when a persistent nodemap is not present.
    /// This happens when the persistent-nodemap experimental feature is not
    /// enabled, or for small revlogs.
    fn rev_from_node_no_persistent_nodemap(
        &self,
        node: NodePrefix,
    ) -> Result<Revision, RevlogError> {
        // Linear scan of the revlog
        // TODO: consider building a non-persistent nodemap in memory to
        // optimize these cases.
        let mut found_by_prefix = None;
        for rev in (-1..self.len() as BaseRevision).rev() {
            let rev = Revision(rev as BaseRevision);
            let candidate_node = if rev == Revision(-1) {
                NULL_NODE
            } else {
                let index_entry =
                    self.index.get_entry(rev).ok_or_else(|| {
                        HgError::corrupted(
                            "revlog references a revision not in the index",
                        )
                    })?;
                *index_entry.hash()
            };
            if node == candidate_node {
                return Ok(rev);
            }
            if node.is_prefix_of(&candidate_node) {
                if found_by_prefix.is_some() {
                    return Err(RevlogError::AmbiguousPrefix);
                }
                found_by_prefix = Some(rev)
            }
        }
        found_by_prefix.ok_or(RevlogError::InvalidRevision)
    }

    /// Returns whether the given revision exists in this revlog.
    pub fn has_rev(&self, rev: UncheckedRevision) -> bool {
        self.index.check_revision(rev).is_some()
    }

    /// Return the full data associated to a revision.
    ///
    /// All entries required to build the final data out of deltas will be
    /// retrieved as needed, and the deltas will be applied to the inital
    /// snapshot to rebuild the final data.
    pub fn get_rev_data(
        &self,
        rev: UncheckedRevision,
    ) -> Result<Cow<[u8]>, RevlogError> {
        if rev == NULL_REVISION.into() {
            return Ok(Cow::Borrowed(&[]));
        };
        self.get_entry(rev)?.data()
    }

    /// [`Self::get_rev_data`] for checked revisions.
    pub fn get_rev_data_for_checked_rev(
        &self,
        rev: Revision,
    ) -> Result<Cow<[u8]>, RevlogError> {
        if rev == NULL_REVISION {
            return Ok(Cow::Borrowed(&[]));
        };
        self.get_entry_for_checked_rev(rev)?.data()
    }

    /// Check the hash of some given data against the recorded hash.
    pub fn check_hash(
        &self,
        p1: Revision,
        p2: Revision,
        expected: &[u8],
        data: &[u8],
    ) -> bool {
        let e1 = self.index.get_entry(p1);
        let h1 = match e1 {
            Some(ref entry) => entry.hash(),
            None => &NULL_NODE,
        };
        let e2 = self.index.get_entry(p2);
        let h2 = match e2 {
            Some(ref entry) => entry.hash(),
            None => &NULL_NODE,
        };

        hash(data, h1.as_bytes(), h2.as_bytes()) == expected
    }

    /// Build the full data of a revision out its snapshot
    /// and its deltas.
    fn build_data_from_deltas(
        snapshot: RevlogEntry,
        deltas: &[RevlogEntry],
    ) -> Result<Vec<u8>, HgError> {
        let snapshot = snapshot.data_chunk()?;
        let deltas = deltas
            .iter()
            .rev()
            .map(RevlogEntry::data_chunk)
            .collect::<Result<Vec<_>, _>>()?;
        let patches: Vec<_> =
            deltas.iter().map(|d| patch::PatchList::new(d)).collect();
        let patch = patch::fold_patch_lists(&patches);
        Ok(patch.apply(&snapshot))
    }

    /// Return the revlog data.
    fn data(&self) -> &[u8] {
        match &self.data_bytes {
            Some(data_bytes) => data_bytes,
            None => panic!(
                "forgot to load the data or trying to access inline data"
            ),
        }
    }

    pub fn make_null_entry(&self) -> RevlogEntry {
        RevlogEntry {
            revlog: self,
            rev: NULL_REVISION,
            bytes: b"",
            compressed_len: 0,
            uncompressed_len: 0,
            base_rev_or_base_of_delta_chain: None,
            p1: NULL_REVISION,
            p2: NULL_REVISION,
            flags: NULL_REVLOG_ENTRY_FLAGS,
            hash: NULL_NODE,
        }
    }

    fn get_entry_for_checked_rev(
        &self,
        rev: Revision,
    ) -> Result<RevlogEntry, RevlogError> {
        if rev == NULL_REVISION {
            return Ok(self.make_null_entry());
        }
        let index_entry = self
            .index
            .get_entry(rev)
            .ok_or(RevlogError::InvalidRevision)?;
        let offset = index_entry.offset();
        let start = if self.index.is_inline() {
            offset + ((rev.0 as usize + 1) * INDEX_ENTRY_SIZE)
        } else {
            offset
        };
        let end = start + index_entry.compressed_len() as usize;
        let data = if self.index.is_inline() {
            self.index.data(start, end)
        } else {
            &self.data()[start..end]
        };
        let base_rev = self
            .index
            .check_revision(index_entry.base_revision_or_base_of_delta_chain())
            .ok_or_else(|| {
                RevlogError::corrupted(format!(
                    "base revision for rev {} is invalid",
                    rev
                ))
            })?;
        let p1 =
            self.index.check_revision(index_entry.p1()).ok_or_else(|| {
                RevlogError::corrupted(format!(
                    "p1 for rev {} is invalid",
                    rev
                ))
            })?;
        let p2 =
            self.index.check_revision(index_entry.p2()).ok_or_else(|| {
                RevlogError::corrupted(format!(
                    "p2 for rev {} is invalid",
                    rev
                ))
            })?;
        let entry = RevlogEntry {
            revlog: self,
            rev,
            bytes: data,
            compressed_len: index_entry.compressed_len(),
            uncompressed_len: index_entry.uncompressed_len(),
            base_rev_or_base_of_delta_chain: if base_rev == rev {
                None
            } else {
                Some(base_rev)
            },
            p1,
            p2,
            flags: index_entry.flags(),
            hash: *index_entry.hash(),
        };
        Ok(entry)
    }

    /// Get an entry of the revlog.
    pub fn get_entry(
        &self,
        rev: UncheckedRevision,
    ) -> Result<RevlogEntry, RevlogError> {
        if rev == NULL_REVISION.into() {
            return Ok(self.make_null_entry());
        }
        let rev = self.index.check_revision(rev).ok_or_else(|| {
            RevlogError::corrupted(format!("rev {} is invalid", rev))
        })?;
        self.get_entry_for_checked_rev(rev)
    }
}

/// The revlog entry's bytes and the necessary informations to extract
/// the entry's data.
#[derive(Clone)]
pub struct RevlogEntry<'revlog> {
    revlog: &'revlog Revlog,
    rev: Revision,
    bytes: &'revlog [u8],
    compressed_len: u32,
    uncompressed_len: i32,
    base_rev_or_base_of_delta_chain: Option<Revision>,
    p1: Revision,
    p2: Revision,
    flags: u16,
    hash: Node,
}

thread_local! {
  // seems fine to [unwrap] here: this can only fail due to memory allocation
  // failing, and it's normal for that to cause panic.
  static ZSTD_DECODER : RefCell<zstd::bulk::Decompressor<'static>> =
      RefCell::new(zstd::bulk::Decompressor::new().ok().unwrap());
}

fn zstd_decompress_to_buffer(
    bytes: &[u8],
    buf: &mut Vec<u8>,
) -> Result<usize, std::io::Error> {
    ZSTD_DECODER
        .with(|decoder| decoder.borrow_mut().decompress_to_buffer(bytes, buf))
}

impl<'revlog> RevlogEntry<'revlog> {
    pub fn revision(&self) -> Revision {
        self.rev
    }

    pub fn node(&self) -> &Node {
        &self.hash
    }

    pub fn uncompressed_len(&self) -> Option<u32> {
        u32::try_from(self.uncompressed_len).ok()
    }

    pub fn has_p1(&self) -> bool {
        self.p1 != NULL_REVISION
    }

    pub fn p1_entry(
        &self,
    ) -> Result<Option<RevlogEntry<'revlog>>, RevlogError> {
        if self.p1 == NULL_REVISION {
            Ok(None)
        } else {
            Ok(Some(self.revlog.get_entry_for_checked_rev(self.p1)?))
        }
    }

    pub fn p2_entry(
        &self,
    ) -> Result<Option<RevlogEntry<'revlog>>, RevlogError> {
        if self.p2 == NULL_REVISION {
            Ok(None)
        } else {
            Ok(Some(self.revlog.get_entry_for_checked_rev(self.p2)?))
        }
    }

    pub fn p1(&self) -> Option<Revision> {
        if self.p1 == NULL_REVISION {
            None
        } else {
            Some(self.p1)
        }
    }

    pub fn p2(&self) -> Option<Revision> {
        if self.p2 == NULL_REVISION {
            None
        } else {
            Some(self.p2)
        }
    }

    pub fn is_censored(&self) -> bool {
        (self.flags & REVISION_FLAG_CENSORED) != 0
    }

    pub fn has_length_affecting_flag_processor(&self) -> bool {
        // Relevant Python code: revlog.size()
        // note: ELLIPSIS is known to not change the content
        (self.flags & (REVIDX_KNOWN_FLAGS ^ REVISION_FLAG_ELLIPSIS)) != 0
    }

    /// The data for this entry, after resolving deltas if any.
    pub fn rawdata(&self) -> Result<Cow<'revlog, [u8]>, RevlogError> {
        let mut entry = self.clone();
        let mut delta_chain = vec![];

        // The meaning of `base_rev_or_base_of_delta_chain` depends on
        // generaldelta. See the doc on `ENTRY_DELTA_BASE` in
        // `mercurial/revlogutils/constants.py` and the code in
        // [_chaininfo] and in [index_deltachain].
        let uses_generaldelta = self.revlog.index.uses_generaldelta();
        while let Some(base_rev) = entry.base_rev_or_base_of_delta_chain {
            entry = if uses_generaldelta {
                delta_chain.push(entry);
                self.revlog.get_entry_for_checked_rev(base_rev)?
            } else {
                let base_rev = UncheckedRevision(entry.rev.0 - 1);
                delta_chain.push(entry);
                self.revlog.get_entry(base_rev)?
            };
        }

        let data = if delta_chain.is_empty() {
            entry.data_chunk()?
        } else {
            Revlog::build_data_from_deltas(entry, &delta_chain)?.into()
        };

        Ok(data)
    }

    fn check_data(
        &self,
        data: Cow<'revlog, [u8]>,
    ) -> Result<Cow<'revlog, [u8]>, RevlogError> {
        if self.revlog.check_hash(
            self.p1,
            self.p2,
            self.hash.as_bytes(),
            &data,
        ) {
            Ok(data)
        } else {
            if (self.flags & REVISION_FLAG_ELLIPSIS) != 0 {
                return Err(HgError::unsupported(
                    "ellipsis revisions are not supported by rhg",
                )
                .into());
            }
            Err(corrupted(format!(
                "hash check failed for revision {}",
                self.rev
            ))
            .into())
        }
    }

    pub fn data(&self) -> Result<Cow<'revlog, [u8]>, RevlogError> {
        let data = self.rawdata()?;
        if self.rev == NULL_REVISION {
            return Ok(data);
        }
        if self.is_censored() {
            return Err(HgError::CensoredNodeError.into());
        }
        self.check_data(data)
    }

    /// Extract the data contained in the entry.
    /// This may be a delta. (See `is_delta`.)
    fn data_chunk(&self) -> Result<Cow<'revlog, [u8]>, HgError> {
        if self.bytes.is_empty() {
            return Ok(Cow::Borrowed(&[]));
        }
        match self.bytes[0] {
            // Revision data is the entirety of the entry, including this
            // header.
            b'\0' => Ok(Cow::Borrowed(self.bytes)),
            // Raw revision data follows.
            b'u' => Ok(Cow::Borrowed(&self.bytes[1..])),
            // zlib (RFC 1950) data.
            b'x' => Ok(Cow::Owned(self.uncompressed_zlib_data()?)),
            // zstd data.
            b'\x28' => Ok(Cow::Owned(self.uncompressed_zstd_data()?)),
            // A proper new format should have had a repo/store requirement.
            format_type => Err(corrupted(format!(
                "unknown compression header '{}'",
                format_type
            ))),
        }
    }

    fn uncompressed_zlib_data(&self) -> Result<Vec<u8>, HgError> {
        let mut decoder = ZlibDecoder::new(self.bytes);
        if self.is_delta() {
            let mut buf = Vec::with_capacity(self.compressed_len as usize);
            decoder
                .read_to_end(&mut buf)
                .map_err(|e| corrupted(e.to_string()))?;
            Ok(buf)
        } else {
            let cap = self.uncompressed_len.max(0) as usize;
            let mut buf = vec![0; cap];
            decoder
                .read_exact(&mut buf)
                .map_err(|e| corrupted(e.to_string()))?;
            Ok(buf)
        }
    }

    fn uncompressed_zstd_data(&self) -> Result<Vec<u8>, HgError> {
        let cap = self.uncompressed_len.max(0) as usize;
        if self.is_delta() {
            // [cap] is usually an over-estimate of the space needed because
            // it's the length of delta-decoded data, but we're interested
            // in the size of the delta.
            // This means we have to [shrink_to_fit] to avoid holding on
            // to a large chunk of memory, but it also means we must have a
            // fallback branch, for the case when the delta is longer than
            // the original data (surprisingly, this does happen in practice)
            let mut buf = Vec::with_capacity(cap);
            match zstd_decompress_to_buffer(self.bytes, &mut buf) {
                Ok(_) => buf.shrink_to_fit(),
                Err(_) => {
                    buf.clear();
                    zstd::stream::copy_decode(self.bytes, &mut buf)
                        .map_err(|e| corrupted(e.to_string()))?;
                }
            };
            Ok(buf)
        } else {
            let mut buf = Vec::with_capacity(cap);
            let len = zstd_decompress_to_buffer(self.bytes, &mut buf)
                .map_err(|e| corrupted(e.to_string()))?;
            if len != self.uncompressed_len as usize {
                Err(corrupted("uncompressed length does not match"))
            } else {
                Ok(buf)
            }
        }
    }

    /// Tell if the entry is a snapshot or a delta
    /// (influences on decompression).
    fn is_delta(&self) -> bool {
        self.base_rev_or_base_of_delta_chain.is_some()
    }
}

/// Calculate the hash of a revision given its data and its parents.
fn hash(
    data: &[u8],
    p1_hash: &[u8],
    p2_hash: &[u8],
) -> [u8; NODE_BYTES_LENGTH] {
    let mut hasher = Sha1::new();
    let (a, b) = (p1_hash, p2_hash);
    if a > b {
        hasher.update(b);
        hasher.update(a);
    } else {
        hasher.update(a);
        hasher.update(b);
    }
    hasher.update(data);
    *hasher.finalize().as_ref()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::IndexEntryBuilder;
    use itertools::Itertools;

    #[test]
    fn test_empty() {
        let temp = tempfile::tempdir().unwrap();
        let vfs = Vfs { base: temp.path() };
        std::fs::write(temp.path().join("foo.i"), b"").unwrap();
        let revlog =
            Revlog::open(&vfs, "foo.i", None, RevlogOpenOptions::new())
                .unwrap();
        assert!(revlog.is_empty());
        assert_eq!(revlog.len(), 0);
        assert!(revlog.get_entry(0.into()).is_err());
        assert!(!revlog.has_rev(0.into()));
        assert_eq!(
            revlog.rev_from_node(NULL_NODE.into()).unwrap(),
            NULL_REVISION
        );
        let null_entry = revlog.get_entry(NULL_REVISION.into()).ok().unwrap();
        assert_eq!(null_entry.revision(), NULL_REVISION);
        assert!(null_entry.data().unwrap().is_empty());
    }

    #[test]
    fn test_inline() {
        let temp = tempfile::tempdir().unwrap();
        let vfs = Vfs { base: temp.path() };
        let node0 = Node::from_hex("2ed2a3912a0b24502043eae84ee4b279c18b90dd")
            .unwrap();
        let node1 = Node::from_hex("b004912a8510032a0350a74daa2803dadfb00e12")
            .unwrap();
        let node2 = Node::from_hex("dd6ad206e907be60927b5a3117b97dffb2590582")
            .unwrap();
        let entry0_bytes = IndexEntryBuilder::new()
            .is_first(true)
            .with_version(1)
            .with_inline(true)
            .with_node(node0)
            .build();
        let entry1_bytes = IndexEntryBuilder::new().with_node(node1).build();
        let entry2_bytes = IndexEntryBuilder::new()
            .with_p1(Revision(0))
            .with_p2(Revision(1))
            .with_node(node2)
            .build();
        let contents = vec![entry0_bytes, entry1_bytes, entry2_bytes]
            .into_iter()
            .flatten()
            .collect_vec();
        std::fs::write(temp.path().join("foo.i"), contents).unwrap();
        let revlog =
            Revlog::open(&vfs, "foo.i", None, RevlogOpenOptions::new())
                .unwrap();

        let entry0 = revlog.get_entry(0.into()).ok().unwrap();
        assert_eq!(entry0.revision(), Revision(0));
        assert_eq!(*entry0.node(), node0);
        assert!(!entry0.has_p1());
        assert_eq!(entry0.p1(), None);
        assert_eq!(entry0.p2(), None);
        let p1_entry = entry0.p1_entry().unwrap();
        assert!(p1_entry.is_none());
        let p2_entry = entry0.p2_entry().unwrap();
        assert!(p2_entry.is_none());

        let entry1 = revlog.get_entry(1.into()).ok().unwrap();
        assert_eq!(entry1.revision(), Revision(1));
        assert_eq!(*entry1.node(), node1);
        assert!(!entry1.has_p1());
        assert_eq!(entry1.p1(), None);
        assert_eq!(entry1.p2(), None);
        let p1_entry = entry1.p1_entry().unwrap();
        assert!(p1_entry.is_none());
        let p2_entry = entry1.p2_entry().unwrap();
        assert!(p2_entry.is_none());

        let entry2 = revlog.get_entry(2.into()).ok().unwrap();
        assert_eq!(entry2.revision(), Revision(2));
        assert_eq!(*entry2.node(), node2);
        assert!(entry2.has_p1());
        assert_eq!(entry2.p1(), Some(Revision(0)));
        assert_eq!(entry2.p2(), Some(Revision(1)));
        let p1_entry = entry2.p1_entry().unwrap();
        assert!(p1_entry.is_some());
        assert_eq!(p1_entry.unwrap().revision(), Revision(0));
        let p2_entry = entry2.p2_entry().unwrap();
        assert!(p2_entry.is_some());
        assert_eq!(p2_entry.unwrap().revision(), Revision(1));
    }

    #[test]
    fn test_nodemap() {
        let temp = tempfile::tempdir().unwrap();
        let vfs = Vfs { base: temp.path() };

        // building a revlog with a forced Node starting with zeros
        // This is a corruption, but it does not preclude using the nodemap
        // if we don't try and access the data
        let node0 = Node::from_hex("00d2a3912a0b24502043eae84ee4b279c18b90dd")
            .unwrap();
        let node1 = Node::from_hex("b004912a8510032a0350a74daa2803dadfb00e12")
            .unwrap();
        let entry0_bytes = IndexEntryBuilder::new()
            .is_first(true)
            .with_version(1)
            .with_inline(true)
            .with_node(node0)
            .build();
        let entry1_bytes = IndexEntryBuilder::new().with_node(node1).build();
        let contents = vec![entry0_bytes, entry1_bytes]
            .into_iter()
            .flatten()
            .collect_vec();
        std::fs::write(temp.path().join("foo.i"), contents).unwrap();

        let mut idx = nodemap::tests::TestNtIndex::new();
        idx.insert_node(Revision(0), node0).unwrap();
        idx.insert_node(Revision(1), node1).unwrap();

        let revlog = Revlog::open_gen(
            &vfs,
            "foo.i",
            None,
            RevlogOpenOptions::new(),
            Some(idx.nt),
        )
        .unwrap();

        // accessing the data shows the corruption
        revlog.get_entry(0.into()).unwrap().data().unwrap_err();

        assert_eq!(
            revlog.rev_from_node(NULL_NODE.into()).unwrap(),
            Revision(-1)
        );
        assert_eq!(revlog.rev_from_node(node0.into()).unwrap(), Revision(0));
        assert_eq!(revlog.rev_from_node(node1.into()).unwrap(), Revision(1));
        assert_eq!(
            revlog
                .rev_from_node(NodePrefix::from_hex("000").unwrap())
                .unwrap(),
            Revision(-1)
        );
        assert_eq!(
            revlog
                .rev_from_node(NodePrefix::from_hex("b00").unwrap())
                .unwrap(),
            Revision(1)
        );
        // RevlogError does not implement PartialEq
        // (ultimately because io::Error does not)
        match revlog
            .rev_from_node(NodePrefix::from_hex("00").unwrap())
            .expect_err("Expected to give AmbiguousPrefix error")
        {
            RevlogError::AmbiguousPrefix => (),
            e => {
                panic!("Got another error than AmbiguousPrefix: {:?}", e);
            }
        };
    }
}
