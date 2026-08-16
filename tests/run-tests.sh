#!/bin/sh
# Tests for tennis-scores.sh. No network: curl is overridden by a shell
# function that serves the canned JSON under tests/fixtures/.
# Usage: sh tests/run-tests.sh

TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
FIXTURES="$TESTS_DIR/fixtures"

# Deterministic local time for the "Next: ... HH:MM" assertion.
TZ=UTC
export TZ

TENNIS_SCORES_TEST=1
export TENNIS_SCORES_TEST
# shellcheck disable=SC1091
. "$TESTS_DIR/../tennis-scores.sh"

fail=0

check() {
    desc=$1
    expected=$2
    actual=$3
    if [ "$actual" = "$expected" ]; then
        echo "ok - $desc"
    else
        echo "FAIL - $desc"
        echo "    expected: [$expected]"
        echo "    actual:   [$actual]"
        fail=1
    fi
}

# Mock curl. Serves MOCK_LIVE for /matches and MOCK_FIXTURES for /fixtures,
# fails like `curl -f` when MOCK_FAIL=1, and counts every invocation.
curl() {
    url=''
    for arg in "$@"; do url=$arg; done
    echo x >>"$CURL_CALLS"
    [ "${MOCK_FAIL:-0}" = "1" ] && return 22
    case $url in
        */matches*)  cat "$MOCK_LIVE" ;;
        */fixtures*) cat "$MOCK_FIXTURES" ;;
        *)           return 22 ;;
    esac
}

calls() {
    if [ -f "$CURL_CALLS" ]; then wc -l <"$CURL_CALLS" | tr -d ' '; else echo 0; fi
}

fresh() {
    CACHE_DIR=$(mktemp -d)
    CURL_CALLS="$CACHE_DIR/curl-calls"
    LIVETENNIS_API_KEY=test-key
    MOCK_FAIL=0
    MOCK_LIVE="$FIXTURES/empty.json"
    MOCK_FIXTURES="$FIXTURES/fixtures.json"
}

# 1. Live matches: compact line, * on the set in play, # on the server (p1).
fresh
MOCK_LIVE="$FIXTURES/live.json"
check "live matches render compactly" \
    "#Alcaraz 6-4 3-2* · Gauff 2-6 1-1*" \
    "$(main)"

# 2. Live match with a null score (score is nullable): name only, no crash.
fresh
MOCK_LIVE="$FIXTURES/live-null-score.json"
check "null score shows the name only" \
    "Djokovic" \
    "$(main)"

# 3. No live matches: fall back to the next fixture (18:30 UTC start).
fresh
check "no live matches falls back to next fixture" \
    "Next: Novak Djokovic vs Carlos Alcaraz 18:30" \
    "$(main)"

# 4. No live matches and no fixtures: quiet.
fresh
MOCK_FIXTURES="$FIXTURES/empty.json"
check "nothing on stays quiet" \
    "" \
    "$(main)"

# 5. API error body: quiet, no fixture lie.
fresh
MOCK_LIVE="$FIXTURES/error.json"
check "error body stays quiet" \
    "" \
    "$(main)"

# 6. Network failure with a cold cache: quiet.
fresh
MOCK_FAIL=1
check "network failure with cold cache stays quiet" \
    "" \
    "$(main)"

# 7. Missing key: tell the user, make no request.
fresh
# shellcheck disable=SC2034 # read by main() in the sourced script
LIVETENNIS_API_KEY=''
check "missing key prints the hint" \
    "set LIVETENNIS_API_KEY" \
    "$(main)"
check "missing key makes no request" "0" "$(calls)"

# 8. Cache floor: a second run inside the TTL is served from disk —
#    even with the network down — and makes no new request.
fresh
MOCK_LIVE="$FIXTURES/live.json"
main >/dev/null
MOCK_FAIL=1
check "second run inside TTL is served from cache" \
    "#Alcaraz 6-4 3-2* · Gauff 2-6 1-1*" \
    "$(main)"
check "second run inside TTL makes no request" "1" "$(calls)"

# 9. Failed refresh keeps the last good payload (stale-if-error) and
#    resets the clock instead of hammering the API.
fresh
MOCK_LIVE="$FIXTURES/live.json"
main >/dev/null
touch -d '20 minutes ago' "$CACHE_DIR/live.json"
MOCK_FAIL=1
check "failed refresh serves the stale payload" \
    "#Alcaraz 6-4 3-2* · Gauff 2-6 1-1*" \
    "$(main)"
mtime=$(stat -c %Y "$CACHE_DIR/live.json")
now=$(date +%s)
if [ $((now - mtime)) -lt 60 ]; then
    echo "ok - failed refresh resets the retry clock"
else
    echo "FAIL - failed refresh resets the retry clock"
    fail=1
fi

# 10. TTL floor: a configured TTL below 900 s is raised to 900 s on load.
ttl=$(
    LIVETENNIS_CACHE_TTL=5
    export LIVETENNIS_CACHE_TTL
    # shellcheck disable=SC1091
    . "$TESTS_DIR/../tennis-scores.sh"
    printf '%s' "$CACHE_TTL"
)
check "TTL floor holds at 900" "900" "$ttl"

if [ "$fail" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
    exit 1
fi
