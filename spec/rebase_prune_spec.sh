# shellcheck shell=sh

Describe 'gprm (pull rebase from main)'
  Mock git
    case "$1" in
      symbolic-ref)
        echo 'refs/remotes/origin/main'
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  End

  It 'fetches main and rebases onto it'
    When call gprm
    The output should include 'git fetch origin main:main'
    The output should include 'git rebase main'
  End
End

Describe 'gbprune (prune merged branches)'
  Mock git
    case "$1" in
      symbolic-ref)
        echo 'refs/remotes/origin/main'
        ;;
      fetch)
        printf '%s\n' "git $*"
        return 0
        ;;
      rev-parse)
        if [[ "${2:-}" = "--verify" ]]; then
          case "${3:-}" in
            refs/heads/squashed)
              echo "${GBPRUNE_SQUASHED_OID:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
              ;;
            *)
              return 1
              ;;
          esac
        else
          echo 'main'
        fi
        return 0
        ;;
      branch)
        if [[ "${2:-}" = "-vv" ]]; then
          printf '  main    abc123 [origin/main] commit msg\n'
          printf '  gone    def456 [origin/gone: gone] old msg\n'
          printf '+ linked ccc333 [origin/linked: gone] linked worktree msg\n'
          return 0
        fi
        if [[ "${2:-}" = "--merged" ]]; then
          printf '  main    abc123\n'
          printf '  gone    def456\n'
          printf '+ linked ccc333\n'
          return 0
        fi
        printf '%s\n' "git $*"
        return 0
        ;;
      for-each-ref)
        case "$*" in
          *upstream:track*)
            printf 'main\t\n'
            printf 'gone\t[gone]\n'
            printf 'linked\t[gone]\n'
            if [[ -n "${GBPRUNE_EXTRA_BRANCH:-}" ]]; then
              printf '%s\t\n' "$GBPRUNE_EXTRA_BRANCH"
            fi
            ;;
          *--merged*)
            printf 'main\n'
            printf 'gone\n'
            printf 'linked\n'
            ;;
          *objectname*)
            printf 'main\t1111111111111111111111111111111111111111\n'
            printf 'gone\t2222222222222222222222222222222222222222\n'
            printf 'linked\t3333333333333333333333333333333333333333\n'
            if [[ -n "${GBPRUNE_EXTRA_BRANCH:-}" ]]; then
              printf '%s\t%s\n' "$GBPRUNE_EXTRA_BRANCH" "${GBPRUNE_SQUASHED_OID:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
            fi
            ;;
          *)
            printf 'main\n'
            printf 'gone\n'
            printf 'linked\n'
            if [[ -n "${GBPRUNE_EXTRA_BRANCH:-}" ]]; then
              printf '%s\n' "$GBPRUNE_EXTRA_BRANCH"
            fi
            ;;
        esac
        return 0
        ;;
      diff)
        if [[ "${2:-}" != "--quiet" && -n "${GBPRUNE_PATCH_EQ_BRANCH:-}" && "${3:-}" = "$GBPRUNE_PATCH_EQ_BRANCH" ]]; then
          printf 'patch for %s\n' "$GBPRUNE_PATCH_EQ_BRANCH"
        fi
        return 1
        ;;
      merge-base)
        printf 'base\n'
        return 0
        ;;
      log)
        if [[ -n "${GBPRUNE_PATCH_EQ_BRANCH:-}" ]]; then
          printf 'patch for %s\n' "$GBPRUNE_PATCH_EQ_BRANCH"
        fi
        return 0
        ;;
      patch-id)
        patch_input=$(while IFS= read -r line; do printf '%s\n' "$line"; done)
        if [[ -n "${GBPRUNE_PATCH_EQ_BRANCH:-}" && "$patch_input" = *"$GBPRUNE_PATCH_EQ_BRANCH"* ]]; then
          printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0000000000000000000000000000000000000000\n'
        fi
        return 0
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  End

  Mock gh
    case "$*" in
      pr\ list*headRefName*headRefOid*)
        if [[ -n "${GBPRUNE_GH_HEAD_OIDS:-}" ]]; then
          printf 'squashed\t%s\n' "$GBPRUNE_GH_HEAD_OIDS"
        fi
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  End

  It 'fetches with prune and force-deletes branches fully merged into main'
    When call gbprune
    The output should include 'gbprune: fetching remotes with prune...'
    The output should include 'gbprune: checking local branches...'
    The output should include 'git fetch --prune'
    The output should include 'gbprune: deleting branch gone'
    The output should include 'git branch -D gone'
    The output should include 'gbprune: deleted 2 branch(es), failed 0'
  End

  It 'parses linked-worktree branch markers as status, not branch names'
    When call gbprune
    The output should include 'git branch -D linked'
    The output should not include 'git branch -D +'
  End

  It 'force-deletes branches whose current tip was merged through a GitHub PR'
    GBPRUNE_EXTRA_BRANCH='squashed'
    GBPRUNE_SQUASHED_OID='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    GBPRUNE_GH_HEAD_OIDS='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    export GBPRUNE_EXTRA_BRANCH GBPRUNE_SQUASHED_OID GBPRUNE_GH_HEAD_OIDS

    When call gbprune
    The output should include 'git branch -D squashed'
  End

  It 'force-deletes branches whose net patch is already on main'
    GBPRUNE_EXTRA_BRANCH='patch-equivalent'
    GBPRUNE_PATCH_EQ_BRANCH='patch-equivalent'
    export GBPRUNE_EXTRA_BRANCH GBPRUNE_PATCH_EQ_BRANCH

    When call gbprune
    The output should include 'git branch -D patch-equivalent'
  End

  It 'does not delete a branch when GitHub merged an older tip with the same branch name'
    GBPRUNE_EXTRA_BRANCH='squashed'
    GBPRUNE_SQUASHED_OID='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    GBPRUNE_GH_HEAD_OIDS='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    export GBPRUNE_EXTRA_BRANCH GBPRUNE_SQUASHED_OID GBPRUNE_GH_HEAD_OIDS

    When call gbprune
    The output should not include 'git branch -D squashed'
  End
