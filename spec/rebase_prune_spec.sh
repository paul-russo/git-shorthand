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

Describe 'gbprune (prune gone branches)'
  Mock git
    case "$1" in
      fetch)
        printf '%s\n' "git $*"
        return 0
        ;;
      branch)
        if [[ "${2:-}" = "-vv" ]]; then
          printf '  main    abc123 [origin/main] commit msg\n'
          printf '  gone    def456 [origin/gone: gone] old msg\n'
          return 0
        fi
        printf '%s\n' "git $*"
        return 0
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  End

  It 'fetches with prune and processes gone branches'
    When call gbprune
    The output should include 'git fetch --prune'
    The output should include 'branch'
  End
End
