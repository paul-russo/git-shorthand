# git-shorthand
This is a collection of Git shorthand aliases and functions. There are many like it, but this one is mine.
It can be installed using a ZSH plugin manager, though it should work in any other BASH-like shell.

## Usage
All commands start with `g` for `git`.

Alias and function names are generally comprised of the `g` prefix, followed by one or more shorthand character sequences. These shorthand sequences are ordered by the order in which the git operations they stand for will be run.

Currently, the exceptions to these rules are:
- The 'rename branch' function `grnb`, which is comprised of a sequence of somewhat non-obvious git operations
- The `git-main-branch` utility function, which dynamically detects whether the repo uses `master` or `main`

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
- `gprm` - Fetch main and rebase current branch on it

## Worktree Operations
Worktrees are stored in a `{repo_name}-worktrees/` sibling directory to keep your workspace clean. Worktrees and branches share a 1-to-1 lifecycle — when you remove a worktree, the branch is deleted with it.

- `gwta <branch>` - Add worktree with a new branch from main
- `gfmwta <branch>` - Fetch main, then add worktree with a new branch from it
- `gwtco <branch>` - Add worktree for an existing branch (e.g. a remote branch)
- `gwtl` - List all worktrees
- `gwtd <branch>` - Remove worktree and delete branch (warns if unmerged)
- `gwtd --force <branch>` - Force-remove worktree and force-delete branch
- `gwtcd <branch>` - `cd` into a worktree by branch name
- `gwtprune` - Prune stale worktree tracking references
