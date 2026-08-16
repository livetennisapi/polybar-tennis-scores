# Script: tennis-scores

A polybar module that shows the live tennis matches in one compact line, powered
by the [Live Tennis API](https://livetennisapi.com):

```
#Alcaraz 6-4 3-2* · Gauff 2-6 1-1*
```

* `*` marks the set currently in play.
* `#` marks the shown player as the current server — replace it with a glyph
  from your icon font (`SERVE_ICON` at the top of the script), the same
  convention the polybar-scripts collection uses.
* When nothing is live it falls back to the next scheduled fixture:
  `Next: Novak Djokovic vs Carlos Alcaraz 18:30` (your local time).
* When nothing is live and nothing is scheduled it prints nothing at all.
* Without an API key it prints `set LIVETENNIS_API_KEY`.


## Dependencies

* `curl`
* `jq`
* GNU coreutils (`date -d`, `stat -c` — any normal Linux)


## Configuration

You need an API key. [Get a free one](https://livetennisapi.com) — the FREE
tier is keyed at **30 requests/minute and 100 requests/day**, which is enough
for this script by design (see the quota math below). Export it as
`LIVETENNIS_API_KEY`.

Optional environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `LIVETENNIS_API_KEY` | — | your API key (required) |
| `LIVETENNIS_MAX_MATCHES` | `3` | max matches shown in the line |
| `LIVETENNIS_CACHE_TTL` | `900` | seconds between live-score fetches; values below 900 are raised to 900 |
| `LIVETENNIS_CACHE_DIR` | `~/.cache/polybar-tennis-scores` | on-disk response cache |


## Quota math (why the cache floor exists)

The script caches API responses on disk and refuses to refetch live scores
more often than every **15 minutes**, no matter what `interval` your bar uses:

* live scores: 24 h ÷ 15 min = **96 calls/day**
* fixture fallback: refreshed at most every 8 h = **≤ 3 calls/day**, and only
  while nothing is live

Worst case ≈ 99 calls/day, inside the free tier's 100/day. A failed fetch
serves the last good response and also waits a full cache window before
retrying, so an outage never turns into a request storm. Your polybar
`interval` therefore only controls how often the *cache* is re-read — set it
to whatever you like without burning quota; `900` simply matches the cadence
at which anything new can appear.


## Module

```ini
[module/tennis-scores]
type = custom/script
exec = ~/polybar-scripts/polybar-tennis-scores/tennis-scores.sh
env-LIVETENNIS_API_KEY = your-key-here
interval = 900
```

(`env-NAME =` needs polybar ≥ 3.6; on older versions export the key in the
environment that launches polybar.)


## Tests

No network needed — `curl` is mocked with canned API responses:

```sh
sh tests/run-tests.sh
```


## API

Endpoints used (both on the FREE tier): `GET /matches?status=live` and
`GET /fixtures` at `https://api.livetennisapi.com/api/public/v1`, Bearer
auth. Full schema: [docs.livetennisapi.com](https://docs.livetennisapi.com).
