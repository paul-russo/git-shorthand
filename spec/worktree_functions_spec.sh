# shellcheck shell=sh

# Shared test fixture base. Each Describe that needs real slot directories
# wipes and recreates this prefix in BeforeEach.
GIT_WT_SPEC_BASE=/tmp/git-shorthand-spec-worktrees

cleanup_pool_base() {
  rm -rf "$GIT_WT_SPEC_BASE" 2>/dev/null || true
}

Describe '_git-main-worktree'
  Mock git
    case "$*" in
      *worktree*list*)
        printf 'worktree /path/to/repo\nbranch refs/heads/main\n'
        printf 'worktree /path/to/repo-worktrees/tree-3\nbranch refs/heads/feature\n'
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
          echo '/tmp/main-repo-worktrees/tree-3'
          ;;
        worktree*list*)
          printf 'worktree /tmp/main-repo\nbranch refs/heads/main\n'
          printf 'worktree /tmp/main-repo-worktrees/tree-3\nbranch refs/heads/feature\n'
          ;;
        *)
          exit 1
          ;;
      esac
    End

    When call _git-current-wt-target
    The output should eq 'tree-3'
  End
End

Describe '_git-wt-pool-slots'
  setup() {
    rm -rf "$GIT_WT_SPEC_BASE" 2>/dev/null || true
    mkdir -p "$GIT_WT_SPEC_BASE/tree-1"
    mkdir -p "$GIT_WT_SPEC_BASE/tree-2"
    mkdir -p "$GIT_WT_SPEC_BASE/tree-10"
    mkdir -p "$GIT_WT_SPEC_BASE/notapool"
    mkdir -p "$GIT_WT_SPEC_BASE/tree-named"
  }
  BeforeEach 'setup'
  AfterEach 'cleanup_pool_base'

  _git-wt-base() {
    print -r -- "$GIT_WT_SPEC_BASE"
  }

  It 'emits tree-<int> dirs in natural numeric order (tree-2 before tree-10)'
    When call _git-wt-pool-slots
    The line 1 of output should eq "$GIT_WT_SPEC_BASE/tree-1"
    The line 2 of output should eq "$GIT_WT_SPEC_BASE/tree-2"
    The line 3 of output should eq "$GIT_WT_SPEC_BASE/tree-10"
    The output should not include 'notapool'
    The output should not include 'tree-named'
  End

  It 'returns empty (success) when no tree-<int> dirs exist'
    rm -rf "$GIT_WT_SPEC_BASE"
    mkdir -p "$GIT_WT_SPEC_BASE/foo"

    When call _git-wt-pool-slots
    The output should eq ''
    The status should be success
  End
End

Describe '_git-wt-detect-lockfile'
  WT_LOCK_DIR=/tmp/git-shorthand-spec-detect-lockfile
  setup() {
    rm -rf "$WT_LOCK_DIR"
    mkdir -p "$WT_LOCK_DIR"
  }
  cleanup() {
    rm -rf "$WT_LOCK_DIR"
  }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'returns pnpm-lock.yaml when present (wins over yarn and npm)'
    touch "$WT_LOCK_DIR/pnpm-lock.yaml"
    touch "$WT_LOCK_DIR/yarn.lock"
    touch "$WT_LOCK_DIR/package-lock.json"

    When call _git-wt-detect-lockfile "$WT_LOCK_DIR"
    The output should eq 'pnpm-lock.yaml'
  End

  It 'returns yarn.lock when pnpm absent (wins over npm)'
    touch "$WT_LOCK_DIR/yarn.lock"
    touch "$WT_LOCK_DIR/package-lock.json"

    When call _git-wt-detect-lockfile "$WT_LOCK_DIR"
    The output should eq 'yarn.lock'
  End

  It 'returns package-lock.json when only npm is present'
    touch "$WT_LOCK_DIR/package-lock.json"

    When call _git-wt-detect-lockfile "$WT_LOCK_DIR"
    The output should eq 'package-lock.json'
  End

  It 'fails when no lockfile is present'
    When call _git-wt-detect-lockfile "$WT_LOCK_DIR"
    The status should be failure
  End
