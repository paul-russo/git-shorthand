# git-shorthand
This is a collection of Git shorthand aliases and functions. There are many like it, but this one is mine.
It can be installed using a ZSH plugin manager, though it should work in any other BASH-like shell.

## Usage
All commands start with `g` for `git`.

Alias and function names are generally comprised of the `g` prefix, followed by one or more shorthand character sequences. These shorthand sequences are ordered by the order in which the git operations they stand for will be run.

Currently, the only exception to these rules is the 'rename branch' function `grnb`, which is comprised of a sequence of somewhat non-obvious git operations.

## Definitions
| Shorthand | Meaning |
| --------- | ------- |
| `a` | `add` |
| `aa` | `add --a` |
| `b` | `branch` |
| `c` | `commit` |
| `co` | `checkout` |
| `d` | `diff` |
| `l` | `list` |
| `p` | `pull` |
| `pp` | `push` |
| `po` | `pop` |
| `r` | `--rebase --autostash` |
| `rn` | rename |
| `s` | `status` |
| `st` | `stash` |
| `u` | `-u origin` |
| `x` | `--staged` |
