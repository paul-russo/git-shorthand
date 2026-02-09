# shellcheck shell=sh

Describe 'grnb (rename branch)'
  Mock git
    case "$1" in
      rev-parse)
        echo 'feature-old'
        return 0
        ;;
      branch)
        printf '%s\n' "git $*"
        return 0
        ;;
      push)
        printf '%s\n' "git $*"
        return 0
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  End

  It 'renames current branch and updates remote'
    When call grnb "feature-new"
    The stdout should include 'branch -m'
    The stdout should include 'feature-new'
    The stdout should include 'push origin :feature-old'
    The stdout should include 'push --set-upstream origin feature-new'
  End
End

Describe 'git-obliterate'
  Mock git
    printf '%s\n' "git $*"
    return 0
  End

  It 'deletes branch locally and removes from remote'
    When call git-obliterate "old-branch"
    The line 1 of stdout should eq 'git branch -d old-branch'
    The line 2 of stdout should eq 'git push origin :old-branch'
  End
End

Describe 'gnb (new branch from main)'
  Mock git
    case "$1" in
      symbolic-ref)
        echo 'refs/remotes/origin/main'
        ;;
      switch)
        printf '%s\n' "git $*"
        return 0
        ;;
      *)
        printf '%s\n' "git $*"
        return 0
        ;;
    esac
  End

  It 'creates new branch from main without checking out main'
    When call gnb "feature/abc"
    The output should include 'git switch -c feature/abc main'
  End
End

Describe 'gnbpp (new branch from main and push)'
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

  It 'creates branch from main and pushes upstream'
    When call gnbpp "feature/xyz"
    The output should include 'git switch -c feature/xyz main'
    The output should include 'git push -u origin feature/xyz'
  End
End

Describe 'gfmnb (fetch main then new branch)'
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

  It 'fetches main then creates new branch from it'
    When call gfmnb "hotfix/123"
    The output should include 'git fetch origin main:main'
    The output should include 'git switch -c hotfix/123 main'
  End
End
