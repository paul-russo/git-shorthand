# shellcheck shell=sh

Describe 'git shorthand aliases'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  # Aliases require eval to be invoked from tests
  It 'ga expands to git add'
    When call eval 'ga file.txt'
    The output should eq 'git add file.txt'
  End

  It 'gaa expands to git add --a'
    When call eval 'gaa'
    The output should eq 'git add --a'
  End

  It 'gs expands to git status'
    When call eval 'gs'
    The output should eq 'git status'
  End

  It 'gco expands to git checkout'
    When call eval 'gco branch-name'
    The output should eq 'git checkout branch-name'
  End

  It 'gpp expands to git push'
    When call eval 'gpp'
    The output should eq 'git push'
  End

  It 'gb expands to git branch'
    When call eval 'gb'
    The output should eq 'git branch'
  End

  It 'gcob expands to git checkout -b'
    When call eval 'gcob new-branch'
    The output should eq 'git checkout -b new-branch'
  End
End
