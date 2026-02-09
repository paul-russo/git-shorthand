# shellcheck shell=sh

# Defining variables and functions here will affect all specfiles.
# Change shell options inside a function may cause different behavior,
# so it is better to set them here.
# set -eu

# This callback function will be invoked only once before loading specfiles.
spec_helper_precheck() {
  # Available functions: info, warn, error, abort, setenv, unsetenv
  # Available variables: VERSION, SHELL_TYPE, SHELL_VERSION
  : minimum_version "0.28.1"
}

# This callback function will be invoked after a specfile has been loaded.
spec_helper_loaded() {
  :
}

# This callback function will be invoked after core modules has been loaded.
spec_helper_configure() {
  # Stub zsh completion to prevent errors when loading plugin (no compdef in test env)
  compdef() { :; }
  add-zsh-hook() { :; }

  # Load the plugin (must be in zsh - .shellspec has --shell zsh)
  . "${SHELLSPEC_PROJECT_ROOT:?}/git-shorthand.plugin.zsh"
}
