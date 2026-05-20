#!/usr/bin/env zsh
#
# One-time migration: convert a repo from the old git-shorthand named-worktree
# layout ({repo}-worktrees/<branch>) to the new pooled layout
# ({repo}-worktrees/tree-N).
#
# Runs in two phases:
#
#   1. Cleanup recommendation. For each candidate branch, checks whether it
#      was already merged into main — first locally via
#      `git merge-base --is-ancestor` (catches fast-forward and rebase
#      merges with no network), then for unresolved candidates via
#      `gh pr list --head <branch>` (catches squash merges). Per-candidate
#      detection stays accurate on repos with hundreds of thousands of
#      merged PRs, where any bulk `gh pr list --limit N` would miss most
#      of the history. Matches offer cleanup: `trash` the worktree
#      directory (much faster than `git worktree remove` on large repos),
#      prune the worktree metadata, and `git branch -D` the local branch.
#      Declining the prompt rolls those candidates into the migration
#      list instead.
#
#   2. Migration. Renames each remaining candidate to the next free
#      tree-N slot with `git worktree move`, preserving the branch,
#      node_modules, and any clean build state.
#
# Dirty worktrees and the worktree containing the current shell are always
# skipped with a warning — commit/stash or `cd` elsewhere, then re-run.
#
# Usage:
#   scripts/migrate-to-pooled-worktrees.sh [--dry-run] [--yes] [--no-cleanup]
#
# Run from anywhere inside a worktree of the repo you want to migrate.

emulate -L zsh
setopt extended_glob no_nomatch pipefail
set -u

usage() {
    cat <<'EOF'
Usage: migrate-to-pooled-worktrees.sh [--dry-run] [--yes] [--no-cleanup]

Phase 1 (cleanup): for each candidate, check whether its branch is already
merged into main — `git merge-base --is-ancestor` first (no network), then
`gh pr list --head <branch>` for unresolved candidates (catches squash
merges). Offers to `trash` the matched worktrees and delete the branches.
Declining rolls those candidates into the migration list.

For best accuracy, run `git fetch origin <main>` first so the local
ancestor check sees recent merges.

Phase 2 (migrate): rename remaining candidates to {repo}-worktrees/tree-N
with `git worktree move`.

Dirty worktrees and the worktree containing your shell are always skipped.

Options:
  --dry-run      Print the plan; make no changes.
  --yes, -y      Skip confirmation prompts.
  --no-cleanup   Skip the merged-branch detection step entirely.
  -h, --help     Show this help.

Cleanup requires `trash` (e.g., `brew install trash`) and `gh` authenticated
against the repo's remote.
EOF
}

dry_run=0
assume_yes=0
do_cleanup=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    dry_run=1; shift ;;
        --yes|-y)     assume_yes=1; shift ;;
        --no-cleanup) do_cleanup=0; shift ;;
        -h|--help)    usage; exit 0 ;;
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

# Resolve the main worktree and its sibling worktrees base. Matches the
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

