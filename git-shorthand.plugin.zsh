# Get main branch name (master or main)
git-main-branch () {
    git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
}

# ---- Output coloring ---------------------------------------------------------
# Plugin status messages and the gwtl table get ANSI color when emitted to a
# TTY. Color is suppressed when any of these hold so plain text reaches files,
# pipes, dumb terminals, and the test runner:
#   - NO_COLOR is set (https://no-color.org)
#   - GIT_SHORTHAND_NO_COLOR is set (plugin-specific opt-out)
#   - TERM is dumb or unset
#   - the target stream is not a TTY
# Helper functions that *return data* on stdout (e.g. _git-wt-slot-state,
# _git-wt-pool-slots) deliberately stay uncolored so their output remains
# parseable by callers.
#
# Returns success when color should be emitted to fd $1 (default 1/stdout).
_git-sh-color-on () {
    [[ -n "${NO_COLOR-}" || -n "${GIT_SHORTHAND_NO_COLOR-}" ]] && return 1
    case "${TERM-}" in dumb|'') return 1 ;; esac
    case "${1:-1}" in
        1) [[ -t 1 ]] || return 1 ;;
        2) [[ -t 2 ]] || return 1 ;;
    esac
    return 0
}

# Populate $_GS_C_* globals for the appropriate output stream. Callers pass the
# fd that carries their primary user-facing output (1 for stdout, 2 for stderr).
# Vars are deliberately globals so we don't pay the cost of dozens of
# `$(_git-sh-c ...)` subshell invocations per print; each user-facing function
# re-initializes at the top, so leaking across calls is harmless.
#
# Semantic roles:
#   _GS_C_TAG    bold cyan   - tool prefixes ("gwta:", "gwtpool:", ...)
#   _GS_C_PATH   blue        - filesystem paths
#   _GS_C_BRANCH yellow      - branch refs
#   _GS_C_OK     green       - success / active state
#   _GS_C_WARN   yellow      - warnings, dirty state, skipped work
#   _GS_C_ERR    red         - failures
#   _GS_C_DIM    dim         - secondary info (idle slots, ages, footnotes)
#   _GS_C_BOLD   bold        - emphasis (table headers, current-slot marker)
#   _GS_C_RST    reset       - end of any color span
_git-sh-init-colors () {
    typeset -g _GS_C_RST="" _GS_C_BOLD="" _GS_C_DIM=""
    typeset -g _GS_C_TAG="" _GS_C_PATH="" _GS_C_BRANCH=""
    typeset -g _GS_C_OK="" _GS_C_WARN="" _GS_C_ERR=""

    _git-sh-color-on "${1:-1}" || return 0

    _GS_C_RST=$'\e[0m'
    _GS_C_BOLD=$'\e[1m'
    _GS_C_DIM=$'\e[2m'
    _GS_C_TAG=$'\e[1;36m'
    _GS_C_PATH=$'\e[34m'
    _GS_C_BRANCH=$'\e[33m'
    _GS_C_OK=$'\e[32m'
    _GS_C_WARN=$'\e[33m'
    _GS_C_ERR=$'\e[31m'
}

# Map a slot state ("idle"/"active"/"dirty"/"current") to its color escape.
# Returns the configured _GS_C_* for that state, or _GS_C_DIM as a safe default.
# Callers must have already run _git-sh-init-colors for the target fd.
_git-sh-state-color () {
    case "$1" in
        active)  print -nr -- "$_GS_C_OK" ;;
        dirty)   print -nr -- "$_GS_C_WARN$_GS_C_BOLD" ;;
        current) print -nr -- "$_GS_C_TAG" ;;
        idle)    print -nr -- "$_GS_C_DIM" ;;
        *)       print -nr -- "$_GS_C_DIM" ;;
    esac
}

# Git shorthand aliases
alias ga="git add"
alias gaa="git add --all"
alias gs="git status"
alias gsd="git status; git diff"
alias gbs="git branch; git status"
alias gc="git commit -m"
alias gd="git diff"
alias gdx="git diff --staged"
alias gda="git diff HEAD"
alias gsc="git status; git commit -m"
alias gaas="git add --all; git status"
alias gst="git stash"
alias gaast="git add --all; git stash"
alias gstl="git stash list"
alias gstpo="git stash pop"
alias gp="git pull"
alias gpp="git push"
alias gb="git branch"
# Wrapper around git checkout. When the target branch is already checked out in
# another worktree, interactive shells may cd there via gwtcd instead.
gco () {
    local err wt_path output
    err=$(mktemp "${TMPDIR:-/tmp}/git-shorthand-gco.XXXXXX") || return 1

    if git checkout "$@" 2>"$err"; then
        [[ -s "$err" ]] && cat "$err" >&2
        rm -f "$err"
        return 0
    fi

    output=$(<"$err")
    rm -f "$err"

    if wt_path=$(_git-co-parse-worktree-in-use "$output"); then
        print -r -- "$output" >&2
        _git-co-offer-gwtcd "$wt_path" && return 0
        return 1
    fi

    print -r -- "$output" >&2
    return 1
}

alias gcob="git checkout -b"
alias gl="git log"
alias gpr="git pull --rebase --autostash"

# Aliases for working with main branch
alias gfm="git fetch origin \$(git-main-branch):\$(git-main-branch)"  # Fetch main
# Checkout main; uses gco so a branch held in a pool slot can route to gwtcd.
gcom () {
    gco "$(git-main-branch)"
}

# Git shorthand functions
gcpp () {
	git commit -m "$*"
	git push
}

gcobpp () {
	git checkout -b "$1"
	git push -u origin "$1"
}

gaascpp () {
	git add --all
	git status
	git commit -m "$*"
	git push
}

gaacpp () {
	git add --all
	git commit -m "$*"
	git push
}

gaac () {
	git add --all
	git commit -m "$*"
}

# From https://gist.github.com/lttlrck/9628955
grnb () {
	local oldBranch
	oldBranch=$(git rev-parse --abbrev-ref HEAD)

	git branch -m "$oldBranch" "$1"
	git push origin ":$oldBranch"
	git push --set-upstream origin "$1"
}

git-obliterate () {
	git branch -d "$1" &&
	git push origin ":$1"
}

# Git functions for main branch operations
# New branch from main (without checking out main)
gnb () {
    git switch -c "$1" "$(git-main-branch)"
}

# New branch from main and push
gnbpp () {
    git switch -c "$1" "$(git-main-branch)"
    git push -u origin "$1"
}

# Fetch main and new branch from it
gfmnb () {
    git fetch origin "$(git-main-branch):$(git-main-branch)"
    git switch -c "$1" "$(git-main-branch)"
}

# Worktree operations
# Worktrees live in a recycled pool under ../{repo_name}-worktrees/tree-N.
# Each slot keeps its own node_modules. Activating a slot checks out a branch
# into it; install only runs when the lockfile actually changed.
#
# Slot states (mutually exclusive; current wins over the rest, dirty wins over
# active/idle):
#   idle    - detached HEAD, clean working tree (eligible for reuse).
#   active  - branch checked out, clean.
#   dirty   - uncommitted or untracked changes (never auto-reused).
#   current - cwd is inside the slot (never auto-released or auto-reused).
#
# The soft cap is the point at which gwta/gfmwta/gwtco will stop lazily
# creating new slots and instead prompt the user to release one or grow.
typeset -g _GIT_WT_POOL_SOFT_CAP=6

