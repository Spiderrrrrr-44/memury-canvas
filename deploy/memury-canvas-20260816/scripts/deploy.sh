#!/usr/bin/env bash

set -Eeuo pipefail

release_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_tag="${MEMURY_RELEASE_TAG:-2026-08-16-qgraph-apple-r3}"
canvas_root="${CANVAS_ROOT:-/opt/canvas-lms}"
base_image="${BASE_IMAGE:-ghcr.io/edulinq/lms-docker-canvas-base:latest}"
target_image="memury/canvas:${release_tag}"
compose_base="${canvas_root}/docker-compose.yml"
compose_overlay="${release_dir}/docker-compose.memury.yml"
backup_root="${canvas_root}/backups/${release_tag}"
compose=(docker-compose -f "${compose_base}" -f "${compose_overlay}")
original_state="$(docker inspect -f '{{.State.Status}}' canvas-lms 2>/dev/null || true)"
switched=false

recover_on_error() {
  exit_code=$?
  if [[ "${switched}" == "true" && -f "${backup_root}/previous-image.txt" ]]; then
    previous_image="$(cat "${backup_root}/previous-image.txt")"
    CANVAS_IMAGE="${previous_image}" "${compose[@]}" up -d --force-recreate canvas || true
  elif [[ "${original_state}" == "running" ]]; then
    docker start canvas-lms >/dev/null 2>&1 || true
  fi
  echo "Deployment stopped safely; the previous Canvas start was attempted." >&2
  exit "${exit_code}"
}

trap recover_on_error ERR

if [[ ! -f "${compose_base}" ]]; then
  echo "Canvas compose file not found: ${compose_base}" >&2
  exit 1
fi

available_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
swap_free_kb="$(awk '/SwapFree/ {print $2}' /proc/meminfo)"
if (( available_kb + swap_free_kb < 2500000 )); then
  echo "At least 2.5 GB combined available memory and swap is required before deployment." >&2
  free -h >&2
  exit 1
fi

mkdir -p "${backup_root}"
cp -a "${compose_base}" "${backup_root}/docker-compose.before.yml"
docker inspect canvas-lms > "${backup_root}/container.before.json" 2>/dev/null || true
docker image inspect "${base_image}" > "${backup_root}/base-image.json"
docker inspect -f '{{.Config.Image}}' canvas-lms > "${backup_root}/previous-image.txt" 2>/dev/null \
  || printf '%s\n' "${base_image}" > "${backup_root}/previous-image.txt"

if [[ "${original_state}" == "running" ]]; then
  docker stop --time 90 canvas-lms >/dev/null
fi

postgres_volume="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/14/main"}}{{.Name}}{{end}}{{end}}' canvas-lms 2>/dev/null || true)"
if [[ -n "${postgres_volume}" ]]; then
  postgres_path="$(docker volume inspect -f '{{.Mountpoint}}' "${postgres_volume}")"
  tar --numeric-owner -C "${postgres_path}" -czf "${backup_root}/postgres-before.tar.gz" .
fi

docker build \
  --build-arg "BASE_IMAGE=${base_image}" \
  --build-arg "MEMURY_RELEASE=${release_tag}" \
  -t "${target_image}" \
  "${release_dir}"

CANVAS_IMAGE="${target_image}" "${compose[@]}" run --rm --no-deps \
  --entrypoint /bin/bash canvas -lc '
    set -Eeuo pipefail
    service postgresql start
    trap "service postgresql stop >/dev/null 2>&1 || true" EXIT
    bundle exec rails db:migrate
    bundle exec rails runner "Account.default.enable_feature!(:memury)"
    LOGIN="${MEMURY_DEMO_LOGIN:-memury.student@example.test}" bundle exec rake memury:demo_seed
  '

CANVAS_IMAGE="${target_image}" "${compose[@]}" up -d --force-recreate canvas
switched=true

printf '%s\n' "${target_image}" > "${backup_root}/deployed-image.txt"
printf '%s\n' "${backup_root}" > "${canvas_root}/.memury-last-backup"

"${release_dir}/scripts/verify.sh"
trap - ERR

echo "Memury deployed with image ${target_image}."
echo "Backup and rollback metadata: ${backup_root}"
