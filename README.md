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

## Color output
Status messages from the worktree and prune commands (`gwta`, `gwtco`, `gwtl`, `gwtd`, `gwtcd`, `gwtprune`, `gbprune`, `gpbprune`, and the internal `gwtpool:` lines) emit ANSI color when stdout/stderr is a TTY. Colors are semantic: command tags (e.g. `gwta:`) are bold cyan, branch refs are yellow, paths are blue, success is green, warnings/dirty state are yellow, errors are red. The `gwtl` table colors the STATE column per state (`active` green, `dirty` bold yellow, `current` bold cyan, `idle` dim).

Color is automatically suppressed when output is redirected to a pipe or file, when `TERM` is `dumb`, and when either `NO_COLOR` (see [no-color.org](https://no-color.org)) or `GIT_SHORTHAND_NO_COLOR` is set.

## Shell Completions
When loaded in `zsh` with completion enabled (`compinit`), shorthand commands complete like their underlying `git` subcommands.

Custom completion is also included for shorthand commands that take branch/worktree names, such as:
- `git-obliterate`, `gwta`, `gfmwta`, `gwtco`, `gwtd`, `gwtcd`
- `gnb`, `gnbpp`, `gfmnb`, `grnb`, `gcobpp`

`gwtcd` completes against pool slot names (`tree-1`, `tree-2`, …), the branches currently checked out in slots, the primary checkout's current branch, and the literal `root`; `gwtd` completes only those branches that actually sit in a slot.

Branch/worktree name completion uses the same slash-aware matching as zsh’s stock `_git` completion, so names like `example/example-branch` complete correctly (not only one path segment at a time).

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
- `gbprune` - Fetch with prune, then force-delete local branches whose changes are fully in main (handles gone upstream, regular merge, rebase merge, equivalent patch/tree changes, and squash-merged GitHub PRs when `gh` is available); prints progress and a summary of deleted/failed branches. If a stale branch is held by a linked worktree (pool slot or otherwise), the slot is auto-released — HEAD is detached and the branch deleted, but the directory and its warm `node_modules` / build artifacts are preserved for reuse. Dirty (or current) slots are skipped with a clear message so uncommitted work is never destroyed. Fetch failures (e.g. transient `cannot lock ref ... is at X but expected Y` races on busy repos) are retried with short backoff; if the retries still fail the prune continues against local state rather than aborting
- `gpbprune` - Pull, then `gbprune` (update current branch, then clean merged local branches)
- `gwtprune` - Release pool slots whose branches are stale (detach HEAD, delete the stale branch). Slots stay in the pool with their `node_modules` intact; see [Worktree Operations](#worktree-operations) below.

If you keep work in pool slots, run `gwtprune` before `gbprune` so stale branches aren't blocked by a slot still holding them.

## Worktree Operations
Worktrees live in a recycled **pool** under a `{repo_name}-worktrees/` sibling directory. Each slot is a long-lived checkout named `tree-1`, `tree-2`, … that keeps its own `node_modules` and build state. Activating a slot means checking a branch out into it; releasing a slot detaches HEAD so it can be reused. Install runs only when the lockfile actually changed between the previous and current HEAD, so common branch hops are nearly instant.

### Pool model
- **Pool soft cap.** New slots are created on demand up to `_GIT_WT_POOL_SOFT_CAP` (default `6`). When you ask for another slot after the cap is reached and no idle slot is available, `gwta`/`gfmwta`/`gwtco` show an interactive picker that lets you (1) pick an active slot to release and reuse, (2) `g` to grow the pool past the cap, or (3) `q` to cancel. In non-interactive shells (stdin not a TTY and closed before a choice is read) the picker lists occupied slots on stderr and fails with a short hint (`gwtd`, `gwtprune`, or an interactive terminal) instead of exiting silently.
- **Slot states.**
  - `idle` — detached HEAD, clean working tree. Eligible for reuse.
  - `active` — branch checked out, clean.
  - `dirty` — uncommitted or untracked changes. Never auto-reused.
  - `current` — your cwd is inside the slot. Never auto-released or auto-reused.
- **Lockfile-aware install.** Each activation compares the slot's previous HEAD against the new HEAD on the detected lockfile (`pnpm-lock.yaml` > `yarn.lock` > `package-lock.json`). If they match, the install step is skipped. Pass `--no-install` to skip unconditionally.
- **Pool post-checkout hook.** Optionally place an executable `post-checkout` script at the root of the `{repo}-worktrees/` directory (next to `tree-1`, `tree-2`, …). It runs after each activation when install is enabled, including when the root lockfile install was skipped. The script receives the slot path and previous HEAD as arguments (`$1`, `$2`) and may use `GWT_SLOT`, `GWT_OLD_HEAD`, and `GWT_MAIN_LOCKFILE_UNCHANGED` (`1` when root install was skipped). Use this for repo-specific extra installs (e.g. a nested `npm ci` under `vscode/` while the monorepo root uses pnpm).

### Commands
- `gwta [--base <ref>] [--no-install] <branch>` — allocate a slot, create `<branch>` from `--base` (default `$(git-main-branch)`), conditionally install, and `cd` in. If `<branch>` is already in a slot, just `cd` there.
- `gfmwta [--base <ref>] [--no-install] <branch>` — fetch `origin/$(git-main-branch)` first, then `gwta`.
- `gwtco [--no-install] <branch>` — allocate a slot and check out an existing branch. Prefers a local branch, falls back to `origin/<branch>` (creates a tracking branch). If `<branch>` is already in a slot, just `cd` there.
- `gwtcd <fuzzy>` — `cd` into a slot by fuzzy match against slot directory names **and** the branches currently checked out. Slot names match literally first (`tree-3`), then with `-`, `_`, and `/` ignored (`tree3`, `coolbranch` → `my-cool-branch`), preferring the closest name when several normalize the same way. Branch names still match literally only. The primary checkout participates as the synthetic `root` slot, so the literal `root` **and** the branch it currently holds both route to the primary repo (e.g. `gwtcd main` when root has `main` checked out). Ambiguous matches print the candidate list and fail; no match prints what is available and fails.
- `gwtl [--dirty]` — print the pool as a table sorted by slot mtime descending. Columns: `BRANCH | STATE | LAST MODIFIED | PATH`. The primary repo is pinned at the top with `(main repo)` in the STATE column. By default the dirty check is skipped so listing stays snappy on large monorepos; pass `--dirty` to additionally report which slots have uncommitted tracked-file changes.
- `gwtd [--delete-branch] [--force] <branch>` — release the slot that currently holds `<branch>`: detach HEAD, optionally also delete the branch. Refreshes the index before the dirty check so release agrees with `git status`. Refuses dirty without `--force`. Always refuses the current slot (cd elsewhere first).
- `gwtprune` — fetch with prune, then release every pool slot whose branch is stale by the same rules as `gbprune` (detach HEAD and delete the stale branch). Slots stay in the pool. Skips dirty and current slots. Finishes with `git worktree prune -v`.
