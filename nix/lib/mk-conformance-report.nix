{
  lib,
  pkgs,
  conformanceScript,
  python,
}: {
  name,
  target,
  libc,
  libstdcxx,
  libatomic,
  zlib,
  cc,
  runtimeLibs,
  extraTargetAttrs ? {},
}: let
  targetJson = pkgs.writeText "${name}-target.json" (
    builtins.toJSON (target // extraTargetAttrs)
  );
in
  pkgs.runCommand name
  {
    nativeBuildInputs = [
      python
      pkgs.binutils
    ];
  }
  ''
    mkdir -p "$out"
    python ${conformanceScript} \
      --target-json ${targetJson} \
      --runtime-lib-dir ${runtimeLibs}/lib \
      --cc ${cc} \
      --readelf ${pkgs.binutils}/bin/readelf \
      --libc ${libc} \
      --libstdcxx ${libstdcxx} \
      --libatomic ${libatomic} \
      --zlib ${zlib} \
      --output "$out/report.json"
  ''
