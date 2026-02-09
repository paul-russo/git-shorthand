# shellcheck shell=sh

Describe 'git-main-branch'
  Mock git
    case "$*" in
      *symbolic-ref*)
        echo 'refs/remotes/origin/main'
        ;;
      *)
        exit 1
        ;;
    esac
  End

  It 'returns main when symbolic-ref points to main'
    When call git-main-branch
    The output should eq 'main'
    The status should be success
  End

  Context 'when branch is master'
    Mock git
      case "$*" in
        *symbolic-ref*)
          echo 'refs/remotes/origin/master'
          ;;
        *)
          exit 1
          ;;
      esac
    End

    It 'returns master when symbolic-ref points to master'
      When call git-main-branch
      The output should eq 'master'
      The status should be success
    End
  End
End
