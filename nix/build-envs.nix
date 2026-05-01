{
  lib,
  pkgs,
  inputs,
  policyTargets,
  system,
}: let
  conformanceScript = ../scripts/conformance_report.py;
  python = pkgs.python312;
  pythonPkgs = pkgs.python312Packages or python.pkgs;
  pkgs19_03 = import inputs.nixpkgs-19_03.outPath {inherit system;};
  pkgs19_09 = import inputs.nixpkgs-19_09.outPath {inherit system;};
  pkgs20_03 = import inputs.nixpkgs-20_03.outPath {inherit system;};
  pkgs21_05 = import inputs.nixpkgs-21_05.outPath {inherit system;};
  pkgs22_05 = import inputs.nixpkgs-22_05.outPath {inherit system;};
  pkgs24_05 = import inputs.nixpkgs-24_05.outPath {inherit system;};
  extractDockerRootfs = import ./lib/extract-docker-rootfs.nix {inherit pkgs;};
  runtimeBundleLib = import ./lib/mk-runtime-bundle.nix {inherit lib pkgs;};
  inherit (runtimeBundleLib) createLibraryBundle;
  inherit (runtimeBundleLib) createLibraryBundleFromPaths;
  optionalPythonBuild = pythonPkgs:
    lib.optional (builtins.hasAttr "build" pythonPkgs) pythonPkgs.build;
  optionalPythonPackage = pythonPkgs: name:
    lib.optional (builtins.hasAttr name pythonPkgs) (builtins.getAttr name pythonPkgs);
  mkConformanceReport = import ./lib/mk-conformance-report.nix {
    inherit lib pkgs conformanceScript python;
  };
  mkBuildShell = import ./lib/mk-build-shell.nix {inherit pkgs;};
  manylinux2014Image = pkgs.dockerTools.pullImage {
    imageName = "quay.io/pypa/manylinux2014_x86_64";
    imageDigest = "sha256:79abced054d8add673e4885d9598e1adc56260989b83aec0922e4cd6eb3ef066";
    hash = "sha256-FAEfyVrU2BIOODfg0NtbHXYGoxqL/H7rwIgT36hmhcA=";
    finalImageName = "quay.io/pypa/manylinux2014_x86_64";
    finalImageTag = "latest";
  };

  manylinux2014Rootfs = extractDockerRootfs {
    name = "manylinux2014-rootfs";
    imageTar = manylinux2014Image;
  };

  getLibOutputs = lib.mapAttrs (_: drv: lib.getLib drv);
  getXorg = attrs: name:
    if builtins.hasAttr "xorg" attrs && builtins.hasAttr name attrs.xorg
    then builtins.getAttr name attrs.xorg
    else throw "Missing xorg.${name} in package set";

  glibc228 = pkgs20_03.glibc.overrideAttrs (prev: {
    version = "2.28";
    pname = prev.pname or "glibc";
    name = "glibc-2.28";
    src = pkgs20_03.fetchurl {
      url = "mirror://gnu/glibc/glibc-2.28.tar.xz";
      sha256 = "10iha5ynvdj5m62vgpgqbq4cwvc2yhyl2w9yyyjgfxmdmx8h145i";
    };
    patches =
      builtins.filter
      (patch: builtins.baseNameOf (toString patch) != "2.30-cve-2020-1752.patch")
      (prev.patches or []);
    passthru = (prev.passthru or {}) // {version = "2.28";};
  });

  mkFilesystemCompatShim = {
    frontendCc,
    runtimeCc,
    runtimeLib,
    useFullFrontendArchive ? false,
  }:
    pkgs.runCommand "manylinux-fscompat-shim" {nativeBuildInputs = [pkgs.binutils pkgs.gcc];} ''
      mkdir -p "$out/lib" work
      cd work
      frontend_archive=${frontendCc}/lib/libstdc++.a
      if [ "${
        if useFullFrontendArchive
        then "1"
        else "0"
      }" = 1 ]; then
        ln -s "$frontend_archive" "$out/lib/libstdc++_frontend.a"
      else
        ar x "$frontend_archive" fs_dir.o fs_ops.o fs_path.o functexcept.o
      fi
      runtime_archive=$("${runtimeCc}/bin/g++" -print-file-name=libstdc++.a)
      mkdir runtime-eh
      (
        cd runtime-eh
        for obj in $(ar t "$runtime_archive" | grep '^eh_.*\.o$'); do
          ar x "$runtime_archive" "$obj"
        done
      )
      cat > compat.c <<'SRC'
      char __libc_single_threaded = 0;
      SRC
      ${pkgs.gcc}/bin/cc -c compat.c -o compat.o
      if [ "${
        if useFullFrontendArchive
        then "1"
        else "0"
      }" = 1 ]; then
        ar rcs "$out/lib/libstdc++_nonshared.a" runtime-eh/*.o compat.o
      else
        ar rcs "$out/lib/libstdc++_nonshared.a" fs_dir.o fs_ops.o fs_path.o functexcept.o runtime-eh/*.o compat.o
      fi
      cat > "$out/lib/libstdc++.so" <<'SCRIPT'
      /* GNU ld script */
      OUTPUT_FORMAT(elf64-x86-64)
      INPUT ( ${runtimeLib}/lib/libstdc++.so.6 ${
        if useFullFrontendArchive
        then "libstdc++_frontend.a "
        else ""
      }libstdc++_nonshared.a ${runtimeLib}/lib/libstdc++.so.6 )
      SCRIPT
    '';

  candidate228 = let
    target = policyTargets.manylinux_2_28;
    runtimeCompiler = pkgs19_03.stdenv.cc.cc;
    runtimeCompilerLib = lib.getLib runtimeCompiler;
    frontendCc = pkgs.gcc14.cc;
    frontendLib = lib.getLib frontendCc;
    filesystemCompatShim = mkFilesystemCompatShim {
      inherit frontendCc;
      runtimeCc = runtimeCompiler;
      runtimeLib = runtimeCompilerLib;
      useFullFrontendArchive = true;
    };
    wrappedBintools = pkgs.wrapBintoolsWith {
      inherit (pkgs.stdenv.cc.bintools) bintools;
      libc = glibc228;
    };
    compilerCc = pkgs.wrapCCWith {
      cc = frontendCc;
      bintools = wrappedBintools;
      libc = glibc228;
      extraBuildCommands = ''
        sed -i 's|-L${frontendLib}/lib||g' "$out/nix-support/cc-ldflags"
        sed -i 's|-B${frontendLib}/lib||g' "$out/nix-support/cc-cflags"
        echo "-L${filesystemCompatShim}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-rpath-link" >> "$out/nix-support/cc-ldflags"
        echo "${filesystemCompatShim}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-B${filesystemCompatShim}/lib" >> "$out/nix-support/cc-cflags"
        echo "-L${runtimeCompilerLib}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-rpath-link" >> "$out/nix-support/cc-ldflags"
        echo "${runtimeCompilerLib}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-B${runtimeCompilerLib}/lib" >> "$out/nix-support/cc-cflags"
      '';
    };
    runtimeProviders = getLibOutputs {
      "libatomic.so.1" = runtimeCompiler;
      "libgcc_s.so.1" = runtimeCompiler;
      "libstdc++.so.6" = runtimeCompiler;
      "libm.so.6" = glibc228;
      "libmvec.so.1" = glibc228;
      "libanl.so.1" = glibc228;
      "libdl.so.2" = glibc228;
      "librt.so.1" = glibc228;
      "libc.so.6" = glibc228;
      "libnsl.so.1" = glibc228;
      "libutil.so.1" = glibc228;
      "libpthread.so.0" = glibc228;
      "libresolv.so.2" = glibc228;
      "libcrypt.so.1" = glibc228;
      "libX11.so.6" = getXorg pkgs20_03 "libX11";
      "libXext.so.6" = getXorg pkgs20_03 "libXext";
      "libXrender.so.1" = getXorg pkgs20_03 "libXrender";
      "libICE.so.6" = getXorg pkgs20_03 "libICE";
      "libSM.so.6" = getXorg pkgs20_03 "libSM";
      "libGL.so.1" = pkgs20_03.libGL;
      "libgobject-2.0.so.0" = pkgs20_03.glib;
      "libgthread-2.0.so.0" = pkgs20_03.glib;
      "libglib-2.0.so.0" = pkgs20_03.glib;
      "libz.so.1" = pkgs20_03.zlib;
      "libexpat.so.1" = pkgs20_03.expat;
      "libpanelw.so.5" = pkgs20_03.ncurses5;
      "libncursesw.so.5" = pkgs20_03.ncurses5;
    };
    runtimeLibs = createLibraryBundle "manylinux_2_28-candidate-runtime-libs" runtimeProviders target.libWhitelist;
    candidateTarget =
      target
      // {
        name = "manylinux_2_28_candidate";
        expectedGlibc = "2.28";
        actualLibcVersion = "2.28";
        compilerRef = "nixos-unstable gcc14 frontend with targeted filesystem compatibility shim";
        stdcxxRef = "nixos-19.03 gcc-7.4.0 shared runtime";
        stdcxxPkgs = pkgs19_09;
        notes =
          target.notes
          + " Candidate hybrid: glibc 2.28 rebuilt from nixos-20.03, gcc14 frontend from nixos-unstable, gcc-7.4.0 shared runtime from nixos-19.03, and a narrow filesystem compatibility archive to keep C++17 path symbols within the manylinux_2_28 ceiling.";
      };
    conformanceReport = mkConformanceReport {
      name = "manylinux_2_28-candidate-conformance-report";
      target = builtins.removeAttrs candidateTarget ["stdcxxPkgs"];
      inherit runtimeLibs;
      cc = "${compilerCc}/bin/cc";
      libc = "${lib.getLib glibc228}/lib/libc.so.6";
      libstdcxx = "${runtimeCompilerLib}/lib/libstdc++.so.6";
      libatomic = "${runtimeCompilerLib}/lib/libatomic.so.1";
      zlib = "${lib.getLib pkgs20_03.zlib}/lib/libz.so.1";
    };
    shell = mkBuildShell {
      name = "manylinux_2_28-candidate-shell";
      packages =
        [
          compilerCc
          pkgs20_03.binutils
          pkgs20_03.patchelf
          pkgs20_03.pkg-config
          pkgs20_03.gnumake
          pkgs.cmake
          python
          pythonPkgs.pip
        ]
        ++ optionalPythonBuild pythonPkgs
        ++ [
          pythonPkgs.setuptools
          pythonPkgs.wheel
          runtimeLibs
        ]
        ++ optionalPythonPackage pythonPkgs "auditwheel"
        ++ optionalPythonPackage pythonPkgs "build";
      env = {
        AUDITWHEEL_POLICY = target.policy;
        NIX_MANYLINUX_TARGET = "manylinux_2_28_candidate";
        NIX_MANYLINUX_PYTHON = "${python}/bin/python";
        NIX_MANYLINUX_RUNTIME_LIBS = "${runtimeLibs}/lib";
        NIX_MANYLINUX_GLIBC_DEV = "${glibc228.dev}/include";
        NIX_MANYLINUX_GLIBC_BIN = "${glibc228.bin}";
        NIX_MANYLINUX_STDCXX = "${runtimeCompilerLib}/lib";
        NIX_MANYLINUX_STDCXX_NONSHARED = "${filesystemCompatShim}/lib";
        NIX_CC = compilerCc;
      };
      shellHook = ''
        export CC="${compilerCc}/bin/cc"
        export CXX="${compilerCc}/bin/c++"
      '';
    };
  in {
    inherit runtimeLibs conformanceReport shell compilerCc glibc228;
    target = candidateTarget;
  };

  candidate234 = let
    target = policyTargets.manylinux_2_34;
    runtimeCompiler = pkgs22_05.stdenv.cc.cc;
    runtimeCompilerLib = lib.getLib runtimeCompiler;
    frontendCc = pkgs.gcc14.cc;
    frontendLib = lib.getLib frontendCc;
    filesystemCompatShim = mkFilesystemCompatShim {
      inherit frontendCc;
      runtimeCc = runtimeCompiler;
      runtimeLib = runtimeCompilerLib;
    };
    wrappedBintools = pkgs.wrapBintoolsWith {
      inherit (pkgs.stdenv.cc.bintools) bintools;
      libc = pkgs22_05.glibc;
    };
    compilerCc = pkgs.wrapCCWith {
      cc = frontendCc;
      bintools = wrappedBintools;
      libc = pkgs22_05.glibc;
      extraBuildCommands = ''
        sed -i 's|-L${frontendLib}/lib||g' "$out/nix-support/cc-ldflags"
        sed -i 's|-B${frontendLib}/lib||g' "$out/nix-support/cc-cflags"
        echo "-L${filesystemCompatShim}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-rpath-link" >> "$out/nix-support/cc-ldflags"
        echo "${filesystemCompatShim}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-B${filesystemCompatShim}/lib" >> "$out/nix-support/cc-cflags"
        echo "-L${runtimeCompilerLib}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-rpath-link" >> "$out/nix-support/cc-ldflags"
        echo "${runtimeCompilerLib}/lib" >> "$out/nix-support/cc-ldflags"
        echo "-B${runtimeCompilerLib}/lib" >> "$out/nix-support/cc-cflags"
      '';
    };
    runtimeProviders = getLibOutputs {
      "libatomic.so.1" = runtimeCompiler;
      "libgcc_s.so.1" = runtimeCompiler;
      "libstdc++.so.6" = runtimeCompiler;
      "libm.so.6" = pkgs22_05.glibc;
      "libmvec.so.1" = pkgs22_05.glibc;
      "libanl.so.1" = pkgs22_05.glibc;
      "libdl.so.2" = pkgs22_05.glibc;
      "librt.so.1" = pkgs22_05.glibc;
      "libc.so.6" = pkgs22_05.glibc;
      "libnsl.so.1" = pkgs22_05.glibc;
      "libutil.so.1" = pkgs22_05.glibc;
      "libpthread.so.0" = pkgs22_05.glibc;
      "libresolv.so.2" = pkgs22_05.glibc;
      "libcrypt.so.1" = pkgs22_05.libxcrypt-legacy;
      "libX11.so.6" = getXorg pkgs22_05 "libX11";
      "libXext.so.6" = getXorg pkgs22_05 "libXext";
      "libXrender.so.1" = getXorg pkgs22_05 "libXrender";
      "libICE.so.6" = getXorg pkgs22_05 "libICE";
      "libSM.so.6" = getXorg pkgs22_05 "libSM";
      "libGL.so.1" = pkgs22_05.libGL;
      "libgobject-2.0.so.0" = pkgs22_05.glib;
      "libgthread-2.0.so.0" = pkgs22_05.glib;
      "libglib-2.0.so.0" = pkgs22_05.glib;
      "libz.so.1" = pkgs21_05.zlib;
      "libexpat.so.1" = pkgs22_05.expat;
    };
    runtimeLibs = createLibraryBundle "manylinux_2_34-candidate-runtime-libs" runtimeProviders target.libWhitelist;
    candidateTarget =
      target
      // {
        name = "manylinux_2_34_candidate";
        expectedGlibc = "2.34";
        actualLibcVersion = "2.34";
        compilerRef = "nixos-unstable gcc14 frontend with targeted filesystem compatibility shim";
        stdcxxRef = "nixos-22.05 gcc-11.3.0 shared runtime";
        stdcxxPkgs = pkgs22_05;
        notes =
          target.notes
          + " Candidate mostly-coherent baseline: glibc 2.34 and gcc-11.3.0 shared runtime from nixos-22.05, gcc14 frontend from nixos-unstable, zlib 1.2.9 surface from nixos-21.05, and the upstream-style linker layering used in the 2.28 candidate.";
      };
    conformanceReport = mkConformanceReport {
      name = "manylinux_2_34-candidate-conformance-report";
      target = builtins.removeAttrs candidateTarget ["stdcxxPkgs"];
      inherit runtimeLibs;
      cc = "${compilerCc}/bin/cc";
      libc = "${lib.getLib pkgs22_05.glibc}/lib/libc.so.6";
      libstdcxx = "${runtimeCompilerLib}/lib/libstdc++.so.6";
      libatomic = "${runtimeCompilerLib}/lib/libatomic.so.1";
      zlib = "${lib.getLib pkgs21_05.zlib}/lib/libz.so.1";
    };
    shell = mkBuildShell {
      name = "manylinux_2_34-candidate-shell";
      packages =
        [
          compilerCc
          pkgs22_05.binutils
          pkgs22_05.patchelf
          pkgs22_05.pkg-config
          pkgs22_05.gnumake
          pkgs.cmake
          python
          pythonPkgs.pip
        ]
        ++ optionalPythonBuild pythonPkgs
        ++ [
          pythonPkgs.setuptools
          pythonPkgs.wheel
          runtimeLibs
        ]
        ++ optionalPythonPackage pythonPkgs "auditwheel"
        ++ optionalPythonPackage pythonPkgs "build";
      env = {
        AUDITWHEEL_POLICY = target.policy;
        NIX_MANYLINUX_TARGET = "manylinux_2_34_candidate";
        NIX_MANYLINUX_PYTHON = "${python}/bin/python";
        NIX_MANYLINUX_RUNTIME_LIBS = "${runtimeLibs}/lib";
        NIX_MANYLINUX_GLIBC_DEV = "${pkgs22_05.glibc.dev}/include";
        NIX_MANYLINUX_GLIBC_BIN = "${pkgs22_05.glibc.bin}";
        NIX_MANYLINUX_STDCXX = "${runtimeCompilerLib}/lib";
        NIX_MANYLINUX_STDCXX_NONSHARED = "${filesystemCompatShim}/lib";
        NIX_CC = compilerCc;
      };
      shellHook = ''
        export CC="${compilerCc}/bin/cc"
        export CXX="${compilerCc}/bin/c++"
      '';
    };
  in {
    inherit runtimeLibs conformanceReport shell compilerCc;
    target = candidateTarget;
  };

  candidate239 = let
    target = policyTargets.manylinux_2_39;
    runtimeCompiler = pkgs24_05.gcc14.cc;
    runtimeCompilerLib = lib.getLib runtimeCompiler;
    wrappedBintools = pkgs.wrapBintoolsWith {
      inherit (pkgs.stdenv.cc.bintools) bintools;
      libc = pkgs24_05.glibc;
    };
    compilerCc = pkgs.wrapCCWith {
      cc = runtimeCompiler;
      bintools = wrappedBintools;
      libc = pkgs24_05.glibc;
    };
    runtimeProviders = getLibOutputs {
      "libatomic.so.1" = runtimeCompiler;
      "libgcc_s.so.1" = runtimeCompiler;
      "libstdc++.so.6" = runtimeCompiler;
      "libm.so.6" = pkgs24_05.glibc;
      "libmvec.so.1" = pkgs24_05.glibc;
      "libanl.so.1" = pkgs24_05.glibc;
      "libdl.so.2" = pkgs24_05.glibc;
      "librt.so.1" = pkgs24_05.glibc;
      "libc.so.6" = pkgs24_05.glibc;
      "libnsl.so.1" = pkgs24_05.glibc;
      "libutil.so.1" = pkgs24_05.glibc;
      "libpthread.so.0" = pkgs24_05.glibc;
      "libresolv.so.2" = pkgs24_05.glibc;
      "libcrypt.so.1" = pkgs24_05.libxcrypt;
      "libX11.so.6" = getXorg pkgs24_05 "libX11";
      "libXext.so.6" = getXorg pkgs24_05 "libXext";
      "libXrender.so.1" = getXorg pkgs24_05 "libXrender";
      "libICE.so.6" = getXorg pkgs24_05 "libICE";
      "libSM.so.6" = getXorg pkgs24_05 "libSM";
      "libGL.so.1" = pkgs24_05.libglvnd;
      "libgobject-2.0.so.0" = pkgs24_05.glib;
      "libgthread-2.0.so.0" = pkgs24_05.glib;
      "libglib-2.0.so.0" = pkgs24_05.glib;
      "libz.so.1" = pkgs24_05.zlib;
      "libexpat.so.1" = pkgs24_05.expat;
    };
    runtimeLibs = createLibraryBundle "manylinux_2_39-candidate-runtime-libs" runtimeProviders target.libWhitelist;
    candidateTarget =
      target
      // {
        name = "manylinux_2_39_candidate";
        expectedGlibc = "2.39";
        actualLibcVersion = "2.39";
        compilerRef = "nixos-24.05 gcc14 frontend/runtime";
        stdcxxRef = "nixos-24.05 gcc14 shared runtime";
        stdcxxPkgs = pkgs24_05;
        notes =
          target.notes
          + " Candidate mostly-coherent baseline: glibc 2.39 and gcc14 runtime from nixos-24.05 with no rootfs import.";
      };
    conformanceReport = mkConformanceReport {
      name = "manylinux_2_39-candidate-conformance-report";
      target = builtins.removeAttrs candidateTarget ["stdcxxPkgs"];
      inherit runtimeLibs;
      cc = "${compilerCc}/bin/cc";
      libc = "${lib.getLib pkgs24_05.glibc}/lib/libc.so.6";
      libstdcxx = "${runtimeCompilerLib}/lib/libstdc++.so.6";
      libatomic = "${runtimeCompilerLib}/lib/libatomic.so.1";
      zlib = "${lib.getLib pkgs24_05.zlib}/lib/libz.so.1";
    };
    shell = mkBuildShell {
      name = "manylinux_2_39-candidate-shell";
      packages =
        [
          compilerCc
          pkgs24_05.binutils
          pkgs24_05.patchelf
          pkgs24_05.pkg-config
          pkgs24_05.gnumake
          pkgs.cmake
          python
          pythonPkgs.pip
        ]
        ++ optionalPythonBuild pythonPkgs
        ++ [
          pythonPkgs.setuptools
          pythonPkgs.wheel
          runtimeLibs
        ]
        ++ optionalPythonPackage pythonPkgs "auditwheel"
        ++ optionalPythonPackage pythonPkgs "build";
      env = {
        AUDITWHEEL_POLICY = target.policy;
        NIX_MANYLINUX_TARGET = "manylinux_2_39_candidate";
        NIX_MANYLINUX_PYTHON = "${python}/bin/python";
        NIX_MANYLINUX_RUNTIME_LIBS = "${runtimeLibs}/lib";
        NIX_MANYLINUX_GLIBC_DEV = "${pkgs24_05.glibc.dev}/include";
        NIX_MANYLINUX_GLIBC_BIN = "${pkgs24_05.glibc.bin}";
        NIX_MANYLINUX_STDCXX = "${runtimeCompilerLib}/lib";
        NIX_CC = compilerCc;
      };
      shellHook = ''
        export CC="${compilerCc}/bin/cc"
        export CXX="${compilerCc}/bin/c++"
      '';
    };
  in {
    inherit runtimeLibs conformanceReport shell compilerCc;
    target = candidateTarget;
  };

  reference2014 = let
    target = policyTargets.manylinux2014;
    runtimeProviders = {
      "libatomic.so.1" = "${manylinux2014Rootfs}/usr/lib64/libatomic.so.1";
      "libgcc_s.so.1" = "${manylinux2014Rootfs}/usr/lib64/libgcc_s.so.1";
      "libstdc++.so.6" = "${manylinux2014Rootfs}/usr/lib64/libstdc++.so.6";
      "libm.so.6" = "${manylinux2014Rootfs}/usr/lib64/libm.so.6";
      "libanl.so.1" = "${manylinux2014Rootfs}/usr/lib64/libanl.so.1";
      "libdl.so.2" = "${manylinux2014Rootfs}/usr/lib64/libdl.so.2";
      "librt.so.1" = "${manylinux2014Rootfs}/usr/lib64/librt.so.1";
      "libc.so.6" = "${manylinux2014Rootfs}/usr/lib64/libc.so.6";
      "libnsl.so.1" = "${manylinux2014Rootfs}/usr/lib64/libnsl.so.1";
      "libutil.so.1" = "${manylinux2014Rootfs}/usr/lib64/libutil.so.1";
      "libpthread.so.0" = "${manylinux2014Rootfs}/usr/lib64/libpthread.so.0";
      "libresolv.so.2" = "${manylinux2014Rootfs}/usr/lib64/libresolv.so.2";
      "libX11.so.6" = "${manylinux2014Rootfs}/usr/lib64/libX11.so.6";
      "libXext.so.6" = "${manylinux2014Rootfs}/usr/lib64/libXext.so.6";
      "libXrender.so.1" = "${manylinux2014Rootfs}/usr/lib64/libXrender.so.1";
      "libICE.so.6" = "${manylinux2014Rootfs}/usr/lib64/libICE.so.6";
      "libSM.so.6" = "${manylinux2014Rootfs}/usr/lib64/libSM.so.6";
      "libGL.so.1" = "${manylinux2014Rootfs}/usr/lib64/libGL.so.1";
      "libgobject-2.0.so.0" = "${manylinux2014Rootfs}/usr/lib64/libgobject-2.0.so.0";
      "libgthread-2.0.so.0" = "${manylinux2014Rootfs}/usr/lib64/libgthread-2.0.so.0";
      "libglib-2.0.so.0" = "${manylinux2014Rootfs}/usr/lib64/libglib-2.0.so.0";
      "libz.so.1" = "${manylinux2014Rootfs}/usr/lib64/libz.so.1";
      "libexpat.so.1" = "${manylinux2014Rootfs}/usr/lib64/libexpat.so.1";
    };
    runtimeLibs = createLibraryBundleFromPaths "manylinux2014-reference-runtime-libs" runtimeProviders target.libWhitelist;
    referenceTarget =
      target
      // {
        name = "manylinux2014_reference";
        expectedGlibc = "2.17";
        actualLibcVersion = "2.17";
        compilerRef = "official manylinux2014 rootfs/runtime reference";
        stdcxxRef = "official manylinux2014 shared runtime (GLIBCXX_3.4.19)";
        notes =
          target.notes
          + " Surface reference extracted from quay.io/pypa/manylinux2014_x86_64. This is the CentOS 7-era runtime/sysroot anchor for the eventual Nix-native builder candidate.";
      };
    conformanceReport = mkConformanceReport {
      name = "manylinux2014-reference-conformance-report";
      target = referenceTarget;
      inherit runtimeLibs;
      cc = "${pkgs22_05.gcc10.cc}/bin/gcc";
      libc = "${manylinux2014Rootfs}/usr/lib64/libc.so.6";
      libstdcxx = "${manylinux2014Rootfs}/usr/lib64/libstdc++.so.6";
      libatomic = "${lib.getLib pkgs22_05.gcc10.cc}/lib/libatomic.so.1";
      zlib = "${manylinux2014Rootfs}/usr/lib64/libz.so.1";
    };
    shell = mkBuildShell {
      name = "manylinux2014-reference-shell";
      packages =
        [
          pkgs22_05.gcc10.cc
          pkgs.binutils
          pkgs.patchelf
          pkgs.pkg-config
          pkgs.gnumake
          pkgs.cmake
          python
          pythonPkgs.pip
        ]
        ++ optionalPythonBuild pythonPkgs
        ++ [
          pythonPkgs.setuptools
          pythonPkgs.wheel
          runtimeLibs
        ]
        ++ optionalPythonPackage pythonPkgs "auditwheel";
      env = {
        AUDITWHEEL_POLICY = target.policy;
        NIX_MANYLINUX_TARGET = "manylinux2014_reference";
        NIX_MANYLINUX_PYTHON = "${python}/bin/python";
        NIX_MANYLINUX_RUNTIME_LIBS = "${runtimeLibs}/lib";
        NIX_MANYLINUX_SYSROOT = manylinux2014Rootfs;
      };
      shellHook = ''
      '';
    };
  in {
    inherit runtimeLibs conformanceReport shell manylinux2014Rootfs;
    target = referenceTarget;
  };

  candidate2014 = let
    target = policyTargets.manylinux2014;
    toolchainLibPath =
      lib.makeLibraryPath [
        reference2014.runtimeLibs
      ]
      + ":${manylinux2014Rootfs}/usr/lib64"
      + ":${manylinux2014Rootfs}/lib64"
      + ":${manylinux2014Rootfs}/opt/rh/devtoolset-10/root/usr/lib64"
      + ":${manylinux2014Rootfs}/opt/rh/devtoolset-10/root/usr/lib/gcc/x86_64-redhat-linux/10";
    frontendCc = pkgs.runCommand "manylinux2014-devtoolset10-toolchain" {nativeBuildInputs = [pkgs.patchelf pkgs.file pkgs.findutils];} ''
      mkdir -p "$out"
      cp -a ${manylinux2014Rootfs}/opt/rh/devtoolset-10/root/usr/. "$out/"
      chmod -R u+w "$out"
      while IFS= read -r -d $'\0' path; do
        if file -b "$path" | grep -q '^ELF '; then
          patchelf --set-rpath '${toolchainLibPath}' "$path" || true
          if patchelf --print-interpreter "$path" >/dev/null 2>&1; then
            patchelf --set-interpreter ${manylinux2014Rootfs}/usr/lib64/ld-linux-x86-64.so.2 "$path" || true
          fi
        fi
      done < <(find "$out" -type f -print0)
    '';
    stdcxxShim = pkgs.runCommand "manylinux2014-stdcxx-shim" {} ''
      mkdir -p "$out/lib"
      for script in ${manylinux2014Rootfs}/usr/lib64/*.so; do
        [ -f "$script" ] || continue
        if file -b "$script" | grep -q '^ASCII text'; then
          name=$(basename "$script")
          sed \
            -e 's|/usr/lib64/|@MANYLINUX_USR_LIB64@|g' \
            -e 's|/lib64/|@MANYLINUX_LIB64@|g' \
            -e 's|@MANYLINUX_USR_LIB64@|${manylinux2014Rootfs}/usr/lib64/|g' \
            -e 's|@MANYLINUX_LIB64@|${manylinux2014Rootfs}/usr/lib64/|g' \
            "$script" > "$out/lib/$name"
        fi
      done
      cat > "$out/lib/libstdc++.so" <<'SCRIPT'
      /* GNU ld script */
      OUTPUT_FORMAT(elf64-x86-64)
      INPUT ( ${manylinux2014Rootfs}/usr/lib64/libstdc++.so.6 ${manylinux2014Rootfs}/opt/rh/devtoolset-10/root/usr/lib/gcc/x86_64-redhat-linux/10/libstdc++_nonshared.a )
      SCRIPT
      cat > "$out/lib/libgcc_s.so" <<'SCRIPT'
      /* GNU ld script */
      OUTPUT_FORMAT(elf64-x86-64)
      GROUP ( ${manylinux2014Rootfs}/usr/lib64/libgcc_s.so.1 ${manylinux2014Rootfs}/opt/rh/devtoolset-10/root/usr/lib/gcc/x86_64-redhat-linux/10/libgcc.a )
      SCRIPT
    '';
    compilerCc = pkgs.runCommand "manylinux2014-devtoolset10-wrapper" {} ''
      mkdir -p "$out/bin"
      cat > "$out/bin/cc" <<'EOF'
      #!${pkgs.bash}/bin/bash
      exec ${frontendCc}/bin/gcc \
        --sysroot=${manylinux2014Rootfs} \
        -idirafter ${manylinux2014Rootfs}/usr/include \
        -L${stdcxxShim}/lib \
        -B${stdcxxShim}/lib \
        -Wl,-rpath-link,${manylinux2014Rootfs}/usr/lib64 \
        -Wl,-rpath-link,${stdcxxShim}/lib \
        "$@"
      EOF
      cat > "$out/bin/c++" <<'EOF'
      #!${pkgs.bash}/bin/bash
      exec ${frontendCc}/bin/g++ \
        --sysroot=${manylinux2014Rootfs} \
        -idirafter ${manylinux2014Rootfs}/usr/include \
        -L${stdcxxShim}/lib \
        -B${stdcxxShim}/lib \
        -Wl,-rpath-link,${manylinux2014Rootfs}/usr/lib64 \
        -Wl,-rpath-link,${stdcxxShim}/lib \
        "$@"
      EOF
      chmod +x "$out/bin/cc" "$out/bin/c++"
    '';
    candidateTarget =
      reference2014.target
      // {
        name = "manylinux2014_candidate";
        compilerRef = "patched official devtoolset-10 frontend wrapped against official manylinux2014 sysroot/runtime";
        stdcxxRef = "official manylinux2014 shared runtime + libstdc++_nonshared";
        notes =
          target.notes
          + " Candidate builder: patched devtoolset-10 frontend from the extracted official manylinux2014 rootfs, using a rootfs-aware libstdc++ shim for the shared + nonshared link pattern.";
      };
    shell = mkBuildShell {
      name = "manylinux2014-candidate-shell";
      packages =
        [
          compilerCc
          pkgs.binutils
          pkgs.patchelf
          pkgs.pkg-config
          pkgs.gnumake
          pkgs.cmake
          python
          pythonPkgs.pip
        ]
        ++ optionalPythonBuild pythonPkgs
        ++ [
          pythonPkgs.setuptools
          pythonPkgs.wheel
          reference2014.runtimeLibs
        ]
        ++ optionalPythonPackage pythonPkgs "auditwheel";
      env = {
        AUDITWHEEL_POLICY = target.policy;
        NIX_MANYLINUX_TARGET = "manylinux2014_candidate";
        NIX_MANYLINUX_PYTHON = "${python}/bin/python";
        NIX_MANYLINUX_RUNTIME_LIBS = "${reference2014.runtimeLibs}/lib";
        NIX_MANYLINUX_SYSROOT = manylinux2014Rootfs;
        NIX_MANYLINUX_STDCXX_NONSHARED = "${manylinux2014Rootfs}/opt/rh/devtoolset-10/root/usr/lib/gcc/x86_64-redhat-linux/10";
        NIX_CC = compilerCc;
      };
      shellHook = ''
        export CC="${compilerCc}/bin/cc"
        export CXX="${compilerCc}/bin/c++"
      '';
    };
  in {
    inherit compilerCc shell;
    inherit (reference2014) runtimeLibs;
    inherit (reference2014) conformanceReport;
    target = candidateTarget;
  };

  mkTarget = targetName: let
    target = policyTargets.${targetName};

    compilerCc =
      if target.preferredCompilerAttr != null && builtins.hasAttr target.preferredCompilerAttr pkgs
      then (builtins.getAttr target.preferredCompilerAttr pkgs).cc
      else pkgs.stdenv.cc;

    compilerLib = lib.getLib compilerCc.cc;

    x86_64LibraryProviders = getLibOutputs (
      with pkgs; {
        "libatomic.so.1" = compilerCc.cc;
        "libgcc_s.so.1" = compilerCc.cc;
        "libstdc++.so.6" = compilerCc.cc;
        "libm.so.6" = glibc;
        "libmvec.so.1" = glibc;
        "libanl.so.1" = glibc;
        "libdl.so.2" = glibc;
        "librt.so.1" = glibc;
        "libc.so.6" = glibc;
        "libnsl.so.1" = glibc;
        "libutil.so.1" = glibc;
        "libpthread.so.0" = glibc;
        "libresolv.so.2" = glibc;
        "libX11.so.6" = libx11;
        "libXext.so.6" = libxext;
        "libXrender.so.1" = libxrender;
        "libICE.so.6" = libice;
        "libSM.so.6" = libsm;
        "libGL.so.1" = libGL;
        "libgobject-2.0.so.0" = glib;
        "libgthread-2.0.so.0" = glib;
        "libglib-2.0.so.0" = glib;
        "libz.so.1" = zlib;
        "libexpat.so.1" = expat;
        "libcrypt.so.1" = libxcrypt;
        "libpanelw.so.5" = ncurses5;
        "libncursesw.so.5" = ncurses5;
      }
    );

    runtimeLibs = createLibraryBundle "${targetName}-runtime-libs" x86_64LibraryProviders target.libWhitelist;

    buildInputs = with pkgs;
      [
        compilerCc
        binutils
        patchelf
        pkg-config
        gnumake
        cmake
        python
        pythonPkgs.pip
      ]
      ++ optionalPythonBuild pythonPkgs
      ++ [
        pythonPkgs.setuptools
        pythonPkgs.wheel
        glibc.dev
        zlib.dev
        expat.dev
        glib.dev
        libx11.dev
        libxext.dev
        libxrender.dev
        libice.dev
        libsm.dev
        libGL.dev
      ]
      ++ optionalPythonPackage pythonPkgs "auditwheel";

    conformanceReport = mkConformanceReport {
      name = "${targetName}-conformance-report";
      inherit target;
      inherit runtimeLibs;
      cc = "${compilerCc}/bin/cc";
      libc = "${lib.getLib pkgs.glibc}/lib/libc.so.6";
      libstdcxx = "${compilerLib}/lib/libstdc++.so.6";
      libatomic = "${compilerLib}/lib/libatomic.so.1";
      zlib = "${lib.getLib pkgs.zlib}/lib/libz.so.1";
      extraTargetAttrs = {
        name = targetName;
        actualLibcVersion = pkgs.glibc.version;
      };
    };

    shell = mkBuildShell {
      name = "${targetName}-build-shell";
      packages = buildInputs ++ [runtimeLibs];
      env = {
        AUDITWHEEL_POLICY = target.policy;
        NIX_MANYLINUX_TARGET = targetName;
        NIX_MANYLINUX_COMPILER = target.preferredCompilerAttr or "stdenv.cc";
        NIX_MANYLINUX_GLIBC_FLOOR = target.glibcFloor;
        NIX_MANYLINUX_PYTHON = "${python}/bin/python";
        NIX_MANYLINUX_RUNTIME_LIBS = "${runtimeLibs}/lib";
      };
      shellHook = ''
      '';
    };
  in {
    inherit runtimeLibs shell buildInputs target conformanceReport;
  };
in {
  manylinux2014 = mkTarget "manylinux2014";
  manylinux2014_reference = reference2014;
  manylinux2014_candidate = candidate2014;
  manylinux_2_28 = mkTarget "manylinux_2_28";
  manylinux_2_34 = mkTarget "manylinux_2_34";
  manylinux_2_39 = mkTarget "manylinux_2_39";
  manylinux_2_28_candidate = candidate228;
  manylinux_2_34_candidate = candidate234;
  manylinux_2_39_candidate = candidate239;
}
