#!/bin/bash
# Fails if any networking API appears in Sources/ (Clipjar is local-only).
set -euo pipefail

# Networking APIs by name, plus APIs that reach the network as a side effect: complete http(s) URL
# literals and `contentsOf:` loads of string-built URLs (e.g. `Data(contentsOf: URL(string: "https://…"))`),
# and HTML import into NSAttributedString, which fetches subresources. Building an https URL from a
# prefix, as link detection does, is not flagged.
pattern='URLSession|NSURLSession|NSURLConnection|URLRequest|import Network|Network\.framework|NWConnection|CFNetwork|CFStream|CFSocket|getStreamsToHost|getaddrinfo|SCNetworkReachability|WebKit|\bsocket\(|\bconnect\('
pattern+='|URL\(string: *"https?://[^"]+"\)|contentsOf: *URL\(string|DocumentType\.html|documentType: *\.html'

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