End

Describe '_git-wt-lockfile-unchanged'
  WT_LOCK_DIR=/tmp/git-shorthand-spec-lockfile-unchanged
  setup() {
    rm -rf "$WT_LOCK_DIR"
    mkdir -p "$WT_LOCK_DIR"
    touch "$WT_LOCK_DIR/yarn.lock"
  }
  cleanup() {
    rm -rf "$WT_LOCK_DIR"
  }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'fails when old_head is empty (no prior HEAD to diff against)'
    When call _git-wt-lockfile-unchanged "$WT_LOCK_DIR" ''
    The status should be failure
  End

  It 'fails when no lockfile is detected (cannot prove unchanged)'
    rm -f "$WT_LOCK_DIR/yarn.lock"

    When call _git-wt-lockfile-unchanged "$WT_LOCK_DIR" abc123
    The status should be failure
  End

  It 'succeeds when git diff --quiet returns 0 (lockfile identical)'
    Mock git
      case "$*" in
        *-C*diff*--quiet*)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    End

    When call _git-wt-lockfile-unchanged "$WT_LOCK_DIR" abc123
    The status should be success
  End

  It 'fails when git diff --quiet returns 1 (lockfile differs)'
    Mock git
      case "$*" in
        *-C*diff*--quiet*)
          return 1
          ;;
        *)
          return 1
          ;;
      esac
    End

    When call _git-wt-lockfile-unchanged "$WT_LOCK_DIR" abc123
    The status should be failure
  End
End

Describe '_git-wt-slot-branch'
  # Hardcoded path because Mock blocks don't see Describe-level variables.
  BeforeEach 'mkdir -p /tmp/git-shorthand-spec-slot-branch'
  AfterEach 'rm -rf /tmp/git-shorthand-spec-slot-branch'

  It 'returns the branch name when the slot has a branch checked out'
    Mock git
      case "$*" in
        *symbolic-ref*--quiet*--short*HEAD*)
          print -r -- 'feature/foo'
          ;;
        *)
          return 1
          ;;
      esac
    End

    When call _git-wt-slot-branch /tmp/git-shorthand-spec-slot-branch
    The output should eq 'feature/foo'
  End

  It 'returns empty when detached'
    Mock git
      case "$*" in
        *symbolic-ref*--quiet*--short*HEAD*)
          return 1
          ;;
      esac
    End

    When call _git-wt-slot-branch /tmp/git-shorthand-spec-slot-branch
    The output should eq ''
    The status should be failure
  End

  It 'fails when slot directory does not exist'
    When call _git-wt-slot-branch /nonexistent/path
    The status should be failure
  End
End

Describe '_git-wt-slot-state'
  # Hardcoded paths because Mock blocks don't see Describe-level variables.
  BeforeEach 'mkdir -p /tmp/git-shorthand-spec-slot-state'
  AfterEach 'rm -rf /tmp/git-shorthand-spec-slot-state'

  It 'returns current when cwd is the slot'
    Mock git
      case "$*" in
        "rev-parse --show-toplevel")
          print -r -- /tmp/git-shorthand-spec-slot-state
          ;;
        *)
          return 1
          ;;
      esac
    End

    When call _git-wt-slot-state /tmp/git-shorthand-spec-slot-state
    The output should eq 'current'
  End

  It 'returns dirty when status --porcelain has output'
    Mock git
      case "$*" in
        "rev-parse --show-toplevel")
          print -r -- /tmp/main-repo
          ;;
        *status*porcelain*)
          print -r -- ' M file.txt'
          ;;
      esac
    End

    When call _git-wt-slot-state /tmp/git-shorthand-spec-slot-state
    The output should eq 'dirty'
  End

  It 'returns active when clean and a branch is checked out'
    Mock git
      case "$*" in
        "rev-parse --show-toplevel")
          print -r -- /tmp/main-repo
          ;;
        *status*porcelain*)
          ;;
        *symbolic-ref*)
          print -r -- 'feature/foo'
          ;;
      esac
    End

    When call _git-wt-slot-state /tmp/git-shorthand-spec-slot-state
    The output should eq 'active'
  End

  It 'returns idle when clean and detached'
    Mock git
      case "$*" in
        "rev-parse --show-toplevel")
          print -r -- /tmp/main-repo
          ;;
        *status*porcelain*)
          ;;
        *symbolic-ref*)
          return 1
          ;;
      esac
    End

    When call _git-wt-slot-state /tmp/git-shorthand-spec-slot-state
    The output should eq 'idle'
  End
