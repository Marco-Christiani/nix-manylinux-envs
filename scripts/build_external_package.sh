#!/usr/bin/env bash
set -euo pipefail

REPAIR_MODE="${NIX_MANYLINUX_REPAIR_MODE:-none}"

usage() {
  cat >&2 <<'EOF'
usage: build_external_package.sh [--repair-mode none|auto|target] TARGET_ATTR SOURCE_DIR OUT_DIR [extra pip packages...]

repair modes:
  none    build raw wheel and run auditwheel show only
  auto    repair wheel with auditwheel's default platform selection
  target  repair wheel with --plat set from the target shell policy
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair-mode)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      REPAIR_MODE=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -lt 3 ]; then
  usage
  exit 2
fi

case "$REPAIR_MODE" in
  none|auto|target) ;;
  *)
    echo "invalid repair mode: $REPAIR_MODE" >&2
    usage
    exit 2
    ;;
esac

TARGET_ATTR=$1
SOURCE_DIR=$2
OUT_DIR=$3
shift 3

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

mkdir -p "$OUT_DIR"
SOURCE_DIR=$(realpath "$SOURCE_DIR")
OUT_DIR=$(realpath "$OUT_DIR")

EXTRA_PIP_PACKAGES=("$@")
if [ "${#EXTRA_PIP_PACKAGES[@]}" -eq 0 ]; then
  EXTRA_PIP_PACKAGES=(setuptools_scm cppy auditwheel build)
fi
EXTRA_PIP_ARGS=$(printf '%q ' "${EXTRA_PIP_PACKAGES[@]}")

nix develop "$REPO_ROOT#${TARGET_ATTR}" -c bash -lc '
  set -euo pipefail

  pybin="${NIX_MANYLINUX_PYTHON:-python}"
  repair_mode="'"$REPAIR_MODE"'"

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

  case "$repair_mode" in
    none)
      ;;
    auto)
      mkdir -p "'"$OUT_DIR"'/repaired"
      .venv/bin/python -m auditwheel repair -w "'"$OUT_DIR"'/repaired" "'"$OUT_DIR"'/dist"/*.whl > "'"$OUT_DIR"'/repair.log" 2>&1
      ;;
    target)
      mkdir -p "'"$OUT_DIR"'/repaired"
      .venv/bin/python -m auditwheel repair --plat "${AUDITWHEEL_POLICY}_x86_64" -w "'"$OUT_DIR"'/repaired" "'"$OUT_DIR"'/dist"/*.whl > "'"$OUT_DIR"'/repair.log" 2>&1
      ;;
  esac
'

cat "$OUT_DIR/auditwheel.txt"
