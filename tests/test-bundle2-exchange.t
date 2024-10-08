Test exchange of common information using bundle2


  $ getmainid() {
  >    hg -R main log --template '{node}\n' --rev "$1"
  > }

enable obsolescence

  $ cp $HGRCPATH $TESTTMP/hgrc.orig
  $ cat > $TESTTMP/bundle2-pushkey-hook.sh << EOF
  > echo pushkey: lock state after \"\$HG_NAMESPACE\"
  > hg debuglock
  > EOF

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > evolution.createmarkers=True
  > evolution.exchange=True
  > bundle2-output-capture=True
  > [command-templates]
  > log={rev}:{node|short} {phase} {author} {bookmarks} {desc|firstline}
  > [web]
  > push_ssl = false
  > allow_push = *
  > [phases]
  > publish=False
  > [hooks]
  > pretxnclose.tip = hg log -r tip -T "pre-close-tip:{node|short} {phase} {bookmarks}\n"
  > txnclose.tip = hg log -r tip -T "postclose-tip:{node|short} {phase} {bookmarks}\n"
  > txnclose.env = sh -c  "HG_LOCAL= printenv.py txnclose"
  > pushkey= sh "$TESTTMP/bundle2-pushkey-hook.sh"
  > EOF

The extension requires a repo (currently unused)

  $ hg init main
  $ cd main
  $ touch a
  $ hg add a
  $ hg commit -m 'a'
  pre-close-tip:3903775176ed draft 
  postclose-tip:3903775176ed draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_PHASES_MOVED=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=commit

  $ hg unbundle $TESTDIR/bundles/rebase.hg
  adding changesets
  adding manifests
  adding file changes
  pre-close-tip:02de42196ebe draft 
  added 8 changesets with 7 changes to 7 files (+3 heads)
  new changesets cd010b8cd998:02de42196ebe (8 drafts)
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NODE=cd010b8cd998f3981a5a8115f94f8da4ab506089 HG_NODE_LAST=02de42196ebee42ef284b6780a87cdc96e8eaab6 HG_PHASES_MOVED=1 HG_SOURCE=unbundle HG_TXNID=TXN:$ID$ HG_TXNNAME=unbundle
  bundle:*/tests/bundles/rebase.hg HG_URL=bundle:*/tests/bundles/rebase.hg (glob)
  (run 'hg heads' to see heads, 'hg merge' to merge)

  $ cd ..

Real world exchange
=====================

Add more obsolescence information

  $ hg -R main debugobsolete -d '0 0' 1111111111111111111111111111111111111111 `getmainid 9520eea781bc`
  pre-close-tip:02de42196ebe draft 
  1 new obsolescence markers
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=debugobsolete
  $ hg -R main debugobsolete -d '0 0' 2222222222222222222222222222222222222222 `getmainid 24b6387c8c8c`
  pre-close-tip:02de42196ebe draft 
  1 new obsolescence markers
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=debugobsolete

clone --pull

  $ hg -R main phase --public cd010b8cd998
  pre-close-tip:02de42196ebe draft 
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_PHASES_MOVED=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=phase
  $ hg clone main other --pull --rev 9520eea781bc
  adding changesets
  adding manifests
  adding file changes
  pre-close-tip:9520eea781bc draft 
  added 2 changesets with 2 changes to 2 files
  1 new obsolescence markers
  new changesets cd010b8cd998:9520eea781bc (1 drafts)
  postclose-tip:9520eea781bc draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_NODE=cd010b8cd998f3981a5a8115f94f8da4ab506089 HG_NODE_LAST=9520eea781bcca16c1e15acc0ba14335a0e8e5ba HG_PHASES_MOVED=1 HG_SOURCE=pull HG_TXNID=TXN:$ID$ HG_TXNNAME=pull
  file:/*/$TESTTMP/main HG_URL=file:$TESTTMP/main (glob)
  updating to branch default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg -R other log -G
  @  1:9520eea781bc draft Nicolas Dumazet <nicdumz.commits@gmail.com>  E
  |
  o  0:cd010b8cd998 public Nicolas Dumazet <nicdumz.commits@gmail.com>  A
  
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

pull

  $ hg -R main phase --public 9520eea781bc
  pre-close-tip:02de42196ebe draft 
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_PHASES_MOVED=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=phase
  $ hg -R other pull -r 24b6387c8c8c
  pulling from $TESTTMP/main
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  pre-close-tip:24b6387c8c8c draft 
  added 1 changesets with 1 changes to 1 files (+1 heads)
  1 new obsolescence markers
  new changesets 24b6387c8c8c (1 drafts)
  postclose-tip:24b6387c8c8c draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_NODE=24b6387c8c8cae37178880f3fa95ded3cb1cf785 HG_NODE_LAST=24b6387c8c8cae37178880f3fa95ded3cb1cf785 HG_PHASES_MOVED=1 HG_SOURCE=pull HG_TXNID=TXN:$ID$ HG_TXNNAME=pull
  file:/*/$TESTTMP/main HG_URL=file:$TESTTMP/main (glob)
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg -R other log -G
  o  2:24b6387c8c8c draft Nicolas Dumazet <nicdumz.commits@gmail.com>  F
  |
  | @  1:9520eea781bc draft Nicolas Dumazet <nicdumz.commits@gmail.com>  E
  |/
  o  0:cd010b8cd998 public Nicolas Dumazet <nicdumz.commits@gmail.com>  A
  
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

