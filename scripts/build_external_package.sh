#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 TARGET_ATTR SOURCE_DIR OUT_DIR [extra pip packages...]" >&2
  exit 2
fi

TARGET_ATTR=$1
SOURCE_DIR=$2
OUT_DIR=$3
shift 3

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

mkdir -p "$OUT_DIR"

EXTRA_PIP_PACKAGES=("$@")
if [ "${#EXTRA_PIP_PACKAGES[@]}" -eq 0 ]; then
  EXTRA_PIP_PACKAGES=(setuptools_scm cppy auditwheel build)
fi
EXTRA_PIP_ARGS=$(printf '%q ' "${EXTRA_PIP_PACKAGES[@]}")

nix develop "$REPO_ROOT#${TARGET_ATTR}" -c bash -lc '
  set -euo pipefail

  pybin="${NIX_MANYLINUX_PYTHON:-python}"

  workdir=$(mktemp -d)
  trap "rm -rf \"$workdir\"" EXIT

  cp -a "'"$SOURCE_DIR"'" "$workdir/src"
  chmod -R u+w "$workdir/src"
  cd "$workdir/src"
  rm -rf .venv build dist
  find . -maxdepth 3 -type d \( -name "*.egg-info" -o -name ".pytest_cache" -o -name ".mypy_cache" \) -prune -exec rm -rf {} +

  "$pybin" -m venv .venv
  .venv/bin/python -m pip install -U pip setuptools wheel '"$EXTRA_PIP_ARGS"' > "'"$OUT_DIR"'/pip.log" 2>&1
  .venv/bin/python -m pip wheel --no-build-isolation --no-deps . -w "'"$OUT_DIR"'/dist" > "'"$OUT_DIR"'/build.log" 2>&1
  .venv/bin/python -m auditwheel show "'"$OUT_DIR"'/dist"/*.whl > "'"$OUT_DIR"'/auditwheel.txt" 2>&1
'

cat "$OUT_DIR/auditwheel.txt"