End

Describe '_git-wt-find-slot-by-branch'
  It 'returns the slot path when a slot has the branch checked out'
    _git-wt-pool-slots() { printf '/tmp/tree-1\n/tmp/tree-2\n'; }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'feature/foo' ;;
        */tree-2) print -r -- 'feature/bar' ;;
      esac
    }

    When call _git-wt-find-slot-by-branch feature/bar
    The output should eq '/tmp/tree-2'
  End

  It 'fails when no slot has the requested branch'
    _git-wt-pool-slots() { printf '/tmp/tree-1\n'; }
    _git-wt-slot-branch() { print -r -- 'something-else'; }

    When call _git-wt-find-slot-by-branch wanted
    The status should be failure
  End

  It 'fails on empty branch input'
    When call _git-wt-find-slot-by-branch ''
    The status should be failure
  End
End

Describe '_git-wt-pick-idle-slot'
  It 'picks the oldest idle slot by mtime'
    _git-wt-pool-slots() { printf '/tmp/tree-1\n/tmp/tree-2\n/tmp/tree-3\n'; }
    _git-wt-slot-state() {
      case "$1" in
        */tree-1) print -r -- 'active' ;;
        */tree-2) print -r -- 'idle' ;;
        */tree-3) print -r -- 'idle' ;;
      esac
    }
    _git-wt-slot-mtime() {
      case "$1" in
        */tree-2) print -r -- '2000' ;;
        */tree-3) print -r -- '1000' ;;
      esac
    }

    When call _git-wt-pick-idle-slot
    The output should eq '/tmp/tree-3'
  End

  It 'fails when no slots are idle'
    _git-wt-pool-slots() { printf '/tmp/tree-1\n'; }
    _git-wt-slot-state() { print -r -- 'active'; }
    _git-wt-slot-mtime() { print -r -- '1000'; }

    When call _git-wt-pick-idle-slot
    The status should be failure
  End

  It 'fails when the pool is empty'
    _git-wt-pool-slots() { :; }

    When call _git-wt-pick-idle-slot
    The status should be failure
  End
End

Describe '_git-wt-allocate-slot'
  It 'picks an idle slot when one exists'
    _git-wt-pick-idle-slot() { print -r -- '/tmp/tree-2'; return 0; }

    When call _git-wt-allocate-slot
    The output should eq '/tmp/tree-2'
  End

  It 'grows the pool lazily when below the soft cap and no idle slot exists'
    _git-wt-pick-idle-slot() { return 1; }
    _git-wt-pool-slots() { printf '/tmp/tree-1\n'; }
    _git-wt-grow-pool() { print -r -- '/tmp/tree-2'; return 0; }

    When call _git-wt-allocate-slot
    The output should include '/tmp/tree-2'
  End

  It 'prompts when pool is at the soft cap and reuses the chosen slot'
    _git-wt-pick-idle-slot() { return 1; }
    _git-wt-pool-slots() {
      printf '/tmp/tree-1\n/tmp/tree-2\n/tmp/tree-3\n/tmp/tree-4\n/tmp/tree-5\n/tmp/tree-6\n'
    }
    _git-wt-prompt-full-pool() { print -r -- '/tmp/tree-1'; return 0; }
    _git-wt-release-slot() { return 0; }

    When call _git-wt-allocate-slot
    The output should include '/tmp/tree-1'
  End

  It 'creates a new slot when the user chooses grow at the prompt'
    _git-wt-pick-idle-slot() { return 1; }
    _git-wt-pool-slots() {
      printf '/tmp/tree-1\n/tmp/tree-2\n/tmp/tree-3\n/tmp/tree-4\n/tmp/tree-5\n/tmp/tree-6\n'
    }
    _git-wt-prompt-full-pool() { print -r -- 'grow'; return 0; }
    _git-wt-grow-pool() { print -r -- '/tmp/tree-7'; return 0; }

    When call _git-wt-allocate-slot
    The output should include '/tmp/tree-7'
  End

  It 'fails (with cancellation note) when the user cancels'
    _git-wt-pick-idle-slot() { return 1; }
    _git-wt-pool-slots() {
      printf '/tmp/tree-1\n/tmp/tree-2\n/tmp/tree-3\n/tmp/tree-4\n/tmp/tree-5\n/tmp/tree-6\n'
    }
    _git-wt-prompt-full-pool() { print -r -- 'cancel'; return 0; }

    When call _git-wt-allocate-slot
    The stderr should include 'cancelled'
    The status should be failure
  End
