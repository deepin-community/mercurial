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

------ Test dirstate._dirs refcounting

  $ hg init t
  $ cd t
  $ mkdir -p a/b/c/d
  $ touch a/b/c/d/x
  $ touch a/b/c/d/y
  $ touch a/b/c/d/z
  $ hg ci -Am m
  adding a/b/c/d/x
  adding a/b/c/d/y
  adding a/b/c/d/z
  $ hg mv a z
  moving a/b/c/d/x to z/b/c/d/x
  moving a/b/c/d/y to z/b/c/d/y
  moving a/b/c/d/z to z/b/c/d/z

Test name collisions

  $ rm z/b/c/d/x
  $ mkdir z/b/c/d/x
  $ touch z/b/c/d/x/y
  $ hg add z/b/c/d/x/y
  abort: file 'z/b/c/d/x' in dirstate clashes with 'z/b/c/d/x/y'
  [255]
  $ rm -rf z/b/c/d
  $ touch z/b/c/d
  $ hg add z/b/c/d
  abort: directory 'z/b/c/d' already in dirstate
  [255]

  $ cd ..

Issue1790: dirstate entry locked into unset if file mtime is set into
the future

Prepare test repo:

  $ hg init u
  $ cd u
  $ echo a > a
  $ hg add
  adding a
  $ hg ci -m1

Set mtime of a into the future:

  $ touch -t 202101011200 a

Status must not set a's entry to unset (issue1790):

  $ hg status
  $ hg debugstate
  n 644          2 2021-01-01 12:00:00 a

Test modulo storage/comparison of absurd dates:

#if no-aix
  $ touch -t 195001011200 a
  $ hg st
  $ hg debugstate
  n 644          2 2018-01-19 15:14:08 a
#endif

Verify that exceptions during a dirstate change leave the dirstate
coherent (issue4353)

  $ cat > ../dirstateexception.py <<EOF
  > from __future__ import absolute_import
  > from mercurial import (
  >   error,
  >   extensions,
  >   mergestate as mergestatemod,
  > )
  > 
  > def wraprecordupdates(*args):
  >     raise error.Abort(b"simulated error while recording dirstateupdates")
  > 
  > def reposetup(ui, repo):
  >     extensions.wrapfunction(mergestatemod, 'recordupdates',
  >                             wraprecordupdates)
  > EOF

  $ hg rm a
  $ hg commit -m 'rm a'
  $ echo "[extensions]" >> .hg/hgrc
  $ echo "dirstateex=../dirstateexception.py" >> .hg/hgrc
  $ hg up 0
  abort: simulated error while recording dirstateupdates
  [255]
  $ hg log -r . -T '{rev}\n'
  1
  $ hg status
  ? a