pull empty (with phase movement)

  $ hg -R main phase --public 24b6387c8c8c
  pre-close-tip:02de42196ebe draft 
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_PHASES_MOVED=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=phase
  $ hg -R other pull -r 24b6387c8c8c
  pulling from $TESTTMP/main
  no changes found
  pre-close-tip:24b6387c8c8c public 
  1 local changesets published
  postclose-tip:24b6387c8c8c public 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=0 HG_PHASES_MOVED=1 HG_SOURCE=pull HG_TXNID=TXN:$ID$ HG_TXNNAME=pull
  file:/*/$TESTTMP/main HG_URL=file:$TESTTMP/main (glob)
  $ hg -R other log -G
  o  2:24b6387c8c8c public Nicolas Dumazet <nicdumz.commits@gmail.com>  F
  |
  | @  1:9520eea781bc draft Nicolas Dumazet <nicdumz.commits@gmail.com>  E
  |/
  o  0:cd010b8cd998 public Nicolas Dumazet <nicdumz.commits@gmail.com>  A
  
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

pull empty

  $ hg -R other pull -r 24b6387c8c8c
  pulling from $TESTTMP/main
  no changes found
  pre-close-tip:24b6387c8c8c public 
  postclose-tip:24b6387c8c8c public 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=0 HG_SOURCE=pull HG_TXNID=TXN:$ID$ HG_TXNNAME=pull
  file:/*/$TESTTMP/main HG_URL=file:$TESTTMP/main (glob)
  $ hg -R other log -G
  o  2:24b6387c8c8c public Nicolas Dumazet <nicdumz.commits@gmail.com>  F
  |
  | @  1:9520eea781bc draft Nicolas Dumazet <nicdumz.commits@gmail.com>  E
  |/
  o  0:cd010b8cd998 public Nicolas Dumazet <nicdumz.commits@gmail.com>  A
  
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

add extra data to test their exchange during push

  $ hg -R main bookmark --rev eea13746799a book_eea1
  pre-close-tip:02de42196ebe draft 
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R main debugobsolete -d '0 0' 3333333333333333333333333333333333333333 `getmainid eea13746799a`
  pre-close-tip:02de42196ebe draft 
  1 new obsolescence markers
  postclose-tip:02de42196ebe draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=debugobsolete
  $ hg -R main bookmark --rev 02de42196ebe book_02de
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R main debugobsolete -d '0 0' 4444444444444444444444444444444444444444 `getmainid 02de42196ebe`
  pre-close-tip:02de42196ebe draft book_02de
  1 new obsolescence markers
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=debugobsolete
  $ hg -R main bookmark --rev 42ccdea3bb16 book_42cc
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R main debugobsolete -d '0 0' 5555555555555555555555555555555555555555 `getmainid 42ccdea3bb16`
  pre-close-tip:02de42196ebe draft book_02de
  1 new obsolescence markers
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=debugobsolete
  $ hg -R main bookmark --rev 5fddd98957c8 book_5fdd
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R main debugobsolete -d '0 0' 6666666666666666666666666666666666666666 `getmainid 5fddd98957c8`
  pre-close-tip:02de42196ebe draft book_02de
  1 new obsolescence markers
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=debugobsolete
  $ hg -R main bookmark --rev 32af7686d403 book_32af
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R main debugobsolete -d '0 0' 7777777777777777777777777777777777777777 `getmainid 32af7686d403`
  pre-close-tip:02de42196ebe draft book_02de
  1 new obsolescence markers
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=debugobsolete

  $ hg -R other bookmark --rev cd010b8cd998 book_eea1
  pre-close-tip:24b6387c8c8c public 
  postclose-tip:24b6387c8c8c public 
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R other bookmark --rev cd010b8cd998 book_02de
  pre-close-tip:24b6387c8c8c public 
  postclose-tip:24b6387c8c8c public 
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R other bookmark --rev cd010b8cd998 book_42cc
  pre-close-tip:24b6387c8c8c public 
  postclose-tip:24b6387c8c8c public 
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R other bookmark --rev cd010b8cd998 book_5fdd
  pre-close-tip:24b6387c8c8c public 
  postclose-tip:24b6387c8c8c public 
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark
  $ hg -R other bookmark --rev cd010b8cd998 book_32af
  pre-close-tip:24b6387c8c8c public 
  postclose-tip:24b6387c8c8c public 
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=bookmark

  $ hg -R main phase --public eea13746799a
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_PHASES_MOVED=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=phase