End

Describe '_git-wt-prompt-full-pool'
  setup_slots() {
    _git-wt-pool-slots() { printf '/tmp/tree-1\n/tmp/tree-2\n'; }
    _git-wt-slot-state() {
      case "$1" in
        */tree-1) print -r -- 'active' ;;
        */tree-2) print -r -- 'active' ;;
      esac
    }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'feature/foo' ;;
        */tree-2) print -r -- 'feature/bar' ;;
      esac
    }
  }

  It 'picks the slot indicated by a numeric choice'
    setup_slots
    Data
      #|2
    End

    When call _git-wt-prompt-full-pool
    The output should eq '/tmp/tree-2'
    The stderr should include 'pool is full (2 active slot(s))'
    The stderr should include '1. tree-1 [feature/foo]'
    The stderr should include '2. tree-2 [feature/bar]'
  End

  It 'returns grow on g'
    setup_slots
    Data
      #|g
    End

    When call _git-wt-prompt-full-pool
    The output should eq 'grow'
    The stderr should be defined
  End

  It 'returns cancel on q'
    setup_slots
    Data
      #|q
    End

    When call _git-wt-prompt-full-pool
    The output should eq 'cancel'
    The stderr should be defined
  End

  It 'returns cancel on out-of-range numeric input'
    setup_slots
    Data
      #|99
    End

    When call _git-wt-prompt-full-pool
    The output should eq 'cancel'
    The stderr should be defined
  End

  It 'returns cancel on unrecognized input'
    setup_slots
    Data
      #|xyz
    End

    When call _git-wt-prompt-full-pool
    The output should eq 'cancel'
    The stderr should be defined
  End

  It 'fails when no active/dirty/current slots exist'
    _git-wt-pool-slots() { :; }

    When call _git-wt-prompt-full-pool
    The status should be failure
  End
End

Describe '_git-wt-activate-slot'
  It 'records old HEAD, runs the checkout, and runs install when lockfile changed'
    _git-wt-lockfile-unchanged() { return 1; }
    _git-wt-install-deps() { print -r -- "install $*"; }

    Mock git
      case "$*" in
        "-C /tmp/tree-1 rev-parse HEAD")
          print -r -- abc123
          ;;
        "-C /tmp/tree-1 checkout -b feature main")
          print -r -- "git $*"
          ;;
        *)
          print -r -- "git $*" >&2
          return 1
          ;;
      esac
    End

    When call _git-wt-activate-slot /tmp/tree-1 1 checkout -b feature main
    The output should include 'git -C /tmp/tree-1 checkout -b feature main'
    The output should include 'install /tmp/tree-1'
  End

  It 'skips install when the lockfile is unchanged'
    _git-wt-lockfile-unchanged() { return 0; }
    _git-wt-install-deps() { print -r -- "install $*"; }

    Mock git
      case "$*" in
        "-C /tmp/tree-1 rev-parse HEAD")
          print -r -- abc123
          ;;
        "-C /tmp/tree-1 checkout feature")
          print -r -- "git $*"
          ;;
      esac
    End

    When call _git-wt-activate-slot /tmp/tree-1 1 checkout feature
    The output should include 'lockfile unchanged, skipping install'
    The output should not include 'install /tmp/tree-1'
  End

  It 'skips lockfile-check and install entirely when run_install=0'
    _git-wt-lockfile-unchanged() {
      print -r -- 'lockfile check should not run'
      return 1
    }
    _git-wt-install-deps() { print -r -- "install $*"; }

    Mock git
      case "$*" in
        "-C /tmp/tree-1 rev-parse HEAD") print -r -- abc123 ;;
        "-C /tmp/tree-1 checkout feature") print -r -- "git $*" ;;
      esac
    End

    When call _git-wt-activate-slot /tmp/tree-1 0 checkout feature
    The output should not include 'lockfile check should not run'
    The output should not include 'install'
  End
