# shellcheck shell=sh

Describe 'zsh branch completion (slashes in names)'
  Mock git
    case "$1" in
      for-each-ref)
        printf '%s\n' 'main' 'cursor/example-branch'
        return 0
        ;;
      *)
        printf '%s\n' "git $*"
        return 1
        ;;
    esac
  End

  It 'uses slash-aware -M matcher for _git_shorthand_local_branches'
    _wanted() {
      printf '%s\n' "$@"
    }
    compadd() {
      :
    }

    When call _git_shorthand_local_branches
    The output should include '-M'
    The output should include 'r:|/=* r:|=*'
  End

  It 'uses slash-aware -M matcher for _git_shorthand_all_branches'
    _wanted() {
      printf '%s\n' "$@"
    }
    compadd() {
      :
    }

    When call _git_shorthand_all_branches
    The output should include '-M'
    The output should include 'r:|/=* r:|=*'
  End
End