# Detect the repo's main branch (main vs master). Used for both the pool
# numbering and the `gh pr list --base` query.
detect_main_branch() {
    if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
        echo main
    elif git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
        echo master
    elif git show-ref --verify --quiet refs/heads/main; then
        echo main
    elif git show-ref --verify --quiet refs/heads/master; then
        echo master
    else
        echo main
    fi
}
main_branch=$(detect_main_branch)

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
    [[ "$wt_path" == "$wt_base"/* ]] || return

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
# and `trash` would yank the directory out from under us.
current_pwd=$(pwd -P)
for cand in "${cand_paths[@]}"; do
    if [[ "$current_pwd" == "$cand" || "$current_pwd" == "$cand"/* ]]; then
        print -r -- "error: cwd ($current_pwd) is inside a worktree slated for migration" >&2
        print -r -- "       cd to the main repo (or any non-candidate path) and re-run." >&2
        exit 1
    fi
done

# Phase 1 prep: per-candidate merged detection. Local ancestor check first
# (fast, no network, catches FF/rebase merges); gh fallback per branch for
# squash merges. Scales with candidate count, not the repo's merge history.
have_gh=0
have_origin_main=0
if (( do_cleanup )); then
    if command -v gh >/dev/null 2>&1; then
        have_gh=1
    fi
    if git rev-parse --verify --quiet "refs/remotes/origin/$main_branch" >/dev/null; then
        have_origin_main=1
    else
        print -r -- "warning: origin/$main_branch not found locally; cleanup detection may miss merges" >&2
        print -r -- "         consider \`git fetch origin $main_branch\` and re-run" >&2
    fi
    if (( ! have_gh && ! have_origin_main )); then
        print -r -- "info: no detection mechanism available; skipping cleanup phase" >&2
        do_cleanup=0
    fi
fi

# Returns 0 if the named branch is already merged into $main_branch.
# Tries local ancestor check first, then a per-branch `gh pr list` query.
#
# Note: a `<base>/main` worktree whose local main is in sync with
# origin/main will land here as "merged" (refs/heads/main is trivially an
# ancestor of refs/remotes/origin/main). That's intentional — the main
# repo and origin/main are the source of truth, so the dedicated main
# worktree (and its local branch ref) can be safely trashed. If local main
# is ahead of origin, the ancestor check fails and we migrate instead,
# preserving the unmerged commits.
is_branch_merged() {
    local branch="$1"

    if (( have_origin_main )) && git merge-base --is-ancestor "refs/heads/$branch" "refs/remotes/origin/$main_branch" 2>/dev/null; then
        return 0
    fi

    if (( have_gh )); then
        local out
        out=$(gh pr list --state merged --head "$branch" --base "$main_branch" --limit 1 --json number --jq '.[].number' 2>/dev/null)
        if [[ -n "$out" ]]; then
            return 0
        fi
    fi

    return 1
}

# Classify each candidate: dirty → SKIP; clean + merged → cleanup; clean + not
# merged (or detached) → migrate.
typeset -a cleanup_paths cleanup_branches
typeset -a migrate_paths migrate_branches
typeset -a skip_paths skip_reasons

if (( do_cleanup )); then
    detect_targets="origin/$main_branch"
    if (( have_gh )); then
        detect_targets+=" and GitHub"
    fi
    print -r -- "info: checking ${#cand_paths} candidate branch(es) against $detect_targets..." >&2
fi

for (( i = 1; i <= ${#cand_paths}; i++ )); do
    old="${cand_paths[$i]}"
    branch="${cand_branches[$i]}"

    status_out=$(git -C "$old" status --porcelain 2>/dev/null || true)
    if [[ -n "$status_out" ]]; then
        skip_paths+=("$old")
        skip_reasons+=("dirty (branch: $branch)")
        continue
    fi

    if (( do_cleanup )) && [[ "$branch" != "<detached>" && "$branch" != "<unknown>" ]] && is_branch_merged "$branch"; then
        print -r -- "  merged: $branch" >&2
        cleanup_paths+=("$old")
        cleanup_branches+=("$branch")
    else
        migrate_paths+=("$old")
        migrate_branches+=("$branch")
    fi
done

if (( do_cleanup )); then
    print -r -- "info: ${#cleanup_paths} of ${#cand_paths} candidate(s) appear merged into $main_branch" >&2
fi

# Surface skips up front so they're not lost between the two action phases.
if (( ${#skip_paths} > 0 )); then
    print -r -- "Skipped (need attention before re-running):"
    for (( i = 1; i <= ${#skip_paths}; i++ )); do
        printf '  SKIP  %s — %s\n' "${skip_paths[$i]}" "${skip_reasons[$i]}"
    done
    print
fi

# Phase 1: cleanup of merged branches.
if (( ${#cleanup_paths} > 0 )); then
    print -r -- "Merged-into-$main_branch branches detected (recommended cleanup):"
    for (( i = 1; i <= ${#cleanup_paths}; i++ )); do
        printf '  TRASH %s (%s)\n' "${cleanup_paths[$i]}" "${cleanup_branches[$i]}"
    done
    print

    if (( dry_run )); then
        print -r -- "(dry run: would trash these directories and delete the local branches)"
    else
        proceed=1
        if (( ! assume_yes )); then
            printf 'Trash %d worktree(s) and delete their branches? [y/N] ' ${#cleanup_paths}
            read -r reply
            case "$reply" in
                y|Y|yes|YES) ;;
                *)
                    proceed=0
                    print -r -- "declined cleanup; these will be migrated to tree-N instead."
                    ;;
            esac
        fi

        if (( proceed )); then
            if ! command -v trash >/dev/null 2>&1; then
                print -r -- "error: \`trash\` not found; install it (e.g., \`brew install trash\`) and re-run," >&2
                print -r -- "       or pass --no-cleanup to skip this phase." >&2
                exit 1
            fi

            typeset -a trashed_branches
            cleanup_failed=0
            for (( i = 1; i <= ${#cleanup_paths}; i++ )); do
                p="${cleanup_paths[$i]}"
                b="${cleanup_branches[$i]}"
                printf 'trash %s ... ' "$p"
                if trash "$p"; then
                    printf 'ok\n'
                    trashed_branches+=("$b")
                else
                    printf 'FAILED\n'
                    cleanup_failed=$(( cleanup_failed + 1 ))
                fi
            done

            # Prune stale worktree metadata in one go so the branch-delete
            # step below isn't blocked by "branch checked out at ..." errors.
            git worktree prune -v >/dev/null 2>&1 || true

            for b in "${trashed_branches[@]}"; do
                printf 'delete branch %s ... ' "$b"
                if git branch -D "$b" >/dev/null 2>&1; then
                    printf 'ok\n'
                else
                    printf 'FAILED (already gone or not local)\n'
                fi
            done

            print
            if (( cleanup_failed > 0 )); then
                print -r -- "cleanup finished with $cleanup_failed failure(s)."
            else
                print -r -- "cleanup finished: trashed ${#trashed_branches} worktree(s)."
            fi
        else
            # User declined: roll cleanup candidates into the migration list.
            for (( i = 1; i <= ${#cleanup_paths}; i++ )); do
                migrate_paths+=("${cleanup_paths[$i]}")
                migrate_branches+=("${cleanup_branches[$i]}")
            done
            cleanup_paths=()
            cleanup_branches=()
        fi
    fi
    print
fi

# Phase 2: migrate remaining candidates to tree-N slots.
if (( ${#migrate_paths} == 0 )); then
    print -r -- "nothing left to migrate."
    exit 0
fi

typeset -a plan_old plan_new plan_branch
typeset -a mig_skip_paths mig_skip_reasons

n=$max_n
print -r -- "Migration plan (base: $wt_base):"
print
for (( i = 1; i <= ${#migrate_paths}; i++ )); do
    old="${migrate_paths[$i]}"
    branch="${migrate_branches[$i]}"

    n=$(( n + 1 ))
    new="$wt_base/tree-$n"

    if [[ -e "$new" ]]; then
        printf '  SKIP  %s (%s) — target %s already exists\n' "$old" "$branch" "$new"
        mig_skip_paths+=("$old")
        mig_skip_reasons+=("target-exists")
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
    print -r -- "no worktrees to migrate."
    if (( ${#mig_skip_paths} > 0 )); then
        print -r -- "skipped ${#mig_skip_paths} candidate(s); see SKIP lines above."
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

failed=0
for (( i = 1; i <= ${#plan_old}; i++ )); do
    old="${plan_old[$i]}"
    new="${plan_new[$i]}"

    printf 'moving %s -> %s ...' "$old" "$new"
    if git worktree move "$old" "$new"; then
        printf ' ok\n'
    else
        printf ' FAILED\n'
        failed=$(( failed + 1 ))
    fi
done

git worktree prune -v >/dev/null 2>&1 || true

print
if (( failed > 0 )); then
    print -r -- "migration completed with $failed failure(s)."
    exit 1
fi

print -r -- "done. Run \`gwtl\` to see the new pool layout."
if (( ${#mig_skip_paths} > 0 )); then
    print -r -- "note: ${#mig_skip_paths} migration candidate(s) were skipped; address them and re-run."
fi
