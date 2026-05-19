#!/usr/bin/env zsh
#
# One-time migration: convert a repo from the old git-shorthand named-worktree
# layout ({repo}-worktrees/<branch>) to the new pooled layout
# ({repo}-worktrees/tree-N).
#
# For each linked worktree that lives directly under {repo}-worktrees/ and is
# not already named tree-N, the script picks the next available tree-N slot
# and renames the worktree with `git worktree move`. The branch, node_modules,
# and any clean build state are preserved in place.
#
# Dirty worktrees are skipped with a warning — commit or stash first, then
# re-run. The worktree containing the current shell is also refused; cd out
# (typically `gwtcd root`) and re-run.
#
# Usage:
#   scripts/migrate-to-pooled-worktrees.sh [--dry-run] [--yes]
#
# Run from anywhere inside a worktree of the repo you want to migrate.

emulate -L zsh
setopt extended_glob no_nomatch pipefail
set -u

usage() {
    cat <<'EOF'
Usage: migrate-to-pooled-worktrees.sh [--dry-run] [--yes]

Migrate from {repo}-worktrees/<branch> to {repo}-worktrees/tree-N.
Renames each old-style named worktree to the next free tree-N slot with
`git worktree move`. Dirty worktrees and the worktree containing your
current shell are skipped.

Options:
  --dry-run   Print the migration plan but make no changes.
  --yes, -y   Skip the confirmation prompt.
  -h, --help  Show this help.
EOF
}

dry_run=0
assume_yes=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=1; shift ;;
        --yes|-y)  assume_yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            print -r -- "error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    print -r -- "error: not inside a git repository" >&2
    exit 1
}

# Resolve the main worktree and its sibling worktrees base. This matches the
# plugin's _git-wt-base / _git-main-worktree helpers exactly so the script
# operates on the same layout the plugin expects.
main_wt=$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)
[[ -n "$main_wt" ]] || {
    print -r -- "error: could not resolve main worktree" >&2
    exit 1
}

wt_base="$(dirname "$main_wt")/$(basename "$main_wt")-worktrees"

if [[ ! -d "$wt_base" ]]; then
    print -r -- "info: no worktrees base at $wt_base — nothing to migrate"
    exit 0
fi

# Find the highest tree-N already in use so newly allocated slots don't
# collide with surviving pool slots.
max_n=0
for entry in "$wt_base"/tree-*(N/); do
    name="${entry:t}"
    [[ "$name" =~ ^tree-[0-9]+$ ]] || continue
    n="${name#tree-}"
    if (( n > max_n )); then
        max_n=$n
    fi
done

# Collect candidates from `git worktree list --porcelain`. A candidate is a
# linked worktree under wt_base whose directory name is NOT already tree-N.
typeset -a cand_paths cand_branches
wt_path=""
wt_branch=""
wt_detached=0

process_record() {
    [[ -z "$wt_path" ]] && return
    [[ "$wt_path" == "$main_wt" ]] && return
    # Stay inside the plugin's wt_base; ignore unrelated worktrees.
    [[ "$wt_path" == "$wt_base"/* ]] || return

    # Already a pooled slot — leave it alone.
    local rel="${wt_path#"$wt_base"/}"
    if [[ "$rel" =~ ^tree-[0-9]+$ ]]; then
        return
    fi

    cand_paths+=("$wt_path")
    if (( wt_detached )); then
        cand_branches+=("<detached>")
    else
        cand_branches+=("${wt_branch:-<unknown>}")
    fi
}

while IFS= read -r line; do
    if [[ -z "$line" ]]; then
        process_record
        wt_path="" wt_branch="" wt_detached=0
        continue
    fi
    case "$line" in
        "worktree "*) wt_path="${line#worktree }" ;;
        "branch "*)   wt_branch="${line#branch refs/heads/}" ;;
        detached)     wt_detached=1 ;;
    esac
done < <(git worktree list --porcelain)
process_record

if (( ${#cand_paths} == 0 )); then
    print -r -- "nothing to migrate: no old-style worktrees under $wt_base"
    exit 0
fi

# Refuse if the current shell sits inside a candidate. `git worktree move`
# would yank the directory out from under us; better to bail with a clear
# message so the user can cd elsewhere first.
current_pwd=$(pwd -P)
for cand in "${cand_paths[@]}"; do
    if [[ "$current_pwd" == "$cand" || "$current_pwd" == "$cand"/* ]]; then
        print -r -- "error: cwd ($current_pwd) is inside a worktree slated for migration" >&2
        print -r -- "       cd to the main repo (or any non-candidate path) and re-run." >&2
        exit 1
    fi
done

# Build the plan: assign each clean candidate the next free tree-N. Dirty
# candidates are reported and skipped — the user can commit/stash and re-run.
typeset -a plan_old plan_new plan_branch
typeset -a skip_paths skip_reasons

n=$max_n
print -r -- "Migration plan (base: $wt_base):"
print
for (( i = 1; i <= ${#cand_paths}; i++ )); do
    old="${cand_paths[$i]}"
    branch="${cand_branches[$i]}"

    status_out=$(git -C "$old" status --porcelain 2>/dev/null || true)
    if [[ -n "$status_out" ]]; then
        printf '  SKIP  %s (%s) — dirty working tree\n' "$old" "$branch"
        skip_paths+=("$old")
        skip_reasons+=("dirty")
        continue
    fi

    n=$(( n + 1 ))
    new="$wt_base/tree-$n"

    if [[ -e "$new" ]]; then
        printf '  SKIP  %s (%s) — target %s already exists\n' "$old" "$branch" "$new"
        skip_paths+=("$old")
        skip_reasons+=("target-exists")
        # Roll back the slot counter so the next candidate reuses the number.
        n=$(( n - 1 ))
        continue
    fi

    plan_old+=("$old")
    plan_new+=("$new")
    plan_branch+=("$branch")

    printf '  MOVE  %s -> %s (%s)\n' "$old" "$new" "$branch"
done
print

if (( ${#plan_old} == 0 )); then
    print -r -- "no clean worktrees to migrate."
    if (( ${#skip_paths} > 0 )); then
        print -r -- "skipped ${#skip_paths} candidate(s); see SKIP lines above."
    fi
    exit 0
fi

if (( dry_run )); then
    print -r -- "dry run; nothing changed."
    exit 0
fi

if (( ! assume_yes )); then
    printf 'Proceed with %d move(s)? [y/N] ' ${#plan_old}
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *)
            print -r -- "aborted."
            exit 1
            ;;
    esac
fi

# Execute. Failures don't abort the loop — we want to migrate as many as we
# can and summarize at the end.
failed=0
for (( i = 1; i <= ${#plan_old}; i++ )); do
    old="${plan_old[$i]}"
    new="${plan_new[$i]}"
    branch="${plan_branch[$i]}"

    printf 'moving %s -> %s ...' "$old" "$new"
    if git worktree move "$old" "$new"; then
        printf ' ok\n'
    else
        printf ' FAILED\n'
        failed=$(( failed + 1 ))
    fi
done

# Clean up any leftover administrative metadata from the moves.
git worktree prune -v >/dev/null 2>&1 || true

print
if (( failed > 0 )); then
    print -r -- "completed with $failed failure(s)."
    exit 1
fi

print -r -- "done. Run \`gwtl\` to see the new pool layout."
if (( ${#skip_paths} > 0 )); then
    print -r -- "note: ${#skip_paths} candidate(s) were skipped; address them and re-run."
fi