End

Describe 'gwta (allocate a slot with a new branch)'
  cd() {
    # shellcheck disable=SC2034
    GWTA_CD_PATH="$1"
    return 0
  }

  git-main-branch() {
    print -r -- 'main'
  }

  It 'cds into the existing slot when the branch is already checked out there'
    _git-wt-find-slot-by-branch() { print -r -- '/tmp/tree-2'; return 0; }

    When call gwta feature
    The output should include 'branch feature already in /tmp/tree-2'
    The variable GWTA_CD_PATH should eq '/tmp/tree-2'
    The status should be success
  End

  It 'allocates a slot, runs checkout -b from main, and cds in'
    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-3'; }
    _git-wt-activate-slot() { print -r -- "activate $*"; }

    When call gwta feature
    The output should include 'activating /tmp/tree-3 with new branch feature from main'
    The output should include 'activate /tmp/tree-3 1 checkout -b feature main'
    The variable GWTA_CD_PATH should eq '/tmp/tree-3'
  End

  It 'overrides the base when --base is supplied'
    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-1'; }
    _git-wt-activate-slot() { print -r -- "activate $*"; }

    When call gwta --base origin/main feature
    The output should include 'activating /tmp/tree-1 with new branch feature from origin/main'
    The output should include 'activate /tmp/tree-1 1 checkout -b feature origin/main'
  End

  It 'passes run_install=0 to activate-slot when --no-install is set'
    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-1'; }
    _git-wt-activate-slot() { print -r -- "activate $*"; }

    When call gwta --no-install feature
    The output should include 'activate /tmp/tree-1 0 checkout -b feature main'
  End

  It 'rejects unknown flags'
    When call gwta --weird foo
    The stderr should include 'unknown option'
    The status should be failure
  End

  It 'requires a branch name'
    When call gwta
    The stderr should include 'usage:'
    The status should be failure
  End
End

Describe 'gfmwta (fetch main, then gwta)'
  cd() {
    # shellcheck disable=SC2034
    GFMWTA_CD_PATH="$1"
    return 0
  }

  git-main-branch() {
    print -r -- 'main'
  }

  It 'fetches origin main:main and forwards args to gwta'
    Mock git
      case "$*" in
        "fetch origin main:main")
          print -r -- "git $*"
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    End

    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-1'; }
    _git-wt-activate-slot() { print -r -- "activate $*"; }

    When call gfmwta feature
    The output should include 'git fetch origin main:main'
    The output should include 'activating /tmp/tree-1 with new branch feature from main'
  End
End

