# shellcheck shell=sh

Describe 'gco (checkout with worktree-in-use recovery)'
  setup_worktree_conflict() {
    git() {
      case "$1" in
        checkout)
          print -r -- "fatal: 'main' is already used by worktree at '/tmp/pool-worktrees/tree-3'" >&2
          return 128
          ;;
        *)
          command git "$@"
          ;;
      esac
    }
    gwtcd() { print -r -- "gwtcd:$*"; return 0; }
  }

  It 'passes through a successful checkout'
    git() { print -r -- "ok"; return 0; }

    When call gco feature-branch
    The status should be success
    The output should eq 'ok'
  End

  It 'fails on unrelated checkout errors without offering gwtcd'
    git() {
      print -r -- 'fatal: reference is not a tree' >&2
      return 128
    }
    gwtcd() { echo 'should not run' >&2; return 0; }

    When call gco bad-ref < /dev/null
    The status should be failure
    The stderr should include 'reference is not a tree'
    The stderr should not include 'should not run'
    The stderr should not include 'Go there now'
  End

  It 'fails without prompting when no terminal is available'
    setup_worktree_conflict
    _git-co-can-prompt() { return 1; }

    When call gco main < /dev/null
    The status should be failure
    The stderr should include "already used by worktree at '/tmp/pool-worktrees/tree-3'"
    The stderr should not include 'Go there now'
    The output should be blank
  End

  It 'does not duplicate the worktree-in-use fatal on stderr when the user declines'
    setup_worktree_conflict
    _git-co-can-prompt() { return 0; }
    Data
      #|n
    End

    When call gco main
    The status should be failure
    The stderr should include "already used by worktree at '/tmp/pool-worktrees/tree-3'"
    The stderr should include 'Go there now'
    The stderr should eq "fatal: 'main' is already used by worktree at '/tmp/pool-worktrees/tree-3'
gco: tree-3 holds this branch at /tmp/pool-worktrees/tree-3. Go there now? [y/N]: "
  End

End

Describe '_git-co-offer-gwtcd'
  It 'cds via gwtcd when the user accepts'
    _git-co-can-prompt() { return 0; }
    gwtcd() { print -r -- "gwtcd:$*"; return 0; }
    Data
      #|y
    End

    When call _git-co-offer-gwtcd /tmp/pool-worktrees/tree-3
    The status should be success
    The stderr should include 'Go there now'
    The output should eq 'gwtcd:tree-3'
  End

  It 'fails when the user declines'
    _git-co-can-prompt() { return 0; }
    gwtcd() { echo 'should not run' >&2; return 0; }
    Data
      #|n
    End

    When call _git-co-offer-gwtcd /tmp/pool-worktrees/tree-3
    The status should be failure
    The stderr should not include 'should not run'
  End

  It 'does not prompt when no terminal is available'
    _git-co-can-prompt() { return 1; }
    gwtcd() { echo 'should not run' >&2; return 0; }

    When call _git-co-offer-gwtcd /tmp/pool-worktrees/tree-3
    The status should be failure
    The stderr should be blank
    The output should be blank
  End

  It 'routes to gwtcd root when the primary checkout holds the branch'
    _git-co-can-prompt() { return 0; }
    _git-main-worktree() { print -r -- /tmp/main-repo; }
    gwtcd() { print -r -- "gwtcd:$*"; return 0; }
    Data
      #|y
    End

    When call _git-co-offer-gwtcd /tmp/main-repo
    The status should be success
    The stderr should include 'Go there now'
    The stderr should include 'root holds this branch'
    The output should eq 'gwtcd:root'
  End
End

Describe '_git-co-parse-worktree-in-use'
  It 'extracts the worktree path from git checkout errors'
    When call _git-co-parse-worktree-in-use "fatal: 'main' is already used by worktree at '/tmp/tree-3'"
    The status should be success
    The output should eq '/tmp/tree-3'
  End

  It 'extracts the worktree path from legacy already-checked-out errors'
    When call _git-co-parse-worktree-in-use "fatal: 'main' is already checked out at '/tmp/tree-3'"
    The status should be success
    The output should eq '/tmp/tree-3'
  End

  It 'returns failure for unrelated messages'
    When call _git-co-parse-worktree-in-use 'fatal: reference is not a tree'
    The status should be failure
  End
End

Describe '_git-co-gwtcd-target-for-path'
  It 'returns root for the primary checkout path'
    _git-main-worktree() { print -r -- /tmp/main-repo; }

    When call _git-co-gwtcd-target-for-path /tmp/main-repo
    The output should eq 'root'
  End

  It 'returns the slot basename for pool worktrees'
    _git-main-worktree() { print -r -- /tmp/main-repo; }

    When call _git-co-gwtcd-target-for-path /tmp/main-repo-worktrees/tree-3
    The output should eq 'tree-3'
  End
End

Describe 'gcom'
  It 'checks out the main branch via gco'
    git-main-branch() { print -r -- main; }
    gco() { print -r -- "gco:$*"; }

    When call gcom
    The output should eq 'gco:main'
  End
End
