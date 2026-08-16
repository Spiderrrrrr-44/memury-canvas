#!/usr/bin/env bash

set -Eeuo pipefail

canvas_root="${CANVAS_ROOT:-/opt/canvas-lms}"
release_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_base="${canvas_root}/docker-compose.yml"
compose_overlay="${release_dir}/docker-compose.memury.yml"
backup_pointer="${canvas_root}/.memury-last-backup"

if [[ ! -f "${backup_pointer}" ]]; then
  echo "No Memury rollback metadata found." >&2
  exit 1
fi

backup_root="$(cat "${backup_pointer}")"
previous_image="$(cat "${backup_root}/previous-image.txt")"

if [[ -z "${previous_image}" ]]; then
  echo "Previous image is missing from ${backup_root}." >&2
  exit 1
fi

CANVAS_IMAGE="${previous_image}" docker-compose \
  -f "${compose_base}" \
  -f "${compose_overlay}" \
  up -d --force-recreate canvas

echo "Rolled Canvas back to ${previous_image}."
echo "Memury migrations are additive and were intentionally retained."
echo "Database archive, if required: ${backup_root}/postgres-before.tar.gz"
