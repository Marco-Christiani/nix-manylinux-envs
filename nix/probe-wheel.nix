{
  compilerCc ? null,
  distName ? null,
  extraCxxFlags ? [],
  headerIncludeDirs ? null,
  lib,
  hostPkgs,
  pkgs,
  target,
  src,
}: let
  python =
    if builtins.hasAttr target.pythonAttr pkgs
    then builtins.getAttr target.pythonAttr pkgs
    else pkgs.python3;

  compilerPkgs = target.compilerPkgs or null;
  compilerStdenv =
    if compilerPkgs != null && target.compilerStdenvAttr != null && builtins.hasAttr target.compilerStdenvAttr compilerPkgs
    then builtins.getAttr target.compilerStdenvAttr compilerPkgs
    else if compilerPkgs != null
    then compilerPkgs.stdenv
    else pkgs.stdenv;
  compilerCc' =
    if compilerCc != null
    then compilerCc
    else compilerStdenv.cc;
  stdcxxPkgs = target.stdcxxPkgs or null;
  stdcxxLibDir =
    if stdcxxPkgs != null
    then "${lib.getLib stdcxxPkgs.stdenv.cc.cc}/lib"
    else if compilerCc != null
    then null
    else "${lib.getLib compilerCc'.cc}/lib";
  headerIncludeDirs' =
    if headerIncludeDirs != null
    then headerIncludeDirs
    else if compilerCc != null
    then []
    else
      lib.filter (path: path != null) [
        (
          if builtins.hasAttr "glibc" pkgs && builtins.hasAttr "dev" pkgs.glibc
          then "${pkgs.glibc.dev}/include"
          else null
        )
        (
          if builtins.hasAttr "libxcrypt" pkgs && builtins.hasAttr "dev" pkgs.libxcrypt
          then "${pkgs.libxcrypt.dev}/include"
          else null
        )
      ];
  headerIncludeFlags =
    lib.concatMapStringsSep " " (dir: "-I${lib.escapeShellArg dir}") headerIncludeDirs';
  extraCxxFlagsString = lib.concatStringsSep " " extraCxxFlags;

  pythonPkgs = python.pkgs or pkgs.python3Packages;
  extraHeaderInputs =
    lib.optional
    (builtins.hasAttr "libxcrypt" pkgs && builtins.hasAttr "dev" pkgs.libxcrypt)
    pkgs.libxcrypt.dev;

  probe = pkgs.stdenv.mkDerivation {
    pname = "manylinux-baseline-probe";
    version = "0.1.0";
    inherit src;
    outputs = ["out" "dist"];

    nativeBuildInputs =
      [
        compilerCc
        python
        pythonPkgs.pip
        pythonPkgs.setuptools
        pythonPkgs.wheel
        pkgs.zlib
      ]
      ++ extraHeaderInputs;

    buildPhase = ''
      runHook preBuild
      export SOURCE_DATE_EPOCH=315532800
      export CC=${compilerCc'}/bin/cc
      export CXX=${compilerCc'}/bin/c++
      ${lib.optionalString (distName != null) ''
        export BASELINE_PROBE_DIST_NAME=${lib.escapeShellArg distName}
      ''}
      export BASELINE_PROBE_EXTRA_COMPILE_ARGS=${lib.escapeShellArg extraCxxFlagsString}
      export CPPFLAGS="${headerIncludeFlags} ''${CPPFLAGS:-}"
      export CFLAGS="${headerIncludeFlags} ''${CFLAGS:-}"
      export CXXFLAGS="${headerIncludeFlags} ''${CXXFLAGS:-}"
      ${lib.optionalString (stdcxxLibDir != null) ''
        export LIBRARY_PATH=${stdcxxLibDir}''${LIBRARY_PATH:+:$LIBRARY_PATH}
        export LDFLAGS="-L${stdcxxLibDir} -Wl,-rpath-link,${stdcxxLibDir} ''${LDFLAGS:-}"
      ''}
      find . -exec touch --date='1980-01-02 00:00:00' {} +
      python -m pip wheel --no-build-isolation --no-deps . -w dist
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$dist" "$out"
      cp dist/*.whl "$dist/"
      cp dist/*.whl "$out/"
      runHook postInstall
    '';

    meta.description = "Tiny native wheel for measuring manylinux baseline floor";
  };

  wheelDirEscaped = lib.escapeShellArg probe.dist;

  showReport =
    pkgs.runCommand "${target.name}-auditwheel-show" {
      nativeBuildInputs = [
        hostPkgs.python3
        hostPkgs.python3Packages.auditwheel
        hostPkgs.binutils
        hostPkgs.patchelf
      ];
    } ''
      mkdir -p "$out"
      wheel_path=$(find ${wheelDirEscaped} -maxdepth 1 -type f -name '*.whl' | sort | head -n1)
      if [ -z "$wheel_path" ]; then
        echo "No wheel found in ${probe.dist}" >&2
        exit 1
      fi
      auditwheel show "$wheel_path" > "$out/report.txt"
      {
        echo "target=${target.name}"
        echo "nixpkgs_ref=${target.nixpkgsRef}"
        echo "expected_glibc=${toString target.expectedGlibc}"
        echo "compiler_ref=${toString (
        if target.compilerRef != null
        then target.compilerRef
        else target.nixpkgsRef
      )}"
        echo "stdcxx_ref=${toString (
        if target.stdcxxRef != null
        then target.stdcxxRef
        else if target.compilerRef != null
        then target.compilerRef
        else target.nixpkgsRef
      )}"
        echo "python=${python.pythonVersion or python.version or "unknown"}"
        echo "wheel=$(basename "$wheel_path")"
      } > "$out/meta.env"
    '';
in {
  wheel = probe.dist;
  inherit showReport python;
}
