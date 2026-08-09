#!/bin/bash
# Creates or reuses the two deterministic simulator profiles used by Phase 3.
# Outputs shell-style UDID assignments; progress goes to stderr.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to select an available simulator runtime" >&2
  exit 1
fi

runtime=$(
  xcrun simctl list runtimes --json \
    | jq -r '
        [.runtimes[] | select(.isAvailable == true and (.identifier | contains("iOS")))]
        | sort_by(.version | split(".") | map(tonumber))
        | last
        | .identifier
      '
)

if [ -z "$runtime" ] || [ "$runtime" = "null" ]; then
  echo "No available iOS simulator runtime was found" >&2
  exit 1
fi

ensure_device() {
  local name="$1"
  local type_identifier="$2"
  local udid

  udid=$(
    xcrun simctl list devices --json \
      | jq -r --arg name "$name" '
          [.devices[][] | select(.isAvailable == true and .name == $name)]
          | first
          | .udid // empty
        '
  )

  if [ -z "$udid" ]; then
    echo "Creating $name" >&2
    udid=$(xcrun simctl create "$name" "$type_identifier" "$runtime")
  else
    echo "Reusing $name" >&2
  fi

  printf '%s' "$udid"
}

small_udid=$(ensure_device \
  "Sober QA Small" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation")
large_udid=$(ensure_device \
  "Sober QA Large" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max")

printf 'SOBER_SMALL_UDID=%s\n' "$small_udid"
printf 'SOBER_LARGE_UDID=%s\n' "$large_udid"
