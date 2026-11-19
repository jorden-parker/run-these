#!/usr/bin/env bash
set -uo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
commit_message_hook="$repository_root/.githooks/commit-msg"
message_file="$(mktemp)"
failures=0
trap 'rm -f "$message_file"' EXIT

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

is_accepted() {
  printf '%s\n' "$1" > "$message_file"
  "$commit_message_hook" "$message_file" >/dev/null 2>&1
}

is_rejected() {
  ! is_accepted "$1"
}

names_the_expected_format() {
  local rejection
  printf 'added stuff\n' > "$message_file"
  rejection="$("$commit_message_hook" "$message_file" 2>&1)"
  [[ "$rejection" == *"type(scope): summary"* ]]
}

expect "accepts a type and summary" is_accepted "feat: add the proxy stream check"
expect "accepts a scope" is_accepted "fix(proxy): send the token on stdin"
expect "accepts a breaking change mark" is_accepted "feat(proxy)!: require a model id"
expect "accepts a body after the subject" is_accepted "$(printf 'docs: list the scripts\n\nOne row per script.')"
expect "accepts a merge commit git wrote" is_accepted "Merge branch 'main' of github.com:someone/run-these"
expect "rejects a plain sentence" is_rejected "added stuff"
expect "rejects a missing colon" is_rejected "feat add the proxy stream check"
expect "rejects an unknown type" is_rejected "feature: add the proxy stream check"
expect "rejects a capitalised type" is_rejected "Feat: add the proxy stream check"
expect "rejects a missing space after the colon" is_rejected "feat:add the proxy stream check"
expect "rejects an empty summary" is_rejected "feat: "
expect "says what format it wants" names_the_expected_format

exit "$failures"
