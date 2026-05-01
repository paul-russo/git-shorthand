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
  cd() {
    # shellcheck disable=SC2034
    # Set in mock cd; asserted by shellspec "The variable GWTCO_CD_PATH"
    GWTCO_CD_PATH="$1"
    return 0
  }

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
    rm -rf /tmp/repo-worktrees/existing-branch 2>/dev/null || true

    When call gwtco "existing-branch"
    The output should include 'worktree add'
    The output should include 'existing-branch'
  End

  It 'changes to an existing worktree instead of adding it again'
    mkdir -p /tmp/repo-worktrees/existing-branch 2>/dev/null || true

    When call gwtco "existing-branch"
    The output should not include 'worktree add'
    The variable GWTCO_CD_PATH should eq "/tmp/repo-worktrees/existing-branch"
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

Describe 'gwtd (remove worktree while preserving branch)'
  git() {
    case "$1" in
      check-ref-format)
        return 0
        ;;
      fetch)
        printf '%s\n' "git $*"
        return 0
        ;;
      worktree)
        if [ "${2:-}" = "list" ]; then
          printf 'worktree /tmp/repo\n'
          return 0
        fi
        if [ "${2:-}" = "prune" ]; then
          printf '%s\n' "git $*"
          return 0
        fi
        return 0
        ;;
      rev-parse)
        if [ "${2:-}" = "--show-toplevel" ]; then
          printf '/tmp/repo\n'
          return 0
        fi
        if [ "${2:-}" = "--abbrev-ref" ]; then
          if [ "${GWTD_HAS_UPSTREAM:-1}" = "0" ]; then
            return 1
          fi
          printf 'origin/%s\n' "${3%%@*}"
          return 0
        fi
        return 0
        ;;
      -C)
        if [ "${3:-}" = "rev-parse" ]; then
          printf '%s\n' "${GWTD_ACTUAL_BRANCH:-${2##*/}}"
          return 0
        fi
        if [ "${3:-}" = "status" ]; then
          printf '%s\n' "${GWTD_STATUS_OUTPUT:-}"
          return 0
        fi
        return 0
        ;;
      merge-base)
        return "${GWTD_MERGE_BASE_STATUS:-0}"
        ;;
      symbolic-ref)
        printf 'refs/remotes/origin/main\n'
        return 0
        ;;
      branch)
        if [ "${2:-}" = "-vv" ]; then
          printf '  merged   abc123 [origin/merged] msg\n'
          printf '  dirty    abc123 [origin/dirty] msg\n'
          printf '  unpushed abc123 [origin/unpushed] msg\n'
          printf '  fresh    abc123 [origin/fresh] msg\n'
          printf '  gone     abc123 [origin/gone: gone] msg\n'
          printf '  local    abc123 msg\n'
          return 0
        fi
        if [ "${2:-}" = "--merged" ]; then
          if [ "${GWTD_IS_STALE:-1}" = "1" ]; then
            printf '  merged\n'
            printf '  dirty\n'
            printf '  unpushed\n'
            printf '  gone\n'
            printf '  local\n'
          fi
          return 0
        fi
        printf '%s\n' "git $*"
        return 0
        ;;
      for-each-ref)
        printf 'main\n'
        printf 'merged\n'
        printf 'dirty\n'
        printf 'unpushed\n'
        printf 'fresh\n'
        printf 'gone\n'
        printf 'local\n'
        return 0
        ;;
      diff)
        return 1
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  }

  rm() {
    printf '%s\n' "rm $*"
    return 0
  }

  mkdir -p /tmp/repo-worktrees/merged /tmp/repo-worktrees/dirty /tmp/repo-worktrees/unpushed /tmp/repo-worktrees/fresh /tmp/repo-worktrees/gone /tmp/repo-worktrees/local 2>/dev/null || true

  It 'removes a clean stale worktree and preserves the branch'
    GWTD_STATUS_OUTPUT=''
    GWTD_MERGE_BASE_STATUS=0
    GWTD_HAS_UPSTREAM=1
    GWTD_IS_STALE=1

    When call gwtd "merged"
    The output should include 'git fetch --prune'
    The output should include 'rm -rf -- /tmp/repo-worktrees/merged'
    The output should include 'git worktree prune -v'
    The output should not include 'branch -d merged'
    The output should not include 'branch -D merged'
    The status should be success
  End

  Context 'with --force'
    It 'removes the worktree without safety checks and preserves the branch'
      GWTD_STATUS_OUTPUT=' M file.txt'
      GWTD_MERGE_BASE_STATUS=1
      GWTD_HAS_UPSTREAM=1
      GWTD_IS_STALE=0

      When call gwtd --force "dirty"
      The output should include 'rm -rf -- /tmp/repo-worktrees/dirty'
      The output should include 'git worktree prune -v'
      The output should not include 'git fetch --prune'
      The output should not include 'branch -D dirty'
      The status should be success
    End
  End

  It 'rejects dirty worktrees without --force'
    GWTD_STATUS_OUTPUT=' M file.txt'
    GWTD_MERGE_BASE_STATUS=0
    GWTD_HAS_UPSTREAM=1
    GWTD_IS_STALE=1

    When call gwtd "dirty"
    The stderr should include 'uncommitted changes'
    The output should not include 'rm -rf'
    The status should be failure
  End

  It 'rejects branches with commits missing from upstream without --force'
    GWTD_STATUS_OUTPUT=''
    GWTD_MERGE_BASE_STATUS=1
    GWTD_HAS_UPSTREAM=1
    GWTD_IS_STALE=1

    When call gwtd "unpushed"
    The stderr should include 'not fully upstreamed'
    The output should not include 'rm -rf'
    The status should be failure
  End

  It 'rejects local branches without an upstream even when their tree is stale'
    GWTD_STATUS_OUTPUT=''
    GWTD_MERGE_BASE_STATUS=0
    GWTD_HAS_UPSTREAM=0
    GWTD_IS_STALE=1

    When call gwtd "local"
    The stderr should include 'not fully upstreamed'
    The output should not include 'rm -rf'
    The status should be failure
  End

  It 'allows gone-upstream branches when they are stale by gbprune rules'
    GWTD_STATUS_OUTPUT=''
    GWTD_MERGE_BASE_STATUS=1
    GWTD_HAS_UPSTREAM=0
    GWTD_IS_STALE=1

    When call gwtd "gone"
    The output should include 'rm -rf -- /tmp/repo-worktrees/gone'
    The output should include 'git worktree prune -v'
    The status should be success
  End

  It 'rejects branches that are not stale by gbprune rules without --force'
    GWTD_STATUS_OUTPUT=''
    GWTD_MERGE_BASE_STATUS=0
    GWTD_HAS_UPSTREAM=1
    GWTD_IS_STALE=0

    When call gwtd "fresh"
    The stderr should include 'not stale'
    The output should not include 'rm -rf'
    The status should be failure
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
