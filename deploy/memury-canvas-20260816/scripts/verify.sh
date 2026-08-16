#!/usr/bin/env bash

set -Eeuo pipefail

canvas_root="${CANVAS_ROOT:-/opt/canvas-lms}"
deadline=$((SECONDS + 720))

while (( SECONDS < deadline )); do
  state="$(docker inspect -f '{{.State.Status}}' canvas-lms 2>/dev/null || true)"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 http://127.0.0.1:30088/login 2>/dev/null || true)"
  if [[ "${state}" == "running" && "${code}" =~ ^(200|302)$ ]]; then
    break
  fi
  sleep 12
done

state="$(docker inspect -f '{{.State.Status}}' canvas-lms 2>/dev/null || true)"
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 http://127.0.0.1:30088/login 2>/dev/null || true)"
if [[ "${state}" != "running" || ! "${code}" =~ ^(200|302)$ ]]; then
  docker logs --tail=180 canvas-lms >&2 || true
  echo "Canvas health check failed: state=${state} http=${code}" >&2
  exit 1
fi

docker exec canvas-lms bash -lc '
  cd /work/canvas-source
  bundle exec rails runner "
    abort(%q{Memury feature is disabled}) unless Account.default.feature_enabled?(:memury)
    abort(%q{Memury profile table missing}) unless ActiveRecord::Base.connection.data_source_exists?(%q{memury_learner_profiles})
    abort(%q{Memury graph table missing}) unless ActiveRecord::Base.connection.data_source_exists?(%q{memury_learning_sessions})
    puts %q{Memury database and feature flag verified.}
  "
'

curl -kfsSI --max-time 20 -H 'Host: canvas.memury.net' https://127.0.0.1/login >/dev/null
echo "Canvas and Memury deployment checks passed."
