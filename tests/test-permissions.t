#require unix-permissions no-root reporevlogstore

#testcases dirstate-v1 dirstate-v1-tree dirstate-v2

#if dirstate-v1-tree
#require rust
  $ echo '[experimental]' >> $HGRCPATH
  $ echo 'dirstate-tree.in-memory=1' >> $HGRCPATH
#endif

#if dirstate-v2
#require rust
  $ echo '[format]' >> $HGRCPATH
  $ echo 'exp-dirstate-v2=1' >> $HGRCPATH
#endif

  $ hg init t
  $ cd t

  $ echo foo > a
  $ hg add a

  $ hg commit -m "1"

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 1 changesets with 1 changes to 1 files

  $ chmod -r .hg/store/data/a.i

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  abort: Permission denied: '$TESTTMP/t/.hg/store/data/a.i'
  [255]

  $ chmod +r .hg/store/data/a.i

  $ hg verify
  checking changesets
  checking manifests
  crosschecking files in changesets and manifests
  checking files
  checked 1 changesets with 1 changes to 1 files

  $ chmod -w .hg/store/data/a.i

  $ echo barber > a
  $ hg commit -m "2"
  trouble committing a!
  abort: Permission denied: '$TESTTMP/t/.hg/store/data/a.i'
  [255]

  $ chmod -w .

  $ hg diff --nodates
  diff -r 2a18120dc1c9 a
  --- a/a
  +++ b/a
  @@ -1,1 +1,1 @@
  -foo
  +barber

  $ chmod +w .

  $ chmod +w .hg/store/data/a.i
  $ mkdir dir
  $ touch dir/a
  $ hg status
  M a
  ? dir/a
  $ chmod -rx dir

#if no-fsmonitor

(fsmonitor makes "hg status" avoid accessing to "dir")

  $ hg status
  dir: Permission denied
  M a

#endif

Reenable perm to allow deletion:

  $ chmod +rx dir

  $ cd ..
