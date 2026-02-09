# shellcheck shell=sh

Describe '_git-main-worktree'
  Mock git
    case "$*" in
      *worktree*list*)
        printf 'worktree /path/to/repo\nbranch refs/heads/main\n'
        printf 'worktree /path/to/repo-worktrees/feature\nbranch refs/heads/feature\n'
        ;;
      *)
        exit 1
        ;;
    esac
  End

  It 'returns the main worktree path (first in list)'
    When call _git-main-worktree
    The output should eq '/path/to/repo'
  End
End

Describe '_git-wt-base'
  Mock git
    case "$*" in
      *worktree*list*)
        printf 'worktree /tmp/my-repo\n'
        ;;
      *)
        exit 1
        ;;
    esac
  End

  It 'returns worktrees base directory (repo name + -worktrees)'
    When call _git-wt-base
    The output should eq '/tmp/my-repo-worktrees'
  End
End

Describe 'gwta (add worktree with new branch from main)'
  Mock git
    case "$1" in
      symbolic-ref)
        echo 'refs/remotes/origin/main'
        ;;
      worktree)
        if [[ "${2:-}" = "list" ]]; then
          printf 'worktree /tmp/test-repo\n'
        else
          printf '%s\n' "git $*"
        fi
        return 0
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  End

  It 'adds worktree with new branch from main'
    When call gwta "feature/foo"
    The output should include 'worktree add -b feature/foo'
    The output should include 'main'
  End
End

Describe 'gwtco (add worktree for existing branch)'
  Mock git
    case "$*" in
      *worktree*list*)
        printf 'worktree /tmp/repo\n'
        ;;
      worktree*)
        printf '%s\n' "git $*"
        return 0
        ;;
      *)
        exit 1
        ;;
    esac
  End

  It 'adds worktree for existing branch'
    When call gwtco "existing-branch"
    The output should include 'worktree add'
    The output should include 'existing-branch'
  End
End

Describe 'gwtl (list worktrees)'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'lists worktrees'
    When call gwtl
    The output should eq 'git worktree list'
  End
End

Describe 'gwtd (remove worktree and delete branch)'
  git() {
    case "$1" in
      worktree)
        if [ "${2:-}" = "list" ]; then
          printf 'worktree /tmp/repo\n'
        elif [ "${2:-}" = "remove" ]; then
          printf 'git worktree remove %s\n' "${3:-}"
          return 0
        fi
        printf 'git %s\n' "$*"
        return 0
        ;;
      branch)
        printf 'git %s\n' "$*"
        return 0
        ;;
      symbolic-ref)
        echo 'refs/remotes/origin/main'
        ;;
      *)
        printf 'git %s\n' "$*"
        return 0
        ;;
    esac
  }

  It 'removes worktree and deletes branch with -d'
    When call gwtd "test-branch"
    The output should include 'branch -d test-branch'
    The status should be success
  End

  Context 'with --force'
    It 'removes worktree with --force and deletes branch with -D'
      When call gwtd --force "test-branch"
      The output should include 'branch -D test-branch'
      The status should be success
    End
  End

  Context 'when worktree has submodules and uncommitted changes'
    git() {
      case "$1" in
        worktree)
          if [ "${2:-}" = "list" ]; then
            printf 'worktree /tmp/repo\n'
          elif [ "${2:-}" = "remove" ]; then
            echo 'fatal: worktree has submodules' >&2
            return 1
          fi
          printf 'git %s\n' "$*"
          return 0
          ;;
        branch)
          printf 'git %s\n' "$*"
          return 0
          ;;
        symbolic-ref)
          echo 'refs/remotes/origin/main'
          ;;
        *)
          printf 'git %s\n' "$*"
          return 0
          ;;
      esac
    }
    # Simulate uncommitted changes (status --porcelain returns something)
    Mock mkdir
      return 0
    End

    BeforeRun 'mkdir -p /tmp/repo-worktrees/dirty-wt 2>/dev/null || true'

    It 'fails with helpful message when worktree has submodules and uncommitted changes'
      # Override git to return submodule error and simulate dirty worktree
      git() {
        case "$1" in
          worktree)
            if [ "${2:-}" = "list" ]; then
              printf 'worktree /tmp/repo\n'
            elif [ "${2:-}" = "remove" ]; then
              echo 'fatal: worktree has submodules' >&2
              return 1
            fi
            return 0
            ;;
          -*|*)
            # git -C ... status --porcelain (simulate dirty)
            if [ "$1" = "-C" ] && [ "${4:-}" = "--porcelain" ]; then
              echo " M file.txt"
              return 0
            fi
            return 0
            ;;
        esac
      }
      When call gwtd "dirty-wt"
      The stderr should include 'submodules'
      The stderr should include 'uncommitted changes'
      The status should be failure
    End
  End
End

Describe 'gwtcd (cd into worktree by branch name)'
  cd() {
    # shellcheck disable=SC2034
    # Set in mock cd; asserted by shellspec "The variable GWTCD_CD_PATH"
    GWTCD_CD_PATH="$1"
    return 0
  }

  It 'changes to main worktree when branch is main'
    Mock git
      case "$*" in
        symbolic-ref*)
          echo 'refs/remotes/origin/main'
          ;;
        worktree*list*)
          printf 'worktree /tmp/main-repo\nbranch refs/heads/main\n'
          ;;
        *)
          exit 1
          ;;
      esac
    End

    When call gwtcd "main"
    The status should be success
    The variable GWTCD_CD_PATH should eq "/tmp/main-repo"
  End

  It 'changes to worktree directory when branch is not main'
    Mock git
      case "$*" in
        symbolic-ref*)
          echo 'refs/remotes/origin/main'
          ;;
        worktree*list*)
          printf 'worktree /tmp/main-repo\nbranch refs/heads/main\n'
          ;;
        *)
          exit 1
          ;;
      esac
    End

    When call gwtcd "feature-branch"
    The status should be success
    The variable GWTCD_CD_PATH should eq "/tmp/main-repo-worktrees/feature-branch"
  End
End

Describe 'gwtprune'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'prunes stale worktree references'
    When call gwtprune
    The output should eq 'git worktree prune -v'
  End
End