Describe 'gwtco (allocate a slot with an existing branch)'
  cd() {
    # shellcheck disable=SC2034
    GWTCO_CD_PATH="$1"
    return 0
  }

  It 'cds into the existing slot when the branch is already checked out there'
    _git-wt-find-slot-by-branch() { print -r -- '/tmp/tree-2'; return 0; }

    When call gwtco feature
    The output should include 'branch feature already in /tmp/tree-2'
    The variable GWTCO_CD_PATH should eq '/tmp/tree-2'
  End

  It 'checks out an existing local branch'
    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-1'; }
    _git-wt-activate-slot() { print -r -- "activate $*"; }

    Mock git
      case "$*" in
        "show-ref --verify --quiet refs/heads/feature")
          return 0
          ;;
      esac
    End

    When call gwtco feature
    The output should include 'activating /tmp/tree-1 with local branch feature'
    The output should include 'activate /tmp/tree-1 1 checkout feature'
  End

  It 'tracks origin/<branch> when no local branch exists'
    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-1'; }
    _git-wt-activate-slot() { print -r -- "activate $*"; }

    Mock git
      case "$*" in
        "show-ref --verify --quiet refs/heads/remote-only")
          return 1
          ;;
        "show-ref --verify --quiet refs/remotes/origin/remote-only")
          return 0
          ;;
      esac
    End

    When call gwtco remote-only
    The output should include 'origin/remote-only as local branch remote-only'
    The output should include 'activate /tmp/tree-1 1 checkout --track -b remote-only origin/remote-only'
  End

  It 'fails when neither a local branch nor origin/<branch> exists'
    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-1'; }

    Mock git
      case "$*" in
        "show-ref --verify --quiet refs/heads/missing")
          return 1
          ;;
        "show-ref --verify --quiet refs/remotes/origin/missing")
          return 1
          ;;
      esac
    End

    When call gwtco missing
    The stderr should include 'no local or origin/missing ref found'
    The status should be failure
  End

  It 'passes run_install=0 when --no-install is set'
    _git-wt-find-slot-by-branch() { return 1; }
    _git-wt-allocate-slot() { print -r -- '/tmp/tree-1'; }
    _git-wt-activate-slot() { print -r -- "activate $*"; }

    Mock git
      case "$*" in
        "show-ref --verify --quiet refs/heads/feature")
          return 0
          ;;
      esac
    End

    When call gwtco --no-install feature
    The output should include 'activate /tmp/tree-1 0 checkout feature'
  End
End

Describe 'gwtcd (cd by fuzzy match)'
  cd() {
    # shellcheck disable=SC2034
    GWTCD_CD_PATH="$1"
    return 0
  }

  It 'cds into the primary worktree when given "root"'
    _git-main-worktree() { print -r -- /tmp/main-repo; }

    When call gwtcd root
    The variable GWTCD_CD_PATH should eq '/tmp/main-repo'
  End

  It 'cds into a slot when the query matches a slot directory name'
    _git-wt-pool-slots() { printf '/tmp/wt/tree-1\n/tmp/wt/tree-2\n/tmp/wt/tree-3\n'; }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'feature/foo' ;;
        */tree-2) ;;
        */tree-3) print -r -- 'feature/bar' ;;
      esac
    }

    When call gwtcd tree-2
    The variable GWTCD_CD_PATH should eq '/tmp/wt/tree-2'
  End

  It 'cds into a slot when the query matches a branch substring'
    _git-wt-pool-slots() { printf '/tmp/wt/tree-1\n/tmp/wt/tree-2\n'; }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'feature/foo' ;;
        */tree-2) print -r -- 'bugfix/bar' ;;
      esac
    }

    When call gwtcd bug
    The variable GWTCD_CD_PATH should eq '/tmp/wt/tree-2'
  End

  It 'fails with a candidate list on ambiguous match'
    _git-wt-pool-slots() { printf '/tmp/wt/tree-1\n/tmp/wt/tree-2\n'; }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'feature/foo' ;;
        */tree-2) print -r -- 'feature/bar' ;;
      esac
    }

    When call gwtcd feature
    The stderr should include 'ambiguous'
    The stderr should include 'feature/foo'
    The stderr should include 'feature/bar'
    The status should be failure
  End

  It 'fails with an available list on no match'
    _git-wt-pool-slots() { printf '/tmp/wt/tree-1\n'; }
    _git-wt-slot-branch() { print -r -- 'feature/foo'; }

    When call gwtcd nothing-here
    The stderr should include 'no slot matching'
    The stderr should include 'tree-1 (feature/foo)'
    The status should be failure
  End

  It 'fails when no slots exist at all'
    _git-wt-pool-slots() { :; }

    When call gwtcd anything
    The stderr should include 'no slots exist'
    The status should be failure
  End

  It 'requires a query argument'
    When call gwtcd
    The stderr should include 'usage:'
    The status should be failure
  End
