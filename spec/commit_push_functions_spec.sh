# shellcheck shell=sh

Describe 'gcpp (commit and push)'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'runs git commit -m with message then git push'
    When call gcpp "fix: resolve bug"
    The line 1 of stdout should eq 'git commit -m fix: resolve bug'
    The line 2 of stdout should eq 'git push'
  End

  It 'passes multi-word message correctly'
    When call gcpp "feat: add new feature"
    The line 1 of stdout should include 'commit -m'
    The line 1 of stdout should include 'feat'
  End
End

Describe 'gcobpp (checkout -b and push -u)'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'creates branch and pushes upstream'
    When call gcobpp "feature/xyz"
    The line 1 of stdout should eq 'git checkout -b feature/xyz'
    The line 2 of stdout should eq 'git push -u origin feature/xyz'
  End
End

Describe 'gaacpp (add all, commit, push)'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'adds all, commits and pushes'
    When call gaacpp "wip"
    The line 1 of stdout should eq 'git add --a'
    The line 2 of stdout should include 'commit -m'
    The line 3 of stdout should eq 'git push'
  End
End

Describe 'gaascpp (add all, status, commit, push)'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'adds all, shows status, commits and pushes'
    When call gaascpp "release v1"
    The line 1 of stdout should eq 'git add --a'
    The line 2 of stdout should eq 'git status'
    The line 3 of stdout should include 'commit -m'
    The line 4 of stdout should eq 'git push'
  End
End

Describe 'gaac (add all and commit)'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'adds all and commits without pushing'
    When call gaac "chore: update deps"
    The line 1 of stdout should eq 'git add --a'
    The line 2 of stdout should include 'commit -m'
    The line 2 of stdout should not include 'push'
  End
End
