#!/usr/bin/env bash
# Builds, starts `next start`, ages the build output past `expire`, requests "/".
# Usage: ./repro.sh [aged|control]   (default: both)
set -u
cd "$(dirname "$0")"
PORT=${PORT:-4600}
NEXT=${NEXT:-node_modules/.bin/next}

build() { rm -rf .next && "$NEXT" build >build.log 2>&1 || { cat build.log; exit 1; }; }

run_case() {
  local name=$1
  build
  if [ "$name" = aged ]; then
    # 30 minutes old: past expire (300 s) -> isStale === -1
    ts=$(date -v-30M +%Y%m%d%H%M.%S 2>/dev/null || date -d '30 minutes ago' +%Y%m%d%H%M.%S)
    find .next/server/app -type f \( -name '*.html' -o -name '*.rsc' -o -name '*.meta' \) -exec touch -t "$ts" {} +
  fi
  PORT=$PORT "$NEXT" start -p "$PORT" >"server-$name.log" 2>&1 &
  local pid=$!
  for _ in $(seq 100); do grep -q "Ready" "server-$name.log" 2>/dev/null && break; sleep 0.2; done
  echo "== $name: next $("$NEXT" --version 2>/dev/null)"
  for i in 1 2 3; do
    curl -s -o /dev/null -w "request $i: HTTP %{http_code} x-nextjs-cache=%header{x-nextjs-cache}\n" "http://127.0.0.1:$PORT/"
  done
  sleep 1
  kill $pid; wait $pid 2>/dev/null
  echo "-- server log (errors):"
  grep -E "uncached or runtime data|NEXT_STATIC_GEN_BAILOUT|Error|loader ran" "server-$name.log" | head -n 8
  echo
}

case "${1:-both}" in
  aged) run_case aged ;;
  control) run_case control ;;
  *) run_case control; run_case aged ;;
esac