# Helper: extract the holding worktree path from a failed git checkout message.
_git-co-parse-worktree-in-use () {
    local msg="$1"

    if [[ "$msg" =~ ' (is already used by worktree|is already checked out) at '\''([^'\'']+)'\''' ]]; then
        print -r -- "${match[2]}"
        return 0
    fi

    return 1
}

# Helper: whether gco may prompt (stdin, stderr, or /dev/tty is an interactive terminal).
_git-co-can-prompt () {
    [[ -t 0 || -t 2 || -r /dev/tty ]]
}

# Helper: read one line for gco prompts from stdin or /dev/tty when stdin is redirected.
_git-co-read-line () {
    if [[ -t 0 ]]; then
        read -r "$@" && return 0
        return 1
    fi

    # Piped stdin (tests, yes | gco): consume the pipe before opening /dev/tty.
    if read -r "$@"; then
        return 0
    fi

    if [[ -r /dev/tty ]]; then
        read -r "$@" < /dev/tty && return 0
    fi

    return 1
}

# Helper: gwtcd query for a worktree path (root for the primary checkout, else slot basename).
_git-co-gwtcd-target-for-path () {
    local wt_path="$1"
    local main_wt

    main_wt=$(_git-main-worktree 2>/dev/null)
    if [[ -n "$main_wt" && "$wt_path" == "$main_wt" ]]; then
        print -r -- "root"
        return 0
    fi

    print -r -- "${wt_path:t}"
}

# Helper: offer to cd into the worktree that holds the branch in interactive shells.
_git-co-offer-gwtcd () {
    local wt_path="$1"
    local gwtcd_target

    _git-co-can-prompt || return 1

    gwtcd_target=$(_git-co-gwtcd-target-for-path "$wt_path")

    _git-sh-init-colors 2

    print -n -- "${_GS_C_TAG}gco:${_GS_C_RST} ${_GS_C_BRANCH}$gwtcd_target${_GS_C_RST} holds this branch at ${_GS_C_PATH}$wt_path${_GS_C_RST}. ${_GS_C_BOLD}Go there now? [y/N]:${_GS_C_RST} " >&2
    local reply
    if ! _git-co-read-line reply; then
        return 1
    fi

    case "$reply" in
        y|Y|yes|YES)
            if gwtcd "$gwtcd_target" 2>/dev/null; then
                return 0
            fi
            cd "$wt_path" || return 1
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Helper: resolve the main worktree directory for the current repo.
_git-main-worktree () {
    git worktree list --porcelain | sed -n 's/^worktree //p' | head -1
}

# Helper: plugin worktrees base directory for a given main worktree path.
_git-wt-base-from-main () {
    local main_wt="$1"
    [[ -n "$main_wt" ]] || return 1
    print -r -- "$(dirname "$main_wt")/$(basename "$main_wt")-worktrees"
}

# Helper: resolve the current gwtcd target name.
# Returns the worktree directory basename, or "root" when on the primary (non-linked) worktree.
_git-current-wt-target () {
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1

    local main_wt
    main_wt=$(_git-main-worktree 2>/dev/null)

    if [[ -n "$main_wt" && "$repo_root" == "$main_wt" ]]; then
        print -r -- "root"
    else
        basename "$repo_root"
    fi
}

# Helper: resolve the worktrees base directory for the current repo.
# Works from the main repo or from inside any worktree.
_git-wt-base () {
    local main_wt
    main_wt=$(_git-main-worktree)
    [[ -n "$main_wt" ]] || return 1
    _git-wt-base-from-main "$main_wt"
}

# Helper: copy root node_modules as a warm cache; package-manager install still
# repairs the result. Used by _git-wt-grow-pool to warm freshly created slots.
_git-wt-seed-node-modules () {
    local source_root="$1"
    local target_root="$2"

    _git-sh-init-colors 2

    if [[ ! -d "$source_root/node_modules" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} no node_modules found at ${_GS_C_PATH}$source_root${_GS_C_RST}; skipping cache seed" >&2
        return 0
    fi

    if [[ -e "$target_root/node_modules" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} node_modules already exists in target; skipping cache seed" >&2
        return 0
    fi

    print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} copying node_modules from ${_GS_C_PATH}$source_root${_GS_C_RST}" >&2
    mkdir -p "$target_root/node_modules"
    rsync -a "$source_root/node_modules/" "$target_root/node_modules/"
}

# Helper: use mise-pinned tools when available, while still working in small repos without mise.
_git-wt-run-with-optional-mise () {
    if command -v mise >/dev/null 2>&1; then
        # `--yes` auto-confirms mise's "trust this config?" TUI prompt, which
        # would otherwise block install when activating a slot in a freshly
        # checked-out branch whose mise.toml hasn't been seen before. The
        # slot's config is the user's own repo at a branch they just asked us
        # to activate, so silent trust matches the rest of the activation
        # flow (which also runs the project's install scripts unprompted).
        mise --yes exec -- "$@"
        return
    fi

    "$@"
}

# Helper: detect the lockfile path (relative to slot) for lockfile-aware install.
# Priority mirrors _git-wt-install-deps: pnpm > yarn > npm.
_git-wt-detect-lockfile () {
    local slot="$1"

    if [[ -f "$slot/pnpm-lock.yaml" ]]; then
        print -r -- "pnpm-lock.yaml"
        return 0
    fi
    if [[ -f "$slot/yarn.lock" ]]; then
        print -r -- "yarn.lock"
        return 0
    fi
    if [[ -f "$slot/package-lock.json" ]]; then
        print -r -- "package-lock.json"
        return 0
    fi
    return 1
}

# Helper: run the detected package manager so seeded dependencies match the target lockfile.
_git-wt-install-deps () {
    local target_root="$1"

    _git-sh-init-colors 1

    if [[ -f "$target_root/pnpm-lock.yaml" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} running ${_GS_C_BOLD}pnpm install --prefer-offline${_GS_C_RST}"
        (cd "$target_root" && _git-wt-run-with-optional-mise pnpm install --prefer-offline)
        return
    fi

    if [[ -f "$target_root/yarn.lock" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} running ${_GS_C_BOLD}yarn install${_GS_C_RST}"
        (cd "$target_root" && _git-wt-run-with-optional-mise yarn install)
        return
    fi

    if [[ -f "$target_root/package-lock.json" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} running ${_GS_C_BOLD}npm ci --prefer-offline${_GS_C_RST}"
        (cd "$target_root" && _git-wt-run-with-optional-mise npm ci --prefer-offline)
        return
    fi

    if [[ -f "$target_root/package.json" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} running ${_GS_C_BOLD}npm install --prefer-offline${_GS_C_RST}"
        (cd "$target_root" && _git-wt-run-with-optional-mise npm install --prefer-offline)
        return
    fi

    print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} no package manifest found; skipping install"
}

# Helper: returns 0 when the slot's lockfile matches between old_head and current HEAD;
# returns 1 in every other case (no old HEAD, no lockfile, contents differ). Callers use
# this to decide whether to skip an install.
_git-wt-lockfile-unchanged () {
    local slot="$1"
    local old_head="$2"

    [[ -n "$old_head" ]] || return 1

    local lockfile
    lockfile=$(_git-wt-detect-lockfile "$slot") || return 1

    git -C "$slot" diff --quiet "$old_head" HEAD -- "$lockfile" 2>/dev/null
}

# Helper: run an optional pool-local post-checkout script after activation.
# Looks for an executable `post-checkout` at the worktrees base (sibling to tree-N
# slots), not inside the git repo. Args: slot path, old HEAD, main_lockfile_unchanged.
_git-wt-run-post-checkout () {
    local slot="$1"
    local old_head="$2"
    local main_lockfile_unchanged="$3"

    local wt_base hook
    wt_base=$(_git-wt-base) || return 0
    hook="$wt_base/post-checkout"
    [[ -x "$hook" ]] || return 0

    _git-sh-init-colors 2
    print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} running post-checkout" >&2
    (
        cd "$slot" || exit 1
        export GWT_SLOT="$slot"
        export GWT_OLD_HEAD="$old_head"
        export GWT_MAIN_LOCKFILE_UNCHANGED="$main_lockfile_unchanged"
        _git-wt-run-with-optional-mise "$hook" "$slot" "$old_head"
    ) || return 1
}

# Helper: emit pool slot paths matching tree-<int>, sorted by N ascending.
# sort -V handles tree-1, tree-2, ..., tree-10 in natural order. The directory
# glob is broad on purpose (tree-*); the regex filter limits to numeric suffixes
# (zsh's <-> glob would be tighter, but shellcheck-as-bash can't parse it).
_git-wt-pool-slots () {
    local wt_base
    wt_base=$(_git-wt-base) || return 1
    [[ -d "$wt_base" ]] || return 0

    setopt local_options extended_glob no_nomatch
    local -a slots
    local entry name
    for entry in "$wt_base"/tree-*(N/); do
        name="${entry:t}"
        [[ "$name" =~ ^tree-[0-9]+$ ]] || continue
        slots+=("$entry")
    done
    (( ${#slots} )) || return 0

    printf '%s\n' "${slots[@]}" | sort -V
}

# Helper: branch name checked out in a slot, empty when detached.
# Returns 0 when the slot exists even if HEAD is detached — symbolic-ref exit 1
# is normal there and must not trip errexit in callers (e.g. _git-wt-slot-state).
_git-wt-slot-branch () {
    local slot="$1"
    [[ -d "$slot" ]] || return 1

    git -C "$slot" symbolic-ref --quiet --short HEAD 2>/dev/null || :
    return 0
}

# Helper: mtime of a slot path. Used by _git-wt-pick-idle-slot for "oldest first"
# and by gwtl for sort-by-recency.
#
# Probes which stat flavor is on PATH because plain `stat -f '%m'` is not safe
# to try first: on GNU coreutils (Linux, or homebrew on macOS) `-f` means
# "display file system status" and prints a multi-line `df`-style block, which
# previously got captured into mtime and broke gwtl's arithmetic.
_git-wt-slot-mtime () {
    local slot="$1"
    [[ -d "$slot" ]] || return 1

    if stat --version >/dev/null 2>&1; then
        stat -c '%Y' "$slot" 2>/dev/null
    else
        stat -f '%m' "$slot" 2>/dev/null
    fi
}

# Helper: classify a slot. Returns one of idle/active/dirty/current.
# Precedence: current beats everything (we never auto-release or auto-reuse the
# slot we are in); dirty beats active/idle (an uncommitted slot is never safe
# to reuse).
#
# "Dirty" intentionally means "tracked-file changes vs HEAD" — staged or
# unstaged. Untracked files do NOT count: in a warm-slot pool they are
# typically build artifacts (node_modules, dist/, etc., often gitignored
# anyway), and `git checkout` preserves untracked files across branch
# switches, so they don't represent data loss when a slot is recycled.
#
# `diff-index --quiet HEAD` is also several times faster than
# `status --porcelain` on a large repo because it skips the untracked-file
# enumeration — but on a multi-gigabyte monorepo it still costs ~0.2–0.5s
# per slot for the stat scan, which is the dominant cost when iterating a
# full pool. Callers that don't need a load-bearing dirty signal can pass
# any non-empty second argument to skip it (the slot then comes back as
# active/idle/current only).
#
# Safety-critical callers (slot recycling via _git-wt-pick-idle-slot, and
# `gwtd`) must NOT pass that flag — skipping the check there would risk
# silently recycling a slot with uncommitted work.
_git-wt-slot-state () {
    local slot="$1"
    local skip_dirty="${2-}"
    [[ -d "$slot" ]] || return 1

    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$repo_root" && "$repo_root" == "$slot" ]]; then
        print -r -- "current"
        return
    fi

    if [[ -z "$skip_dirty" ]]; then
        # Reconcile index stat cache before diff-index (same idea as `git status`).
        # Without this, diff-index can report dirty when only mtimes drifted or
        # fsmonitor left the index stale — while status looks clean.
        git -C "$slot" update-index --refresh >/dev/null 2>&1 || true

        # diff-index exit codes: 0 = clean, 1 = tracked-file changes vs HEAD,
        # >1 = real error (e.g. no HEAD on a brand-new worktree). Only treat
        # exit 1 as dirty so a fresh detached slot doesn't get mislabeled.
        local rc=0
        git -C "$slot" diff-index --quiet HEAD -- 2>/dev/null || rc=$?
        if (( rc == 1 )); then
            print -r -- "dirty"
            return
        fi
    fi

    local branch
    branch=$(_git-wt-slot-branch "$slot")
    if [[ -n "$branch" ]]; then
        print -r -- "active"
    else
        print -r -- "idle"
    fi
}

# Helper: find a slot that already has the given branch checked out.
_git-wt-find-slot-by-branch () {
    local target_branch="$1"
    [[ -n "$target_branch" ]] || return 1

    local slot branch
    for slot in "${(@f)$(_git-wt-pool-slots)}"; do
        [[ -z "$slot" ]] && continue
        branch=$(_git-wt-slot-branch "$slot")
        if [[ "$branch" == "$target_branch" ]]; then
            print -r -- "$slot"
            return 0
        fi
    done
    return 1
}

# Helper: pick the oldest idle slot by mtime, or fail when none exist.
_git-wt-pick-idle-slot () {
    local oldest_mtime="" oldest_slot=""
    local slot mtime state
    for slot in "${(@f)$(_git-wt-pool-slots)}"; do
        [[ -z "$slot" ]] && continue
        state=$(_git-wt-slot-state "$slot")
        [[ "$state" == "idle" ]] || continue

        mtime=$(_git-wt-slot-mtime "$slot")
        if [[ -z "$oldest_mtime" || "$mtime" -lt "$oldest_mtime" ]]; then
            oldest_mtime="$mtime"
            oldest_slot="$slot"
        fi
    done

    [[ -n "$oldest_slot" ]] || return 1
    print -r -- "$oldest_slot"
}

# Helper: create the next tree-N slot from current HEAD and seed node_modules
# from the primary worktree. Prints the new slot path on success (UI on stderr).
_git-wt-grow-pool () {
    local wt_base
    wt_base=$(_git-wt-base) || return 1
    mkdir -p "$wt_base"

    local -a slots
    slots=("${(@f)$(_git-wt-pool-slots)}")

    local max_n=0 slot name num
    for slot in "${slots[@]}"; do
        [[ -z "$slot" ]] && continue
        name="${slot:t}"
        num="${name#tree-}"
        if (( num > max_n )); then
            max_n=$num
        fi
    done

    local next_n=$(( max_n + 1 ))
    local new_slot="$wt_base/tree-$next_n"

    _git-sh-init-colors 2
    print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} creating ${_GS_C_PATH}$new_slot${_GS_C_RST}" >&2
    git worktree add --detach "$new_slot" HEAD >&2 || return 1

    local main_wt
    main_wt=$(_git-main-worktree)
    if [[ -n "$main_wt" && "$main_wt" != "$new_slot" ]]; then
        _git-wt-seed-node-modules "$main_wt" "$new_slot" || return 1
    fi

    print -r -- "$new_slot"
}

# Helper: interactive picker shown when the pool is full. Lists active/dirty/current
# slots with branch and marker, plus "g" to grow and "q" to cancel. Emits the chosen
# slot path, "grow", or "cancel" on stdout; UI lines go to stderr so callers can
# capture the choice cleanly.
_git-wt-prompt-full-pool () {
    local -a active_slots active_branches active_states
    local slot branch state
    for slot in "${(@f)$(_git-wt-pool-slots)}"; do
        [[ -z "$slot" ]] && continue
        state=$(_git-wt-slot-state "$slot")
        # Idle slots wouldn't have brought us here; show everything else.
        [[ "$state" == "active" || "$state" == "dirty" || "$state" == "current" ]] || continue
        active_slots+=("$slot")
        active_branches+=("$(_git-wt-slot-branch "$slot")")
        active_states+=("$state")
    done

    if (( ${#active_slots} == 0 )); then
        return 1
    fi

    _git-sh-init-colors 2

    print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} pool is full (${_GS_C_BOLD}${#active_slots}${_GS_C_RST} active slot(s)):" >&2

    local i name marker marker_color state_color
    for (( i=1; i<=${#active_slots}; i++ )); do
        slot="${active_slots[$i]}"
        branch="${active_branches[$i]}"
        state="${active_states[$i]}"
        name="${slot:t}"
        marker=""
        marker_color=""
        if [[ "$state" == "dirty" ]]; then
            marker=" (dirty)"
            marker_color="$_GS_C_WARN"
        elif [[ "$state" == "current" ]]; then
            marker=" (current)"
            marker_color="$_GS_C_TAG"
        fi
        state_color=$(_git-sh-state-color "$state")
        print -r -- "  ${_GS_C_BOLD}$i.${_GS_C_RST} ${state_color}$name${_GS_C_RST} [${_GS_C_BRANCH}${branch:-<detached>}${_GS_C_RST}]${marker_color}${marker}${_GS_C_RST}" >&2
    done
    print -r -- "  ${_GS_C_BOLD}g.${_GS_C_RST} ${_GS_C_OK}grow pool${_GS_C_RST} (create a new slot)" >&2
    print -r -- "  ${_GS_C_BOLD}q.${_GS_C_RST} ${_GS_C_ERR}cancel${_GS_C_RST}" >&2

    print -n -- "${_GS_C_BOLD}Choice:${_GS_C_RST} " >&2
    local choice
    if ! read -r choice; then
        if ! [[ -t 0 ]]; then
            print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} stdin is not a tty and input ended; cannot prompt for a slot to recycle" >&2
            print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} release a slot with ${_GS_C_BOLD}gwtd${_GS_C_RST}, run ${_GS_C_BOLD}gwtprune${_GS_C_RST}/${_GS_C_BOLD}gbprune${_GS_C_RST}, or run from an interactive shell" >&2
            return 1
        fi
        choice=""
    fi

    case "$choice" in
        g|G)
            print -r -- "grow"
            ;;
        q|Q|"")
            print -r -- "cancel"
            ;;
        *)
            # Numeric choice picks a slot; anything else cancels.
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#active_slots} )); then
                print -r -- "${active_slots[$choice]}"
            else
                print -r -- "cancel"
            fi
            ;;
    esac
}

# Helper: release a slot back into the pool. Detaches HEAD so the slot is idle
# again. Guards against releasing the current slot or a dirty slot (--force
# overrides dirty but not current). Optionally also deletes the branch that was
# checked out.
_git-wt-release-slot () {
    local slot=""
    local delete_branch=0 force=0

    _git-sh-init-colors 1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --delete-branch)
                delete_branch=1
                shift
                ;;
            --force)
                force=1
                shift
                ;;
            *)
                [[ -z "$slot" ]] || {
                    print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} ${_GS_C_ERR}extra argument:${_GS_C_RST} $1" >&2
                    return 1
                }
                slot="$1"
                shift
                ;;
        esac
    done

    [[ -n "$slot" && -d "$slot" ]] || {
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} ${_GS_C_ERR}invalid slot:${_GS_C_RST} $slot" >&2
        return 1
    }

    local state
    state=$(_git-wt-slot-state "$slot") || return 1

    if [[ "$state" == "current" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} ${_GS_C_ERR}refusing to release current slot${_GS_C_RST} (${_GS_C_PATH}$slot${_GS_C_RST}); cd elsewhere first" >&2
        return 1
    fi

    if [[ "$state" == "dirty" && $force -eq 0 ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} ${_GS_C_PATH}$slot${_GS_C_RST} has ${_GS_C_WARN}uncommitted changes${_GS_C_RST}; commit/stash first, or use ${_GS_C_BOLD}--force${_GS_C_RST}" >&2
        return 1
    fi

    local branch
    branch=$(_git-wt-slot-branch "$slot")

    if [[ -n "$branch" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} detaching HEAD in ${_GS_C_PATH}$slot${_GS_C_RST} (was ${_GS_C_BRANCH}$branch${_GS_C_RST})"
        git -C "$slot" checkout --detach HEAD || return 1
    fi

    if (( delete_branch )) && [[ -n "$branch" ]]; then
        print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} deleting branch ${_GS_C_BRANCH}$branch${_GS_C_RST}"
        git branch -D "$branch" || return 1
    fi
}

# Helper: allocate a slot for a new activation. Prefers the oldest idle slot,
# lazily grows the pool up to _GIT_WT_POOL_SOFT_CAP, then falls back to the
# interactive picker when the pool is full. Prints the chosen slot path on stdout.
#
# Callers must check _git-wt-find-slot-by-branch first; this helper assumes the
# requested branch is NOT already in a slot.
_git-wt-allocate-slot () {
    local slot
    if slot=$(_git-wt-pick-idle-slot); then
        print -r -- "$slot"
        return 0
    fi

    local -a slots
    slots=("${(@f)$(_git-wt-pool-slots)}")

    local count=0 s
    for s in "${slots[@]}"; do
        [[ -n "$s" ]] && (( count++ ))
    done

    if (( count < _GIT_WT_POOL_SOFT_CAP )); then
        _git-wt-grow-pool || return 1
        return 0
    fi

    local choice
    choice=$(_git-wt-prompt-full-pool) || return 1
    case "$choice" in
        grow)
            _git-wt-grow-pool || return 1
            ;;
        cancel|"")
            _git-sh-init-colors 2
            print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} ${_GS_C_DIM}cancelled${_GS_C_RST}" >&2
            return 1
            ;;
        *)
            _git-wt-release-slot "$choice" >&2 || return 1
            print -r -- "$choice"
            ;;
    esac
}

# Helper: perform the checkout-and-conditional-install dance inside a slot.
# Captures the slot's HEAD before checkout so the post-checkout lockfile diff
# can decide whether to skip install. Remaining args after run_install are the
# git command to run inside the slot (e.g. checkout -b feature main).
_git-wt-activate-slot () {
    local slot="$1"
    local run_install="$2"
    shift 2

    local old_head
    old_head=$(git -C "$slot" rev-parse HEAD 2>/dev/null)

    git -C "$slot" "$@" || return 1

    if (( run_install )); then
        local main_lockfile_unchanged=0
        if _git-wt-lockfile-unchanged "$slot" "$old_head"; then
            main_lockfile_unchanged=1
            _git-sh-init-colors 1
            print -r -- "${_GS_C_TAG}gwtpool:${_GS_C_RST} ${_GS_C_DIM}lockfile unchanged, skipping install${_GS_C_RST}"
        else
            _git-wt-install-deps "$slot" || return 1
        fi
        _git-wt-run-post-checkout "$slot" "$old_head" "$main_lockfile_unchanged" || return 1
    fi
}

# Allocate a slot and create a new branch in it from main (or --base).
gwta () {
    local base_ref="" branch=""
    local run_install=1

    _git-sh-init-colors 1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)
                [[ $# -ge 2 ]] || {
                    print -r -- "${_GS_C_TAG}gwta:${_GS_C_RST} ${_GS_C_ERR}--base requires a ref${_GS_C_RST}" >&2
                    return 1
                }
                base_ref="$2"
                shift 2
                ;;
            --no-install)
                run_install=0
                shift
                ;;
            -h|--help)
                print -r -- "usage: gwta [--base <ref>] [--no-install] <branch>"
                return 0
                ;;
            -*)
                print -r -- "${_GS_C_TAG}gwta:${_GS_C_RST} ${_GS_C_ERR}unknown option:${_GS_C_RST} $1" >&2
                return 1
                ;;
            *)
                [[ -z "$branch" ]] || {
                    print -r -- "${_GS_C_TAG}gwta:${_GS_C_RST} expected one branch, got extra argument: $1" >&2
                    return 1
                }
                branch="$1"
                shift
                ;;
        esac
    done

    [[ -n "$branch" ]] || {
        print -r -- "usage: gwta [--base <ref>] [--no-install] <branch>" >&2
        return 1
    }

    [[ -n "$base_ref" ]] || base_ref="$(git-main-branch)"

    local slot
    if slot=$(_git-wt-find-slot-by-branch "$branch"); then
        print -r -- "${_GS_C_TAG}gwta:${_GS_C_RST} branch ${_GS_C_BRANCH}$branch${_GS_C_RST} already in ${_GS_C_PATH}$slot${_GS_C_RST}"
        cd "$slot" || return 1
        return 0
    fi

    slot=$(_git-wt-allocate-slot) || return 1

    print -r -- "${_GS_C_TAG}gwta:${_GS_C_RST} activating ${_GS_C_PATH}$slot${_GS_C_RST} with new branch ${_GS_C_BRANCH}$branch${_GS_C_RST} from ${_GS_C_BRANCH}$base_ref${_GS_C_RST}"
    _git-wt-activate-slot "$slot" "$run_install" checkout -b "$branch" "$base_ref" || return 1

    cd "$slot" || return 1
    print -r -- "${_GS_C_TAG}gwta:${_GS_C_RST} ${_GS_C_OK}ready:${_GS_C_RST} ${_GS_C_PATH}$slot${_GS_C_RST}"
}

