PatchParseError = error.PatchParseError
PatchApplicationError = error.PatchApplicationError
            # pytype: disable=wrong-arg-types
            # pytype: enable=wrong-arg-types
    class fiter:
    if not util.safehasattr(stream, 'next'):
class patchmeta:
class linereader:
class abstractbackend:
        except FileNotFoundError:
            pass
        except FileNotFoundError:
        if not self.repo.dirstate.get_entry(fname).any_tracked and self.exists(
            fname
        ):
            raise PatchApplicationError(
                _(b'cannot patch %s: file is not tracked') % fname
            )
        with self.repo.dirstate.changing_files(self.repo):
            wctx = self.repo[None]
            changed = set(self.changed)
            for src, dst in self.copied:
                scmutil.dirstatecopy(self.ui, self.repo, wctx, src, dst)
            if self.removed:
                wctx.forget(sorted(self.removed))
                for f in self.removed:
                    if f not in self.repo.dirstate:
                        # File was deleted and no longer belongs to the
                        # dirstate, it was probably marked added then
                        # deleted, and should not be considered by
                        # marktouched().
                        changed.discard(f)
            if changed:
                scmutil.marktouched(self.repo, changed, self.similarity)
            return sorted(self.changed)


class filestore:
            raise PatchApplicationError(
                _(b'cannot patch %s: file is not tracked') % fname
            )
class patchfile:
            raise PatchParseError(
        for fuzzlen in range(self.ui.configint(b"patch", b"fuzz") + 1):
class header:
class recordhunk:
                    for line in patchfp:
            [h for h in applied.values() if h[0].special() or len(h) > 1],
class hunk:
            raise PatchParseError(_(b"bad hunk #%d") % self.number)
            raise PatchParseError(_(b"bad hunk #%d: %s") % (self.number, e))
            raise PatchParseError(_(b"bad hunk #%d") % self.number)
        for x in range(self.lena):
                raise PatchParseError(
            raise PatchParseError(_(b"bad hunk #%d") % self.number)
        for x in range(self.lenb):
                raise PatchParseError(
            for x in range(hlen - 1):
                for x in range(hlen - 1):
class binhunk:
                raise PatchParseError(
                raise PatchParseError(
            raise PatchParseError(