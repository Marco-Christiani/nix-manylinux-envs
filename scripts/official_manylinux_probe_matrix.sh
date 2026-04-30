#!/usr/bin/env bash

set -euo pipefail

IMAGE="${1:-quay.io/pypa/manylinux_2_28_x86_64}"
ARG2="${2:-}"
ARG3="${3:-}"
ARG4="${4:-modern}"

if [[ -z "${ARG2}" ]]; then
  OUT_DIR="/tmp/manylinux-2_28-official-probes"
  PYTAG="cp312-cp312"
  SUITE="${ARG4}"
elif [[ "${ARG2}" == /* ]]; then
  OUT_DIR="${ARG2}"
  PYTAG="${ARG3:-cp312-cp312}"
  SUITE="${ARG4}"
else
  PYTAG="${ARG2}"
  OUT_DIR="${ARG3:-/tmp/manylinux-2_28-official-probes}"
  SUITE="${ARG4}"
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
PROBE_DIR="${ROOT_DIR}/probe"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

docker run --rm \
  -v "${PROBE_DIR}:/src:ro" \
  -v "${OUT_DIR}:/out" \
  -e SUITE="${SUITE}" \
  -e PYTAG="${PYTAG}" \
  "${IMAGE}" \
  bash -lc "
    set -euo pipefail
    pybin=
    if [[ \"${PYTAG}\" =~ ^cp([0-9])([0-9]{2})-cp[0-9]+$ ]]; then
      minor=\${BASH_REMATCH[2]}
      pycmd=python3.\${minor#0}
      if command -v \"\$pycmd\" >/dev/null 2>&1; then
        pybin=\$(command -v \"\$pycmd\")
      fi
    fi
    if [[ -z \"\$pybin\" ]] && command -v python3.12 >/dev/null 2>&1; then
      pybin=\$(command -v python3.12)
    fi
    if [[ -z \"\$pybin\" ]] && command -v python3 >/dev/null 2>&1; then
      pybin=\$(command -v python3)
    fi
    if [[ -z \"\$pybin\" ]] && command -v python >/dev/null 2>&1; then
      pybin=\$(command -v python)
    fi
    if [[ -z \"\$pybin\" || ! -x \"\$pybin\" ]]; then
      pybin=\$( \
        { find /opt/python -maxdepth 3 -path '*/bin/python' 2>/dev/null || true; \
          find /opt/_internal -maxdepth 3 -path '/opt/_internal/cpython-*/bin/python' 2>/dev/null || true; } \
        | grep -v -- '-nogil/' \
        | sort -V \
        | tail -n 1 \
      )
    fi
    if [[ -z \"\${pybin:-}\" || ! -x \"\$pybin\" ]]; then
      echo \"No usable Python found under /opt/python\" >&2
      exit 2
    fi
    work=/tmp/probe-work
    mkdir -p /out

    \"\$pybin\" -m pip install -U setuptools wheel >/tmp/bootstrap.log

    case \"${SUITE}\" in
      legacy2014)
        variants=(
          baseline:
          shared-state:-DBASELINE_PROBE_ENABLE_SHARED_STATE=1,-DBASELINE_PROBE_ENABLE_VARIANT=1
          random-device:-DBASELINE_PROBE_ENABLE_RANDOM_DEVICE=1
        )
        ;;
      modern|modern228|modern234)
        variants=(
          baseline:
          float-charconv:-DBASELINE_PROBE_ENABLE_FLOAT_CHARCONV=1
          pmr:-DBASELINE_PROBE_ENABLE_PMR=1
          shared-state:-DBASELINE_PROBE_ENABLE_SHARED_STATE=1,-DBASELINE_PROBE_ENABLE_VARIANT=1
          random-device:-DBASELINE_PROBE_ENABLE_RANDOM_DEVICE=1
        )
        ;;
      *)
        echo \"Unknown suite: ${SUITE}\" >&2
        exit 2
        ;;
    esac

    for item in \"\${variants[@]}\"; do
      name=\${item%%:*}
      flags=\${item#*:}
      rm -rf \"\$work\"
      cp -a /src \"\$work\"
      cd \"\$work\"

      export BASELINE_PROBE_DIST_NAME=\"manylinux-baseline-probe-\${name}\"
      if [[ -n \"\$flags\" ]]; then
        export BASELINE_PROBE_EXTRA_COMPILE_ARGS=\$(printf '%s' \"\$flags\" | tr ',' ' ')
      else
        export BASELINE_PROBE_EXTRA_COMPILE_ARGS=
      fi

      \"\$pybin\" -m build --wheel --no-isolation
      wheel=\$(find dist -maxdepth 1 -name '*.whl' | head -1)
      cp \"\$wheel\" \"/out/\${name}.whl\"
      auditwheel show \"\$wheel\" > \"/out/\${name}.report.txt\"
    done
  "

  python - <<'PY' "${OUT_DIR}" "${SUITE}"
import json
import pathlib
import re
import sys

out_dir = pathlib.Path(sys.argv[1])
suite = sys.argv[2]
tag_re = re.compile(r'This constrains the platform tag to "([^"]+)"')

summary = []
for report in sorted(out_dir.glob("*.report.txt")):
    text = report.read_text(encoding="utf-8")
    match = tag_re.search(text)
    summary.append(
        {
            "probe": report.stem.removesuffix(".report"),
            "tag": match.group(1) if match else None,
            "wheel": f"{report.stem.removesuffix('.report')}.whl",
        }
    )

(out_dir / "summary.json").write_text(json.dumps({
    "suite": suite,
    "results": summary,
}, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"suite": suite, "results": summary}, indent=2))
PY