# Fetch main, then gwta. Flags forward straight through.
gfmwta () {
    git fetch origin "$(git-main-branch):$(git-main-branch)" || return 1
    gwta "$@"
}

# Allocate a slot and check out an existing branch (local first, else origin/<branch>).
gwtco () {
    local branch=""
    local run_install=1

    _git-sh-init-colors 1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-install)
                run_install=0
                shift
                ;;
            -h|--help)
                print -r -- "usage: gwtco [--no-install] <branch>"
                return 0
                ;;
            -*)
                print -r -- "${_GS_C_TAG}gwtco:${_GS_C_RST} ${_GS_C_ERR}unknown option:${_GS_C_RST} $1" >&2
                return 1
                ;;
            *)
                [[ -z "$branch" ]] || {
                    print -r -- "${_GS_C_TAG}gwtco:${_GS_C_RST} expected one branch, got extra argument: $1" >&2
                    return 1
                }
                branch="$1"
                shift
                ;;
        esac
    done

    [[ -n "$branch" ]] || {
        print -r -- "usage: gwtco [--no-install] <branch>" >&2
        return 1
    }

    local slot
    if slot=$(_git-wt-find-slot-by-branch "$branch"); then
        print -r -- "${_GS_C_TAG}gwtco:${_GS_C_RST} branch ${_GS_C_BRANCH}$branch${_GS_C_RST} already in ${_GS_C_PATH}$slot${_GS_C_RST}"
        cd "$slot" || return 1
        return 0
    fi

    slot=$(_git-wt-allocate-slot) || return 1

    if git show-ref --verify --quiet "refs/heads/$branch"; then
        print -r -- "${_GS_C_TAG}gwtco:${_GS_C_RST} activating ${_GS_C_PATH}$slot${_GS_C_RST} with local branch ${_GS_C_BRANCH}$branch${_GS_C_RST}"
        _git-wt-activate-slot "$slot" "$run_install" checkout "$branch" || return 1
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        print -r -- "${_GS_C_TAG}gwtco:${_GS_C_RST} activating ${_GS_C_PATH}$slot${_GS_C_RST} with ${_GS_C_BRANCH}origin/$branch${_GS_C_RST} as local branch ${_GS_C_BRANCH}$branch${_GS_C_RST}"
        _git-wt-activate-slot "$slot" "$run_install" checkout --track -b "$branch" "origin/$branch" || return 1
    else
        print -r -- "${_GS_C_TAG}gwtco:${_GS_C_RST} ${_GS_C_ERR}no local or origin/$branch ref found${_GS_C_RST}" >&2
        return 1
    fi

    cd "$slot" || return 1
    print -r -- "${_GS_C_TAG}gwtco:${_GS_C_RST} ${_GS_C_OK}ready:${_GS_C_RST} ${_GS_C_PATH}$slot${_GS_C_RST}"
}

