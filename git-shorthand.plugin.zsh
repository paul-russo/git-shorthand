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

# Helper: resolve the worktrees base directory for the current repo.
# Works from the main repo or from inside any worktree.
_git-wt-base () {
    local main_wt=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
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
    local wt_base=$(_git-wt-base)
    cd "$wt_base/$1"
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