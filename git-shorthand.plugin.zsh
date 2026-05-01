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

# List local branch names stale relative to origin's main branch: upstream gone, merged into
# main, or identical tree to main. Always omits the main branch itself. If $1 is set, that
# branch name is omitted (gbprune passes the current HEAD so it is not deleted in place).
_git-stale-local-branches () {
    local exclude_branch="${1-}"

    local main_branch main_ref
    main_branch=$(git-main-branch)
    main_ref="origin/$main_branch"

    local -a to_delete
    local branch

    # 1. Branches whose upstream remote-tracking ref is gone
    while read -r branch; do
        [[ -z "$branch" ]] && continue
        [[ -n "$exclude_branch" && "$branch" == "$exclude_branch" ]] && continue
        [[ "$branch" == "$main_branch" ]] && continue
        to_delete+=("$branch")
    done < <(git branch -vv 2>/dev/null | grep ': gone]' | sed 's/^\*//' | awk '{print $1}')

    # 2. Branches whose commits are ancestors of main (regular merge, rebase)
    while read -r branch; do
        [[ -z "$branch" ]] && continue
        [[ -n "$exclude_branch" && "$branch" == "$exclude_branch" ]] && continue
        [[ "$branch" == "$main_branch" ]] && continue
        to_delete+=("$branch")
    done < <(git branch --merged "$main_ref" 2>/dev/null | sed 's/^\*//' | awk '{print $1}')

    # 3. Branches with identical tree to main (squash merge, etc.)
    for branch in $(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
        [[ -n "$exclude_branch" && "$branch" == "$exclude_branch" ]] && continue
        [[ "$branch" == "$main_branch" ]] && continue
        if git diff --quiet "$main_ref" "$branch" 2>/dev/null; then
            to_delete+=("$branch")
        fi
    done

    for branch in "${(u)to_delete[@]}"; do
        [[ -n "$branch" ]] && print -r -- "$branch"
    done
}

# Helper: returns success when a branch matches the same stale rules as gbprune.
_git-local-branch-is-stale () {
    local target_branch="$1"
    local stale_branch

    for stale_branch in "${(@f)$(_git-stale-local-branches)}"; do
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
    local gone_branch

    for gone_branch in "${(@f)$(git branch -vv 2>/dev/null | grep ': gone]' | sed 's/^\*//' | awk '{print $1}')}"; do
        [[ -z "$gone_branch" ]] && continue
        [[ "$gone_branch" == "$target_branch" ]] && return 0
    done

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
    git fetch --prune

    local current branch
    current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    for branch in "${(@f)$(_git-stale-local-branches "$current")}"; do
        [[ -z "$branch" ]] && continue
        git branch -D "$branch"
    done
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
    git fetch --prune

    local porcelain main_wt wt_base repo_root
    # One `git worktree list --porcelain` for main path, wt_base, and parsing (not separate calls).
    porcelain=$(git worktree list --porcelain) || return 1
    main_wt=$(print -r -- "$porcelain" | sed -n 's/^worktree //p' | head -1)
    [[ -n "$main_wt" ]] || return 1
    wt_base=$(_git-wt-base-from-main "$main_wt") || return 1

    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1

    local -A stale_map
    local b
    for b in "${(@f)$(_git-stale-local-branches)}"; do
        [[ -n "$b" ]] && stale_map[$b]=1
    done

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

        if [[ -z "${stale_map[$wt_branch]-}" ]]; then
            wt_path="" wt_branch="" saw_detached=0
            return 0
        fi

        if [[ "$wt_path" == "$repo_root" ]]; then
            print -r -- "gwtprune: skipping $wt_path (current directory)" >&2
            wt_path="" wt_branch="" saw_detached=0
            return 0
        fi

        if git worktree remove "$wt_path"; then
            git branch -D "$wt_branch"
        else
            print -r -- "gwtprune: worktree remove failed for $wt_path" >&2
        fi

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

    git worktree prune -v
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
