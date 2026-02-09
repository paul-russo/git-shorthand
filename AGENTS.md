# Agent instructions for git-shorthand

## README documentation

Keep the README in sync with the commands defined in `git-shorthand.plugin.zsh`.

- When adding, removing, or changing aliases or functions, update the README accordingly.
- The README should document all user-facing shorthand commands (aliases and functions), including:
  - Definitions table (shorthand character meanings)
  - Main branch operations
  - Worktree operations
  - Any new sections needed for new command categories
- Run `just check` to lint the plugin and spec files.

## Testing

All changes must be validated using [ShellSpec](https://shellspec.info/).

- Run tests with `just test` (or `shellspec`).
- When adding or changing behavior, add or update specs in the `spec/` directory.
- Ensure tests pass before considering work complete; run `just all` to lint and test together.
