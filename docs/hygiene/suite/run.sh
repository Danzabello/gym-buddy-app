#!/usr/bin/env bash
# Reward and streak suite, one command. Everything runs on live inside transactions that abort, so nothing persists.
#   docs/hygiene/suite/run.sh                      # test what is live
#   docs/hygiene/suite/run.sh --with <migration>   # test a migration before it is pushed (inlined, rolled back)
# Needs `supabase login` and a linked project. Exit 0 only when every line is PASS.
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mig=/dev/null
if [[ "${1:-}" == --with ]]; then mig=$2; fi

fails=0
for f in grants_fresh economy_suite; do
  python3 -c '
import sys
s, m = open(sys.argv[1]).read(), open(sys.argv[2]).read()
assert s.count("-- @@MIGRATION@@\n") == 1, "marker"
sys.stdout.write(s.replace("-- @@MIGRATION@@\n", m))' "$dir/$f.sql" "$mig" > "$tmp/$f.sql"
  supabase db query --linked -f "$tmp/$f.sql" > "$tmp/$f.out" 2>&1 || true
  echo "== $f"
  # The block ends in RAISE 'SUITE_RESULTS…': the results come back as the error message.
  python3 -c '
import json, sys
raw = open(sys.argv[1]).read()
i = raw.find("{\"message\"")
msg = json.JSONDecoder().raw_decode(raw, i)[0]["message"] if i >= 0 else raw
if "SUITE_RESULTS" not in msg:
    print("FAIL no results (crash or connection):"); print(msg[-2000:]); sys.exit(0)
body = msg.split("SUITE_RESULTS\n", 1)[1].split("\nCONTEXT:", 1)[0]
print(body)' "$tmp/$f.out" | tee "$tmp/$f.res"
  p=$(grep -c '^PASS ' "$tmp/$f.res" || true); n=$(grep -c '^FAIL ' "$tmp/$f.res" || true)
  echo "-- $f: $p PASS, $n FAIL"
  fails=$((fails + n))
done
echo "== total FAIL: $fails"
[[ $fails -eq 0 ]]
