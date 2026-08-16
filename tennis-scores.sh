#!/bin/sh
# tennis-scores.sh — live tennis scores in your polybar.
#
# Powered by the Live Tennis API (https://livetennisapi.com).
# Get a free key: https://livetennisapi.com — export it as LIVETENNIS_API_KEY.
#
# Output:
#   live matches:  "#Alcaraz 6-4 3-2* · Gauff 2-6 1-1*"
#                  (* = set in play; # = the shown player is serving —
#                   replace SERVE_ICON with a glyph from your icon font)
#   no live play:  "Next: <player1> vs <player2> HH:MM"  (local time)
#   nothing on:    no output (quiet)
#   no key set:    "set LIVETENNIS_API_KEY"
#
# Quota safety: responses are cached on disk and never refetched before
# CACHE_TTL seconds (floor: 900). Your polybar `interval` can be anything —
# the script, not the bar, decides when the network is hit.

API_BASE="${LIVETENNIS_API_BASE:-https://api.livetennisapi.com/api/public/v1}"
CACHE_DIR="${LIVETENNIS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/polybar-tennis-scores}"
MAX_MATCHES="${LIVETENNIS_MAX_MATCHES:-3}"

# Icon shown before the name of the player currently serving.
# Kept as "#" so you can pick a glyph from your own icon font.
SERVE_ICON="#"

# 15-minute floor on live-score fetches: 24 h / 15 min = 96 calls/day,
# inside the free tier's 100 requests/day. Lower values are ignored.
CACHE_TTL="${LIVETENNIS_CACHE_TTL:-900}"
case "$CACHE_TTL" in
    *[!0-9]*) CACHE_TTL=900 ;;
esac
[ "$CACHE_TTL" -lt 900 ] && CACHE_TTL=900

# Fixtures move slowly; refresh them at most every 8 h (max 3 calls/day,
# and only on days with no live match in the cache window).
FIXTURES_TTL=28800

# fetch_cached <name> <ttl> <url>
# Prints the cached body if younger than <ttl> seconds, otherwise fetches.
# On a failed or invalid fetch the old body (if any) is kept and its clock
# reset, so a broken API is retried at most once per <ttl> — never hammered.
fetch_cached() {
    f="$CACHE_DIR/$1.json"
    ttl=$2
    url=$3
    now=$(date +%s)
    mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt "$ttl" ]; then
        cat "$f" 2>/dev/null
        return 0
    fi
    if body=$(curl -sf --max-time 10 \
            -H "Authorization: Bearer $LIVETENNIS_API_KEY" "$url") \
        && printf '%s' "$body" | jq -e '.data' >/dev/null 2>&1; then
        printf '%s\n' "$body" >"$f"
    else
        touch "$f"
    fi
    cat "$f" 2>/dev/null
}

# format_live: stdin = /matches?status=live body, stdout = the bar line.
format_live() {
    jq -r --argjson max "$MAX_MATCHES" --arg icon "$SERVE_ICON" '
        def surname: (. // "") | split(" ") | if length > 0 then .[-1] else "" end;
        [ .data[]
          | select(.status == "live")
          | (.players.p1.name | surname) as $name
          | (.score // {}) as $s
          | ($s.games // []) as $g
          | ([ range(0; (($g[0] // []) | length))
               | "\($g[0][.])-\($g[1][.])" ]) as $sets
          | ($sets
             | if length > 0 then (.[:-1] + [.[-1] + "*"]) | join(" ")
               else "" end) as $score
          | (if $s.server == 1 then $icon else "" end) as $srv
          | [$srv + $name, $score] | map(select(length > 0)) | join(" ")
          | select(length > 0)
        ]
        | .[:$max]
        | join(" · ")
    '
}

# format_next: stdin = /fixtures body, stdout = "Next: A vs B [HH:MM]".
format_next() {
    row=$(jq -r '
        .data[0] // empty
        | [(.player1_name // "TBD"), (.player2_name // "TBD"),
           (.start_time // "")]
        | @tsv
    ') || return 1
    [ -z "$row" ] && return 0
    p1=$(printf '%s\n' "$row" | cut -f1)
    p2=$(printf '%s\n' "$row" | cut -f2)
    st=$(printf '%s\n' "$row" | cut -f3)
    hm=""
    if [ -n "$st" ]; then
        hm=$(date -d "$st" +%H:%M 2>/dev/null) || hm=""
    fi
    if [ -n "$hm" ]; then
        printf 'Next: %s vs %s %s\n' "$p1" "$p2" "$hm"
    else
        printf 'Next: %s vs %s\n' "$p1" "$p2"
    fi
}

main() {
    if [ -z "${LIVETENNIS_API_KEY:-}" ]; then
        echo "set LIVETENNIS_API_KEY"
        return 0
    fi
    mkdir -p "$CACHE_DIR"

    live=$(fetch_cached live "$CACHE_TTL" "$API_BASE/matches?status=live")
    out=$(printf '%s' "$live" | format_live 2>/dev/null) || out=""
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
        return 0
    fi

    # A valid-but-empty live payload means nothing is on: show the next
    # fixture. Anything else (error body, empty cache) stays quiet.
    if printf '%s' "$live" | jq -e '.data' >/dev/null 2>&1; then
        fx=$(fetch_cached fixtures "$FIXTURES_TTL" "$API_BASE/fixtures?limit=1")
        line=$(printf '%s' "$fx" | format_next 2>/dev/null) || line=""
        [ -n "$line" ] && printf '%s\n' "$line"
    fi
    return 0
}

if [ "${TENNIS_SCORES_TEST:-0}" != "1" ]; then
    main
fi
