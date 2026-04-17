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

Describe '_git-wt-base-from-main'
  It 'returns the plugin worktrees base for a main worktree path'
    When call _git-wt-base-from-main '/tmp/foo/my-repo'
    The output should eq '/tmp/foo/my-repo-worktrees'
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

Describe '_git-current-wt-target'
  It 'returns root when cwd is the primary worktree'
    Mock git
      case "$*" in
        rev-parse*show-toplevel*)
          echo '/tmp/main-repo'
          ;;
        worktree*list*)
          printf 'worktree /tmp/main-repo\nbranch refs/heads/main\n'
          ;;
        *)
          exit 1
          ;;
      esac
    End

    When call _git-current-wt-target
    The output should eq 'root'
  End

  It 'returns directory basename when cwd is a linked worktree'
    Mock git
      case "$*" in
        rev-parse*show-toplevel*)
          echo '/tmp/main-repo-worktrees/feature-branch'
          ;;
        worktree*list*)
          printf 'worktree /tmp/main-repo\nbranch refs/heads/main\n'
          printf 'worktree /tmp/main-repo-worktrees/feature-branch\nbranch refs/heads/feature-branch\n'
          ;;
        *)
          exit 1
          ;;
      esac
    End

    When call _git-current-wt-target
    The output should eq 'feature-branch'
  End
End

Describe 'gwtcd (cd into worktree by branch name)'
  cd() {
    # shellcheck disable=SC2034
    # Set in mock cd; asserted by shellspec "The variable GWTCD_CD_PATH"
    GWTCD_CD_PATH="$1"
    return 0
  }

  It 'changes to primary worktree when target is root'
    Mock git
      case "$*" in
        worktree*list*)
          printf 'worktree /tmp/main-repo\nbranch refs/heads/main\n'
          ;;
        *)
          exit 1
          ;;
      esac
    End

    When call gwtcd "root"
    The status should be success
    The variable GWTCD_CD_PATH should eq "/tmp/main-repo"
  End

  It 'changes to worktree directory for branch main like any other branch name'
    Mock git
      case "$*" in
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
    The variable GWTCD_CD_PATH should eq "/tmp/main-repo-worktrees/main"
  End

  It 'changes to worktree directory when branch is not root'
    Mock git
      case "$*" in
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
  # Set GWTPRUNE_REV_PARSE and GWTPRUNE_SECOND_WT in each example.
  Mock git
    _gwtprune_common_git_mock() {
      case "$1" in
        fetch)
          printf '%s\n' "git $*"
          return 0
          ;;
        symbolic-ref)
          echo 'refs/remotes/origin/main'
          return 0
          ;;
        rev-parse)
          echo "${GWTPRUNE_REV_PARSE:?GWTPRUNE_REV_PARSE must be set}"
          return 0
          ;;
        branch)
          if [ "${2:-}" = "-vv" ]; then
            printf '  main    abc123 [origin/main] commit msg\n'
            printf '  gone    def456 [origin/gone: gone] old msg\n'
            return 0
          fi
          if [ "${2:-}" = "--merged" ]; then
            printf '  main    abc123\n'
            printf '  gone    def456\n'
            return 0
          fi
          printf '%s\n' "git $*"
          return 0
          ;;
        for-each-ref)
          printf 'main\n'
          printf 'gone\n'
          return 0
          ;;
        diff)
          return 1
          ;;
        worktree)
          case "$*" in
            *list*--porcelain*)
              printf 'worktree /tmp/main-repo\n'
              printf 'HEAD 1111111111111111111111111111111111111111\n'
              printf 'branch refs/heads/main\n'
              printf '\n'
              printf 'worktree %s\n' "${GWTPRUNE_SECOND_WT:?GWTPRUNE_SECOND_WT must be set}"
              printf 'HEAD 2222222222222222222222222222222222222222\n'
              printf 'branch refs/heads/gone\n'
              printf '\n'
              return 0
              ;;
            remove*)
              printf '%s\n' "git $*"
              return 0
              ;;
            prune*)
              printf '%s\n' "git $*"
              return 0
              ;;
            *)
              printf '%s\n' "git $*"
              return 0
              ;;
          esac
          ;;
        *)
          printf '%s\n' "git $*"
          return 0
          ;;
      esac
    }
    _gwtprune_common_git_mock "$@"
  End

  It 'removes plugin-layout worktrees when the branch is stale and matches the path'
    GWTPRUNE_REV_PARSE=/tmp/main-repo
    GWTPRUNE_SECOND_WT=/tmp/main-repo-worktrees/gone
    export GWTPRUNE_REV_PARSE GWTPRUNE_SECOND_WT

    When call gwtprune
    The output should include 'git fetch --prune'
    The output should include 'git worktree remove /tmp/main-repo-worktrees/gone'
    The output should include 'git branch -D gone'
    The output should include 'git worktree prune -v'
  End

  It 'does not remove when directory name does not match checked-out branch'
    GWTPRUNE_REV_PARSE=/tmp/main-repo
    GWTPRUNE_SECOND_WT=/tmp/main-repo-worktrees/foo-dir
    export GWTPRUNE_REV_PARSE GWTPRUNE_SECOND_WT

    When call gwtprune
    The output should not include 'git worktree remove'
    The output should include 'git worktree prune -v'
  End

  It 'skips removal when cwd is the matching stale worktree'
    GWTPRUNE_REV_PARSE=/tmp/main-repo-worktrees/gone
    GWTPRUNE_SECOND_WT=/tmp/main-repo-worktrees/gone
    export GWTPRUNE_REV_PARSE GWTPRUNE_SECOND_WT

    When call gwtprune
    The stderr should include 'gwtprune: skipping /tmp/main-repo-worktrees/gone (current directory)'
    The output should not include 'git worktree remove'
    The output should include 'git worktree prune -v'
  End
End
