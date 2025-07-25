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
| `co` | `checkout` |
| `d` | `diff` / `delete` (in worktree context) |
| `f` | `fetch` |
| `l` | `list` / `log` |
| `m` | main branch (master/main) |
| `n` | new (branch) |
| `p` | `pull` |
| `pp` | `push` |
| `po` | `pop` |
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
- `gwta <branch>` - Add new worktree with branch from main
- `gwtl` - List all worktrees
- `gwtd <worktree>` - Delete/remove worktree