push
  $ hg -R main push other --rev eea13746799a --bookmark book_eea1
  pushing to other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: pre-close-tip:eea13746799a public book_eea1
  remote: added 1 changesets with 0 changes to 0 files (-1 heads)
  remote: 1 new obsolescence markers
  remote: pushkey: lock state after "bookmarks"
  remote: lock:  free
  remote: wlock: free
  remote: postclose-tip:eea13746799a public book_eea1
  remote: txnclose hook: HG_BOOKMARK_MOVED=1 HG_BUNDLE2=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_NODE=eea13746799a9e0bfd88f29d3c2e9dc9389f524f HG_NODE_LAST=eea13746799a9e0bfd88f29d3c2e9dc9389f524f HG_PHASES_MOVED=1 HG_SOURCE=push HG_TXNID=TXN:$ID$ HG_TXNNAME=push HG_URL=file:$TESTTMP/other
  updating bookmark book_eea1
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_SOURCE=push-response HG_TXNID=TXN:$ID$ HG_TXNNAME=push-response
  file:/*/$TESTTMP/other HG_URL=file:$TESTTMP/other (glob)
  $ hg -R other log -G
  o    3:eea13746799a public Nicolas Dumazet <nicdumz.commits@gmail.com> book_eea1 G
  |\
  | o  2:24b6387c8c8c public Nicolas Dumazet <nicdumz.commits@gmail.com>  F
  | |
  @ |  1:9520eea781bc public Nicolas Dumazet <nicdumz.commits@gmail.com>  E
  |/
  o  0:cd010b8cd998 public Nicolas Dumazet <nicdumz.commits@gmail.com> book_02de book_32af book_42cc book_5fdd A
  
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  3333333333333333333333333333333333333333 eea13746799a9e0bfd88f29d3c2e9dc9389f524f 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

pull over ssh

  $ hg -R other pull ssh://user@dummy/main -r 02de42196ebe --bookmark book_02de
  pulling from ssh://user@dummy/main
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  updating bookmark book_02de
  pre-close-tip:02de42196ebe draft book_02de
  added 1 changesets with 1 changes to 1 files (+1 heads)
  1 new obsolescence markers
  new changesets 02de42196ebe (1 drafts)
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_NODE=02de42196ebee42ef284b6780a87cdc96e8eaab6 HG_NODE_LAST=02de42196ebee42ef284b6780a87cdc96e8eaab6 HG_PHASES_MOVED=1 HG_SOURCE=pull HG_TXNID=TXN:$ID$ HG_TXNNAME=pull
  ssh://user@dummy/main HG_URL=ssh://user@dummy/main
  (run 'hg heads' to see heads, 'hg merge' to merge)
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  3333333333333333333333333333333333333333 eea13746799a9e0bfd88f29d3c2e9dc9389f524f 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  4444444444444444444444444444444444444444 02de42196ebee42ef284b6780a87cdc96e8eaab6 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

pull over http

  $ hg serve -R main -p $HGPORT -d --pid-file=main.pid -E main-error.log
  $ cat main.pid >> $DAEMON_PIDS

  $ hg -R other pull http://localhost:$HGPORT/ -r 42ccdea3bb16 --bookmark book_42cc
  pulling from http://localhost:$HGPORT/
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  updating bookmark book_42cc
  pre-close-tip:42ccdea3bb16 draft book_42cc
  added 1 changesets with 1 changes to 1 files (+1 heads)
  1 new obsolescence markers
  new changesets 42ccdea3bb16 (1 drafts)
  postclose-tip:42ccdea3bb16 draft book_42cc
  txnclose hook: HG_BOOKMARK_MOVED=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_NODE=42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 HG_NODE_LAST=42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 HG_PHASES_MOVED=1 HG_SOURCE=pull HG_TXNID=TXN:$ID$ HG_TXNNAME=pull
  http://localhost:$HGPORT/ HG_URL=http://localhost:$HGPORT/
  (run 'hg heads .' to see heads, 'hg merge' to merge)
  $ cat main-error.log
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  3333333333333333333333333333333333333333 eea13746799a9e0bfd88f29d3c2e9dc9389f524f 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  4444444444444444444444444444444444444444 02de42196ebee42ef284b6780a87cdc96e8eaab6 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  5555555555555555555555555555555555555555 42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

push over ssh

  $ hg -R main push ssh://user@dummy/other -r 5fddd98957c8 --bookmark book_5fdd
  pushing to ssh://user@dummy/other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: pre-close-tip:5fddd98957c8 draft book_5fdd
  remote: added 1 changesets with 1 changes to 1 files
  remote: 1 new obsolescence markers
  remote: pushkey: lock state after "bookmarks"
  remote: lock:  free
  remote: wlock: free
  remote: postclose-tip:5fddd98957c8 draft book_5fdd
  remote: txnclose hook: HG_BOOKMARK_MOVED=1 HG_BUNDLE2=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_NODE=5fddd98957c8a54a4d436dfe1da9d87f21a1b97b HG_NODE_LAST=5fddd98957c8a54a4d436dfe1da9d87f21a1b97b HG_SOURCE=serve HG_TXNID=TXN:$ID$ HG_TXNNAME=serve HG_URL=remote:ssh:$LOCALIP
  updating bookmark book_5fdd
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_SOURCE=push-response HG_TXNID=TXN:$ID$ HG_TXNNAME=push-response
  ssh://user@dummy/other HG_URL=ssh://user@dummy/other
  $ hg -R other log -G
  o  6:5fddd98957c8 draft Nicolas Dumazet <nicdumz.commits@gmail.com> book_5fdd C
  |
  o  5:42ccdea3bb16 draft Nicolas Dumazet <nicdumz.commits@gmail.com> book_42cc B
  |
  | o  4:02de42196ebe draft Nicolas Dumazet <nicdumz.commits@gmail.com> book_02de H
  | |
  | | o  3:eea13746799a public Nicolas Dumazet <nicdumz.commits@gmail.com> book_eea1 G
  | |/|
  | o |  2:24b6387c8c8c public Nicolas Dumazet <nicdumz.commits@gmail.com>  F
  |/ /
  | @  1:9520eea781bc public Nicolas Dumazet <nicdumz.commits@gmail.com>  E
  |/
  o  0:cd010b8cd998 public Nicolas Dumazet <nicdumz.commits@gmail.com> book_32af A
  
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  3333333333333333333333333333333333333333 eea13746799a9e0bfd88f29d3c2e9dc9389f524f 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  4444444444444444444444444444444444444444 02de42196ebee42ef284b6780a87cdc96e8eaab6 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  5555555555555555555555555555555555555555 42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  6666666666666666666666666666666666666666 5fddd98957c8a54a4d436dfe1da9d87f21a1b97b 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

push over http

  $ hg serve -R other -p $HGPORT2 -d --pid-file=other.pid -E other-error.log
  $ cat other.pid >> $DAEMON_PIDS

  $ hg -R main phase --public 32af7686d403
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_PHASES_MOVED=1 HG_TXNID=TXN:$ID$ HG_TXNNAME=phase
  $ hg -R main push http://localhost:$HGPORT2/ -r 32af7686d403 --bookmark book_32af
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: pre-close-tip:32af7686d403 public book_32af
  remote: added 1 changesets with 1 changes to 1 files
  remote: 1 new obsolescence markers
  remote: pushkey: lock state after "bookmarks"
  remote: lock:  free
  remote: wlock: free
  remote: postclose-tip:32af7686d403 public book_32af
  remote: txnclose hook: HG_BOOKMARK_MOVED=1 HG_BUNDLE2=1 HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_NEW_OBSMARKERS=1 HG_NODE=32af7686d403cf45b5d95f2d70cebea587ac806a HG_NODE_LAST=32af7686d403cf45b5d95f2d70cebea587ac806a HG_PHASES_MOVED=1 HG_SOURCE=serve HG_TXNID=TXN:$ID$ HG_TXNNAME=serve HG_URL=remote:http:$LOCALIP: (glob)
  updating bookmark book_32af
  pre-close-tip:02de42196ebe draft book_02de
  postclose-tip:02de42196ebe draft book_02de
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_SOURCE=push-response HG_TXNID=TXN:$ID$ HG_TXNNAME=push-response
  http://localhost:$HGPORT2/ HG_URL=http://localhost:$HGPORT2/
  $ cat other-error.log

Check final content.

  $ hg -R other log -G
  o  7:32af7686d403 public Nicolas Dumazet <nicdumz.commits@gmail.com> book_32af D
  |
  o  6:5fddd98957c8 public Nicolas Dumazet <nicdumz.commits@gmail.com> book_5fdd C
  |
  o  5:42ccdea3bb16 public Nicolas Dumazet <nicdumz.commits@gmail.com> book_42cc B
  |
  | o  4:02de42196ebe draft Nicolas Dumazet <nicdumz.commits@gmail.com> book_02de H
  | |
  | | o  3:eea13746799a public Nicolas Dumazet <nicdumz.commits@gmail.com> book_eea1 G
  | |/|
  | o |  2:24b6387c8c8c public Nicolas Dumazet <nicdumz.commits@gmail.com>  F
  |/ /
  | @  1:9520eea781bc public Nicolas Dumazet <nicdumz.commits@gmail.com>  E
  |/
  o  0:cd010b8cd998 public Nicolas Dumazet <nicdumz.commits@gmail.com>  A
  
  $ hg -R other debugobsolete
  1111111111111111111111111111111111111111 9520eea781bcca16c1e15acc0ba14335a0e8e5ba 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  2222222222222222222222222222222222222222 24b6387c8c8cae37178880f3fa95ded3cb1cf785 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  3333333333333333333333333333333333333333 eea13746799a9e0bfd88f29d3c2e9dc9389f524f 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  4444444444444444444444444444444444444444 02de42196ebee42ef284b6780a87cdc96e8eaab6 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  5555555555555555555555555555555555555555 42ccdea3bb16d28e1848c95fe2e44c000f3f21b1 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  6666666666666666666666666666666666666666 5fddd98957c8a54a4d436dfe1da9d87f21a1b97b 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  7777777777777777777777777777777777777777 32af7686d403cf45b5d95f2d70cebea587ac806a 0 (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}

(check that no 'pending' files remain)

  $ ls -1 other/.hg/bookmarks*
  other/.hg/bookmarks
  $ ls -1 other/.hg/store/phaseroots*
  other/.hg/store/phaseroots
  $ ls -1 other/.hg/store/00changelog.i*
  other/.hg/store/00changelog.i

Error Handling
==============

Check that errors are properly returned to the client during push.

Setting up

  $ cat > failpush.py << EOF
  > """A small extension that makes push fails when using bundle2
  > 
  > used to test error handling in bundle2
  > """
  > 
  > from mercurial import error
  > from mercurial import bundle2
  > from mercurial import exchange
  > from mercurial import extensions
  > from mercurial import registrar
  > cmdtable = {}
  > command = registrar.command(cmdtable)
  > 
  > configtable = {}
  > configitem = registrar.configitem(configtable)
  > configitem(b'failpush', b'reason',
  >     default=None,
  > )
  > 
  > def _pushbundle2failpart(pushop, bundler):
  >     reason = pushop.ui.config(b'failpush', b'reason')
  >     part = None
  >     if reason == b'abort':
  >         bundler.newpart(b'test:abort')
  >     if reason == b'unknown':
  >         bundler.newpart(b'test:unknown')
  >     if reason == b'race':
  >         # 20 Bytes of crap
  >         bundler.newpart(b'check:heads', data=b'01234567890123456789')
  > 
  > @bundle2.parthandler(b"test:abort")
  > def handleabort(op, part):
  >     raise error.Abort(b'Abandon ship!', hint=b"don't panic")
  > 
  > def uisetup(ui):
  >     exchange.b2partsgenmapping[b'failpart'] = _pushbundle2failpart
  >     exchange.b2partsgenorder.insert(0, b'failpart')
  > 
  > EOF

  $ cd main
  $ hg up tip
  3 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ echo 'I' > I
  $ hg add I
  $ hg ci -m 'I'
  pre-close-tip:e7ec4e813ba6 draft 
  postclose-tip:e7ec4e813ba6 draft 
  txnclose hook: HG_HOOKNAME=txnclose.env HG_HOOKTYPE=txnclose HG_TXNID=TXN:$ID$ HG_TXNNAME=commit
  $ hg id
  e7ec4e813ba6 tip
  $ cd ..

  $ cat << EOF >> $HGRCPATH
  > [extensions]
  > failpush=$TESTTMP/failpush.py
  > EOF

  $ killdaemons.py
  $ hg serve -R other -p $HGPORT2 -d --pid-file=other.pid -E other-error.log
  $ cat other.pid >> $DAEMON_PIDS

Doing the actual push: Abort error

  $ cat << EOF >> $HGRCPATH
  > [failpush]
  > reason = abort
  > EOF

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  abort: Abandon ship!
  (don't panic)
  [255]

  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  remote: Abandon ship!
  remote: (don't panic)
  abort: push failed on remote
  [100]

  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: Abandon ship!
  remote: (don't panic)
  abort: push failed on remote
  [100]


Doing the actual push: unknown mandatory parts

  $ cat << EOF >> $HGRCPATH
  > [failpush]
  > reason = unknown
  > EOF

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  abort: missing support for test:unknown
  [100]

  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  abort: missing support for test:unknown
  [100]

  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  abort: missing support for test:unknown
  [100]

Doing the actual push: race

  $ cat << EOF >> $HGRCPATH
  > [failpush]
  > reason = race
  > EOF

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  abort: push failed:
  'remote repository changed while pushing - please try again'
  [255]

  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  abort: push failed:
  'remote repository changed while pushing - please try again'
  [255]

  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  abort: push failed:
  'remote repository changed while pushing - please try again'
  [255]

Doing the actual push: hook abort

  $ cat << EOF >> $HGRCPATH
  > [failpush]
  > reason =
  > [hooks]
  > pretxnclose.failpush = sh -c "echo 'You shall not pass!'; false"
  > txnabort.failpush = sh -c "echo 'Cleaning up the mess...'"
  > EOF

  $ killdaemons.py
  $ hg serve -R other -p $HGPORT2 -d --pid-file=other.pid -E other-error.log
  $ cat other.pid >> $DAEMON_PIDS

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: pre-close-tip:e7ec4e813ba6 draft 
  remote: You shall not pass!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  abort: pretxnclose.failpush hook exited with status 1
  [40]

  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: pre-close-tip:e7ec4e813ba6 draft 
  remote: You shall not pass!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pretxnclose.failpush hook exited with status 1
  abort: push failed on remote
  [100]

  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: pre-close-tip:e7ec4e813ba6 draft 
  remote: You shall not pass!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pretxnclose.failpush hook exited with status 1
  abort: push failed on remote
  [100]

(check that no 'pending' files remain)

  $ ls -1 other/.hg/bookmarks*
  other/.hg/bookmarks
  $ ls -1 other/.hg/store/phaseroots*
  other/.hg/store/phaseroots
  $ ls -1 other/.hg/store/00changelog.i*
  other/.hg/store/00changelog.i

Check error from hook during the unbundling process itself

  $ cat << EOF >> $HGRCPATH
  > pretxnchangegroup = sh -c "echo 'Fail early!'; false"
  > EOF
  $ killdaemons.py # reload http config
  $ hg serve -R other -p $HGPORT2 -d --pid-file=other.pid -E other-error.log
  $ cat other.pid >> $DAEMON_PIDS

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: Fail early!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  abort: pretxnchangegroup hook exited with status 1
  [40]
  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: Fail early!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pretxnchangegroup hook exited with status 1
  abort: push failed on remote
  [100]
  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: Fail early!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pretxnchangegroup hook exited with status 1
  abort: push failed on remote
  [100]

Check output capture control.

(should be still forced for http, disabled for local and ssh)

  $ cat >> $HGRCPATH << EOF
  > [experimental]
  > bundle2-output-capture=False
  > EOF

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  Fail early!
  transaction abort!
  Cleaning up the mess...
  rollback completed
  abort: pretxnchangegroup hook exited with status 1
  [40]
  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: Fail early!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pretxnchangegroup hook exited with status 1
  abort: push failed on remote
  [100]
  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: Fail early!
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pretxnchangegroup hook exited with status 1
  abort: push failed on remote
  [100]

Check abort from mandatory pushkey

  $ cat > mandatorypart.py << EOF
  > from mercurial import exchange
  > from mercurial import pushkey
  > from mercurial import node
  > from mercurial import error
  > @exchange.b2partsgenerator(b'failingpuskey')
  > def addfailingpushey(pushop, bundler):
  >     enc = pushkey.encode
  >     part = bundler.newpart(b'pushkey')
  >     part.addparam(b'namespace', enc(b'phases'))
  >     part.addparam(b'key', enc(b'cd010b8cd998f3981a5a8115f94f8da4ab506089'))
  >     part.addparam(b'old', enc(b'0')) # successful update
  >     part.addparam(b'new', enc(b'0'))
  >     def fail(pushop, exc):
  >         raise error.Abort(b'Correct phase push failed (because hooks)')
  >     pushop.pkfailcb[part.id] = fail
  > EOF
  $ cat >> $HGRCPATH << EOF
  > [hooks]
  > pretxnchangegroup=
  > pretxnclose.failpush=
  > prepushkey.failpush = sh -c "echo 'do not push the key !'; false"
  > [extensions]
  > mandatorypart=$TESTTMP/mandatorypart.py
  > EOF
  $ "$TESTDIR/killdaemons.py" $DAEMON_PIDS # reload http config
  $ hg serve -R other -p $HGPORT2 -d --pid-file=other.pid -E other-error.log
  $ cat other.pid >> $DAEMON_PIDS

(Failure from a hook)

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  do not push the key !
  pushkey-abort: prepushkey.failpush hook exited with status 1
  transaction abort!
  Cleaning up the mess...
  rollback completed
  abort: Correct phase push failed (because hooks)
  [255]
  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: do not push the key !
  remote: pushkey-abort: prepushkey.failpush hook exited with status 1
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  abort: Correct phase push failed (because hooks)
  [255]
  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: do not push the key !
  remote: pushkey-abort: prepushkey.failpush hook exited with status 1
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  abort: Correct phase push failed (because hooks)
  [255]

(Failure from a the pushkey)

  $ cat > mandatorypart.py << EOF
  > from mercurial import exchange
  > from mercurial import pushkey
  > from mercurial import node
  > from mercurial import error
  > @exchange.b2partsgenerator(b'failingpuskey')
  > def addfailingpushey(pushop, bundler):
  >     enc = pushkey.encode
  >     part = bundler.newpart(b'pushkey')
  >     part.addparam(b'namespace', enc(b'phases'))
  >     part.addparam(b'key', enc(b'cd010b8cd998f3981a5a8115f94f8da4ab506089'))
  >     part.addparam(b'old', enc(b'4')) # will fail
  >     part.addparam(b'new', enc(b'3'))
  >     def fail(pushop, exc):
  >         raise error.Abort(b'Clown phase push failed')
  >     pushop.pkfailcb[part.id] = fail
  > EOF
  $ cat >> $HGRCPATH << EOF
  > [hooks]
  > prepushkey.failpush =
  > EOF
  $ "$TESTDIR/killdaemons.py" $DAEMON_PIDS # reload http config
  $ hg serve -R other -p $HGPORT2 -d --pid-file=other.pid -E other-error.log
  $ cat other.pid >> $DAEMON_PIDS

  $ hg -R main push other -r e7ec4e813ba6
  pushing to other
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  transaction abort!
  Cleaning up the mess...
  rollback completed
  pushkey: lock state after "phases"
  lock:  free
  wlock: free
  abort: Clown phase push failed
  [255]
  $ hg -R main push ssh://user@dummy/other -r e7ec4e813ba6
  pushing to ssh://user@dummy/other
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pushkey: lock state after "phases"
  remote: lock:  free
  remote: wlock: free
  abort: Clown phase push failed
  [255]
  $ hg -R main push http://localhost:$HGPORT2/ -r e7ec4e813ba6
  pushing to http://localhost:$HGPORT2/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: transaction abort!
  remote: Cleaning up the mess...
  remote: rollback completed
  remote: pushkey: lock state after "phases"
  remote: lock:  free
  remote: wlock: free
  abort: Clown phase push failed
  [255]

Test lazily acquiring the lock during unbundle
  $ cp $TESTTMP/hgrc.orig $HGRCPATH

  $ cat >> $TESTTMP/locktester.py <<EOF
  > import os
  > from mercurial import bundle2, error, extensions
  > def checklock(orig, repo, *args, **kwargs):
  >     if repo.svfs.lexists(b"lock"):
  >         raise error.Abort(b"Lock should not be taken")
  >     return orig(repo, *args, **kwargs)
  > def extsetup(ui):
  >    extensions.wrapfunction(bundle2, 'processbundle', checklock)
  > EOF

  $ hg init lazylock
  $ cat >> lazylock/.hg/hgrc <<EOF
  > [extensions]
  > locktester=$TESTTMP/locktester.py
  > EOF

  $ hg clone -q ssh://user@dummy/lazylock lazylockclient
  $ cd lazylockclient
  $ touch a && hg ci -Aqm a
  $ hg push
  pushing to ssh://user@dummy/lazylock
  searching for changes
  remote: Lock should not be taken
  abort: push failed on remote
  [100]

  $ cat >> ../lazylock/.hg/hgrc <<EOF
  > [experimental]
  > bundle2lazylocking=True
  > EOF
  $ hg push
  pushing to ssh://user@dummy/lazylock
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files

  $ cd ..

Servers can disable bundle1 for clone/pull operations

  $ killdaemons.py
  $ hg init bundle2onlyserver
  $ cd bundle2onlyserver
  $ cat > .hg/hgrc << EOF
  > [server]
  > bundle1.pull = false
  > EOF

  $ touch foo
  $ hg -q commit -A -m initial

  $ hg serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS

  $ hg --config devel.legacy.exchange=bundle1 clone http://localhost:$HGPORT/ not-bundle2
  requesting all changes
  abort: remote error:
  incompatible Mercurial client; bundle2 required
  (see https://www.mercurial-scm.org/wiki/IncompatibleClient)
  [100]
  $ killdaemons.py
  $ cd ..

bundle1 can still pull non-generaldelta repos when generaldelta bundle1 disabled

  $ hg --config format.usegeneraldelta=false init notgdserver
  $ cd notgdserver
  $ cat > .hg/hgrc << EOF
  > [server]
  > bundle1gd.pull = false
  > EOF

  $ touch foo
  $ hg -q commit -A -m initial
  $ hg serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS

  $ hg --config devel.legacy.exchange=bundle1 clone http://localhost:$HGPORT/ not-bundle2-1
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 96ee1d7354c4
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ killdaemons.py
  $ cd ../bundle2onlyserver

bundle1 pull can be disabled for generaldelta repos only

  $ cat > .hg/hgrc << EOF
  > [server]
  > bundle1gd.pull = false
  > EOF

  $ hg serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS
  $ hg --config devel.legacy.exchange=bundle1 clone http://localhost:$HGPORT/ not-bundle2
  requesting all changes
  abort: remote error:
  incompatible Mercurial client; bundle2 required
  (see https://www.mercurial-scm.org/wiki/IncompatibleClient)
  [100]

  $ killdaemons.py

Verify the global server.bundle1 option works

  $ cd ..
  $ cat > bundle2onlyserver/.hg/hgrc << EOF
  > [server]
  > bundle1 = false
  > EOF
  $ hg serve -R bundle2onlyserver -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS
  $ hg --config devel.legacy.exchange=bundle1 clone http://localhost:$HGPORT not-bundle2
  requesting all changes
  abort: remote error:
  incompatible Mercurial client; bundle2 required
  (see https://www.mercurial-scm.org/wiki/IncompatibleClient)
  [100]
  $ killdaemons.py

  $ hg --config devel.legacy.exchange=bundle1 clone ssh://user@dummy/bundle2onlyserver not-bundle2-ssh
  requesting all changes
  adding changesets
  remote: abort: incompatible Mercurial client; bundle2 required
  remote: (see https://www.mercurial-scm.org/wiki/IncompatibleClient)
  transaction abort!
  rollback completed
  abort: stream ended unexpectedly (got 0 bytes, expected 4)
  [255]

  $ cat > bundle2onlyserver/.hg/hgrc << EOF
  > [server]
  > bundle1gd = false
  > EOF
  $ hg serve -R bundle2onlyserver -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS

  $ hg --config devel.legacy.exchange=bundle1 clone http://localhost:$HGPORT/ not-bundle2
  requesting all changes
  abort: remote error:
  incompatible Mercurial client; bundle2 required
  (see https://www.mercurial-scm.org/wiki/IncompatibleClient)
  [100]

  $ killdaemons.py

  $ cd notgdserver
  $ cat > .hg/hgrc << EOF
  > [server]
  > bundle1gd = false
  > EOF
  $ hg serve -p $HGPORT -d --pid-file=hg.pid
  $ cat hg.pid >> $DAEMON_PIDS

  $ hg --config devel.legacy.exchange=bundle1 clone http://localhost:$HGPORT/ not-bundle2-2
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 96ee1d7354c4
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ killdaemons.py
  $ cd ../bundle2onlyserver

Verify bundle1 pushes can be disabled

  $ cat > .hg/hgrc << EOF
  > [server]
  > bundle1.push = false
  > [web]
  > allow_push = *
  > push_ssl = false
  > EOF

  $ hg serve -p $HGPORT -d --pid-file=hg.pid -E error.log
  $ cat hg.pid >> $DAEMON_PIDS
  $ cd ..

  $ hg clone http://localhost:$HGPORT bundle2-only
  requesting all changes
  adding changesets
  adding manifests
  adding file changes
  added 1 changesets with 1 changes to 1 files
  new changesets 96ee1d7354c4
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd bundle2-only
  $ echo commit > foo
  $ hg commit -m commit
  $ hg --config devel.legacy.exchange=bundle1 push
  pushing to http://localhost:$HGPORT/
  searching for changes
  abort: remote error:
  incompatible Mercurial client; bundle2 required
  (see https://www.mercurial-scm.org/wiki/IncompatibleClient)
  [100]

(also check with ssh)

  $ hg --config devel.legacy.exchange=bundle1 push ssh://user@dummy/bundle2onlyserver
  pushing to ssh://user@dummy/bundle2onlyserver
  searching for changes
  remote: abort: incompatible Mercurial client; bundle2 required
  remote: (see https://www.mercurial-scm.org/wiki/IncompatibleClient)
  [1]

  $ hg push
  pushing to http://localhost:$HGPORT/
  searching for changes
  remote: adding changesets
  remote: adding manifests
  remote: adding file changes
  remote: added 1 changesets with 1 changes to 1 files
