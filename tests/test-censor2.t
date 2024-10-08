  $ cat >> $HGRCPATH <<EOF
  > [censor]
  > policy=ignore
  > EOF

  $ mkdir r
  $ cd r
  $ hg init
  $ echo secret > target
  $ hg commit -Am "secret"
  adding target
  $ touch bystander
  $ hg commit -Am "innocent"
  adding bystander
  $ echo erased-secret > target
  $ hg commit -m "erased secret"
  $ hg censor target --config extensions.censor= -r ".^^"
  checking for the censored content in 1 heads
  checking for the censored content in the working directory
  censoring 1 file revisions
  $ hg update ".^"
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cat target
  $ hg update tip
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
