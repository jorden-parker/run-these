#!/usr/bin/env bash
set -uo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
sandbox="$(mktemp -d)"
failures=0
trap 'rm -rf "$sandbox"' EXIT

mkdir "$sandbox/plain" "$sandbox/configured"
cp "$repository_root/proxy-stream-check" "$sandbox/plain/"
cp "$repository_root/proxy-stream-check" "$sandbox/configured/"
proxy_stream_check="$sandbox/plain/proxy-stream-check"
configured_check="$sandbox/configured/proxy-stream-check"
cat > "$sandbox/configured/.env" <<'SETTINGS'
ANTHROPIC_BASE_URL="https://proxy.example"
ANTHROPIC_AUTH_TOKEN="secret-value"
ANTHROPIC_MODEL="some-model"
SETTINGS

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

run_check() {
  rm -rf "$sandbox/calls"
  mkdir "$sandbox/calls"
  env -i PATH="$repository_root/tests/stubs:/usr/bin:/bin" CURL_CALLS="$sandbox/calls" "$@" \
    > "$sandbox/output" 2>&1
}

sends_two_requests() {
  [ "$(cat "$sandbox/calls/count")" = "2" ]
}

is_first_request_non_streaming() {
  ! grep -q '"stream"' "$sandbox/calls/arguments-1"
}

is_second_request_streaming() {
  grep -q '"stream":true' "$sandbox/calls/arguments-2"
}

targets_the_messages_endpoint() {
  grep -qx 'https://proxy.example/v1/messages' "$sandbox/calls/arguments-1"
}

names_the_model() {
  grep -q '"model":"some-model"' "$sandbox/calls/arguments-1"
}

keeps_the_secret_off_the_command_line() {
  ! grep -q "secret-value" "$sandbox/calls/arguments-1" "$sandbox/calls/arguments-2"
}

sends_header_on_input() {
  grep -qx "$1" "$sandbox/calls/input-1" && grep -qx "$1" "$sandbox/calls/input-2"
}

labels_both_responses() {
  grep -q "non-streaming" "$sandbox/output" && grep -q "^=== streaming" "$sandbox/output"
}

names_the_other_model() {
  grep -q '"model":"other-model"' "$sandbox/calls/arguments-1"
}

is_settings_file_ignored() {
  git -C "$repository_root" check-ignore -q .env
}

exits_with_usage() {
  [ "$exit_code" = "2" ] && [ ! -e "$sandbox/calls/count" ] && grep -q "$1" "$sandbox/output"
}

run_check ANTHROPIC_BASE_URL=https://proxy.example ANTHROPIC_AUTH_TOKEN=secret-value \
  "$proxy_stream_check" some-model
expect "sends two requests" sends_two_requests
expect "sends the first request without stream" is_first_request_non_streaming
expect "sends the second request with stream true" is_second_request_streaming
expect "posts to the proxy's messages endpoint" targets_the_messages_endpoint
expect "names the model it was given" names_the_model
expect "keeps the token off the command line" keeps_the_secret_off_the_command_line
expect "sends the token as a bearer header on input" sends_header_on_input "Authorization: Bearer secret-value"
expect "labels both responses" labels_both_responses

run_check ANTHROPIC_BASE_URL=https://proxy.example/ ANTHROPIC_API_KEY=secret-value \
  ANTHROPIC_MODEL=some-model "$proxy_stream_check"
expect "sends an API key as x-api-key" sends_header_on_input "x-api-key: secret-value"
expect "reads the model from ANTHROPIC_MODEL" names_the_model
expect "drops a trailing slash from the proxy address" targets_the_messages_endpoint

run_check ANTHROPIC_AUTH_TOKEN=secret-value "$proxy_stream_check" some-model
exit_code=$?
expect "stops with usage when the proxy address is missing" exits_with_usage "ANTHROPIC_BASE_URL"

run_check ANTHROPIC_BASE_URL=https://proxy.example ANTHROPIC_AUTH_TOKEN=secret-value \
  "$proxy_stream_check"
exit_code=$?
expect "stops with usage when the model id is missing" exits_with_usage "model id"

run_check ANTHROPIC_BASE_URL=https://proxy.example "$proxy_stream_check" some-model
exit_code=$?
expect "stops with usage when there is no credential" exits_with_usage "ANTHROPIC_AUTH_TOKEN"

run_check "$configured_check"
expect "reads the proxy address from .env beside the script" targets_the_messages_endpoint
expect "reads the model from .env" names_the_model
expect "reads the token from .env" sends_header_on_input "Authorization: Bearer secret-value"

run_check ANTHROPIC_BASE_URL=https://other.example "$configured_check"
expect "prefers .env over the environment" targets_the_messages_endpoint

run_check "$configured_check" other-model
expect "prefers the model argument over .env" names_the_other_model

expect "git ignores .env, so a token cannot be committed" is_settings_file_ignored

exit "$failures"
