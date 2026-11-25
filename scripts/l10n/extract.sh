#!/bin/bash
# Prints (as JSON) every localizable string key used by the app, as seen by the Swift compiler.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
swift build --package-path "$ROOT/App" --build-path "$TMP/build" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$TMP/strings" >/dev/null 2>&1
python3 - "$TMP" <<'PY'
import glob, json, sys
keys = set()
for f in glob.glob(sys.argv[1] + "/build/**/*.stringsdata", recursive=True):
    for entries in json.load(open(f)).get("tables", {}).values():
        keys.update(e["key"] for e in entries)
print(json.dumps(sorted(keys), ensure_ascii=False, indent=0))
PY
