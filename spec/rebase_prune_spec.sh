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
        printf 'main\n'
        printf 'gone\n'
        printf 'linked\n'
        if [[ -n "${GBPRUNE_EXTRA_BRANCH:-}" ]]; then
          printf '%s\n' "$GBPRUNE_EXTRA_BRANCH"
        fi
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
  End

  Mock gh
    case "$*" in
      pr\ list*--head\ squashed*)
        printf '%s\n' "${GBPRUNE_GH_HEAD_OIDS:-}"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  End

  It 'fetches with prune and force-deletes branches fully merged into main'
    When call gbprune
    The output should include 'git fetch --prune'
    The output should include 'git branch -D gone'
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
        printf 'main\n'
        printf 'gone\n'
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
  End

  Mock gh
    return 1
  End

  It 'pulls then runs gbprune'
    When call gpbprune
    The output should include 'git pull'
    The output should include 'git fetch --prune'
    The output should include 'git branch -D gone'
  End
End
