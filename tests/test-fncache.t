  $ hg verify -q
  checking dirstate
  $ hg verify -q
  .hg/branch
  .hg/undo.backup.branch.bck
  .hg/branch
  .hg/store/requires
  .hg/undo.backup.branch.bck
  > import signal
  >         os.kill(os.getpid(), signal.SIGKILL)
# Cannot rely on the return code value as chg use a different one.
# So we use a `|| echo` trick
# XXX-CHG fixing chg behavior would be nice here.
  $ hg ci -qAm z || echo "He's Dead, Jim." 2>/dev/null
  *Killed* (glob) (?)
  He's Dead, Jim.
  checking dirstate
  fncache load triggered!