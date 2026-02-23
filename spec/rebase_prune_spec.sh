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

  It 'fetches with prune and force-deletes branches fully merged into main'
    When call gbprune
    The output should include 'git fetch --prune'
    The output should include 'git branch -D gone'
  End
End