End

Describe 'gpbprune (pull then branch prune)'
  Mock git
    case "$1" in
      pull)
        printf '%s\n' "git $*"
        return 0
        ;;
      symbolic-ref)
        echo 'refs/remotes/origin/main'
        ;;
      fetch)
        printf '%s\n' "git $*"
        return 0
        ;;
      rev-parse)
        if [[ "${2:-}" = "--verify" ]]; then
          return 1
        fi
        echo 'main'
        return 0
        ;;
      branch)
        if [[ "${2:-}" = "-vv" ]]; then
          printf '  main    abc123 [origin/main] commit msg\n'
          printf '  gone    def456 [origin/gone: gone] old msg\n'
          return 0
        fi
        if [[ "${2:-}" = "--merged" ]]; then
          printf '  main    abc123\n'
          printf '  gone    def456\n'
          return 0
        fi
        printf '%s\n' "git $*"
        return 0
        ;;
      for-each-ref)
        case "$*" in
          *upstream:track*)
            printf 'main\t\n'
            printf 'gone\t[gone]\n'
            ;;
          *--merged*)
            printf 'main\n'
            printf 'gone\n'
            ;;
          *objectname*)
            printf 'main\t1111111111111111111111111111111111111111\n'
            printf 'gone\t2222222222222222222222222222222222222222\n'
            ;;
          *)
            printf 'main\n'
            printf 'gone\n'
            ;;
        esac
        return 0
        ;;
      diff)
        return 1
        ;;
      merge-base|log|patch-id)
        return 0
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  End

  Mock gh
    return 1
  End

  It 'pulls then runs gbprune'
    When call gpbprune
    The output should include 'git pull'
    The output should include 'git fetch --prune'
    The output should include 'git branch -D gone'
    The output should include 'gbprune: deleted 1 branch(es), failed 0'
  End
End