End

Describe 'gwtl (list pool)'
  _git-main-worktree() { print -r -- /tmp/main-repo; }

  It 'prints header, then a main-repo row, then slots sorted by mtime desc'
    _git-wt-pool-slots() { printf '/tmp/wt/tree-1\n/tmp/wt/tree-2\n'; }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'feature/foo' ;;
        */tree-2) ;;
      esac
    }
    _git-wt-slot-state() {
      case "$1" in
        */tree-1) print -r -- 'active' ;;
        */tree-2) print -r -- 'idle' ;;
      esac
    }
    _git-wt-slot-mtime() {
      case "$1" in
        */tree-1) print -r -- '100' ;;
        */tree-2) print -r -- '999999999999' ;;
      esac
    }

    Mock git
      case "$*" in
        "-C /tmp/main-repo symbolic-ref --quiet --short HEAD")
          print -r -- 'main'
          ;;
      esac
    End

    When call gwtl
    The line 1 of output should include 'BRANCH'
    The line 1 of output should include 'STATE'
    The line 1 of output should include 'PATH'
    The line 2 of output should include 'main'
    The line 2 of output should include '(main repo)'
    The line 3 of output should include '<detached>'
    The line 3 of output should include 'tree-2'
    The line 4 of output should include 'feature/foo'
    The line 4 of output should include 'tree-1'
  End

  It 'prints only the header and main-repo row when no slots exist'
    _git-wt-pool-slots() { :; }

    Mock git
      case "$*" in
        "-C /tmp/main-repo symbolic-ref --quiet --short HEAD")
          return 1
          ;;
      esac
    End

    When call gwtl
    The line 1 of output should include 'BRANCH'
    The line 2 of output should include '<detached>'
    The line 2 of output should include '(main repo)'
  End
End

Describe '_git-wt-release-slot'
  # Hardcoded path because Mock blocks don't see Describe-level variables.
  BeforeEach 'mkdir -p /tmp/git-shorthand-spec-release-slot'
  AfterEach 'rm -rf /tmp/git-shorthand-spec-release-slot'

  It 'detaches HEAD and keeps the branch by default'
    _git-wt-slot-state() { print -r -- 'active'; }
    _git-wt-slot-branch() { print -r -- 'feature/foo'; }

    Mock git
      print -r -- "git $*"
      return 0
    End

    When call _git-wt-release-slot /tmp/git-shorthand-spec-release-slot
    The output should include 'detaching HEAD'
    The output should include 'git -C /tmp/git-shorthand-spec-release-slot checkout --detach HEAD'
    The output should not include 'deleting branch'
    The status should be success
  End

  It 'also deletes the branch when --delete-branch is set'
    _git-wt-slot-state() { print -r -- 'active'; }
    _git-wt-slot-branch() { print -r -- 'feature/foo'; }

    Mock git
      print -r -- "git $*"
      return 0
    End

    When call _git-wt-release-slot --delete-branch /tmp/git-shorthand-spec-release-slot
    The output should include 'deleting branch feature/foo'
    The output should include 'git branch -D feature/foo'
  End

  It 'refuses to release the current slot (no --force override)'
    _git-wt-slot-state() { print -r -- 'current'; }
    _git-wt-slot-branch() { print -r -- 'feature/foo'; }

    When call _git-wt-release-slot --force /tmp/git-shorthand-spec-release-slot
    The stderr should include 'refusing to release current slot'
    The status should be failure
  End

  It 'refuses dirty without --force'
    _git-wt-slot-state() { print -r -- 'dirty'; }
    _git-wt-slot-branch() { print -r -- 'feature/foo'; }

    When call _git-wt-release-slot /tmp/git-shorthand-spec-release-slot
    The stderr should include 'uncommitted changes'
    The status should be failure
  End

  It 'allows dirty with --force'
    _git-wt-slot-state() { print -r -- 'dirty'; }
    _git-wt-slot-branch() { print -r -- 'feature/foo'; }

    Mock git
      print -r -- "git $*"
      return 0
    End

    When call _git-wt-release-slot --force /tmp/git-shorthand-spec-release-slot
    The output should include 'detaching HEAD'
    The status should be success
  End
