use crate::errors::HgError;
use crate::revlog::Revision;
use crate::revlog::{Node, NodePrefix};
use crate::revlog::{Revlog, RevlogEntry, RevlogError};
use crate::utils::hg_path::HgPath;
use crate::vfs::Vfs;
use itertools::Itertools;
use std::ascii::escape_default;
use std::borrow::Cow;
use std::fmt::{Debug, Formatter};

/// A specialized `Revlog` to work with changelog data format.
pub struct Changelog {
    /// The generic `revlog` format.
    pub(crate) revlog: Revlog,
}

impl Changelog {
    /// Open the `changelog` of a repository given by its root.
    pub fn open(store_vfs: &Vfs, use_nodemap: bool) -> Result<Self, HgError> {
        let revlog =
            Revlog::open(store_vfs, "00changelog.i", None, use_nodemap)?;
        Ok(Self { revlog })
    }

    /// Return the `ChangelogRevisionData` for the given node ID.
    pub fn data_for_node(
        &self,
        node: NodePrefix,
    ) -> Result<ChangelogRevisionData, RevlogError> {
        let rev = self.revlog.rev_from_node(node)?;
        self.data_for_rev(rev)
    }

    /// Return the [`ChangelogEntry`] for the given revision number.
    pub fn entry_for_rev(
        &self,
        rev: Revision,
    ) -> Result<ChangelogEntry, RevlogError> {
        let revlog_entry = self.revlog.get_entry(rev)?;
        Ok(ChangelogEntry { revlog_entry })
    }

    /// Return the [`ChangelogRevisionData`] for the given revision number.
    ///
    /// This is a useful shortcut in case the caller does not need the
    /// generic revlog information (parents, hashes etc). Otherwise
    /// consider taking a [`ChangelogEntry`] with
    /// [entry_for_rev](`Self::entry_for_rev`) and doing everything from there.
    pub fn data_for_rev(
        &self,
        rev: Revision,
    ) -> Result<ChangelogRevisionData, RevlogError> {
        self.entry_for_rev(rev)?.data()
    }

    pub fn node_from_rev(&self, rev: Revision) -> Option<&Node> {
        self.revlog.node_from_rev(rev)
    }

    pub fn rev_from_node(
        &self,
        node: NodePrefix,
    ) -> Result<Revision, RevlogError> {
        self.revlog.rev_from_node(node)
    }
}

/// A specialized `RevlogEntry` for `changelog` data format
///
/// This is a `RevlogEntry` with the added semantics that the associated
/// data should meet the requirements for `changelog`, materialized by
/// the fact that `data()` constructs a `ChangelogRevisionData`.
/// In case that promise would be broken, the `data` method returns an error.
#[derive(Clone)]
pub struct ChangelogEntry<'changelog> {
    /// Same data, as a generic `RevlogEntry`.
    pub(crate) revlog_entry: RevlogEntry<'changelog>,
}

impl<'changelog> ChangelogEntry<'changelog> {
    pub fn data<'a>(
        &'a self,
    ) -> Result<ChangelogRevisionData<'changelog>, RevlogError> {
        let bytes = self.revlog_entry.data()?;
        if bytes.is_empty() {
            Ok(ChangelogRevisionData::null())
        } else {
            Ok(ChangelogRevisionData::new(bytes).map_err(|err| {
                RevlogError::Other(HgError::CorruptedRepository(format!(
                    "Invalid changelog data for revision {}: {:?}",
                    self.revlog_entry.revision(),
                    err
                )))
            })?)
        }
    }

    /// Obtain a reference to the underlying `RevlogEntry`.
    ///
    /// This allows the caller to access the information that is common
    /// to all revlog entries: revision number, node id, parent revisions etc.
    pub fn as_revlog_entry(&self) -> &RevlogEntry {
        &self.revlog_entry
    }

    pub fn p1_entry(&self) -> Result<Option<ChangelogEntry>, RevlogError> {
        Ok(self
            .revlog_entry
            .p1_entry()?
            .map(|revlog_entry| Self { revlog_entry }))
    }

    pub fn p2_entry(&self) -> Result<Option<ChangelogEntry>, RevlogError> {
        Ok(self
            .revlog_entry
            .p2_entry()?
            .map(|revlog_entry| Self { revlog_entry }))
    }
}

/// `Changelog` entry which knows how to interpret the `changelog` data bytes.
#[derive(PartialEq)]
pub struct ChangelogRevisionData<'changelog> {
    /// The data bytes of the `changelog` entry.
    bytes: Cow<'changelog, [u8]>,
    /// The end offset for the hex manifest (not including the newline)
    manifest_end: usize,
    /// The end offset for the user+email (not including the newline)
    user_end: usize,
    /// The end offset for the timestamp+timezone+extras (not including the
    /// newline)
    timestamp_end: usize,
    /// The end offset for the file list (not including the newline)
    files_end: usize,
}

impl<'changelog> ChangelogRevisionData<'changelog> {
    fn new(bytes: Cow<'changelog, [u8]>) -> Result<Self, HgError> {
        let mut line_iter = bytes.split(|b| b == &b'\n');
        let manifest_end = line_iter
            .next()
            .expect("Empty iterator from split()?")
            .len();
        let user_slice = line_iter.next().ok_or_else(|| {
            HgError::corrupted("Changeset data truncated after manifest line")
        })?;
        let user_end = manifest_end + 1 + user_slice.len();
        let timestamp_slice = line_iter.next().ok_or_else(|| {
            HgError::corrupted("Changeset data truncated after user line")
        })?;
        let timestamp_end = user_end + 1 + timestamp_slice.len();
        let mut files_end = timestamp_end + 1;
        loop {
            let line = line_iter.next().ok_or_else(|| {
                HgError::corrupted("Changeset data truncated in files list")
            })?;
            if line.is_empty() {
                if files_end == bytes.len() {
                    // The list of files ended with a single newline (there
                    // should be two)
                    return Err(HgError::corrupted(
                        "Changeset data truncated after files list",
                    ));
                }
                files_end -= 1;
                break;
            }
            files_end += line.len() + 1;
        }

        Ok(Self {
            bytes,
            manifest_end,
            user_end,
            timestamp_end,
            files_end,
        })
    }

