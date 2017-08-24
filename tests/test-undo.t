  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > undo = $TESTDIR/../hgext3rd/undo.py
  > inhibit=$TESTDIR/../hgext3rd/inhibit.py
  > [undo]
  > _duringundologlock=1
  > [experimental]
  > evolution=createmarkers
  > [ui]
  > interactive = true
  > EOF

Build up a repo

  $ hg init repo
  $ cd repo

Test data store

  $ hg book master
  $ touch a1 && hg add a1 && hg ci -ma1
  $ touch a2 && hg add a2 && hg ci -ma2
  $ hg book feature1
  $ touch b && hg add b && hg ci -mb
  $ hg up -q master
  $ touch c1 && hg add c1 && hg ci -mc1
  created new head
  $ touch c2 && hg add c2 && hg ci -mc2
  $ hg book feature2
  $ touch d && hg add d && hg ci -md
  $ hg debugindex .hg/undolog/command.i
     rev    offset  length   base linkrev nodeid       p1           p2
       0         0       0      0       1 b80de5d13875 000000000000 000000000000
       1         0      22      1       1 bae41a9d0ae9 000000000000 000000000000
       2        22      15      2       1 6086ecd42962 000000000000 000000000000
       3        37      15      3       1 5cc3b22d9c65 000000000000 000000000000
       4        52      24      4       1 efaf8be657bb 000000000000 000000000000
       5        76      14      5       1 fe69d6bf5432 000000000000 000000000000
       6        90      20      6       1 720b2d7eb02b 000000000000 000000000000
       7       110      15      7       1 0595892db30f 000000000000 000000000000
       8       125      15      8       1 c8265ade52fa 000000000000 000000000000
       9       140      24      9       1 0d8f98a931b9 000000000000 000000000000
      10       164      14     10       1 fded10d93e92 000000000000 000000000000
  $ hg debugdata .hg/undolog/command.i 0
  $ hg debugdata .hg/undolog/command.i 1
  bookmarks\x00book\x00master (no-eol) (esc)
  $ hg debugdata .hg/undolog/command.i 2
  commit\x00ci\x00-ma1 (no-eol) (esc)
  $ hg debugdata .hg/undolog/command.i 3
  commit\x00ci\x00-ma2 (no-eol) (esc)
  $ hg debugdata .hg/undolog/bookmarks.i 0
  $ hg debugdata .hg/undolog/bookmarks.i 1
  master 0000000000000000000000000000000000000000 (no-eol)
  $ hg debugdata .hg/undolog/bookmarks.i 2
  master df4fd610a3d6ca792281e7576587fa18f940d37a (no-eol)
  $ hg debugdata .hg/undolog/workingparent.i 0
  0000000000000000000000000000000000000000 (no-eol)
  $ hg debugdata .hg/undolog/workingparent.i 1
  df4fd610a3d6ca792281e7576587fa18f940d37a (no-eol)
  $ hg debugdata .hg/undolog/draftheads.i 1
  df4fd610a3d6ca792281e7576587fa18f940d37a (no-eol)
  $ hg debugdata .hg/undolog/draftheads.i 2
  b68836a6e2cac33ba33a20249b85a486eec78186 (no-eol)
  $ hg debugdata .hg/undolog/index.i 1
  bookmarks 8153d44860d076e9c328951c8f36cf8daebe695a
  command bae41a9d0ae9614fc3aa843a0f5cbdf47bc98c43
  date * (glob)
  draftheads b80de5d138758541c5f05265ad144ab9fa86d1db
  draftobsolete b80de5d138758541c5f05265ad144ab9fa86d1db
  unfinished False
  workingparent fcb754f6a51eaf982f66d0637b39f3d2e6b520d5 (no-eol)
  $ touch a3 && hg add a3
  $ hg commit --amend
  $ hg debugdata .hg/undolog/command.i 11
  commit\x00commit\x00--amend (no-eol) (esc)

Test debugundohistory
  $ hg debugundohistory -l
  0: commit --amend
  1: ci -md
  2: book feature2
  3: ci -mc2
  4: ci -mc1
  $ hg update master
  0 files updated, 0 files merged, 2 files removed, 0 files unresolved
  (activating bookmark master)
  $ echo "test" >> a1
  $ hg commit -m "words"
  created new head
  $ hg debugundohistory -l
  0: commit -m words
  1: update master
  2: commit --amend
  3: ci -md
  4: book feature2
  $ hg debugundohistory -n 0
  command:
  	commit -m words
  bookmarks:
  	feature1 49cdb4091aca3c09f402ff001cd20cf086873683
  	feature2 296fda51a303650465d07a1cd054075cbe6d3cbd
  	master 0a3dd3e15e65b90836f492112d816f3ee073d897
  date:
  	* (glob)
  draftheads:
  	ADDED:
  		0a3dd3e15e65b90836f492112d816f3ee073d897
  	REMOVED:
  	
  draftobsolete:
  
  unfinished:	False

