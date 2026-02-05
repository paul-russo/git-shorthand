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
	git commit -m $argv
	git push
}

gcobpp () {
	git checkout -b $argv
	git push -u origin $argv
}

gaascpp () {
	git add --a
	git status
	git commit -m $argv
	git push
}

gaacpp () {
	git add --a
	git commit -m $argv
	git push
}

gaac () {
	git add --a
	git commit -m $argv
}

# From https://gist.github.com/lttlrck/9628955
grnb () {
	local oldBranch=$(git branch | grep \* | cut -d ' ' -f2)

	git branch -m $oldBranch $argv
	git push origin :$oldBranch
	git push --set-upstream origin $argv
}

git-obliterate () {
	git branch -d $argv && 
	git push origin :$argv
}

# Git functions for main branch operations
# New branch from main (without checking out main)
gnb () {
    git switch -c $argv $(git-main-branch)
}

# New branch from main and push
gnbpp () {
    git switch -c $argv $(git-main-branch)
    git push -u origin $argv
}

# Fetch main and new branch from it
gfmnb () {
    git fetch origin $(git-main-branch):$(git-main-branch)
    git switch -c $argv $(git-main-branch)
}

# Worktree operations
# Worktrees are stored in ../{repo_name}-worktrees/ to keep src/ clean.
# Worktrees and branches are managed together (1-to-1 lifecycle).

# Helper: resolve the main worktree directory for the current repo.
_git-main-worktree () {
    git worktree list --porcelain | sed -n 's/^worktree //p' | head -1
}

# Helper: resolve the current gwtcd target name.
# Returns the current worktree directory name, or main/master when on the primary worktree.
_git-current-wt-target () {
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1

    local main_wt
    main_wt=$(_git-main-worktree 2>/dev/null)

    if [[ -n "$main_wt" && "$repo_root" == "$main_wt" ]]; then
        git-main-branch 2>/dev/null
    else
        basename "$repo_root"
    fi
}

# Helper: resolve the worktrees base directory for the current repo.
# Works from the main repo or from inside any worktree.
_git-wt-base () {
    local main_wt=$(_git-main-worktree)
    [[ -n "$main_wt" ]] || return 1
    echo "$(dirname "$main_wt")/$(basename "$main_wt")-worktrees"
}

# Add worktree with a new branch from main
gwta () {
    local wt_base=$(_git-wt-base)
    mkdir -p "$wt_base"
    git worktree add -b "$1" "$wt_base/$1" $(git-main-branch)
}

# Fetch main, then add worktree with a new branch from it
gfmwta () {
    git fetch origin $(git-main-branch):$(git-main-branch)
    local wt_base=$(_git-wt-base)
    mkdir -p "$wt_base"
    git worktree add -b "$1" "$wt_base/$1" $(git-main-branch)
}

# Add worktree for an existing branch (e.g. a remote branch)
gwtco () {
    local wt_base=$(_git-wt-base)
    mkdir -p "$wt_base"
    git worktree add "$wt_base/$1" "$1"
}

# List worktrees
gwtl () {
    git worktree list
}

# Remove worktree and delete branch (pass --force to force both)
gwtd () {
    local wt_base=$(_git-wt-base)
    if [[ "$1" == "--force" ]]; then
        git worktree remove --force "$wt_base/$2" && git branch -D "$2"
    else
        git worktree remove "$wt_base/$1" && git branch -d "$1"
    fi
}

# cd into a worktree by branch name
gwtcd () {
    local target_branch="$1"
    local main_branch
    main_branch=$(git-main-branch 2>/dev/null) || return 1

    if [[ "$target_branch" == "$main_branch" ]]; then
        local main_wt
        main_wt=$(_git-main-worktree) || return 1
        cd "$main_wt"
    else
        local wt_base=$(_git-wt-base)
        cd "$wt_base/$target_branch"
    fi
}

# Prune stale worktree tracking references
gwtprune () {
    git worktree prune -v
}

# Pull rebase from main
gprm () {
    git fetch origin $(git-main-branch):$(git-main-branch)
    git rebase $(git-main-branch)
}

# Zsh completion support for shorthand aliases and functions.
if [[ -n "${ZSH_VERSION-}" ]]; then
    _git_shorthand_local_branches () {
        local -a branches
        branches=("${(@f)$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)}")
        _describe -t branches 'local branch' branches
    }

    _git_shorthand_all_branches () {
        local -a branches
        branches=("${(@f)$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null | sed '/\\/HEAD$/d')}")
        _describe -t branches 'branch' branches
    }

    _git_shorthand_worktree_branches () {
        local wt_base
        wt_base=$(_git-wt-base 2>/dev/null) || return 1

        local main_branch
        main_branch=$(git-main-branch 2>/dev/null)

        local current_target
        current_target=$(_git-current-wt-target 2>/dev/null)
        [[ -z "$current_target" ]] && current_target="$main_branch"

        local -a candidates
        candidates=("$wt_base"/*(N:t))
        [[ -n "$main_branch" ]] && candidates+=("$main_branch")

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
        _wanted branches expl 'worktree branch' compadd -Q -o nosort -- "${suggestions[@]}"
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
                '--force[force-remove worktree and delete branch]' \
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

        autoload -Uz +X _git

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