# Helper: drop -, _, and / for separator-insensitive slot-name matching.
_git-wt-strip-name-separators () {
    print -r -- "${1//[\-_\/]/}"
}

# Helper: lower score is a better slot-directory match for gwtcd.
# Emits the score on stdout; returns 1 when the name does not match.
_git-wt-gwtcd-name-score () {
    local name="$1" query="$2"
    local q_norm n_norm

    if [[ "$name" == "$query" ]]; then
        print -r -- 0
        return 0
    fi

    if [[ "$name" == *"$query"* ]]; then
        print -r -- $(( 1000 + ${#name} - ${#query} ))
        return 0
    fi

    q_norm="$(_git-wt-strip-name-separators "$query")"
    [[ -n "$q_norm" ]] || return 1

    n_norm="$(_git-wt-strip-name-separators "$name")"

    if [[ "$n_norm" == "$q_norm" ]]; then
        print -r -- 2000
        return 0
    fi

    if [[ "$n_norm" == *"$q_norm"* ]]; then
        print -r -- $(( 3000 + ${#n_norm} - ${#q_norm} ))
        return 0
    fi

    return 1
}

# Helper: tie-break equal name scores (lower is better).
_git-wt-gwtcd-name-tiebreak () {
    local name="$1" stripped

    stripped="$(_git-wt-strip-name-separators "$name")"
    print -r -- $(( (${#name} - ${#stripped}) * 1000 + ${#name} ))
}

# cd into a slot by fuzzy substring match against slot directory names AND branch
# names. The primary checkout participates as the synthetic "root" slot, so the
# literal "root" and the branch it currently holds (e.g. "main") both route to
# it. Ambiguous matches print the candidate list and fail; no match prints
# what's available and fails.
gwtcd () {
    local query="$1"

    _git-sh-init-colors 2

    [[ -n "$query" ]] || {
        print -r -- "usage: gwtcd <fuzzy>" >&2
        return 2
    }

    local main_wt
    main_wt=$(_git-main-worktree 2>/dev/null)

    # The literal target "root" always routes to the primary checkout.
    if [[ "$query" == "root" ]]; then
        [[ -n "$main_wt" ]] || return 1
        cd "$main_wt" || return 1
        return 0
    fi

    local -a slot_paths slot_names slot_branches
    local slot

    # Seed the candidate set with the primary checkout so its current branch is
    # matchable by substring (e.g. `gwtcd main` when root holds main). Listing
    # it first makes it lead the ambiguity/no-match reports below.
    if [[ -n "$main_wt" ]]; then
        slot_paths+=("$main_wt")
        slot_names+=("root")
        slot_branches+=("$(_git-wt-slot-branch "$main_wt")")
    fi

    for slot in "${(@f)$(_git-wt-pool-slots)}"; do
        [[ -z "$slot" ]] && continue
        slot_paths+=("$slot")
        slot_names+=("${slot:t}")
        slot_branches+=("$(_git-wt-slot-branch "$slot")")
    done

    if (( ${#slot_paths} == 0 )); then
        print -r -- "${_GS_C_TAG}gwtcd:${_GS_C_RST} ${_GS_C_DIM}no slots exist; create one with${_GS_C_RST} ${_GS_C_BOLD}gwta${_GS_C_RST}/${_GS_C_BOLD}gwtco${_GS_C_RST}" >&2
        return 1
    fi

    # Parallel arrays for matched slots; carrying name + branch separately
    # keeps the ambiguity reporter from having to parse "name (branch)" back
    # apart for colorization, which is brittle under extended_glob.
    local -a match_paths match_names match_branches match_scores match_tiebreaks
    local -A seen
    local i name branch score name_score branch_score tiebreak best_score best_tiebreak
    for (( i=1; i<=${#slot_paths}; i++ )); do
        slot="${slot_paths[$i]}"
        name="${slot_names[$i]}"
        branch="${slot_branches[$i]}"

        score=""
        tiebreak=0

        if name_score="$(_git-wt-gwtcd-name-score "$name" "$query" 2>/dev/null)"; then
            score=$name_score
            tiebreak="$(_git-wt-gwtcd-name-tiebreak "$name")"
        fi

        if [[ -n "$branch" ]]; then
            if [[ "$branch" == *"$query"* ]]; then
                # Flat score keeps multiple literal branch hits ambiguous.
                if [[ -z "$score" || score -gt 1500 ]]; then
                    score=1500
                    tiebreak=0
                fi
            elif branch_score="$(_git-wt-gwtcd-name-score "$branch" "$query" 2>/dev/null)"; then
                branch_tiebreak="$(_git-wt-gwtcd-name-tiebreak "$branch")"
                if [[ -z "$score" || branch_score -lt score ]]; then
                    score=$branch_score
                    tiebreak=$branch_tiebreak
                fi
            fi
        fi

        [[ -n "$score" ]] || continue
        if (( ${+seen[$slot]} )); then
            continue
        fi
        seen[$slot]=1
        match_paths+=("$slot")
        match_names+=("$name")
        match_branches+=("$branch")
        match_scores+=("$score")
        match_tiebreaks+=("$tiebreak")
    done

    if (( ${#match_paths} == 0 )); then
        print -r -- "${_GS_C_TAG}gwtcd:${_GS_C_RST} ${_GS_C_ERR}no slot matching '$query'${_GS_C_RST}" >&2
        print -r -- "${_GS_C_BOLD}available:${_GS_C_RST}" >&2
        for (( i=1; i<=${#slot_paths}; i++ )); do
            name="${slot_names[$i]}"
            branch="${slot_branches[$i]}"
            if [[ -n "$branch" ]]; then
                print -r -- "  $name (${_GS_C_BRANCH}$branch${_GS_C_RST})" >&2
            else
                print -r -- "  $name" >&2
            fi
        done
        return 1
    fi

    best_score=${match_scores[1]}
    best_tiebreak=${match_tiebreaks[1]}
    for (( i=2; i<=${#match_scores}; i++ )); do
        if (( match_scores[i] < best_score )); then
            best_score=${match_scores[i]}
            best_tiebreak=${match_tiebreaks[i]}
        elif (( match_scores[i] == best_score && match_tiebreaks[i] < best_tiebreak )); then
            best_tiebreak=${match_tiebreaks[i]}
        fi
    done

    local -a winner_paths winner_names winner_branches
    for (( i=1; i<=${#match_paths}; i++ )); do
        if (( match_scores[i] == best_score && match_tiebreaks[i] == best_tiebreak )); then
            winner_paths+=("${match_paths[$i]}")
            winner_names+=("${match_names[$i]}")
            winner_branches+=("${match_branches[$i]}")
        fi
    done

    if (( ${#winner_paths} > 1 )); then
        print -r -- "${_GS_C_TAG}gwtcd:${_GS_C_RST} ${_GS_C_WARN}ambiguous match for '$query':${_GS_C_RST}" >&2
        for (( i=1; i<=${#winner_paths}; i++ )); do
            name="${winner_names[$i]}"
            branch="${winner_branches[$i]}"
            if [[ -n "$branch" ]]; then
                print -r -- "  $name (${_GS_C_BRANCH}$branch${_GS_C_RST})" >&2
            else
                print -r -- "  $name" >&2
            fi
        done
        return 1
    fi

    cd "${winner_paths[1]}" || return 1
}

# List the pool: main repo row, then slots sorted by mtime descending. Columns
# are BRANCH | STATE | LAST MODIFIED | PATH.
gwtl () {
    # Disable job-control notifications for the duration of this function:
    # the parallel collection below uses `{ ... } &`, and from an
    # interactive shell with MONITOR on that prints `[N] PID` / `[N] done`
    # noise per slot. `local_options` reverts both flags on function exit.
    setopt local_options no_monitor no_notify

    _git-sh-init-colors 1

    # Default to fast mode: skip the per-slot dirty check, which on a
    # multi-gigabyte monorepo dominates wall time even when parallelized
    # (the kernel saturates on simultaneous tree scans across slots).
    # `--dirty` opts into the slow path when the user actually wants to
    # see which slots have uncommitted edits.
    local skip_dirty=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dirty)
                skip_dirty=
                shift
                ;;
            -h|--help)
                print -r -- "usage: gwtl [--dirty]"
                return 0
                ;;
            *)
                print -r -- "${_GS_C_TAG}gwtl:${_GS_C_RST} ${_GS_C_ERR}unknown option:${_GS_C_RST} $1" >&2
                return 1
                ;;
        esac
    done

    local main_wt
    main_wt=$(_git-main-worktree) || return 1

    local main_branch
    main_branch=$(git -C "$main_wt" symbolic-ref --quiet --short HEAD 2>/dev/null) || main_branch="<detached>"

    # Collect per-slot metadata in parallel. Even with the dirty check
    # skipped, the symbolic-ref + mtime probes per slot benefit from
    # running concurrently; with --dirty the parallelism is essential to
    # avoid multi-second serial latency.
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/git-shorthand-gwtl.XXXXXX" 2>/dev/null) || return 1

    local slot
    for slot in "${(@f)$(_git-wt-pool-slots)}"; do
        [[ -z "$slot" ]] && continue
        {
            local b s m
            b=$(_git-wt-slot-branch "$slot")
            [[ -z "$b" ]] && b="<detached>"
            s=$(_git-wt-slot-state "$slot" "$skip_dirty")
            m=$(_git-wt-slot-mtime "$slot")
            [[ -z "$m" ]] && m=0
            # Single appended line; well under PIPE_BUF, so concurrent writes
            # from sibling jobs stay atomic.
            print -r -- "$m"$'\t'"$b"$'\t'"$s"$'\t'"$slot" >> "$tmpfile"
        } &
    done
    wait

    local -a sortable
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && sortable+=("$line")
    done < "$tmpfile"
    rm -f "$tmpfile"

    # Compute column widths from the actual data. Branches can be long (the
    # plugin's own naming convention encourages descriptive names), so a
    # fixed width truncates or pushes columns out of alignment.
    local hdr_branch="BRANCH" hdr_state="STATE" hdr_age="LAST MODIFIED"
    local main_repo_state="(main repo)"
    local max_branch=${#hdr_branch} max_state=${#hdr_state} max_age=${#hdr_age}
    (( ${#main_branch} > max_branch )) && max_branch=${#main_branch}
    (( ${#main_repo_state} > max_state )) && max_state=${#main_repo_state}

    # Avoid `path` as a local: zsh ties it to the PATH array, so a string
    # assignment quietly clobbers PATH inside the function and leaves later
    # commands (`date`, etc.) "not found".
    local mtime branch state slot_path now age delta rest
    now=$(date +%s)

    # First pass: compute widths and build display-ready rows so we don't
    # repeat the age formatting in the print loop.
    local -a rows
    for line in "${(@On)sortable}"; do
        mtime="${line%%$'\t'*}"
        rest="${line#*$'\t'}"
        branch="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        state="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        slot_path="$rest"

        delta=$((now - mtime))
        if (( delta < 60 )); then
            age="${delta}s ago"
        elif (( delta < 3600 )); then
            age="$((delta/60))m ago"
        elif (( delta < 86400 )); then
            age="$((delta/3600))h ago"
        else
            age="$((delta/86400))d ago"
        fi

        (( ${#branch} > max_branch )) && max_branch=${#branch}
        (( ${#state} > max_state )) && max_state=${#state}
        (( ${#age} > max_age )) && max_age=${#age}

        rows+=("$branch"$'\t'"$state"$'\t'"$age"$'\t'"$slot_path")
    done

    # Column widths drive printf padding. Padding must be computed on the
    # plain text first (ANSI escapes are bytes that printf would otherwise
    # mis-count), so each row is built by:
    #   1. printf -v <var> "%-Ns" "$plain" — pad to N visible chars,
    #   2. wrap the padded result in this column's color span,
    #   3. concatenate columns separated by two spaces.
    local pb ps pa
    printf -v pb "%-${max_branch}s" "$hdr_branch"
    printf -v ps "%-${max_state}s" "$hdr_state"
    printf -v pa "%-${max_age}s" "$hdr_age"
    print -r -- "${_GS_C_BOLD}${pb}${_GS_C_RST}  ${_GS_C_BOLD}${ps}${_GS_C_RST}  ${_GS_C_BOLD}${pa}${_GS_C_RST}  ${_GS_C_BOLD}PATH${_GS_C_RST}"

    printf -v pb "%-${max_branch}s" "$main_branch"
    printf -v ps "%-${max_state}s" "$main_repo_state"
    printf -v pa "%-${max_age}s" ""
    # Main repo row gets the tag color on its branch so it visually anchors
    # the table; the state slot reuses tag color to distinguish it from
    # ordinary slot states (idle/active/dirty/current).
    print -r -- "${_GS_C_TAG}${pb}${_GS_C_RST}  ${_GS_C_TAG}${ps}${_GS_C_RST}  ${_GS_C_DIM}${pa}${_GS_C_RST}  ${_GS_C_PATH}${main_wt}${_GS_C_RST}"

    local row b s a p state_color
    for row in "${rows[@]}"; do
        b="${row%%$'\t'*}"
        rest="${row#*$'\t'}"
        s="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        a="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        p="$rest"

        printf -v pb "%-${max_branch}s" "$b"
        printf -v ps "%-${max_state}s" "$s"
        printf -v pa "%-${max_age}s" "$a"

        state_color=$(_git-sh-state-color "$s")
        # Detached slots get dim branch text to match their semantic weight
        # (they're idle holdings, not active work).
        local branch_color="$_GS_C_BRANCH"
        [[ "$b" == "<detached>" ]] && branch_color="$_GS_C_DIM"

        print -r -- "${branch_color}${pb}${_GS_C_RST}  ${state_color}${ps}${_GS_C_RST}  ${_GS_C_DIM}${pa}${_GS_C_RST}  ${_GS_C_PATH}${p}${_GS_C_RST}"
    done
}

# Release the slot holding <branch> back into the pool: detach HEAD, optionally
# delete the branch. Refuses current slot always; refuses dirty without --force.
gwtd () {
    local delete_branch=0 force=0 branch=""

    _git-sh-init-colors 2

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --delete-branch)
                delete_branch=1
                shift
                ;;
            --force)
                force=1
                shift
                ;;
            -h|--help)
                print -r -- "usage: gwtd [--delete-branch] [--force] <branch>"
                return 0
                ;;
            -*)
                print -r -- "${_GS_C_TAG}gwtd:${_GS_C_RST} ${_GS_C_ERR}unknown option:${_GS_C_RST} $1" >&2
                return 1
                ;;
            *)
                [[ -z "$branch" ]] || {
                    print -r -- "${_GS_C_TAG}gwtd:${_GS_C_RST} extra argument: $1" >&2
                    return 1
                }
                branch="$1"
                shift
                ;;
        esac
    done

    [[ -n "$branch" ]] || {
        print -r -- "usage: gwtd [--delete-branch] [--force] <branch>" >&2
        return 2
    }

    local slot
    slot=$(_git-wt-find-slot-by-branch "$branch") || {
        print -r -- "${_GS_C_TAG}gwtd:${_GS_C_RST} ${_GS_C_ERR}no slot has branch ${_GS_C_BRANCH}$branch${_GS_C_ERR} checked out${_GS_C_RST}" >&2
        return 1
    }

    local -a release_args
    release_args=("$slot")
    (( delete_branch )) && release_args+=(--delete-branch)
    (( force )) && release_args+=(--force)

    _git-wt-release-slot "${release_args[@]}"
}

# Helper: list local branch names without invoking the human-oriented `git branch` formatter.
_git-local-branch-names () {
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
}

# Helper: print a branch merge-base and aggregate patch-id for comparing squash-equivalent changes.
_git-local-branch-patch-id () {
    local branch="$1"
    local main_ref="$2"

    local merge_base
    merge_base=$(git merge-base "$main_ref" "$branch" 2>/dev/null) || return 1

    local branch_patch
    branch_patch=$(git diff "$merge_base" "$branch" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{ print $1; exit }') || return 1
    [[ -n "$branch_patch" ]] || return 1

    print -r -- "$merge_base	$branch_patch"
}

# Helper: print candidate branches whose exact tips are reported merged by GitHub.
# Issues one `gh pr list --head <branch>` query per candidate instead of a single
# bulk `--limit 1000` fetch. The bulk approach silently misses merges on repos
# whose merge history exceeds the limit; per-branch queries scale with the local
# candidate count, not the repo's PR history, and stay accurate on huge repos.
# Queries run in parallel (bounded concurrency) so wall-clock time stays
# reasonable even with hundreds of candidates. Each match still requires the
# merged PR's headRefOid to equal the local branch tip — otherwise the local
# branch carries commits beyond what was merged and is unsafe to auto-delete.
_git-github-merged-local-branches () {
    local main_branch="$1"
    shift

    command -v gh >/dev/null 2>&1 || return 0
    (( $# > 0 )) || return 0

    # gbprune is invoked interactively, so suppress zsh's `[N] PID` /
    # `[N] done` job-control noise from the parallel `gh` calls below.
    # Reverted on function exit via local_options.
    setopt local_options no_monitor no_notify

    # Snapshot all candidate local tip OIDs in a single ref walk, instead of
    # one `git rev-parse` per branch. Needed for the safety match below.
    local -A candidate_set local_oid_by_branch
    local branch oid
    for branch in "$@"; do
        [[ -n "$branch" ]] && candidate_set[$branch]=1
    done
    while IFS=$'\t' read -r branch oid; do
        [[ -n "${candidate_set[$branch]-}" ]] && local_oid_by_branch[$branch]="$oid"
    done < <(git for-each-ref --format=$'%(refname:short)\t%(objectname)' refs/heads 2>/dev/null)

    (( ${#local_oid_by_branch} > 0 )) || return 0

    _git-sh-init-colors 2

    local total=${#local_oid_by_branch}
    print -r -- "  ${_GS_C_DIM}querying GitHub for $total candidate branch(es) (parallel)...${_GS_C_RST}" >&2

    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/git-shorthand-gh.XXXXXX" 2>/dev/null) || return 0

    # Background each `gh` call, capping outstanding jobs to keep us well below
    # GitHub's secondary rate limit. Each writes a "<branch>\t<oid>" line on
    # success; the shared tmpfile is safe because each line is well under
    # PIPE_BUF (atomic append). `wait` between batches is coarse but simple.
    local concurrency=16
    local active=0

    for branch in "${(@k)local_oid_by_branch}"; do
        {
            local merged_oid
            merged_oid=$(gh pr list --state merged --head "$branch" --base "$main_branch" --limit 1 --json headRefOid --jq '.[].headRefOid' 2>/dev/null)
            [[ -n "$merged_oid" ]] && print -r -- "$branch	$merged_oid" >> "$tmpfile"
        } &

        (( active += 1 ))
        if (( active >= concurrency )); then
            wait
            active=0
        fi
    done
    wait

    local pr_branch pr_oid
    while IFS=$'\t' read -r pr_branch pr_oid; do
        [[ -n "$pr_branch" && -n "$pr_oid" ]] || continue
        [[ "${local_oid_by_branch[$pr_branch]-}" == "$pr_oid" ]] && print -r -- "$pr_branch"
    done < "$tmpfile"

    rm -f "$tmpfile"
}

# List local branch names stale relative to origin's main branch: upstream gone, merged into
# main, equivalent changes already on main, or reported merged by GitHub. Always omits the
# main branch itself. If $1 is set, that branch name is omitted (gbprune passes the current
# HEAD so it is not deleted in place). Additional arguments restrict detection to those branch
# names, which lets worktree pruning avoid classifying unrelated local branches.
_git-stale-local-branches () {
    local exclude_branch="${1-}"
    shift 2>/dev/null || true

    local main_branch main_ref
    main_branch=$(git-main-branch)
    main_ref="origin/$main_branch"

    local -a candidates unstale_candidates
    if (( $# > 0 )); then
        candidates=("$@")
    else
        candidates=("${(@f)$(_git-local-branch-names)}")
    fi

    local -A candidate_map stale_map
    local branch
    for branch in "${candidates[@]}"; do
        [[ -z "$branch" ]] && continue
        [[ -n "$exclude_branch" && "$branch" == "$exclude_branch" ]] && continue
        [[ "$branch" == "$main_branch" ]] && continue
        candidate_map[$branch]=1
    done

    (( ${#candidate_map} > 0 )) || return 0

    # 1. Branches whose upstream remote-tracking ref is gone
    local track
    while IFS=$'\t' read -r branch track; do
        [[ -z "$branch" ]] && continue
        [[ -z "${candidate_map[$branch]-}" ]] && continue
        [[ "$track" == "[gone]" ]] && stale_map[$branch]=1
    done < <(git for-each-ref --format=$'%(refname:short)\t%(upstream:track)' refs/heads 2>/dev/null)

    # 2. Branches whose commits are ancestors of main (regular merge, rebase)
    while read -r branch; do
        [[ -z "$branch" ]] && continue
        [[ -z "${candidate_map[$branch]-}" ]] && continue
        stale_map[$branch]=1
    done < <(git for-each-ref --merged "$main_ref" --format='%(refname:short)' refs/heads 2>/dev/null)

    # 3. Branches whose exact tip was merged through a GitHub PR (squash merge, etc.).
    # Runs before the patch-id fallback so squash merges resolve via one cheap
    # `gh pr list --head <branch>` round trip per branch. On huge repos this
    # avoids generating the multi-gigabyte `git log -p merge_base..main` diff
    # the patch-id step would otherwise produce for every unresolved branch.
    for branch in "${(@k)candidate_map}"; do
        [[ -z "${stale_map[$branch]-}" ]] && unstale_candidates+=("$branch")
    done

    for branch in "${(@f)$(_git-github-merged-local-branches "$main_branch" "${unstale_candidates[@]}")}"; do
        [[ -n "${candidate_map[$branch]-}" ]] && stale_map[$branch]=1
    done

    # 4. Patch-id fallback: catches non-PR merges (cherry-picks, manual squashes
    # without a PR) on whatever the gh check couldn't classify. Skipped
    # entirely when `gh` is available — gh's per-branch query already covers
    # squash merges much faster, and the `git log -p merge_base..main` step
    # below generates the full diff of every commit since each branch
    # diverged from main, which can take many seconds per unique merge-base
    # on large repos. Users without gh still get patch-id as a fallback so
    # squash merges are detected somehow. The
    # `_GIT_SHORTHAND_TEST_FORCE_PATCH_ID` env var is an internal hook for
    # specs to exercise this branch without removing the gh PATH shim.
    if [[ -n "${_GIT_SHORTHAND_TEST_FORCE_PATCH_ID:-}" ]] || ! command -v gh >/dev/null 2>&1; then
        local -a patch_id_candidates
        for branch in "${(@k)candidate_map}"; do
            [[ -z "${stale_map[$branch]-}" ]] && patch_id_candidates+=("$branch")
        done

        if (( ${#patch_id_candidates} > 0 )); then
            _git-sh-init-colors 2
            print -r -- "  ${_GS_C_DIM}comparing patch-ids for ${#patch_id_candidates} branch(es) (no gh available)...${_GS_C_RST}" >&2

            local -A main_patch_ids_by_base
            local patch_info merge_base branch_patch main_patch_ids
            for branch in "${patch_id_candidates[@]}"; do
                if git diff --quiet "$main_ref" "$branch" 2>/dev/null; then
                    stale_map[$branch]=1
                    continue
                fi

                patch_info=$(_git-local-branch-patch-id "$branch" "$main_ref") || continue
                merge_base="${patch_info%%$'\t'*}"
                branch_patch="${patch_info#*$'\t'}"

                if (( ! ${+main_patch_ids_by_base[$merge_base]} )); then
                    main_patch_ids=$(git log --no-merges --format=format:%H -p "$merge_base..$main_ref" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{ print $1 }')
                    main_patch_ids_by_base[$merge_base]=$'\n'"$main_patch_ids"$'\n'
                fi

                if [[ "${main_patch_ids_by_base[$merge_base]}" == *$'\n'"$branch_patch"$'\n'* ]]; then
                    stale_map[$branch]=1
                fi
            done
        fi
    fi

    local -A printed_map
    for branch in "${candidates[@]}"; do
        [[ -z "$branch" ]] && continue
        [[ -z "${stale_map[$branch]-}" ]] && continue
        [[ -n "${printed_map[$branch]-}" ]] && continue
        printed_map[$branch]=1
        print -r -- "$branch"
    done
}

# Helper: returns success when a branch matches the same stale rules as gbprune.
_git-local-branch-is-stale () {
    local target_branch="$1"
    local stale_branch

    for stale_branch in "${(@f)$(_git-stale-local-branches "" "$target_branch")}"; do
        [[ -z "$stale_branch" ]] && continue
        [[ "$stale_branch" == "$target_branch" ]] && return 0
    done

    return 1
}

# Helper: best-effort `git fetch --prune`. Retries with short backoff on
# failure, since the most common cause on busy repos is a transient
# remote-tracking ref-lock race — another `git fetch` (IDE background sync,
# another shell, a worktree operation, a `gbprune` in a sibling worktree)
# updates `refs/remotes/origin/<ref>` between when our fetch reads the
# expected value and when it tries to write the new one, surfacing as
# "error: cannot lock ref ...: is at X but expected Y". A 1s/2s backoff
# usually lets the concurrent writer finish.
#
# If all retries fail (network down, auth gone, persistent lock), returns 0
# anyway after a clear warning: the caller's prune work still runs against
# whatever local state we have, and the only cost is potentially missing
# merges from the very latest commits. The branch detection cares about
# what's on `origin/<main>` locally, not whether this exact invocation
# fetched.
_git-fetch-prune-best-effort () {
    local label="${1:-gbprune}"
    local attempts=3 attempt

    _git-sh-init-colors 2

    for (( attempt = 1; attempt <= attempts; attempt++ )); do
        if git fetch --prune; then
            return 0
        fi
        if (( attempt < attempts )); then
            print -r -- "${_GS_C_TAG}${label}:${_GS_C_RST} ${_GS_C_WARN}fetch attempt $attempt/$attempts failed${_GS_C_RST} (likely transient ref-lock race); retrying in ${attempt}s..." >&2
            sleep "$attempt"
        fi
    done

    print -r -- "${_GS_C_TAG}${label}:${_GS_C_RST} ${_GS_C_WARN}fetch failed after $attempts attempts${_GS_C_RST}; continuing with local state — recent merges may not be detected this run" >&2
    return 0
}

# Prune local branches that have been fully merged into main (by any method).
# Handles: upstream gone, regular merge, squash merge, rebase merge.
#
# When a stale branch is still held by a linked worktree, `git branch -D`
# refuses to delete it. Auto-handle that case here by delegating to
# `_git-wt-release-slot --delete-branch`, which detaches HEAD and deletes
# the branch but leaves the worktree directory intact — so pool slots
# stay in the pool with their warm `node_modules` / build artifacts ready
# for reuse. Dirty (or `current`) holders are refused by the helper with
# a clear message, so uncommitted work is never silently destroyed.
gbprune () {
    _git-sh-init-colors 1

    print -r -- "${_GS_C_TAG}gbprune:${_GS_C_RST} fetching remotes with prune..."
    _git-fetch-prune-best-effort gbprune

    local current branch
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Map "branch -> worktree path" for every linked worktree so we can detect
    # held branches without re-scanning per stale branch. Skip the main
    # worktree's HEAD (`current` already excludes it from the stale list).
    typeset -A worktree_by_branch
    local wt_path="" wt_branch="" wt_detached=0
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            if [[ -n "$wt_path" && -n "$wt_branch" ]] && (( ! wt_detached )); then
                worktree_by_branch[$wt_branch]="$wt_path"
            fi
            wt_path="" wt_branch="" wt_detached=0
            continue
        fi
        case "$line" in
            "worktree "*) wt_path="${line#worktree }" ;;
            "branch "*)   wt_branch="${line#branch refs/heads/}" ;;
            detached)     wt_detached=1 ;;
        esac
    done < <(git worktree list --porcelain)
    if [[ -n "$wt_path" && -n "$wt_branch" ]] && (( ! wt_detached )); then
        worktree_by_branch[$wt_branch]="$wt_path"
    fi

    print -r -- "${_GS_C_TAG}gbprune:${_GS_C_RST} checking local branches..."
    local deleted_branches=0 failed_branches=0 released_worktrees=0
    for branch in "${(@f)$(_git-stale-local-branches "$current")}"; do
        [[ -z "$branch" ]] && continue

        local holder="${worktree_by_branch[$branch]-}"
        if [[ -n "$holder" ]]; then
            # Release the slot (detach HEAD + delete branch) and keep the
            # directory so the warm pool slot can be reused. The helper
            # prints "gwtpool: detaching HEAD in <slot> (was <branch>)" and
            # "gwtpool: deleting branch <branch>", and refuses dirty/current
            # slots without touching them. On success the branch is already
            # gone, so skip the trailing `git branch -D` below.
            print -r -- "${_GS_C_TAG}gbprune:${_GS_C_RST} releasing slot ${_GS_C_PATH}$holder${_GS_C_RST} for stale branch ${_GS_C_BRANCH}$branch${_GS_C_RST}"
            if _git-wt-release-slot --delete-branch "$holder"; then
                (( deleted_branches += 1 ))
                (( released_worktrees += 1 ))
            else
                print -r -- "${_GS_C_TAG}gbprune:${_GS_C_RST} ${_GS_C_WARN}skipping ${_GS_C_BRANCH}$branch${_GS_C_RST} — slot ${_GS_C_PATH}$holder${_GS_C_RST} could not be released (see message above)"
                (( failed_branches += 1 ))
            fi
            continue
        fi

        print -r -- "${_GS_C_TAG}gbprune:${_GS_C_RST} deleting branch ${_GS_C_BRANCH}$branch${_GS_C_RST}"
        if git branch -D "$branch"; then
            (( deleted_branches += 1 ))
        else
            (( failed_branches += 1 ))
        fi
    done

    # Build a colored summary line. The body remains "gbprune: deleted N
    # branch(es), failed M [(released K slot(s))]" so existing test matchers
    # ('deleted X branch(es), failed Y') keep working.
    local fail_color="$_GS_C_OK"
    (( failed_branches > 0 )) && fail_color="$_GS_C_ERR"
    local summary="${_GS_C_TAG}gbprune:${_GS_C_RST} deleted ${_GS_C_OK}$deleted_branches${_GS_C_RST} branch(es), failed ${fail_color}$failed_branches${_GS_C_RST}"
    (( released_worktrees > 0 )) && summary+=" (released ${_GS_C_OK}$released_worktrees${_GS_C_RST} slot(s))"
    print -r -- "$summary"
    (( failed_branches == 0 ))
}

# Pull current branch, then prune local branches fully merged into main (see gbprune).
gpbprune () {
    git pull && gbprune
}

# For every pool slot whose checked-out branch is stale (same rules as gbprune),
# release it: detach HEAD and delete the branch. The slot stays in the pool with
# its node_modules intact. Skips dirty and current slots (you can release those
# manually with `gwtd --force` and/or `gwtd --delete-branch`). Always finishes
# with `git worktree prune -v` to clean up administrative cruft.
gwtprune () {
    _git-sh-init-colors 1

    print -r -- "${_GS_C_TAG}gwtprune:${_GS_C_RST} fetching remotes with prune..."
    _git-fetch-prune-best-effort gwtprune

    local -a slot_paths slot_branches
    local slot branch state state_color
    for slot in "${(@f)$(_git-wt-pool-slots)}"; do
        [[ -z "$slot" ]] && continue
        branch=$(_git-wt-slot-branch "$slot")
        [[ -z "$branch" ]] && continue

        state=$(_git-wt-slot-state "$slot")
        if [[ "$state" == "dirty" || "$state" == "current" ]]; then
            state_color=$(_git-sh-state-color "$state")
            print -r -- "${_GS_C_TAG}gwtprune:${_GS_C_RST} ${_GS_C_DIM}skipping${_GS_C_RST} ${_GS_C_PATH}$slot${_GS_C_RST} (${_GS_C_BRANCH}$branch${_GS_C_RST}, ${state_color}$state${_GS_C_RST})" >&2
            continue
        fi

        slot_paths+=("$slot")
        slot_branches+=("$branch")
    done

    local -A stale_map
    local b
    if (( ${#slot_branches} > 0 )); then
        for b in "${(@f)$(_git-stale-local-branches "" "${slot_branches[@]}")}"; do
            [[ -n "$b" ]] && stale_map[$b]=1
        done
    fi

    print -r -- "${_GS_C_TAG}gwtprune:${_GS_C_RST} scanning slots (${_GS_C_BOLD}${#slot_branches}${_GS_C_RST} branch candidate(s), ${_GS_C_BOLD}${#stale_map}${_GS_C_RST} stale)..."

    local released=0 failed=0 i
    for (( i = 1; i <= ${#slot_paths}; i++ )); do
        slot="${slot_paths[$i]}"
        branch="${slot_branches[$i]}"

        [[ -n "${stale_map[$branch]-}" ]] || continue

        print -r -- "${_GS_C_TAG}gwtprune:${_GS_C_RST} releasing ${_GS_C_PATH}$slot${_GS_C_RST} (${_GS_C_BRANCH}$branch${_GS_C_RST})"
        if _git-wt-release-slot --delete-branch "$slot"; then
            (( released += 1 ))
        else
            (( failed += 1 ))
        fi
    done

    local prune_status=0
    git worktree prune -v || prune_status=$?
    local fail_color="$_GS_C_OK"
    (( failed > 0 )) && fail_color="$_GS_C_ERR"
    print -r -- "${_GS_C_TAG}gwtprune:${_GS_C_RST} released ${_GS_C_OK}$released${_GS_C_RST} slot(s), failed ${fail_color}$failed${_GS_C_RST}"
    (( prune_status == 0 && failed == 0 ))
}

# Pull from main
alias gpm="git pull origin \$(git-main-branch)"

# Pull rebase from main
gprm () {
    git fetch origin "$(git-main-branch):$(git-main-branch)"
    git rebase "$(git-main-branch)"
}

# Zsh completion support for shorthand aliases and functions.
# shellcheck disable=SC2153
#   CURRENT and words are provided by zsh's completion system.
if [[ -n "${ZSH_VERSION-}" ]]; then
    _git_shorthand_local_branches () {
        local expl
        local -a branches
        branches=("${(@f)$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)}")
        (( ${#branches} )) || return 1

        # -M 'r:|/=* r:|=*' matches across '/' (same as zsh's stock _git / __git_describe_commit).
        _wanted branches expl 'local branch' compadd -M 'r:|/=* r:|=*' -o nosort -a - branches
    }

    _git_shorthand_all_branches () {
        local expl
        local -a branches
        branches=("${(@f)$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null | sed '\#/HEAD$#d')}")
        (( ${#branches} )) || return 1

        _wanted branches expl 'branch' compadd -M 'r:|/=* r:|=*' -o nosort -a - branches
    }

    # Branches currently checked out in any pool slot. Used to complete `gwtd`
    # (which only operates on slots that actually hold the named branch).
    _git_shorthand_slot_branches () {
        local -a slots
        slots=("${(@f)$(_git-wt-pool-slots 2>/dev/null)}")
        (( ${#slots} )) || return 1

        local -a branches
        local slot ref
        for slot in "${slots[@]}"; do
            [[ -z "$slot" ]] && continue
            ref=$(git -C "$slot" symbolic-ref --quiet --short HEAD 2>/dev/null) || continue
            [[ -n "$ref" ]] && branches+=("$ref")
        done
        (( ${#branches} )) || return 1

        local expl
        _wanted branches expl 'slot branch' compadd -M 'r:|/=* r:|=*' -o nosort -a - branches
    }

    # gwtcd accepts a fuzzy substring. We suggest slot directory names (tree-N),
    # the branches currently checked out in slots, the primary checkout's
    # current branch, and "root". The current target is omitted to avoid
    # suggesting a no-op.
    _git_shorthand_gwtcd_targets () {
        local current_target
        current_target=$(_git-current-wt-target 2>/dev/null)
        [[ -z "$current_target" ]] && current_target="root"

        local -a slots
        slots=("${(@f)$(_git-wt-pool-slots 2>/dev/null)}")

        local -a candidates
        local slot ref
        for slot in "${slots[@]}"; do
            [[ -z "$slot" ]] && continue
            candidates+=("${slot:t}")
            ref=$(git -C "$slot" symbolic-ref --quiet --short HEAD 2>/dev/null) || continue
            [[ -n "$ref" ]] && candidates+=("$ref")
        done

        # Offer the primary checkout's branch so `gwtcd main` (or whatever root
        # holds) completes to the root clone, mirroring gwtcd's matching. Skip
        # when already in root, where it would only suggest a no-op.
        if [[ "$current_target" != "root" ]]; then
            local main_wt
            main_wt=$(_git-main-worktree 2>/dev/null)
            if [[ -n "$main_wt" ]]; then
                ref=$(git -C "$main_wt" symbolic-ref --quiet --short HEAD 2>/dev/null)
                [[ -n "$ref" ]] && candidates+=("$ref")
            fi
        fi

        candidates+=("root")

        local -a suggestions
        local -A seen
        local entry
        for entry in "${candidates[@]}"; do
            [[ -n "$entry" ]] || continue
            (( ${+seen[$entry]} )) && continue
            seen[$entry]=1
            [[ -n "$current_target" && "$entry" == "$current_target" ]] && continue
            suggestions+=("$entry")
        done
        (( ${#suggestions} )) || return 1

        local expl
        _wanted slots expl 'slot or branch' compadd -M 'r:|/=* r:|=*' -Q -o nosort -- "${suggestions[@]}"
    }

    _git_shorthand_new_branch_name () {
        if (( CURRENT == 2 )); then
            _message 'new branch name'
        else
            _message 'no more arguments'
        fi
    }

    _git_shorthand_gwta () {
        _arguments \
            '--base[base ref for the new branch]:base:_git_shorthand_all_branches' \
            '--no-install[skip package-manager install after activation]' \
            '1:new branch name:'
    }

    _git_shorthand_gwtco () {
        _arguments \
            '--no-install[skip package-manager install after activation]' \
            '1:branch:_git_shorthand_all_branches'
    }

    _git_shorthand_gwtd () {
        _arguments \
            '--delete-branch[also delete the branch after release]' \
            '--force[ignore dirty working tree]' \
            '1:branch:_git_shorthand_slot_branches'
    }

    _git_shorthand_gwtcd () {
        if (( CURRENT == 2 )); then
            _git_shorthand_gwtcd_targets
        else
            _message 'no more arguments'
        fi
    }

    _git_shorthand_single_local_branch () {
        if (( CURRENT == 2 )); then
            _git_shorthand_local_branches
        else
            _message 'no more arguments'
        fi
    }

    _git_shorthand_register_completions () {
        (( $+functions[compdef] )) || return 1
        (( ${+_git_shorthand_completions_registered} )) && return 0

        compdef _git \
            ga=git-add \
            gaa=git-add \
            gaas=git-status \
            gaast=git-stash \
            gs=git-status \
            gbs=git-status \
            gsd=git-diff \
            gc=git-commit \
            gsc=git-commit \
            gaac=git-commit \
            gaacpp=git-commit \
            gaascpp=git-commit \
            gcpp=git-commit \
            gd=git-diff \
            gdx=git-diff \
            gda=git-diff \
            gst=git-stash \
            gstl=git-stash \
            gstpo=git-stash \
            gp=git-pull \
            gpm=git-pull \
            gpbprune=git-pull \
            gpr=git-pull \
            gpp=git-push \
            gb=git-branch \
            gco=git-checkout \
            gcom=git-checkout \
            gcob=git-checkout \
            gl=git-log \
            gfm=git-fetch \
            gprm=git-rebase

        compdef _git_shorthand_new_branch_name gnb gnbpp gfmnb grnb gcobpp
        compdef _git_shorthand_single_local_branch git-obliterate
        compdef _git_shorthand_gwta gwta gfmwta
        compdef _git_shorthand_gwtco gwtco
        compdef _git_shorthand_gwtd gwtd
        compdef _git_shorthand_gwtcd gwtcd

        typeset -g _git_shorthand_completions_registered=1
    }

    if (( $+functions[compdef] )); then
        _git_shorthand_register_completions
    else
        autoload -Uz add-zsh-hook
        _git_shorthand_register_completions_precmd () {
            _git_shorthand_register_completions || return 0
            add-zsh-hook -d precmd _git_shorthand_register_completions_precmd 2>/dev/null
        }
        add-zsh-hook precmd _git_shorthand_register_completions_precmd
    fi
fi
