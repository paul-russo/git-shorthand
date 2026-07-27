---
name: git-worktrees
description: >
  Manage git worktrees as a recycled pool using Paul's git-shorthand commands
  (gwta, gfmwta, gwtco, gwtd, gwtcd, gwtl, gwtprune, gwtshrink, gbprune). Use
  whenever the user asks to start work on a new branch in an isolated directory,
  check out a PR branch, release a worktree slot, shrink the pool, clean up
  stale branches, or list/navigate worktrees. The slots are recycled to keep
  node_modules and build outputs warm across branch switches.
---

# Git Worktrees via git-shorthand (pooled model)

The user's shell has `git-shorthand` loaded. It manages a fixed pool of generically named worktree slots — `tree-1`, `tree-2`, … — that get reused across branches so `node_modules`, build outputs, and other untracked artifacts stay warm. Branches are independent of slots: releasing a slot does NOT delete the branch by default.

Always use these commands instead of raw `git worktree` — they enforce conventions the user relies on.

## Branch naming

When creating branches for the user, use the prefix `ppr_` followed by a short, lowercase, hyphen-separated description:

```
ppr_fix-memory-leak
ppr_crash-metrics-upload
ppr_cache-keys
```

Keep it brief and descriptive. No ticket numbers, no `feat/`/`fix/` prefixes, no slashes. Just `ppr_` + what-it-is.

## Directory layout

```
~/src/
  my-cool-thing/                 ← primary repo
  my-cool-thing-worktrees/
    tree-1/                      ← pool slot (holds whichever branch was
    tree-2/                        last activated into it)
    ...
    tree-6/
```

Up to 6 slots (`_GIT_WT_POOL_SOFT_CAP`) are created lazily. Slot names are opaque — the agent never picks or computes them. The activation commands `cd` into the allocated slot themselves, so to know which slot was used, read the shell's CWD after the command returns. Do **not** derive a path from the branch name.

## Creating / activating

| Command | What it does |
|---------|--------------|
| `gfmwta [--base <ref>] [--no-install] <branch>` | Fetch main, allocate a slot, create `<branch>` from `<ref>` (default: main) |
| `gwta   [--base <ref>] [--no-install] <branch>` | Same but no fetch — use when local main is current or offline |
| `gwtco  [--no-install] <branch>`                | Allocate a slot and check out an existing branch (local first, then `origin/<branch>` as a tracking branch) |

- All three reuse an idle slot when one is available, otherwise allocate a new `tree-N` up to the pool cap.
- If the pool is full they prompt the user interactively to recycle a slot or grow the cap. The interactive prompt is awkward for an agent; prefer running `gwtprune` or `gbprune` first to surface an idle slot.
- All three skip the install step (`npm install`, `yarn install`, etc.) when the lockfile is unchanged from the previous HEAD of the slot. Pass `--no-install` to suppress it entirely.
- If `<branch>` is already in some slot, the command just `cd`s there instead of re-allocating.
- **Prefer `gfmwta`** over `gwta` for new branches — fetching main first ensures the new branch starts from the latest remote state.

## Navigating / listing

| Command | What it does |
|---------|--------------|
| `gwtl`           | Fast list of the pool sorted by mtime: BRANCH / STATE (active/idle/current) / LAST MODIFIED / PATH |
| `gwtl --dirty`   | Same, but additionally runs a per-slot dirty check. Slow on multi-GB monorepos. |
| `gwtcd <fuzzy>`  | `cd` into a slot by substring match against slot directory names (`tree-3`) **and** the branches currently checked out in slots. `root` always routes to the primary repo. |

`gwtcd` lists candidates and fails on an ambiguous match; on no match it lists what's available.

## Releasing a slot

`gwtd` releases the slot back to the pool — it detaches HEAD so the slot becomes idle and reusable. The directory and any warm build outputs are preserved. The branch is preserved by default.

| Command | What it does |
|---------|--------------|
| `gwtd <branch>`                 | Find the slot holding `<branch>`, detach HEAD. Slot returns to the pool. Branch is kept. |
| `gwtd --delete-branch <branch>` | Also delete the local branch (refuses if it has unmerged work unless `--force`). |
| `gwtd --force <branch>`         | Allow release even if the slot is dirty (uncommitted tracked-file edits). |

`gwtd` always refuses the *current* slot — `cd` elsewhere first (`gwtcd root` or `gwtcd <other>`).

## Cleanup

| Command | What it does |
|---------|--------------|
| `gwtprune`  | Fetch with prune (retries on transient ref-lock races), then release every pool slot whose branch is stale (merged or gone from origin). Slots stay in the pool. Skips dirty and current slots. |
| `gwtshrink` | Permanently remove idle slots until the pool is at `_GIT_WT_POOL_SOFT_CAP`. Highest-numbered idle slots go first. Never removes active/dirty/current slots. Use after growing past the soft cap (`g` in the full-pool picker). |
| `gbprune`   | Delete local branches that are merged/squashed into main. If a stale branch is held by a clean pool slot, auto-releases the slot first (directory preserved, slot becomes idle). Dirty slots are skipped with a warning. |

Run `gbprune` after merging PRs to keep the pool full of useful, current branches. Run `gwtshrink` when you want to reclaim disk after the pool has grown past the soft cap.

## After creating/checking out: move the agent workspace

After `gfmwta`, `gwta`, or `gwtco` succeeds, the function leaves the shell in the allocated slot. Move the agent's workspace root there so file operations, linting, and search target the right directory:

```
CallMcpTool:
  server: "cursor-app-control"
  toolName: "move_agent_to_root"
  arguments: { "rootPath": "<absolute path to the new CWD>" }
```

Read the path from the shell's CWD after the activation command. Do **not** compute it from the branch — pool slots are named `tree-N`, not by branch.

Before using `cdev`, either complete this workspace move or pass the branch,
slot, or absolute path explicitly (for example, `cdev up ppr_my-feature`).
Never assume the activation function's `cd` persisted into a later agent shell
call; bare `cdev up` targets that call's actual cwd.

## Typical workflow

1. **Cleanup first** (recommended): `gbprune` — frees slots holding merged branches.
2. **Create / activate**: `gfmwta ppr_my-feature` — fetches main, allocates a slot, creates the branch, runs install if the lockfile changed.
3. **Move agent**: `move_agent_to_root` with the post-command CWD.
4. **Work**: edit, commit, push from the slot.
5. **After merge** (from anywhere): `gbprune` — auto-releases the slot that held the now-merged branch.

## Edge cases

- **Pool is full**: `gwta`/`gfmwta`/`gwtco` prompt interactively. As an agent, run `gwtprune` or `gbprune` first to surface an idle slot before activating, since the prompt is not script-friendly.
- **Branch already in a slot**: the activation commands detect this and `cd` into the existing slot rather than re-allocating.
- **Untracked files do not count as dirty**: in the warm-pool model they're typically build artifacts (node_modules, dist, etc.), and `git checkout` preserves them across branch switches. "Dirty" means staged or unstaged changes to tracked files.
- **Main branch detection**: the commands auto-detect `main` vs `master` via `git-main-branch`. You don't need to check.
- **Anywhere works**: `gwtl`, `gwtcd`, `gwtprune`, `gwtshrink`, `gbprune`, and `gwtd` can run from any slot or the primary repo — they resolve the pool base independently of CWD.
