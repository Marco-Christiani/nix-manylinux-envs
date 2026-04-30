# manylinux-env

Nix-native manylinux builder experiments.

This repository contains:
- policy metadata derived from `auditwheel`
- reusable builder compositions for selected manylinux targets
- a small C++ Python extension used as an ABI stress probe
- conformance and official-image cross-check tooling

## Validated Targets

Current validated targets:
- `manylinux2014` / `manylinux_2_17_x86_64`
- `manylinux_2_28_x86_64`
- `manylinux_2_34_x86_64`

Validation means:
- runtime surface conformance passes for the target builder/reference
- the target-specific crafted probe suite passes
- the same probe suite matches the expected tag in the official manylinux image

## Repository Layout

- `data/manylinux-policy.json`: vendored policy data used by local checks
- `nix/policy-targets.nix`: normalized target definitions
- `nix/policy-specs.nix`: policy/spec helpers
- `nix/build-envs.nix`: builder/reference compositions
- `nix/probe-wheel.nix`: probe build and `auditwheel show` helpers
- `nix/targets.nix`: historical/pinned baseline experiments
- `probe/`: tiny Python/C++ extension used for ABI pressure testing
- `scripts/conformance_report.py`: surface conformance reporting
- `scripts/probe_suite_summary.py`: candidate probe-suite summary generation
- `scripts/official_manylinux_probe_matrix.sh`: official-image cross-check helper

## Flake Surfaces

Examples:
- `nix run .#show-policy-targets`
- `nix run .#show-conformance`
- `nix run .#show-targets`

Builder/reference shells:
- `nix develop .#manylinux2014_reference`
- `nix develop .#manylinux2014_candidate`
- `nix develop .#manylinux_2_28_candidate`
- `nix develop .#manylinux_2_34_candidate`

Reference/runtime outputs:
- `.#manylinux2014-reference-runtime-libs`
- `.#manylinux_2_28-runtime-libs`
- `.#manylinux_2_34-runtime-libs`

Check outputs:
- `.#checks.x86_64-linux.manylinux2014_reference-conformance`
- `.#checks.x86_64-linux.manylinux2014_candidate-probe-suite`
- `.#checks.x86_64-linux.manylinux_2_28_candidate-conformance`
- `.#checks.x86_64-linux.manylinux_2_28_candidate-probe-suite`
- `.#checks.x86_64-linux.manylinux_2_34_candidate-conformance`
- `.#checks.x86_64-linux.manylinux_2_34_candidate-probe-suite`

## Verification

### Local Conformance

```bash
cd experiments/manylinux-env

nix build .#checks.x86_64-linux.manylinux2014_reference-conformance --no-write-lock-file
cat ./result/report.json | jq

nix build .#checks.x86_64-linux.manylinux2014_candidate-probe-suite --no-write-lock-file
cat ./result

nix build .#checks.x86_64-linux.manylinux_2_28_candidate-conformance --no-write-lock-file
cat ./result/report.json | jq

nix build .#checks.x86_64-linux.manylinux_2_28_candidate-probe-suite --no-write-lock-file
cat ./result

nix build .#checks.x86_64-linux.manylinux_2_34_candidate-conformance --no-write-lock-file
cat ./result/report.json | jq

nix build .#checks.x86_64-linux.manylinux_2_34_candidate-probe-suite --no-write-lock-file
cat ./result
```

Expected headlines:
- `manylinux2014_reference`: `surfaceConformance.overallConforms = true`
- `manylinux2014_candidate`: `allPass = true`, expected tag `manylinux_2_17_x86_64`
- `manylinux_2_28_candidate`: `surfaceConformance.overallConforms = true`, probe suite `allPass = true`, expected tag `manylinux_2_28_x86_64`
- `manylinux_2_34_candidate`: `surfaceConformance.overallConforms = true`, probe suite `allPass = true`, expected tag `manylinux_2_34_x86_64`

### Official Image Cross-Checks

Argument order for `official_manylinux_probe_matrix.sh` is:
- `IMAGE OUT_DIR PYTAG SUITE`

Examples:

```bash
./scripts/official_manylinux_probe_matrix.sh \
  quay.io/pypa/manylinux2014_x86_64 \
  /tmp/manylinux2014-official-probes \
  manylinux2014 \
  legacy2014

./scripts/official_manylinux_probe_matrix.sh \
  quay.io/pypa/manylinux_2_28_x86_64 \
  /tmp/manylinux-2_28-official-probes \
  cp312-cp312 \
  modern228

./scripts/official_manylinux_probe_matrix.sh \
  quay.io/pypa/manylinux_2_34_x86_64 \
  /tmp/manylinux-2_34-official-probes \
  cp312-cp312 \
  modern234
```

The script prefers versioned `python3.x` binaries from `PATH` inside the image and falls back to internal manylinux layouts when needed.

## Probe Suites

The probe package is a single C++ extension with feature regions gated by macros.
Target-specific pressure comes from named suites rather than separate projects.

Current suites:
- `legacy2014`
  - `baseline`
  - `shared-state`
  - `random-device`
- `modern228`
  - `baseline`
  - `float-charconv`
  - `pmr`
  - `shared-state`
  - `random-device`
- `modern234`
  - same set as `modern228`

## Current Builder Shapes

### `manylinux2014_candidate`

Uses:
- extracted official `manylinux2014` rootfs
- patched official `devtoolset-10` frontend
- rootfs-aware linker-script shims for `libstdc++.so`, `libgcc_s.so`, and glibc script libraries

### `manylinux_2_28_candidate`

Uses:
- glibc `2.28` rebuilt from `nixos-20.03`
- GCC 14 frontend from current nixpkgs
- GCC 7.4 shared runtime from `nixos-19.03`
- narrow filesystem compatibility archive
- upstream-style `libstdc++.so` shared/nonshared/shared layering

### `manylinux_2_34_candidate`

Uses:
- mostly coherent `nixos-22.05` base
- GCC 14 frontend from current nixpkgs
- `zlib` pinned from `nixos-21.05` to preserve the target surface ceiling

## Scope

This repository is an experiment and a reference implementation for reusable manylinux builder derivations in Nix. It is not yet a published library interface.
