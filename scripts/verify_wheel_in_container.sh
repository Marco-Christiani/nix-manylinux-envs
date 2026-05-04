#!/usr/bin/env bash
set -euo pipefail

python_image=""
wheel=""
wheel_dir=""
cache_volume=""
gpu=0
quiet=0
deps=()
import_code="import sys; print(sys.version)"

usage() {
  cat <<'USAGE'
verify-wheel-in-container --python-image IMAGE (--wheel FILE | --wheel-dir DIR) [options]

Options:
  --dependency SPEC       Install an additional dependency before the wheel.
  --gpu                  Add Docker CDI GPU device mount: --device nvidia.com/gpu=all.
  --cache-volume NAME    Mount a Docker volume at /root/.cache/pip.
  --import-module NAME   Import a module after wheel installation.
  --import-code CODE     Run arbitrary Python code after wheel installation.
  --quiet                Print only START/PASS lines unless verification fails.
  --show-output          Disable --quiet if both flags are present.
  --help                 Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --python-image)
      python_image="$2"
      shift 2
      ;;
    --wheel)
      wheel="$2"
      shift 2
      ;;
    --wheel-dir)
      wheel_dir="$2"
      shift 2
      ;;
    --dependency)
      deps+=("$2")
      shift 2
      ;;
    --gpu)
      gpu=1
      shift
      ;;
    --quiet)
      quiet=1
      shift
      ;;
    --show-output)
      quiet=0
      shift
      ;;
    --cache-volume)
      cache_volume="$2"
      shift 2
      ;;
    --import-module)
      import_code="import $2; print($2)"
      shift 2
      ;;
    --import-code)
      import_code="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$python_image" ]; then
  echo "--python-image is required" >&2
  exit 2
fi

if [ -n "$wheel" ] && [ -n "$wheel_dir" ]; then
  echo "use only one of --wheel or --wheel-dir" >&2
  exit 2
fi

if [ -n "$wheel" ]; then
  wheel_dir="$(dirname "$wheel")"
  wheel_name="$(basename "$wheel")"
elif [ -n "$wheel_dir" ]; then
  wheel_name="$(find "$wheel_dir" -maxdepth 1 -type f -name '*.whl' -printf '%f\n' | sort | head -n 1)"
  if [ -z "$wheel_name" ]; then
    echo "no wheel found in $wheel_dir" >&2
    exit 1
  fi
else
  echo "one of --wheel or --wheel-dir is required" >&2
  exit 2
fi

docker_args=(--rm)
if [ "$gpu" = 1 ]; then
  docker_args+=(--device nvidia.com/gpu=all)
fi
docker_args+=(-v "$wheel_dir:/wheel:ro")
if [ -n "$cache_volume" ]; then
  docker_args+=(-v "$cache_volume:/root/.cache/pip")
fi

install_deps=()
if [ "${#deps[@]}" -gt 0 ]; then
  install_deps=(python -m pip install --root-user-action=ignore --disable-pip-version-check)
  if [ -n "$cache_volume" ]; then
    install_deps+=(--cache-dir /root/.cache/pip)
  else
    install_deps+=(--no-cache-dir)
  fi
  install_deps+=("${deps[@]}")
fi

install_wheel=(python -m pip install --root-user-action=ignore --disable-pip-version-check --no-deps)
if [ -n "$cache_volume" ]; then
  install_wheel+=(--cache-dir /root/.cache/pip)
else
  install_wheel+=(--no-cache-dir)
fi
install_wheel+=("/wheel/$wheel_name")

script='set -euo pipefail'
if [ "${#install_deps[@]}" -gt 0 ]; then
  script+="
$(printf '%q ' "${install_deps[@]}")"
fi
script+="
$(printf '%q ' "${install_wheel[@]}")
python - <<'PY'
$import_code
PY"

echo "START ${wheel_name} ${python_image}"
start_time=$(date +%s)
if [ "$quiet" = 1 ]; then
  log_file="$(mktemp)"
  if docker run "${docker_args[@]}" "$python_image" sh -lc "$script" >"$log_file" 2>&1; then
    end_time=$(date +%s)
    echo "PASS ${wheel_name} $((end_time - start_time))s"
    rm -f "$log_file"
  else
    status=$?
    echo "FAIL ${wheel_name}" >&2
    cat "$log_file" >&2
    rm -f "$log_file"
    exit "$status"
  fi
else
  docker run "${docker_args[@]}" "$python_image" sh -lc "$script"
  end_time=$(date +%s)
  echo "PASS ${wheel_name} $((end_time - start_time))s"
fi
