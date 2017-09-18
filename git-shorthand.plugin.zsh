# Git shorthand aliases
alias ga="git add"
alias gaa="git add --a"
alias gs="git status"
alias gbs="git branch; git status"
alias gc="git commit -m"
alias gsc="git status; git commit -m"
alias gaas="git add --a; git status"
alias gst="git stash"
alias gaast="git add --a; git stash"
alias gstl="git stash list"
alias gstpo="git stash pop"
alias gp="git pull"
alias gpp="git push"
alias gppu="git push -u origin"
alias gb="git branch"
alias gco="git checkout"
alias gcob="git checkout -b"
alias gl="git log"
alias gpr="git pull --rebase --autostash"

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