    fn null() -> Self {
        Self::new(Cow::Borrowed(
            b"0000000000000000000000000000000000000000\n\n0 0\n\n",
        ))
        .unwrap()
    }

    /// Return an iterator over the lines of the entry.
    pub fn lines(&self) -> impl Iterator<Item = &[u8]> {
        self.bytes.split(|b| b == &b'\n')
    }

    /// Return the node id of the `manifest` referenced by this `changelog`
    /// entry.
    pub fn manifest_node(&self) -> Result<Node, HgError> {
        let manifest_node_hex = &self.bytes[..self.manifest_end];
        Node::from_hex_for_repo(manifest_node_hex)
    }

    /// The full user string (usually a name followed by an email enclosed in
    /// angle brackets)
    pub fn user(&self) -> &[u8] {
        &self.bytes[self.manifest_end + 1..self.user_end]
    }

    /// The full timestamp line (timestamp in seconds, offset in seconds, and
    /// possibly extras)
    // TODO: We should expose this in a more useful way
    pub fn timestamp_line(&self) -> &[u8] {
        &self.bytes[self.user_end + 1..self.timestamp_end]
    }

    /// The files changed in this revision.
    pub fn files(&self) -> impl Iterator<Item = &HgPath> {
        self.bytes[self.timestamp_end + 1..self.files_end]
            .split(|b| b == &b'\n')
            .map(HgPath::new)
    }

    /// The change description.
    pub fn description(&self) -> &[u8] {
        &self.bytes[self.files_end + 2..]
    }
}

impl Debug for ChangelogRevisionData<'_> {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ChangelogRevisionData")
            .field("bytes", &debug_bytes(&self.bytes))
            .field("manifest", &debug_bytes(&self.bytes[..self.manifest_end]))
            .field(
                "user",
                &debug_bytes(
                    &self.bytes[self.manifest_end + 1..self.user_end],
                ),
            )
            .field(
                "timestamp",
                &debug_bytes(
                    &self.bytes[self.user_end + 1..self.timestamp_end],
                ),
            )
            .field(
                "files",
                &debug_bytes(
                    &self.bytes[self.timestamp_end + 1..self.files_end],
                ),
            )
            .field(
                "description",
                &debug_bytes(&self.bytes[self.files_end + 2..]),
            )
            .finish()
    }
}

fn debug_bytes(bytes: &[u8]) -> String {
    String::from_utf8_lossy(
        &bytes.iter().flat_map(|b| escape_default(*b)).collect_vec(),
    )
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vfs::Vfs;
    use crate::NULL_REVISION;
    use pretty_assertions::assert_eq;

    #[test]
    fn test_create_changelogrevisiondata_invalid() {
        // Completely empty
        assert!(ChangelogRevisionData::new(Cow::Borrowed(b"abcd")).is_err());
        // No newline after manifest
        assert!(ChangelogRevisionData::new(Cow::Borrowed(b"abcd")).is_err());
        // No newline after user
        assert!(ChangelogRevisionData::new(Cow::Borrowed(b"abcd\n")).is_err());
        // No newline after timestamp
        assert!(
            ChangelogRevisionData::new(Cow::Borrowed(b"abcd\n\n0 0")).is_err()
        );
        // Missing newline after files
        assert!(ChangelogRevisionData::new(Cow::Borrowed(
            b"abcd\n\n0 0\nfile1\nfile2"
        ))
        .is_err(),);
        // Only one newline after files
        assert!(ChangelogRevisionData::new(Cow::Borrowed(
            b"abcd\n\n0 0\nfile1\nfile2\n"
        ))
        .is_err(),);
    }

    #[test]
    fn test_create_changelogrevisiondata() {
        let data = ChangelogRevisionData::new(Cow::Borrowed(
            b"0123456789abcdef0123456789abcdef01234567
Some One <someone@example.com>
0 0
file1
file2

some
commit
message",
        ))
        .unwrap();
        assert_eq!(
            data.manifest_node().unwrap(),
            Node::from_hex("0123456789abcdef0123456789abcdef01234567")
                .unwrap()
        );
        assert_eq!(data.user(), b"Some One <someone@example.com>");
        assert_eq!(data.timestamp_line(), b"0 0");
        assert_eq!(
            data.files().collect_vec(),
            vec![HgPath::new("file1"), HgPath::new("file2")]
        );
        assert_eq!(data.description(), b"some\ncommit\nmessage");
    }

    #[test]
    fn test_data_from_rev_null() -> Result<(), RevlogError> {
        // an empty revlog will be enough for this case
        let temp = tempfile::tempdir().unwrap();
        let vfs = Vfs { base: temp.path() };
        std::fs::write(temp.path().join("foo.i"), b"").unwrap();
        let revlog = Revlog::open(&vfs, "foo.i", None, false).unwrap();

        let changelog = Changelog { revlog };
        assert_eq!(
            changelog.data_for_rev(NULL_REVISION)?,
            ChangelogRevisionData::null()
        );
        // same with the intermediate entry object
        assert_eq!(
            changelog.entry_for_rev(NULL_REVISION)?.data()?,
            ChangelogRevisionData::null()
        );
        Ok(())
    }
}