Test gap in data (extension dis and enabled)
  $ hg debugundohistory -l
  0: commit -m words
  1: update master
  2: commit --amend
  3: ci -md
  4: book feature2
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > undo =!
  > EOF
  $ touch cmiss && hg add cmiss && hg ci -mcmiss
  $ cat >>$HGRCPATH <<EOF
  > [extensions]
  > undo = $TESTDIR/../hgext3rd/undo.py
  > EOF
  $ touch a5 && hg add a5 && hg ci -ma5
  $ hg debugundohistory -l
  0: ci -ma5
  1:  -- gap in log -- 
  2: commit -m words
  3: update master
  4: commit --amend
  $ hg debugundohistory 1
  command:
  	unkown command(s) run, gap in log
  bookmarks:
  	feature1 49cdb4091aca3c09f402ff001cd20cf086873683
  	feature2 296fda51a303650465d07a1cd054075cbe6d3cbd
  	master 1dafc0b436123cab96f82a8e9e8d1d42c0301aaa
  date:
  	* (glob)
  draftheads:
  	ADDED:
  		1dafc0b436123cab96f82a8e9e8d1d42c0301aaa
  	REMOVED:
  		0a3dd3e15e65b90836f492112d816f3ee073d897
  draftobsolete:
  
  unfinished:	False

Index out of bound error
  $ hg debugundohistory -n 50
  abort: index out of bounds
  [255]

Revset tests
  $ hg log -G -r 'draft()' --hidden > /dev/null
  $ hg debugundohistory -n 0
  command:
  	ci -ma5
  bookmarks:
  	feature1 49cdb4091aca3c09f402ff001cd20cf086873683
  	feature2 296fda51a303650465d07a1cd054075cbe6d3cbd
  	master aa430c8afedf9b2ec3f0655d39eef6b6b0a2ddb6
  date:
  	* (glob)
  draftheads:
  	ADDED:
  		aa430c8afedf9b2ec3f0655d39eef6b6b0a2ddb6
  	REMOVED:
  		1dafc0b436123cab96f82a8e9e8d1d42c0301aaa
  draftobsolete:
  
  unfinished:	False

Test 'olddraft([NUM])' revset
  $ hg log -G -r 'olddraft(0) - olddraft(1)' --hidden -T compact
  @  10[tip][master]   aa430c8afedf   1970-01-01 00:00 +0000   test
  |    a5
  ~
  $ hg log -G -r 'olddraft(1) and draft()' -T compact
  o  9   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  |
  o  8:4   0a3dd3e15e65   1970-01-01 00:00 +0000   test
  |    words
  |
  | o  7[feature2]:4   296fda51a303   1970-01-01 00:00 +0000   test
  |/     d
  |
  o  4   38d85b506754   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  3:1   ec7553f7b382   1970-01-01 00:00 +0000   test
  |    c1
  |
  | o  2[feature1]   49cdb4091aca   1970-01-01 00:00 +0000   test
  |/     b
  |
  o  1   b68836a6e2ca   1970-01-01 00:00 +0000   test
  |    a2
  |
  o  0   df4fd610a3d6   1970-01-01 00:00 +0000   test
       a1
  
  $ hg log -G -r 'olddraft(1) and public()' -T compact

Test undolog lock
  $ hg log --config hooks.duringundologlock="sleep 1" > /dev/null &
  $ sleep 0.1
  $ hg st --time
  time: real [1-9]*\..* (re)

