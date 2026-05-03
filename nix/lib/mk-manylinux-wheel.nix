{
  lib,
  pkgs,
  targetShell,
  pname,
  version,
  src,
  python ? pkgs.python312,
  nativeBuildInputs ? [],
  buildInputs ? [],
  propagatedBuildInputs ? [],
  repairMode ? "target",
  auditwheelExclude ? [],
  auditwheelFlags ? [],
  strip ? true,
  removeGeneratedSources ? true,
  generatedSourcePredicates ? [
    ''
      "/_cython/" in path and path.endswith((".c", ".cpp"))
    ''
  ],
  preBuild ? "",
  buildWheelCommand ? ''
    "$NIX_MANYLINUX_PYTHON" -m pip wheel --no-build-isolation --no-deps . -w dist
  '',
  postBuild ? "",
  preInstall ? "",
  postInstall ? "",
  passthru ? {},
  meta ? {},
  ...
} @ args: let
  extraArgs = builtins.removeAttrs args [
    "lib"
    "pkgs"
    "targetShell"
    "pname"
    "version"
    "src"
    "python"
    "nativeBuildInputs"
    "buildInputs"
    "propagatedBuildInputs"
    "repairMode"
    "auditwheelExclude"
    "auditwheelFlags"
    "strip"
    "removeGeneratedSources"
    "generatedSourcePredicates"
    "preBuild"
    "buildWheelCommand"
    "postBuild"
    "preInstall"
    "postInstall"
    "passthru"
    "meta"
  ];
  repairFlagString =
    lib.concatStringsSep " "
    (
      lib.optional strip "--strip"
      ++ map (soname: "--exclude ${lib.escapeShellArg soname}") auditwheelExclude
      ++ auditwheelFlags
    );
  generatedSourcePredicate =
    if generatedSourcePredicates == []
    then "False"
    else lib.concatStringsSep " or " (map (predicate: "(${predicate})") generatedSourcePredicates);
in
  pkgs.stdenvNoCC.mkDerivation (
    extraArgs
    // {
      inherit pname version src buildInputs propagatedBuildInputs passthru;

      inputsFrom = [targetShell] ++ (extraArgs.inputsFrom or []);

      nativeBuildInputs =
        [
          pkgs.binutils
          python.pkgs.auditwheel
          python.pkgs.build
          python.pkgs.pip
          python.pkgs.setuptools
          python.pkgs.wheel
        ]
        ++ nativeBuildInputs;

      inherit
        (targetShell)
        AUDITWHEEL_POLICY
        NIX_MANYLINUX_GLIBC_BIN
        NIX_MANYLINUX_GLIBC_DEV
        NIX_MANYLINUX_RUNTIME_LIBS
        NIX_MANYLINUX_TARGET
        ;

      NIX_CC = targetShell.NIX_CC or "";
      NIX_MANYLINUX_PYTHON = "${python}/bin/python";
      NIX_MANYLINUX_STDCXX = targetShell.NIX_MANYLINUX_STDCXX or "";
      NIX_MANYLINUX_STDCXX_NONSHARED = targetShell.NIX_MANYLINUX_STDCXX_NONSHARED or "";

      dontConfigure = extraArgs.dontConfigure or true;

      buildPhase = ''
        runHook preBuild

        if [ -n "''${NIX_CC:-}" ]; then
          export CC="$NIX_CC/bin/cc"
          export CXX="$NIX_CC/bin/c++"
        fi
        unset NIX_CFLAGS_COMPILE
        unset NIX_LDFLAGS
        export NIX_DONT_SET_RPATH="''${NIX_DONT_SET_RPATH:-1}"

        ${preBuild}

        mkdir -p dist
        ${buildWheelCommand}

        ${lib.optionalString removeGeneratedSources ''
          "$NIX_MANYLINUX_PYTHON" <<'PY'
          import csv
          import io
          import os
          import zipfile
          from pathlib import Path

          def drop(path: str) -> bool:
              return ${generatedSourcePredicate}

          for wheel in Path("dist").glob("*.whl"):
              tmp = wheel.with_suffix(".whl.tmp")
              with zipfile.ZipFile(wheel, "r") as src, zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as dst:
                  record_name = next(name for name in src.namelist() if name.endswith(".dist-info/RECORD"))
                  record_rows = []
                  for row in csv.reader(io.StringIO(src.read(record_name).decode())):
                      if row and not drop(row[0]):
                          record_rows.append(row)

                  for info in src.infolist():
                      if drop(info.filename) or info.filename == record_name:
                          continue
                      dst.writestr(info, src.read(info.filename))

                  rendered = io.StringIO()
                  csv.writer(rendered, lineterminator="\n").writerows(record_rows)
                  record_info = zipfile.ZipInfo(record_name)
                  record_info.external_attr = 0o644 << 16
                  dst.writestr(record_info, rendered.getvalue())
              os.replace(tmp, wheel)
          PY
        ''}

        "$NIX_MANYLINUX_PYTHON" -m auditwheel show dist/*.whl > auditwheel.txt

        ${postBuild}

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        ${preInstall}

        mkdir -p "$out/dist" "$out/logs"
        cp auditwheel.txt "$out/logs/"
        cp dist/*.whl "$out/dist/"

        case "${repairMode}" in
          none)
            ;;
          target)
            mkdir -p "$out/repaired"
            "$NIX_MANYLINUX_PYTHON" -m auditwheel repair \
              ${repairFlagString} \
              --plat "$AUDITWHEEL_POLICY"_x86_64 \
              -w "$out/repaired" \
              dist/*.whl
            ;;
          auto)
            mkdir -p "$out/repaired"
            "$NIX_MANYLINUX_PYTHON" -m auditwheel repair \
              ${repairFlagString} \
              -w "$out/repaired" \
              dist/*.whl
            ;;
          *)
            echo "unsupported repairMode: ${repairMode}" >&2
            exit 2
            ;;
        esac

        ${postInstall}

        runHook postInstall
      '';

      meta =
        {
          description = "Python wheel built in a Nix manylinux target environment";
          platforms = ["x86_64-linux"];
        }
        // meta;
    }
  )
