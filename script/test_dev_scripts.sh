#!/usr/bin/env bash
# Scenario tests for ./setup and ./dev. Run from the app root:
#
#   script/test_dev_scripts.sh
#
# They start throwaway listeners with python3 to occupy ports, then drive ./dev
# with scripted answers. ./dev --dry-run prints the server command instead of
# starting Rails, so nothing here boots a server.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0
# Listeners are started inside $(...) subshells, so find them by a marker in
# their command line rather than by remembering pids.
cleanup() { pkill -f "kiln-test-listener" 2>/dev/null; }
trap cleanup EXIT

occupy() { # occupy PORT -> starts a listener, prints its pid
  python3 -c "
import socket, time  # kiln-test-listener
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', $1)); s.listen(); time.sleep(600)" >/dev/null 2>&1 &
  # python3 may be a shim that starts the real interpreter as a child, so ask
  # the port who is listening rather than trusting $!.
  local pid=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    pid=$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1)
    [ -n "$pid" ] && break
    sleep 0.2
  done
  echo "$pid"
}

check() { # check NAME CONDITION...
  local name=$1; shift
  if "$@"; then
    PASS=$((PASS + 1)); printf '  \033[32mok\033[0m   %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$name"
    printf '       output was:\n%s\n' "$OUT" | sed 's/^/       | /' | head -40
  fi
}

contains() { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
not_contains() { ! contains "$1"; }
# A killed listener can linger as a zombie when nothing reaps it (PID 1 in a
# container), so a zombie counts as dead.
alive() { kill -0 "$1" 2>/dev/null && ! ps -o stat= -p "$1" 2>/dev/null | grep -q Z; }
dead() { ! alive "$1"; }

run_dev() { # run_dev "answers" args...
  local answers=$1; shift
  OUT=$(printf '%b' "$answers" | KILN_FORCE_INTERACTIVE=1 ./dev --dry-run "$@" 2>&1); STATUS=$?
}

echo "./dev"

OUT=$(./dev --help 2>&1); STATUS=$?
check "--help exits 0 and explains the port option" test "$STATUS" -eq 0 -a -n "$(contains '--port' && echo y)"

run_dev "" --port 3461
check "a free port starts straight away" contains "bin/rails server -p 3461"

P=$(occupy 3462)
run_dev "q\n" --port 3462
check "a busy port names the process using it" contains "python"
check "a busy port shows the pid" contains "$P"
check "quitting exits non-zero" test "$STATUS" -ne 0
check "quitting leaves the process alone" alive "$P"
check "quitting does not start a server" not_contains "bin/rails server"

run_dev "n\n" --port 3462
check "moving on picks the next free port" contains "bin/rails server -p 3463"

P2=$(occupy 3464)
run_dev "c\n3464\nc\n3466\n" --port 3462
check "a chosen port is checked again, and named when busy" contains "$P2"
check "then the next choice is used" contains "bin/rails server -p 3466"

run_dev "c\nabc\n3467\n" --port 3462
check "a port that is not a number is refused and asked again" contains "bin/rails server -p 3467"

run_dev "k\n" --port 3462
check "killing frees the port and starts on it" contains "bin/rails server -p 3462"
check "killing really stopped the process" dead "$P"

occupy 3468 >/dev/null
occupy 3469 >/dev/null
OUT=$(./dev --dry-run --auto --port 3468 </dev/null 2>&1); STATUS=$?
check "--auto without a terminal skips busy ports" contains "bin/rails server -p 3470"

OUT=$(./dev --dry-run --port 3468 </dev/null 2>&1); STATUS=$?
check "without a terminal and without --auto it stops and explains" test "$STATUS" -ne 0 -a -n "$(contains '--auto' && echo y)"

mkdir -p tmp/pids
echo 999999 > tmp/pids/server.pid
run_dev "" --port 3471
check "a stale server.pid is cleared" test ! -f tmp/pids/server.pid
check "and the server starts" contains "bin/rails server -p 3471"

echo "./setup"

OUT=$(./setup --help 2>&1); STATUS=$?
check "--help exits 0" test "$STATUS" -eq 0

rm -f tmp/.kiln-ruby
OUT=$(./setup --yes --no-editor 2>&1); STATUS=$?
check "a full run succeeds" test "$STATUS" -eq 0
check "a full run finishes with the specs passing" contains " 0 failures"
OUT=$(./setup --yes --skip-tests --no-editor 2>&1); STATUS=$?
check "a second run succeeds" test "$STATUS" -eq 0
check "a second run skips the Ruby install" contains "already installed"
check "a second run does not import the sample twice" contains "already imported"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
