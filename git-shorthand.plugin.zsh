# Get main branch name (master or main)
git-main-branch () {
    git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
}

# Git shorthand aliases
alias ga="git add"
alias gaa="git add --a"
alias gs="git status"
alias gsd="git status; git diff"
alias gbs="git branch; git status"
alias gc="git commit -m"
alias gd="git diff"
alias gdx="git diff --staged"
alias gda="git diff HEAD"
alias gsc="git status; git commit -m"
alias gaas="git add --a; git status"
alias gst="git stash"
alias gaast="git add --a; git stash"
alias gstl="git stash list"
alias gstpo="git stash pop"
alias gp="git pull"
alias gpp="git push"
alias gb="git branch"
alias gco="git checkout"
alias gcob="git checkout -b"
alias gl="git log"
alias gpr="git pull --rebase --autostash"

# Aliases for working with main branch
alias gfm="git fetch origin \$(git-main-branch):\$(git-main-branch)"  # Fetch main
alias gcom="git checkout \$(git-main-branch)"  # Checkout main (when available)

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
	git add --a
	git status
	git commit -m "$*"
	git push
}

gaacpp () {
	git add --a
	git commit -m "$*"
	git push
}

gaac () {
	git add --a
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
# Worktrees are stored in ../{repo_name}-worktrees/ to keep src/ clean.
# Worktrees and branches are managed together (1-to-1 lifecycle).

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

# Add worktree with a new branch from main
gwta () {
    local wt_base
    wt_base=$(_git-wt-base)
    mkdir -p "$wt_base"
    git worktree add -b "$1" "$wt_base/$1" "$(git-main-branch)"
}

# Fetch main, then add worktree with a new branch from it
gfmwta () {
    git fetch origin "$(git-main-branch):$(git-main-branch)"
    local wt_base
    wt_base=$(_git-wt-base)
    mkdir -p "$wt_base"
    git worktree add -b "$1" "$wt_base/$1" "$(git-main-branch)"
}

# Add worktree for an existing branch (e.g. a remote branch)
gwtco () {
    local wt_base
    wt_base=$(_git-wt-base)
    local wt_path="$wt_base/$1"

    if [[ -d "$wt_path" ]]; then
        cd "$wt_path" || return 1
        return 0
    fi

    mkdir -p "$wt_base"
    git worktree add "$wt_path" "$1"
}

# List worktrees
gwtl () {
    git worktree list
}

# cd into a worktree by branch name (use "root" for the primary checkout; branch "main" is a normal name).
gwtcd () {
    local target_branch="$1"

    if [[ "$target_branch" == "root" ]]; then
        local main_wt
        main_wt=$(_git-main-worktree) || return 1
        cd "$main_wt" || return 1
    else
        local wt_base
        wt_base=$(_git-wt-base) || return 1
        cd "$wt_base/$target_branch" || return 1
    fi
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
_git-github-merged-local-branches () {
    local main_branch="$1"
    shift

    command -v gh >/dev/null 2>&1 || return 0
    (( $# > 0 )) || return 0

    local -A candidate_name_map candidate_oid_by_branch
    local branch oid
    for branch in "$@"; do
        [[ -n "$branch" ]] && candidate_name_map[$branch]=1
    done

    while IFS=$'\t' read -r branch oid; do
        [[ -n "$branch" && -n "$oid" ]] || continue
        if [[ -n "${candidate_name_map[$branch]-}" ]]; then
            candidate_oid_by_branch[$branch]="$oid"
        fi
    done < <(git for-each-ref --format=$'%(refname:short)\t%(objectname)' refs/heads 2>/dev/null)

    (( ${#candidate_oid_by_branch} > 0 )) || return 0

    local pr_branch pr_oid
    while IFS=$'\t' read -r pr_branch pr_oid; do
        [[ -n "$pr_branch" && -n "$pr_oid" ]] || continue
        [[ "${candidate_oid_by_branch[$pr_branch]-}" == "$pr_oid" ]] && print -r -- "$pr_branch"
    done < <(gh pr list --state merged --base "$main_branch" --limit 1000 --json headRefName,headRefOid --jq '.[] | [.headRefName, .headRefOid] | @tsv' 2>/dev/null)
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

    # 3. Branches whose net changes are already on main (identical tree, squash, etc.)
    local -A main_patch_ids_by_base
    local patch_info merge_base branch_patch main_patch_ids
    for branch in "${(@k)candidate_map}"; do
        [[ -n "${stale_map[$branch]-}" ]] && continue

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

    # 4. Branches whose exact tip was merged through a GitHub PR (squash merge, etc.)
    for branch in "${(@k)candidate_map}"; do
        [[ -z "${stale_map[$branch]-}" ]] && unstale_candidates+=("$branch")
    done

    for branch in "${(@f)$(_git-github-merged-local-branches "$main_branch" "${unstale_candidates[@]}")}"; do
        [[ -n "${candidate_map[$branch]-}" ]] && stale_map[$branch]=1
    done

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

# Helper: returns success when the branch has an upstream containing all local commits.
_git-local-branch-is-fully-upstreamed () {
    local branch="$1"
    local upstream
    upstream=$(git rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null) || return 1

    git merge-base --is-ancestor "$branch" "$upstream" 2>/dev/null
}

# Helper: returns success when the branch's configured upstream has been pruned away.
_git-local-branch-has-gone-upstream () {
    local target_branch="$1"
    local branch track

    while IFS=$'\t' read -r branch track; do
        [[ "$branch" == "$target_branch" && "$track" == "[gone]" ]] && return 0
    done < <(git for-each-ref --format=$'%(refname:short)\t%(upstream:track)' refs/heads 2>/dev/null)

    return 1
}

# Helper: remove a plugin-managed worktree directory and prune Git's stale metadata.
_git-remove-worktree-directory () {
    local wt_path="$1"
    local wt_base="$2"

    if [[ -z "$wt_path" || -z "$wt_base" || "$wt_path" == "$wt_base" || "$wt_path" != "$wt_base"/* ]]; then
        print -r -- "gwtd: refusing to remove unsafe worktree path: $wt_path" >&2
        return 1
    fi

    rm -rf -- "$wt_path" || return 1
    git worktree prune -v
}

# Remove a worktree checkout without deleting its branch.
# Without --force, the worktree must be clean and the branch must be safely stale.
gwtd () {
    local branch branch_force
    if [[ "$1" == "--force" ]]; then
        branch="$2"
        branch_force=1
    else
        branch="$1"
        branch_force=0
    fi

    if [[ -z "$branch" ]]; then
        print -r -- "usage: gwtd [--force] <branch>" >&2
        return 2
    fi

    if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
        print -r -- "gwtd: invalid branch name: $branch" >&2
        return 1
    fi

    local wt_base
    wt_base=$(_git-wt-base) || return 1

    local wt_path="$wt_base/$branch"
    if [[ ! -d "$wt_path" ]]; then
        print -r -- "gwtd: worktree not found: $wt_path" >&2
        return 1
    fi

    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    if [[ "$repo_root" == "$wt_path" ]]; then
        print -r -- "gwtd: refusing to remove the current worktree; cd elsewhere first" >&2
        return 1
    fi

    local wt_branch
    wt_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    if [[ "$wt_branch" != "$branch" ]]; then
        print -r -- "gwtd: $wt_path is checked out as $wt_branch, not $branch" >&2
        return 1
    fi

    if (( ! branch_force )); then
        if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
            print -r -- "gwtd: worktree has uncommitted changes; commit or stash first, or use gwtd --force" >&2
            return 1
        fi

        git fetch --prune || return 1

        if ! _git-local-branch-is-fully-upstreamed "$branch" && ! _git-local-branch-has-gone-upstream "$branch"; then
            print -r -- "gwtd: branch is not fully upstreamed; push first, or use gwtd --force" >&2
            return 1
        fi

        if ! _git-local-branch-is-stale "$branch"; then
            print -r -- "gwtd: branch is not stale relative to origin/$(git-main-branch); merge it first, or use gwtd --force" >&2
            return 1
        fi
    fi

    _git-remove-worktree-directory "$wt_path" "$wt_base"
}

# Prune local branches that have been fully merged into main (by any method).
# Handles: upstream gone, regular merge, squash merge, rebase merge.
gbprune () {
    print -r -- "gbprune: fetching remotes with prune..."
    git fetch --prune || return 1

    local current branch
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    print -r -- "gbprune: checking local branches..."
    local deleted_branches=0 failed_branches=0
    for branch in "${(@f)$(_git-stale-local-branches "$current")}"; do
        [[ -z "$branch" ]] && continue
        print -r -- "gbprune: deleting branch $branch"
        if git branch -D "$branch"; then
            (( deleted_branches += 1 ))
        else
            (( failed_branches += 1 ))
        fi
    done

    print -r -- "gbprune: deleted $deleted_branches branch(es), failed $failed_branches"
    (( failed_branches == 0 ))
}

# Pull current branch, then prune local branches fully merged into main (see gbprune).
gpbprune () {
    git pull && gbprune
}

# Remove linked worktrees under the plugin layout ({repo}-worktrees/<branch>) when the path
# matches the checked-out branch and that branch is stale (same rules as gbprune). Skips the
# primary worktree, detached HEAD, mismatched path/branch, and the worktree you are in. Finishes
# with git worktree prune for leftover administrative cruft.
gwtprune () {
    print -r -- "gwtprune: fetching remotes with prune..."
    git fetch --prune || return 1

    local porcelain main_wt wt_base repo_root
    # One `git worktree list --porcelain` for main path, wt_base, and parsing (not separate calls).
    porcelain=$(git worktree list --porcelain) || return 1
    main_wt=$(print -r -- "$porcelain" | sed -n 's/^worktree //p' | head -1)
    [[ -n "$main_wt" ]] || return 1
    wt_base=$(_git-wt-base-from-main "$main_wt") || return 1

    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1

    local -a candidate_wt_paths candidate_wt_branches candidate_branches
    local wt_path="" wt_branch="" saw_detached=0

    flush_wt_record () {
        if [[ -z "$wt_path" ]]; then
            wt_branch="" saw_detached=0
            return 0
        fi

        if (( saw_detached )) || [[ -z "$wt_branch" ]]; then
            wt_path="" wt_branch="" saw_detached=0
            return 0
        fi

        if [[ "$wt_path" == "$main_wt" ]]; then
            wt_path="" wt_branch="" saw_detached=0
            return 0
        fi

        local rel="${wt_path#"$wt_base"/}"
        if [[ "$wt_path" != "$wt_base/$rel" ]] || [[ "$rel" != "$wt_branch" ]]; then
            wt_path="" wt_branch="" saw_detached=0
            return 0
        fi

        candidate_wt_paths+=("$wt_path")
        candidate_wt_branches+=("$wt_branch")
        candidate_branches+=("$wt_branch")
        wt_path="" wt_branch="" saw_detached=0
    }

    local line ref
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            flush_wt_record
            continue
        fi

        case "$line" in
            worktree\ *)
                flush_wt_record
                wt_path="${line#worktree }"
                wt_branch="" saw_detached=0
                ;;
            detached)
                saw_detached=1
                ;;
            branch\ *)
                ref="${line#branch }"
                wt_branch="${ref#refs/heads/}"
                if [[ "$wt_branch" == "$ref" ]]; then
                    wt_branch=""
                fi
                ;;
        esac
    done < <(print -r -- "$porcelain")

    flush_wt_record

    local -A stale_map
    local b
    if (( ${#candidate_branches} > 0 )); then
        for b in "${(@f)$(_git-stale-local-branches "" "${candidate_branches[@]}")}"; do
            [[ -n "$b" ]] && stale_map[$b]=1
        done
    fi

    print -r -- "gwtprune: scanning worktrees (${#candidate_branches} managed branch candidate(s), ${#stale_map} stale)..."
    local removed_worktrees=0 deleted_branches=0 skipped_current=0 failed_worktrees=0 failed_branches=0

    local i
    for (( i = 1; i <= ${#candidate_wt_paths}; i++ )); do
        wt_path="${candidate_wt_paths[$i]}"
        wt_branch="${candidate_wt_branches[$i]}"

        if [[ -z "${stale_map[$wt_branch]-}" ]]; then
            continue
        fi

        if [[ "$wt_path" == "$repo_root" ]]; then
            print -r -- "gwtprune: skipping $wt_path (current directory)" >&2
            (( skipped_current += 1 ))
            continue
        fi

        print -r -- "gwtprune: removing worktree $wt_path ($wt_branch)"
        if git worktree remove "$wt_path"; then
            (( removed_worktrees += 1 ))
            print -r -- "gwtprune: deleting branch $wt_branch"
            if git branch -D "$wt_branch"; then
                (( deleted_branches += 1 ))
            else
                (( failed_branches += 1 ))
            fi
        else
            print -r -- "gwtprune: worktree remove failed for $wt_path" >&2
            (( failed_worktrees += 1 ))
        fi
    done

    local prune_status=0
    git worktree prune -v || prune_status=$?
    print -r -- "gwtprune: removed $removed_worktrees worktree(s), deleted $deleted_branches branch(es), skipped $skipped_current current worktree(s), failed $failed_worktrees worktree removal(s), failed $failed_branches branch deletion(s)"
    (( prune_status == 0 && failed_worktrees == 0 && failed_branches == 0 ))
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

    _git_shorthand_worktree_branches () {
        local wt_base
        wt_base=$(_git-wt-base 2>/dev/null) || return 1

        local current_target
        current_target=$(_git-current-wt-target 2>/dev/null)
        [[ -z "$current_target" ]] && current_target="root"

        local -a candidates
        candidates=("$wt_base"/*(N:t))
        candidates+=("root")

        local -a suggestions
        local -A seen
        local branch
        for branch in "${candidates[@]}"; do
            [[ -n "$branch" ]] || continue
            (( ${+seen[$branch]} )) && continue
            seen[$branch]=1
            [[ -n "$current_target" && "$branch" == "$current_target" ]] && continue
            suggestions+=("$branch")
        done
        if [[ -n "$current_target" ]] && (( ${+seen[$current_target]} )); then
            suggestions+=("$current_target")
        fi
        (( ${#suggestions} )) || return 1

        local expl
        _wanted branches expl 'worktree branch' compadd -M 'r:|/=* r:|=*' -Q -o nosort -- "${suggestions[@]}"
    }

    _git_shorthand_new_branch_name () {
        if (( CURRENT == 2 )); then
            _message 'new branch name'
        else
            _message 'no more arguments'
        fi
    }

    _git_shorthand_gwtd () {
        if (( CURRENT == 2 )); then
            _arguments \
                '--force[remove worktree without safety checks]' \
                '1:branch:_git_shorthand_local_branches'
        elif (( CURRENT == 3 )) && [[ "${words[2]}" == "--force" ]]; then
            _git_shorthand_local_branches
        else
            _message 'no more arguments'
        fi
    }

    _git_shorthand_gwtcd () {
        if (( CURRENT == 2 )); then
            _git_shorthand_worktree_branches
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

    _git_shorthand_single_all_branches () {
        if (( CURRENT == 2 )); then
            _git_shorthand_all_branches
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

        compdef _git_shorthand_new_branch_name gnb gnbpp gfmnb gwta gfmwta grnb gcobpp
        compdef _git_shorthand_single_local_branch git-obliterate
        compdef _git_shorthand_single_all_branches gwtco
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
