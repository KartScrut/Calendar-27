#!/usr/bin/env bash
# Applies stub auth + migrations + seed + tests to the database in $PGDATABASE
# (uses the standard PG* environment variables). For local/CI use only.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
run() { psql -v ON_ERROR_STOP=1 -q -f "$1" >/dev/null; }
run "$here/00_stub_auth.sql"
for f in "$root"/migrations/*.sql; do run "$f"; done
run "$root/seed/content_seed.sql"
run "$root/seed/sudoku_seed.sql"
psql -v ON_ERROR_STOP=1 -q -c "insert into public.sudoku_puzzles (id, difficulty, givens) values ('t1','medium','530070000600195000098000060800060003400803001700020006060000280000419005000080079'); insert into private.sudoku_solutions values ('t1','534678912672195348198342567859761423426853791713924856961537284287419635345286179');"
psql -v ON_ERROR_STOP=1 -f "$here/security_tests.sql"
