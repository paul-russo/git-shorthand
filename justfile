# Lint the plugin and spec files with ShellCheck
check:
    shellcheck -s bash git-shorthand.plugin.zsh
    shellcheck spec/*.sh

# Run ShellSpec tests
test:
    shellspec

# Lint and test
[default]
all: check test
