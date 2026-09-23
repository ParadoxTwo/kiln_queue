# shellcheck shell=bash
# Shared helpers for ./setup and ./dev. Sourced, not run.
#
# Written for bash 3.2, which is what macOS ships in /bin/bash: no associative
# arrays, no ${var,,}, no mapfile.

# ---- output ---------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

step() { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '    %s✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()  { err "$*"; exit 1; }
dim()  { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

has() { command -v "$1" >/dev/null 2>&1; }

# ---- prompts --------------------------------------------------------------

# True when we can ask the person at the keyboard a question.
# KILN_FORCE_INTERACTIVE lets the scenario tests pipe answers in.
interactive() { [ -t 0 ] || [ -n "${KILN_FORCE_INTERACTIVE:-}" ]; }

# ask_yn "Question?" y|n  -> returns 0 for yes. ASSUME_YES=1 answers the default.
# Talks on stderr, so it can be used inside $(...) without polluting the result.
ask_yn() { _ask_yn "$@" >&2; }
_ask_yn() {
  local question=$1 default=${2:-y} hint answer
  if [ "$default" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  if [ "${ASSUME_YES:-0}" = 1 ] || ! interactive; then
    info "$question $hint $default (automatic)"
    [ "$default" = y ]; return
  fi
  while true; do
    printf '    %s?%s %s %s ' "$C_BOLD" "$C_RESET" "$question" "$hint"
    IFS= read -r answer || answer=""
    [ -z "$answer" ] && answer=$default
    case "$answer" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
      *) info "Please answer y or n." ;;
    esac
  done
}

# ---- ruby ----------------------------------------------------------------

APP_ROOT=${APP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
RUBY_ENV_FILE="$APP_ROOT/tmp/.kiln-ruby"

# The version the app asks for, without the "ruby-" prefix.
required_ruby() { sed -e 's/^ruby-//' "$APP_ROOT/.ruby-version" | tr -d '[:space:]'; }

find_rbenv() {
  if has rbenv; then command -v rbenv; return; fi
  local candidate
  for candidate in "${RBENV_ROOT:-$HOME/.rbenv}/bin/rbenv" /opt/homebrew/bin/rbenv /usr/local/bin/rbenv; do
    [ -x "$candidate" ] && { echo "$candidate"; return; }
  done
  return 1
}

# Puts the chosen Ruby first on PATH for this process and its children.
#
# For "path", DIR is the bin folder of that Ruby. It goes first on PATH, along
# with the folder its gems install commands into, so bundle, rspec and ruby all
# come from the same install even when several Rubies are on the machine.
activate_ruby() { # activate_ruby MANAGER VERSION [DIR]
  KILN_RUBY_MANAGER=$1
  KILN_RUBY_VERSION=$2
  KILN_RUBY_DIR=${3:-}
  case "$KILN_RUBY_MANAGER" in
    rbenv)
      local rbenv_bin
      rbenv_bin=$(find_rbenv) || die "rbenv is not installed. Run ./setup first."
      PATH="$(dirname "$rbenv_bin"):$PATH"
      eval "$("$rbenv_bin" init - bash)"
      export RBENV_VERSION=$KILN_RUBY_VERSION
      ;;
    asdf)
      PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
      export ASDF_RUBY_VERSION=$KILN_RUBY_VERSION
      ;;
    path)
      if [ -n "$KILN_RUBY_DIR" ]; then
        [ -x "$KILN_RUBY_DIR/ruby" ] || return 1
        local gem_bin
        gem_bin=$("$KILN_RUBY_DIR/ruby" -e 'print Gem.bindir' 2>/dev/null || true)
        PATH="$KILN_RUBY_DIR:$PATH"
        [ -n "$gem_bin" ] && [ "$gem_bin" != "$KILN_RUBY_DIR" ] && PATH="$gem_bin:$PATH"
      fi
      ;;
    mise) ;;
    *) die "Unknown Ruby manager '$KILN_RUBY_MANAGER' in $RUBY_ENV_FILE. Run ./setup again." ;;
  esac
  export PATH KILN_RUBY_MANAGER KILN_RUBY_VERSION KILN_RUBY_DIR
}

# Runs a command with the chosen Ruby.
rb() {
  if [ "${KILN_RUBY_MANAGER:-path}" = mise ]; then
    mise exec "ruby@$KILN_RUBY_VERSION" -- "$@"
  else
    "$@"
  fi
}

# Replaces this process with a command run under the chosen Ruby.
rb_exec() {
  if [ "${KILN_RUBY_MANAGER:-path}" = mise ]; then
    exec mise exec "ruby@$KILN_RUBY_VERSION" -- "$@"
  else
    exec "$@"
  fi
}

save_ruby_choice() {
  mkdir -p "$APP_ROOT/tmp"
  printf 'KILN_RUBY_MANAGER=%s\nKILN_RUBY_VERSION=%s\nKILN_RUBY_DIR=%s\n' \
    "$KILN_RUBY_MANAGER" "$KILN_RUBY_VERSION" "${KILN_RUBY_DIR:-}" > "$RUBY_ENV_FILE"
}

# Loads what ./setup chose. Returns 1 when ./setup has not been run.
load_ruby_choice() {
  [ -f "$RUBY_ENV_FILE" ] || return 1
  local manager version dir
  manager=$(sed -n 's/^KILN_RUBY_MANAGER=//p' "$RUBY_ENV_FILE")
  version=$(sed -n 's/^KILN_RUBY_VERSION=//p' "$RUBY_ENV_FILE")
  dir=$(sed -n 's/^KILN_RUBY_DIR=//p' "$RUBY_ENV_FILE")
  [ -n "$manager" ] && [ -n "$version" ] || return 1
  case "$manager" in
    rbenv) find_rbenv >/dev/null || return 1 ;;
    mise|asdf) has "$manager" || return 1 ;;
  esac
  activate_ruby "$manager" "$version" "$dir"
}