End

Describe 'gwtd (release slot holding <branch>)'
  It 'finds the slot and delegates to _git-wt-release-slot'
    _git-wt-find-slot-by-branch() { print -r -- '/tmp/tree-3'; return 0; }
    _git-wt-release-slot() { print -r -- "release $*"; return 0; }

    When call gwtd feature
    The output should include 'release /tmp/tree-3'
  End

  It 'forwards --delete-branch and --force flags'
    _git-wt-find-slot-by-branch() { print -r -- '/tmp/tree-3'; return 0; }
    _git-wt-release-slot() { print -r -- "release $*"; return 0; }

    When call gwtd --delete-branch --force feature
    The output should include 'release /tmp/tree-3 --delete-branch --force'
  End

  It 'fails when no slot holds the branch'
    _git-wt-find-slot-by-branch() { return 1; }

    When call gwtd feature
    The stderr should include 'no slot has branch feature'
    The status should be failure
  End

  It 'requires a branch argument'
    When call gwtd
    The stderr should include 'usage:'
    The status should be failure
  End
End

Describe 'gwtprune (release stale slots)'
  It 'releases (detach + delete-branch) slots whose branches are stale'
    Mock git
      case "$*" in
        "fetch --prune")
          print -r -- "git $*"
          ;;
        "worktree prune -v")
          print -r -- "git $*"
          ;;
      esac
    End

    _git-wt-pool-slots() { printf '/tmp/tree-1\n/tmp/tree-2\n/tmp/tree-3\n'; }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'merged' ;;
        */tree-2) ;;
        */tree-3) print -r -- 'active' ;;
      esac
    }
    _git-wt-slot-state() {
      case "$1" in
        */tree-1) print -r -- 'active' ;;
        */tree-3) print -r -- 'active' ;;
      esac
    }
    _git-stale-local-branches() { print -r -- 'merged'; }
    _git-wt-release-slot() { print -r -- "release $*"; return 0; }

    When call gwtprune
    The output should include 'fetching remotes with prune'
    The output should include 'git fetch --prune'
    The output should include 'releasing /tmp/tree-1 (merged)'
    The output should include 'release --delete-branch /tmp/tree-1'
    The output should not include 'release --delete-branch /tmp/tree-3'
    The output should include 'git worktree prune -v'
    The output should include 'released 1 slot(s), failed 0'
  End

  It 'skips dirty and current slots without classifying them as stale'
    Mock git
      case "$*" in
        "fetch --prune")
          print -r -- "git $*"
          ;;
        "worktree prune -v")
          print -r -- "git $*"
          ;;
      esac
    End

    _git-wt-pool-slots() { printf '/tmp/tree-1\n/tmp/tree-2\n'; }
    _git-wt-slot-branch() {
      case "$1" in
        */tree-1) print -r -- 'dirty-branch' ;;
        */tree-2) print -r -- 'current-branch' ;;
      esac
    }
    _git-wt-slot-state() {
      case "$1" in
        */tree-1) print -r -- 'dirty' ;;
        */tree-2) print -r -- 'current' ;;
      esac
    }
    _git-stale-local-branches() { :; }
    _git-wt-release-slot() { print -r -- "release $*"; return 0; }

    When call gwtprune
    The stderr should include 'skipping /tmp/tree-1 (dirty-branch, dirty)'
    The stderr should include 'skipping /tmp/tree-2 (current-branch, current)'
    The output should not include 'releasing'
    The output should include 'released 0 slot(s), failed 0'
  End
End
