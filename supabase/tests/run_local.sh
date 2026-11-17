#!/usr/bin/env bash
# Starts a throwaway PostgreSQL cluster, runs the database tests, removes it.
# Requires PostgreSQL binaries (initdb, pg_ctl) on this machine.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$(dirname "$(command -v initdb || ls /usr/lib/postgresql/*/bin/initdb | tail -1)")"
dir="$(mktemp -d)"; port=54329
cleanup() { "$bin/pg_ctl" -D "$dir/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$dir"; }
trap cleanup EXIT
"$bin/initdb" -D "$dir/data" -U postgres -A trust >/dev/null
"$bin/pg_ctl" -D "$dir/data" -o "-p $port -k $dir -c listen_addresses=''" -l "$dir/log" -w start >/dev/null
PGHOST="$dir" PGPORT="$port" PGUSER=postgres PGDATABASE=postgres bash "$here/apply_all.sh"
