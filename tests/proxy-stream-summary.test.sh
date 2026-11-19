#!/usr/bin/env bash
set -uo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
sandbox="$(mktemp -d)"
failures=0
trap 'rm -rf "$sandbox"' EXIT

mkdir "$sandbox/scripts"
cp "$repository_root/proxy-stream-check" "$repository_root/proxy-stream-summary" "$sandbox/scripts/" 2>/dev/null
proxy_stream_summary="$sandbox/scripts/proxy-stream-summary"

expect() {
  local description="$1"
  shift
  if "$@"; then
    echo "ok: $description"
  else
    echo "FAIL: $description"
    failures=$((failures + 1))
  fi
}

run_summary() {
  rm -rf "$sandbox/calls"
  mkdir "$sandbox/calls"
  env -i PATH="$repository_root/tests/stubs:/usr/bin:/bin" CURL_CALLS="$sandbox/calls" "$@" \
    > "$sandbox/output" 2>&1
}

has_line() {
  grep -qx "$1" "$sandbox/output"
}

has_line_count() {
  [ "$(grep -cx "$1" "$sandbox/output")" = "$2" ]
}

lacks_text() {
  ! grep -q "$1" "$sandbox/output"
}

has_request_count() {
  [ "$(cat "$sandbox/calls/count" 2>/dev/null)" = "$1" ]
}

run_summary ANTHROPIC_BASE_URL=https://proxy.example ANTHROPIC_AUTH_TOKEN=secret-value \
  "$proxy_stream_summary" first-model second-model
expect "sends two requests per model id" has_request_count 4
expect "heads each model's result with its id" has_line "##### first-model"
expect "heads the second model's result too" has_line "##### second-model"
expect "keeps every status line" has_line_count "HTTP/1.1 429 Too Many Requests" 4
expect "keeps the retry-after header" has_line_count "retry-after: 12" 4
expect "keeps the rate limit headers" has_line_count "anthropic-ratelimit-requests-remaining: 0" 4
expect "keeps the error body" has_line_count '{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}' 4
expect "keeps the request labels" has_line_count "=== streaming, what a normal turn sends ===" 2
expect "drops cookies" lacks_text "set-cookie"
expect "drops other headers" lacks_text "gateway.internal"
expect "never prints the token" lacks_text "secret-value"

run_summary ANTHROPIC_BASE_URL=https://proxy.example ANTHROPIC_MODEL=configured-model \
  "$proxy_stream_summary"
expect "checks the configured model once when no id is given" has_request_count 2

run_summary "$proxy_stream_summary" first-model
expect "shows why the check could not run" has_line "ANTHROPIC_BASE_URL is not set."

exit "$failures"
