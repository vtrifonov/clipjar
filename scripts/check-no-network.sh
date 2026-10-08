#!/bin/bash
# Fails if any networking API appears in Sources/ (Clipjar is local-only).
set -euo pipefail

pattern='URLSession|NSURLConnection|import Network|NWConnection|CFNetwork|CFStream|SCNetworkReachability|WebKit|\bsocket\(|\bconnect\('

set +e
matches=$(rg -n "$pattern" Sources)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "Networking code found in Sources/:"
  echo "$matches"
  exit 1
elif [ "$status" -eq 1 ]; then
  echo "No networking code found."
  exit 0
else
  echo "ripgrep failed with status $status" >&2
  exit "$status"
fi
