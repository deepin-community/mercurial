  $ hg init t
  $ cd t
  $ echo a > a
  $ hg add a
  $ hg commit -m test
  $ rm .hg/requires
  $ hg tip
  abort: unknown version (65535) in revlog 00changelog
  [50]
  $ echo indoor-pool > .hg/requires
  $ hg tip
  abort: repository requires features unknown to this Mercurial: indoor-pool
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]
  $ echo outdoor-pool >> .hg/requires
  $ hg tip
  abort: repository requires features unknown to this Mercurial: indoor-pool outdoor-pool
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]
  $ cd ..

Test checking between features supported locally and ones required in
another repository of push/pull/clone on localhost:

  $ mkdir supported-locally
  $ cd supported-locally

  $ hg init supported
  $ echo a > supported/a
  $ hg -R supported commit -Am '#0 at supported'
  adding a

  $ echo 'featuresetup-test' >> supported/.hg/requires
  $ cat > $TESTTMP/supported-locally/supportlocally.py <<EOF
  > from __future__ import absolute_import
  > from mercurial import extensions, localrepo
  > def featuresetup(ui, supported):
  >     for name, module in extensions.extensions(ui):
  >         if __name__ == module.__name__:
  >             # support specific feature locally
  >             supported |= {b'featuresetup-test'}
  >             return
  > def uisetup(ui):
  >     localrepo.featuresetupfuncs.add(featuresetup)
  > EOF
  $ cat > supported/.hg/hgrc <<EOF
  > [extensions]
  > # enable extension locally
  > supportlocally = $TESTTMP/supported-locally/supportlocally.py
  > EOF
  $ hg -R supported debugrequirements
  dotencode
  exp-dirstate-v2 (dirstate-v2 !)
  featuresetup-test
  fncache
  generaldelta
  persistent-nodemap (rust !)
  revlog-compression-zstd (zstd !)
  revlogv1
  sparserevlog
  store
  $ hg -R supported status

  $ hg init push-dst
  $ hg -R supported push push-dst
  pushing to push-dst
  abort: required features are not supported in the destination: featuresetup-test
  [255]

  $ hg init pull-src
  $ hg -R pull-src pull supported
  pulling from supported
  abort: required features are not supported in the destination: featuresetup-test
  [255]

  $ hg clone supported clone-dst
  abort: repository requires features unknown to this Mercurial: featuresetup-test
  (see https://mercurial-scm.org/wiki/MissingRequirement for more information)
  [255]
  $ hg clone --pull supported clone-dst
  abort: required features are not supported in the destination: featuresetup-test
  [255]

  $ cd ..
