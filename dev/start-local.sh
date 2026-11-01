#!/usr/bin/env bash
# Startet eine lokale Testdatenbank und den Testserver (conda-Umgebung "wichtel").
# Aufruf aus Git Bash:  bash dev/start-local.sh
set -e
cd "$(dirname "$0")"
E="$(conda info --base 2>/dev/null || echo "$HOME/anaconda3")/envs/wichtel"
export PATH="$E/Library/bin:$E:$PATH"
DATA="$PWD/pgdata"
if [ ! -d "$DATA" ]; then
  initdb -D "$DATA" -U postgres -A trust -E UTF8 >/dev/null
  pg_ctl -D "$DATA" -o "-p 54329" -l "$PWD/pg.log" -w start
  psql -p 54329 -U postgres -q -c "create role anon nologin; create role authenticated nologin;"
else
  pg_ctl -D "$DATA" -o "-p 54329" -l "$PWD/pg.log" -w start || true
fi
psql -p 54329 -U postgres -q -f ../supabase/schema.sql 2>/dev/null
[ -d node_modules ] || npm install --silent
echo "Öffne http://localhost:8787  (beenden mit Ctrl+C, Datenbank stoppen: pg_ctl -D dev/pgdata stop)"
node server.js ..
