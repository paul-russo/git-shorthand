# Lint the plugin, spec files, and scripts with ShellCheck
check:
    shellcheck -s bash git-shorthand.plugin.zsh
    shellcheck spec/*.sh
    shellcheck -s bash scripts/*.sh

# Run ShellSpec tests
test:
    shellspec

# Lint and test
[default]
all: check test
