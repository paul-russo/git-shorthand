# git-shorthand
This is a collection of Git shorthand aliases and functions.

## Development
- `just check` – lint the plugin with [ShellCheck](https://www.shellcheck.net/)
- `just test` – run tests with [ShellSpec](https://shellspec.info/)
- `just all` – lint and test

There are many like it, but this one is mine.
It can be installed using a ZSH plugin manager, though it should work in any other BASH-like shell.

## Usage
All commands start with `g` for `git`.

Alias and function names are generally comprised of the `g` prefix, followed by one or more shorthand character sequences. These shorthand sequences are ordered by the order in which the git operations they stand for will be run.

Currently, the exceptions to these rules are:
- The 'rename branch' function `grnb`, which is comprised of a sequence of somewhat non-obvious git operations
- The `git-main-branch` utility function, which dynamically detects whether the repo uses `master` or `main`

## Shell Completions
When loaded in `zsh` with completion enabled (`compinit`), shorthand commands complete like their underlying `git` subcommands.

Custom completion is also included for shorthand commands that take branch/worktree names, such as:
- `git-obliterate`, `gwtco`, `gwtd`, `gwtcd`
- `gnb`, `gnbpp`, `gfmnb`, `gwta`, `gfmwta`, `grnb`, `gcobpp`

Branch/worktree name completion uses the same slash-aware matching as zsh’s stock `_git` completion, so names like `cursor/example-branch` complete correctly (not only one path segment at a time).

## Definitions
| Shorthand | Meaning |
| --------- | ------- |
| `a` | `add` |
| `aa` | `add --a` |
| `b` | `branch` |
| `c` | `commit` |
| `cd` | `cd` (change directory) |
| `co` | `checkout` |
| `d` | `diff` / `delete` (in worktree context) |
| `f` | `fetch` |
| `l` | `list` / `log` |
| `m` | main branch (master/main) |
| `n` | new (branch) |
| `p` | `pull` |
| `pp` | `push` |
| `po` | `pop` |
| `prune` | `prune` |
| `r` | `--rebase --autostash` |
| `rn` | rename |
| `s` | `status` |
| `st` | `stash` |
| `wt` | `worktree` |
| `x` | `--staged` |

## Main Branch Operations
These commands work with either `master` or `main` branches automatically:
- `gfm` - Fetch main branch without checking it out
- `gcom` - Checkout main branch (when not already checked out elsewhere)
- `gnb <branch>` - Create new branch from main
- `gnbpp <branch>` - Create new branch from main and push
- `gfmnb <branch>` - Fetch main, then create new branch from it
- `gpm` - Pull from main
- `gprm` - Fetch main and rebase current branch on it
- `gbprune` - Fetch with prune, then force-delete local branches whose changes are fully in main (handles gone upstream, regular merge, squash merge, rebase merge)
- `gpbprune` - Pull, then `gbprune` (update current branch, then clean merged local branches)

If you use linked worktrees under `{repo_name}-worktrees/`, run `gwtprune` before `gbprune` when cleaning up stale branches. Git will not delete a branch that is still checked out in another worktree until that checkout is removed.

## Worktree Operations
Worktrees are stored in a `{repo_name}-worktrees/` sibling directory to keep your workspace clean. Worktrees and branches share a 1-to-1 lifecycle — when you remove a worktree, the branch is deleted with it.

- `gwta <branch>` - Add worktree with a new branch from main
- `gfmwta <branch>` - Fetch main, then add worktree with a new branch from it
- `gwtco <branch>` - Add worktree for an existing branch (e.g. a remote branch)
- `gwtl` - List all worktrees
- `gwtd <branch>` - Remove worktree and delete branch (warns if unmerged)
- `gwtd --force <branch>` - Force-remove worktree and force-delete branch
- `gwtcd <branch>` - `cd` into a worktree by branch name (`root` goes to the primary repo worktree; `main` is a normal branch name)
- `gwtprune` - Fetch with prune; remove `{repo}-worktrees/<branch>` checkouts whose relative path matches the checked-out branch and that branch is stale (same detection as `gbprune`); then `git worktree prune -v`. Skips the primary worktree, non-plugin paths, detached HEAD, branch/path mismatches, and the worktree you are currently in. If remove fails (for example dirty tree or submodules), use `gwtd --force <branch>` for that checkout.