hg undo command tests
  $ hg undo
  undone to *, before ci -ma5 (glob)
  $ hg log -G -T compact -l2
  @  9[tip][master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  |
  o  8:4   0a3dd3e15e65   1970-01-01 00:00 +0000   test
  |    words
  ~
  $ hg update 0a3dd3e15e65
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (leaving bookmark master)
  $ hg undo
  undone to *, before update 0a3dd3e15e65 (glob)
  $ hg log -G -T compact -l1
  @  9[tip][master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ touch c11 && hg add c11
  $ hg commit --amend
  $ hg log -G -T compact -l1
  @  12[tip][master]:8   2dca609174c2   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ hg undo
  undone to *, before commit --amend (glob)
  $ hg log -G -T compact -l4
  @  9[tip][master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  |
  o  8:4   0a3dd3e15e65   1970-01-01 00:00 +0000   test
  |    words
  |
  | o  7[feature2]:4   296fda51a303   1970-01-01 00:00 +0000   test
  |/     d
  |
  o  4   38d85b506754   1970-01-01 00:00 +0000   test
  |    c2
  ~
  $ hg graft 296fda51a303
  grafting 7:296fda51a303 "d" (feature2)
  $ hg log -G -T compact -l2
  @  13[tip]:9   f007a7cf4c3d   1970-01-01 00:00 +0000   test
  |    d
  |
  o  9[master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ hg undo
  undone to *, before graft 296fda51a303 (glob)
  $ hg log -G -T compact -l1
  @  9[tip][master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ hg book test
  $ hg undo
  undone to *, before book test (glob)
  $ hg bookmarks
     feature1                  2:49cdb4091aca
     feature2                  7:296fda51a303
     master                    9:1dafc0b43612

hg undo with negative step
  $ hg undo -n -1
  undone to *, before undo (glob)
  $ hg log -G -T compact -l1
  @  9[tip][master,test]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ hg undo
  undone to *, before book test (glob)
  $ hg log -G -T compact -l1
  @  9[tip][master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ hg undo -n 5
  undone to *, before undo (glob)
  $ hg undo -n -5
  undone to *, before book test (glob)
  $ hg log -G -T compact -l1
  @  9[tip][master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ hg undo -n -100
  abort: cannot undo this far - undo extension was not enabled
  [255]

hg undo --absolute tests
  $ hg undo -a
  undone to *, before undo -n -5 (glob)
  $ hg undo -n -1
  undone to *, before undo -a (glob)
  $ hg undo -a
  undone to *, before undo -n -1 (glob)
  $ hg undo -n -1
  undone to *, before undo -a (glob)
  $ hg undo -n 5
  undone to *, before undo (glob)
  $ hg log -G -T compact -l1
  @  9[tip][master,test]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~
  $ hg undo -a
  undone to *, before undo -n 5 (glob)
  $ hg log -G -T compact -l1
  @  9[tip][master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  ~

hg undo --force tests
  $ hg debugundohistory -l 18
  18: undo
  19: ci -ma5
  20:  -- gap in log -- 
  21: commit -m words
  22: update master
  $ hg undo -a -n 25
  abort: attempted risky undo across missing history
  [255]
  $ hg undo -a -n 25 -f
  undone to *, before ci -md (glob)
  $ hg undo -a
  undone to *, before undo -a -n 25 -f (glob)

hg undo --keep tests
  $ touch kfl1 && hg add kfl1
  $ hg st
  A kfl1
  $ hg commit --amend
  $ hg st
  $ hg undo --keep
  undone to *, before commit --amend (glob)
  $ hg st
  A kfl1
  $ hg commit --amend

hg undo informative obsmarkers
check 1 to 1 undos have informative obsmarker
check 1 to many undos (generally a redo of split or divergence) do not connect
the changesets with obsmarkers as we do not differentiate between split and
divergence cases in undo.  The original split/divergence obsmarkers suffice for
checking split/divergence.
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > smartlog = $TESTDIR/../hgext3rd/smartlog.py
  > tweakdefaults = $TESTDIR/../hgext3rd/tweakdefaults.py
  > fbamend = $TESTDIR/../hgext3rd/fbamend/
  > EOF
  $ hg undo
  undone to *, before commit --amend (glob)
  $ hg sl --all --hidden -T "{node|short} {if(undosuccessors, label('sl.undo', '(Undone as {join(undosuccessors% \'{shortest(undosuccessor, 6)}\', ', ')})'))}"
  x  db3723da827c
  |
  | x  f007a7cf4c3d
  |/
  | x  128fe7e6098d
  |/
  | x  aa430c8afedf
  |/
  @  1dafc0b43612
  :
  : x  c9476255bc2a (Undone as 1dafc0)
  :/
  : x  2dca609174c2
  :/
  : o  296fda51a303
  :/
  : x  551c0e5b57c9
  : |
  : x  db92053d5c83
  :/
  : o  49cdb4091aca
  :/
  o  b68836a6e2ca
  |
  ~
  $ echo "a" >> newa && echo "b" >> newb && hg add newa newb && hg ci -m "newfiles"
  $ hg split --quiet << EOF
  > y
  > y
  > n
  > y
  > EOF
  diff --git a/newa b/newa
  new file mode 100644
  examine changes to 'newa'? [Ynesfdaq?] y
  
  @@ -0,0 +1,1 @@
  +a
  record change 1/2 to 'newa'? [Ynesfdaq?] y
  
  diff --git a/newb b/newb
  new file mode 100644
  examine changes to 'newb'? [Ynesfdaq?] n
  
  Done splitting? [yN] y
  $ hg debugobsolete | tail -5
  db3723da827c373768d500ab4e3a9c59a78314a6 0 {1dafc0b436123cab96f82a8e9e8d1d42c0301aaa} (Thu Jan 01 00:00:00 1970 +0000) {'user': 'test'}
  c9476255bc2a68672c844021397838ff4eeefcda 1dafc0b436123cab96f82a8e9e8d1d42c0301aaa 0 (Thu Jan 01 00:00:04 1970 +0000) {'user': 'test'}
  1dafc0b436123cab96f82a8e9e8d1d42c0301aaa c9476255bc2a68672c844021397838ff4eeefcda 0 (Thu Jan 01 00:00:05 1970 +0000) {'user': 'test'}
  c9476255bc2a68672c844021397838ff4eeefcda 1dafc0b436123cab96f82a8e9e8d1d42c0301aaa 0 (Thu Jan 01 00:00:06 1970 +0000) {'operation': 'undo', 'user': 'test'}
  f86734247df6db66a810e549cc938a72cd5c6d1a d0fdb9510dbf78c1a7e62c3e6628ff1f978f87ea 75f63379f12bf02d40fe7444587ad67be9ae81b8 0 (Thu Jan 01 00:00:00 1970 +0000) {'operation': 'split', 'user': 'test'}
  $ hg undo
  undone to *, before split --quiet (glob)
  $ hg undo -n -1
  undone to *, before undo (glob)
  $ hg debugobsolete | tail -5
  d0fdb9510dbf78c1a7e62c3e6628ff1f978f87ea f86734247df6db66a810e549cc938a72cd5c6d1a 0 (Thu Jan 01 00:00:01 1970 +0000) {'operation': 'undo', 'user': 'test'}
  75f63379f12bf02d40fe7444587ad67be9ae81b8 0 {d0fdb9510dbf78c1a7e62c3e6628ff1f978f87ea} (Thu Jan 01 00:00:01 1970 +0000) {'operation': 'undo', 'user': 'test'}
  f86734247df6db66a810e549cc938a72cd5c6d1a 0 {1dafc0b436123cab96f82a8e9e8d1d42c0301aaa} (Thu Jan 01 00:00:02 1970 +0000) {'operation': 'undo', 'user': 'test'}
  d0fdb9510dbf78c1a7e62c3e6628ff1f978f87ea d0fdb9510dbf78c1a7e62c3e6628ff1f978f87ea 0 (Thu Jan 01 00:00:01 1970 +0000) {'operation': 'revive', 'user': 'test'}
  75f63379f12bf02d40fe7444587ad67be9ae81b8 75f63379f12bf02d40fe7444587ad67be9ae81b8 0 (Thu Jan 01 00:00:01 1970 +0000) {'operation': 'revive', 'user': 'test'}
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > smartlog =!
  > tweakdefaults =!
  > fbamend =!
  > EOF

File corruption handling
  $ echo 111corruptedrevlog > .hg/undolog/index.i
#if chg
(note: chg has issues with the below test)
#else
  $ hg st --debug
  caught revlog error. undolog/index.i was probably corrupted
#endif
  $ hg debugundohistory -l
  0:  -- gap in log -- 

_localbranch revset tests
  $ hg log -r '_localbranch(75f63379f12b)'
  changeset:   0:df4fd610a3d6
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     a1
  
  changeset:   1:b68836a6e2ca
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     a2
  
  changeset:   2:49cdb4091aca
  bookmark:    feature1
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     b
  
  changeset:   3:ec7553f7b382
  parent:      1:b68836a6e2ca
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     c1
  
  changeset:   4:38d85b506754
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     c2
  
  changeset:   7:296fda51a303
  bookmark:    feature2
  parent:      4:38d85b506754
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     d
  
  changeset:   8:0a3dd3e15e65
  parent:      4:38d85b506754
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     words
  
  changeset:   9:1dafc0b43612
  bookmark:    master
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     cmiss
  
  changeset:   17:d0fdb9510dbf
  parent:      9:1dafc0b43612
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
  changeset:   18:75f63379f12b
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
Test with public commit
  $ hg phase -r 0a3dd3e15e65 -p
  $ hg log -r '_localbranch(75f63379f12b)'
  changeset:   9:1dafc0b43612
  bookmark:    master
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     cmiss
  
  changeset:   17:d0fdb9510dbf
  parent:      9:1dafc0b43612
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
  changeset:   18:75f63379f12b
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
  $ hg log -r '_localbranch(0a3dd3e15e65)'
  changeset:   9:1dafc0b43612
  bookmark:    master
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     cmiss
  
  changeset:   17:d0fdb9510dbf
  parent:      9:1dafc0b43612
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
  changeset:   18:75f63379f12b
  tag:         tip
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  

localbranch undos
Make changes on two branches (old and new)
Undo only changes in one branch (old)
Includes commit and book changes
  $ hg book "oldbook"
  $ touch oldbranch
  $ hg add oldbranch && hg ci -moldbranch
  $ hg update null
  0 files updated, 0 files merged, 8 files removed, 0 files unresolved
  (leaving bookmark oldbook)
  $ touch newbranch
  $ hg add newbranch && hg ci -mnewbranch
  created new head
  $ hg book "newbook"
  $ hg log -l 2
  changeset:   20:805791ba4bcd
  bookmark:    newbook
  tag:         tip
  parent:      -1:000000000000
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newbranch
  
  changeset:   19:7b0ef4f2a1ae
  bookmark:    oldbook
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     oldbranch
  
  $ hg up 75f63379f12b
  7 files updated, 0 files merged, 1 files removed, 0 files unresolved
  (leaving bookmark newbook)
3 changes within local scope: commit, book, update
  $ hg undo -b 75f63379f12b
  undone to *, before update null (glob)
  $ hg undo -b 75f63379f12b
  undone to *, before ci -moldbranch (glob)
  $ hg undo -b 75f63379f12b
  undone to *, before book oldbook (glob)
  $ hg log -l 2
  changeset:   20:805791ba4bcd
  bookmark:    newbook
  tag:         tip
  parent:      -1:000000000000
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newbranch
  
  changeset:   18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
Check rebase local undos of rebases
Make sure bookmarks and commits are not lost
and commits are not duplicated
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase =
  > EOF
  $ hg rebase -s 8057 -d 75f6
  rebasing 20:805791ba4bcd "newbranch" (tip newbook)
  $ hg log -l 2
  changeset:   21:35324a911c0d
  bookmark:    newbook
  tag:         tip
  parent:      18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newbranch
  
  changeset:   18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
  $ hg undo -b 3532
  undone to *, before rebase -s 8057 -d 75f6 (glob)
  $ hg log -l 2
  changeset:   20:805791ba4bcd
  bookmark:    newbook
  tag:         tip
  parent:      -1:000000000000
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newbranch
  
  changeset:   18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase = !
  > EOF

Check local undo works forward
  $ hg undo -n -1 -b 3532
  undone to *, before undo -b 3532 (glob)
  $ hg log -l 2
  changeset:   21:35324a911c0d
  bookmark:    newbook
  tag:         tip
  parent:      18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newbranch
  
  changeset:   18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newfiles
  
  $ touch a9 && hg add a9 && hg ci -m a9
  created new head
  $ hg log -r . -T {node}
  3ee6a6880888df9e48cdc568b5e835bd3087f8cb (no-eol)
  $ hg undo -b 3532
  undone to *, before ci -m a9 (glob)
  $ hg undo -b 3532
  undone to *, before undo -n -1 -b 3532 (glob)
  $ hg undo -n -1 -b 75f6
  undone to *, before ci -m a9 (glob)
  $ hg undo -n -1 -b 75f6
  undone to *, before undo -b 3532 (glob)
  $ hg log -l 2
  changeset:   22:3ee6a6880888
  tag:         tip
  parent:      18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     a9
  
  changeset:   21:35324a911c0d
  bookmark:    newbook
  parent:      18:75f63379f12b
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     newbranch
  
Check local undo with facebook style strip
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > strip =
  > fbamend = $TESTDIR/../hgext3rd/fbamend/
  > EOF
  $ hg strip 3ee6
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  working directory now at 75f63379f12b
  1 changesets pruned
  $ hg undo -b 3532
  undone to *, before strip 3ee6 (glob)
  $ hg log -r . -T {node}
  3ee6a6880888df9e48cdc568b5e835bd3087f8cb (no-eol)
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > strip =!
  > fbamend =!
  > EOF

hg undo --preview test
  $ touch prev1 && hg add prev1 && hg ci -m prev1
  $ cat >> $HGRCPATH <<EOF
  > [templatealias]
  > undopreview = '{if(undonecommits(UNDOINDEX), "Undone")}'
  > EOF
  $ hg undo -p
  @  Undone
  |
  o
  |
  o
  |
  o
  |
  o
  :
  o
  |
  ~
  undo to *, before ci -m prev1 (glob)
  $ hg undo -p -n 2
  @  Undone
  |
  o  Undone
  |
  o
  |
  o
  |
  o
  :
  o
  |
  ~
  undo to *, before undo -b 3532 (glob)

hg redo tests
  $ hg log -G -T compact
  @  23[tip]   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  |
  o  22:18   3ee6a6880888   1970-01-01 00:00 +0000   test
  |    a9
  |
  | o  21[newbook]:18   35324a911c0d   1970-01-01 00:00 +0000   test
  |/     newbranch
  |
  o  18   75f63379f12b   1970-01-01 00:00 +0000   test
  |    newfiles
  |
  o  17:9   d0fdb9510dbf   1970-01-01 00:00 +0000   test
  |    newfiles
  |
  o  9[master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  |
  o  8:4   0a3dd3e15e65   1970-01-01 00:00 +0000   test
  |    words
  |
  | o  7[feature2]:4   296fda51a303   1970-01-01 00:00 +0000   test
  |/     d
  |
  o  4   38d85b506754   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  3:1   ec7553f7b382   1970-01-01 00:00 +0000   test
  |    c1
  |
  | o  2[feature1]   49cdb4091aca   1970-01-01 00:00 +0000   test
  |/     b
  |
  o  1   b68836a6e2ca   1970-01-01 00:00 +0000   test
  |    a2
  |
  o  0   df4fd610a3d6   1970-01-01 00:00 +0000   test
       a1
  
  $ hg log -r . -T {node}
  a0b72b3048d6d07b35b1d79c8e5c46b159d21cc9 (no-eol)
  $ hg undo -n 2
  undone to *, before undo -b 3532 (glob)
  $ hg redo
  undone to *, before undo -n 2 (glob)
  $ hg log -r . -T {node}
  a0b72b3048d6d07b35b1d79c8e5c46b159d21cc9 (no-eol)
  $ hg undo
  undone to *, before ci -m prev1 (glob)
  $ hg undo
  undone to *, before undo -b 3532 (glob)
  $ hg log -r . -T {node}
  75f63379f12bf02d40fe7444587ad67be9ae81b8 (no-eol)
  $ hg undo -n 1
  undone to *, before strip 3ee6 (glob)
  $ hg redo
  undone to *, before undo -n 1 (glob)
  $ hg log -r . -T {node}
  75f63379f12bf02d40fe7444587ad67be9ae81b8 (no-eol)
  $ hg undo -n 1
  undone to *, before strip 3ee6 (glob)
  $ hg redo
  undone to *, before undo -n 1 (glob)
  $ hg redo
  undone to *, before undo (glob)
  $ hg redo
  undone to *, before undo (glob)
  $ hg log -r . -T {node}
  a0b72b3048d6d07b35b1d79c8e5c46b159d21cc9 (no-eol)
  $ hg undo -fn 3
  undone to *, before strip 3ee6 (glob)
  $ hg undo --force --step -1
  undone to *, before undo -b 3532 (glob)
  $ hg debugundohistory -l
  0: undo --force --step -1
  1: undo -fn 3
  2: redo
  3: redo
  4: redo
  $ hg redo
  undone to *, before undo --force --step -1 (glob)
  $ hg undo
  undone to *, before undo -n -1 -b 75f6 (glob)
  $ hg log -r . -T {node}
  75f63379f12bf02d40fe7444587ad67be9ae81b8 (no-eol)
  $ hg redo
  undone to *, before undo (glob)
  $ hg redo
  undone to *, before undo -fn 3 (glob)
  $ hg log -r . -T {node}
  a0b72b3048d6d07b35b1d79c8e5c46b159d21cc9 (no-eol)
  $ hg undo --traceback
  undone to *, before ci -m prev1 (glob)
  $ hg undo -an1
  undone to *, before undo --traceback (glob)
  $ hg redo
  undone to *, before undo -an1 (glob)
  $ hg redo
  abort: can't redo past absolute undo
  [255]
  $ hg undo -n -1
  undone to *, before redo (glob)
  $ hg log -G -T compact
  @  23[tip]   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  |
  o  22:18   3ee6a6880888   1970-01-01 00:00 +0000   test
  |    a9
  |
  | o  21[newbook]:18   35324a911c0d   1970-01-01 00:00 +0000   test
  |/     newbranch
  |
  o  18   75f63379f12b   1970-01-01 00:00 +0000   test
  |    newfiles
  |
  o  17:9   d0fdb9510dbf   1970-01-01 00:00 +0000   test
  |    newfiles
  |
  o  9[master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  |
  o  8:4   0a3dd3e15e65   1970-01-01 00:00 +0000   test
  |    words
  |
  | o  7[feature2]:4   296fda51a303   1970-01-01 00:00 +0000   test
  |/     d
  |
  o  4   38d85b506754   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  3:1   ec7553f7b382   1970-01-01 00:00 +0000   test
  |    c1
  |
  | o  2[feature1]   49cdb4091aca   1970-01-01 00:00 +0000   test
  |/     b
  |
  o  1   b68836a6e2ca   1970-01-01 00:00 +0000   test
  |    a2
  |
  o  0   df4fd610a3d6   1970-01-01 00:00 +0000   test
       a1
  
'Refined branch testing
Specific edge case testing
  $ hg up null
  0 files updated, 0 files merged, 9 files removed, 0 files unresolved
  $ touch b1 && hg add b1 && hg ci -m b1
  created new head
  $ touch b2 && hg add b2 && hg ci -m b2
  $ touch b3 && hg add b3 && hg ci -m b3
  $ hg up null
  0 files updated, 0 files merged, 3 files removed, 0 files unresolved
  $ touch c1 && hg add c1 && hg ci -m c1
  created new head
  $ touch c2 && hg add c2 && hg ci -m c2
  $ touch c3 && hg add c3 && hg ci -m c3
  $ hg log -G -T compact
  @  29[tip]   0963b9e31e70   1970-01-01 00:00 +0000   test
  |    c3
  |
  o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
       c1
  
  o  26   f57edd138754   1970-01-01 00:00 +0000   test
  |    b3
  |
  o  25   0cb4447a10a7   1970-01-01 00:00 +0000   test
  |    b2
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  |
  o  22:18   3ee6a6880888   1970-01-01 00:00 +0000   test
  |    a9
  |
  | o  21[newbook]:18   35324a911c0d   1970-01-01 00:00 +0000   test
  |/     newbranch
  |
  o  18   75f63379f12b   1970-01-01 00:00 +0000   test
  |    newfiles
  |
  o  17:9   d0fdb9510dbf   1970-01-01 00:00 +0000   test
  |    newfiles
  |
  o  9[master]   1dafc0b43612   1970-01-01 00:00 +0000   test
  |    cmiss
  |
  o  8:4   0a3dd3e15e65   1970-01-01 00:00 +0000   test
  |    words
  |
  | o  7[feature2]:4   296fda51a303   1970-01-01 00:00 +0000   test
  |/     d
  |
  o  4   38d85b506754   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  3:1   ec7553f7b382   1970-01-01 00:00 +0000   test
  |    c1
  |
  | o  2[feature1]   49cdb4091aca   1970-01-01 00:00 +0000   test
  |/     b
  |
  o  1   b68836a6e2ca   1970-01-01 00:00 +0000   test
  |    a2
  |
  o  0   df4fd610a3d6   1970-01-01 00:00 +0000   test
       a1
  
  $ hg undo -b f57e
  undone to *, before ci -m b3 (glob)
  $ hg undo -b f57e
  undone to *, before ci -m b2 (glob)
  $ hg log -G -T compact -l5
  o  29[tip]   0963b9e31e70   1970-01-01 00:00 +0000   test
  |    c3
  |
  o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
       c1
  
  @  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  ~
  $ hg redo
  undone to *, before undo -b f57e (glob)
  $ hg log -G -T compact -l6
  o  29[tip]   0963b9e31e70   1970-01-01 00:00 +0000   test
  |    c3
  |
  o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
       c1
  
  @  25   0cb4447a10a7   1970-01-01 00:00 +0000   test
  |    b2
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  ~
  $ hg undo -b 0963
  undone to *, before ci -m c3 (glob)
  $ hg log -G -T compact -l5
  @  28[tip]   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
       c1
  
  o  25   0cb4447a10a7   1970-01-01 00:00 +0000   test
  |    b2
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  ~
  $ hg undo
  undone to *, before undo -b 0963 (glob)
  $ hg log -G -T compact -l6
  o  29[tip]   0963b9e31e70   1970-01-01 00:00 +0000   test
  |    c3
  |
  o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
       c1
  
  @  25   0cb4447a10a7   1970-01-01 00:00 +0000   test
  |    b2
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  ~
  $ hg redo
  undone to *, before undo (glob)
  $ hg redo
  undone to *, before undo -b 0963 (glob)
  $ hg log -G -T compact -l6
  o  29[tip]   0963b9e31e70   1970-01-01 00:00 +0000   test
  |    c3
  |
  o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
       c1
  
  @  25   0cb4447a10a7   1970-01-01 00:00 +0000   test
  |    b2
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  ~
  $ hg undo -b f57e
  undone to *, before redo (glob)
  $ hg log -G -T compact -l5
  o  29[tip]   0963b9e31e70   1970-01-01 00:00 +0000   test
  |    c3
  |
  o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  |    c2
  |
  o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
       c1
  
  @  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  ~

Interupted commands
Commands like hg rebase, unshelve and histedit may interupt in order for the
user to solve merge conflicts etc.  Since for example hg rebase --abort may
permanently delete a commit, we do not want to undo to this state.
  $ touch afile
  $ echo "afile" > afile
  $ hg add afile && hg ci -m afile
  $ hg up 0963b9e31e70
  3 files updated, 0 files merged, 2 files removed, 0 files unresolved
  $ touch afile
  $ echo "bfile" > afile
  $ hg add afile && hg ci -m bfile
  $ hg log -G -T compact -l6
  @  31[tip]:29   00617a57f780   1970-01-01 00:00 +0000   test
  |    bfile
  |
  | o  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  | |    afile
  | |
  o |  29   0963b9e31e70   1970-01-01 00:00 +0000   test
  | |    c3
  | |
  o |  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  o |  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
   /     c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase =
  > EOF
  $ hg rebase -r 00617 -d 28dfc
  rebasing 31:00617a57f780 "bfile" (tip)
  merging afile
  warning: conflicts while merging afile! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see hg resolve, then hg rebase --continue)
  [1]
  $ hg log -G -T compact -l6
  @  31[tip]:29   00617a57f780   1970-01-01 00:00 +0000   test
  |    bfile
  |
  | @  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  | |    afile
  | |
  o |  29   0963b9e31e70   1970-01-01 00:00 +0000   test
  | |    c3
  | |
  o |  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  o |  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
   /     c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  $ hg resolve -m afile
  (no more unresolved files)
  continue: hg rebase --continue
  $ hg rebase --continue
  rebasing 31:00617a57f780 "bfile" (tip)
  $ hg log -G -T compact -l6
  @  32[tip]:30   e642892c5cb0   1970-01-01 00:00 +0000   test
  |    bfile
  |
  o  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  |    afile
  |
  | o  29   0963b9e31e70   1970-01-01 00:00 +0000   test
  | |    c3
  | |
  | o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  | o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
  |      c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  $ hg undo
  undone to *, before rebase -r 00617 -d 28dfc (glob)
  $ hg log -G -T compact -l6
  @  31[tip]:29   00617a57f780   1970-01-01 00:00 +0000   test
  |    bfile
  |
  | o  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  | |    afile
  | |
  o |  29   0963b9e31e70   1970-01-01 00:00 +0000   test
  | |    c3
  | |
  o |  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  o |  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
   /     c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  $ hg redo
  undone to *, before undo (glob)
  $ hg log -G -T compact -l6
  @  32[tip]:30   e642892c5cb0   1970-01-01 00:00 +0000   test
  |    bfile
  |
  o  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  |    afile
  |
  | o  29   0963b9e31e70   1970-01-01 00:00 +0000   test
  | |    c3
  | |
  | o  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  | o  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
  |      c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  $ hg undo
  undone to *, before rebase -r 00617 -d 28dfc (glob)
  $ hg rebase -r 00617 -d 28dfc
  rebasing 31:00617a57f780 "bfile" (tip)
  merging afile
  warning: conflicts while merging afile! (edit, then use 'hg resolve --mark')
  unresolved conflicts (see hg resolve, then hg rebase --continue)
  [1]
  $ hg rebase --abort
  rebase aborted
  $ hg undo
  undone to *, before rebase -r 00617 -d 28dfc (glob)
  $ hg log -G -T compact -l6
  @  31[tip]:29   00617a57f780   1970-01-01 00:00 +0000   test
  |    bfile
  |
  | o  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  | |    afile
  | |
  o |  29   0963b9e31e70   1970-01-01 00:00 +0000   test
  | |    c3
  | |
  o |  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  o |  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
   /     c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > rebase =!
  > EOF

Obsmarkers for instack amend
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > fbamend = $TESTDIR/../hgext3rd/fbamend/
  > EOF
  $ hg update 0963
  0 files updated, 0 files merged, 1 files removed, 0 files unresolved
  $ touch c5 && hg add c5 && hg amend c5
  warning: the changeset's children were left behind
  (use 'hg restack' to rebase them)
  $ hg log -G -T compact -l7
  @  34[tip]:28   e1c5a2a441f5   1970-01-01 00:00 +0000   test
  |    c3
  |
  | o  31:29   00617a57f780   1970-01-01 00:00 +0000   test
  | |    bfile
  | |
  | | o  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  | | |    afile
  | | |
  | x |  29[e1c5a2a441f5.preamend]   0963b9e31e70   1970-01-01 00:00 +0000   test
  |/ /     c3
  | |
  o |  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  o |  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
   /     c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  $ hg undo && hg update 00617a
  undone to *, before amend c5 (glob)
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ hg log -G -T compact -l7
  @  31[tip]:29   00617a57f780   1970-01-01 00:00 +0000   test
  |    bfile
  |
  | o  30:24   28dfc398cab7   1970-01-01 00:00 +0000   test
  | |    afile
  | |
  o |  29   0963b9e31e70   1970-01-01 00:00 +0000   test
  | |    c3
  | |
  o |  28   4e0ac6fa4ca0   1970-01-01 00:00 +0000   test
  | |    c2
  | |
  o |  27:-1   c54b1b73bb58   1970-01-01 00:00 +0000   test
   /     c1
  |
  o  24:-1   90af9088326b   1970-01-01 00:00 +0000   test
       b1
  
  o  23   a0b72b3048d6   1970-01-01 00:00 +0000   test
  |    prev1
  ~
  $ cat >> $HGRCPATH <<EOF
  > [extensions]
  > famend =!
  > EOF
