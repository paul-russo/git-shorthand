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

  It 'fails without prompting when stdin is not a tty'
    setup_worktree_conflict

    When call gco main < /dev/null
    The status should be failure
    The stderr should include "already used by worktree at '/tmp/pool-worktrees/tree-3'"
    The stderr should not include 'Go there now'
    The output should be blank
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

  It 'does not prompt when stdin is not a tty'
    _git-co-can-prompt() { return 1; }
    gwtcd() { echo 'should not run' >&2; return 0; }

    When call _git-co-offer-gwtcd /tmp/pool-worktrees/tree-3
    The status should be failure
    The stderr should be blank
    The output should be blank
  End
End

Describe '_git-co-parse-worktree-in-use'
  It 'extracts the worktree path from git checkout errors'
    When call _git-co-parse-worktree-in-use "fatal: 'main' is already used by worktree at '/tmp/tree-3'"
    The status should be success
    The output should eq '/tmp/tree-3'
  End

  It 'returns failure for unrelated messages'
    When call _git-co-parse-worktree-in-use 'fatal: reference is not a tree'
    The status should be failure
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
