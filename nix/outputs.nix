{
  lib,
  pkgs,
  inputs,
  system,
}: let
  targets = import ./targets.nix {inherit inputs system;};
  targetNames = builtins.attrNames targets;
  policyTargetMetadata = import ./policy-targets.nix;
  policyTargetSpecs = import ./policy-specs.nix {inherit lib;};
  policyTargets =
    lib.mapAttrs (
      name: metadata:
        metadata
        // (policyTargetSpecs.${name} or {})
    )
    policyTargetMetadata;
  policyTargetNames = builtins.attrNames policyTargets;
  buildEnvs = import ./build-envs.nix {
    inherit inputs lib pkgs policyTargets system;
  };
  buildEnvNames = builtins.attrNames buildEnvs;
  mkManylinuxWheel = import ./lib/mk-manylinux-wheel.nix;
  targetMatrixLib = import ./lib/target-matrix.nix {inherit lib;};
  buildTargets = targetMatrixLib.mkBuildTargets buildEnvs;
  mkManylinuxWheelSmokes = {
    cp312 = import ./mk-manylinux-wheel-smoke.nix {
      inherit lib pkgs mkManylinuxWheel;
      targetShell = buildEnvs.manylinux_2_28_candidate.shell;
      python = pkgs.python312;
      suffix = "cp312";
    };
    cp313 = import ./mk-manylinux-wheel-smoke.nix {
      inherit lib pkgs mkManylinuxWheel;
      targetShell = buildEnvs.manylinux_2_28_candidate.shell;
      python = pkgs.python313;
      suffix = "cp313";
    };
  };

  probeVariantDefs = {
    baseline = {
      extraCxxFlags = [];
      notes = "";
    };
    float-charconv = {
      extraCxxFlags = ["-DBASELINE_PROBE_ENABLE_FLOAT_CHARCONV=1"];
      notes = "Adds floating-point std::to_chars pressure.";
    };
    shared-state = {
      extraCxxFlags = [
        "-DBASELINE_PROBE_ENABLE_SHARED_STATE=1"
        "-DBASELINE_PROBE_ENABLE_VARIANT=1"
      ];
      notes = "Adds promise/future/thread/shared_ptr/variant pressure.";
    };
    pmr = {
      extraCxxFlags = ["-DBASELINE_PROBE_ENABLE_PMR=1"];
      notes = "Adds polymorphic memory resource pressure.";
    };
    random-device = {
      extraCxxFlags = ["-DBASELINE_PROBE_ENABLE_RANDOM_DEVICE=1"];
      notes = "Adds std::random_device pressure.";
    };
    glibc-239 = {
      extraCxxFlags = ["-DBASELINE_PROBE_ENABLE_GLIBC_239=1"];
      notes = "Adds glibc 2.39 stdbit pressure.";
    };
  };

  probeSuites = {
    legacy2014 = [
      "baseline"
      "shared-state"
      "random-device"
    ];
    modern = [
      "baseline"
      "float-charconv"
      "pmr"
      "shared-state"
      "random-device"
    ];
    modern239 = [
      "baseline"
      "float-charconv"
      "pmr"
      "shared-state"
      "random-device"
      "glibc-239"
    ];
  };

  mkProbe = targetName:
    import ./probe-wheel.nix {
      inherit lib;
      hostPkgs = pkgs;
      inherit (targets.${targetName}) pkgs;
      target = targets.${targetName};
      src = ../probe;
    };

  candidate228Target =
    buildEnvs.manylinux_2_28_candidate.target
    // {
      nixpkgsRef = "hybrid(glibc-2.28, gcc14-frontend, gcc8-runtime, fs-compat)";
      notes = "Probe using the first-class manylinux_2_28 candidate env.";
      pythonAttr = "python312";
    };
  candidate234Target =
    buildEnvs.manylinux_2_34_candidate.target
    // {
      nixpkgsRef = "mostly-coherent(nixos-22.05 + zlib-1.2.9)";
      notes = "Probe using the first-class manylinux_2_34 candidate env.";
      pythonAttr = "python312";
    };
  candidate2014Target =
    buildEnvs.manylinux2014_candidate.target
    // {
      nixpkgsRef = "official-manylinux2014-rootfs + devtoolset10-frontend";
      notes = "Probe using the first-class manylinux2014 candidate env.";
      pythonAttr = "python312";
    };

  mkCandidateProbe = {
    compilerCc,
    distPkgs,
    baseTarget,
    stdcxxPkgs,
    suffix,
    extraCxxFlags ? [],
    notes ? "",
  }:
    import ./probe-wheel.nix {
      inherit lib extraCxxFlags;
      inherit compilerCc;
      distName = "manylinux-baseline-probe-${suffix}";
      headerIncludeDirs = [];
      hostPkgs = pkgs;
      pkgs = distPkgs;
      target =
        baseTarget
        // {
          name = "${baseTarget.name}_${suffix}";
          notes =
            if notes == ""
            then baseTarget.notes
            else "${baseTarget.notes} ${notes}";
          inherit stdcxxPkgs;
        };
      src = ../probe;
    };

  mkCandidateProbeSet = {
    compilerCc,
    distPkgs,
    baseTarget,
    stdcxxPkgs,
  }:
    lib.mapAttrs
    (
      suffix: variant:
        mkCandidateProbe ({
            inherit compilerCc distPkgs baseTarget stdcxxPkgs suffix;
          }
          // variant)
    )
    probeVariantDefs;

  candidate228Probes = mkCandidateProbeSet {
    inherit (buildEnvs.manylinux_2_28_candidate) compilerCc;
    distPkgs = import inputs.nixpkgs-20_03.outPath {inherit system;};
    baseTarget = candidate228Target;
    inherit (buildEnvs.manylinux_2_28_candidate.target) stdcxxPkgs;
  };
  candidate234Probes = mkCandidateProbeSet {
    inherit (buildEnvs.manylinux_2_34_candidate) compilerCc;
    distPkgs = import inputs.nixpkgs-22_05.outPath {inherit system;};
    baseTarget = candidate234Target;
    inherit (buildEnvs.manylinux_2_34_candidate.target) stdcxxPkgs;
  };
  candidate2014Probes = mkCandidateProbeSet {
    inherit (buildEnvs.manylinux2014_candidate) compilerCc;
    distPkgs = import inputs.nixpkgs-22_05.outPath {inherit system;};
    baseTarget = candidate2014Target;
    stdcxxPkgs = null;
  };
  candidate239Target =
    buildEnvs.manylinux_2_39_candidate.target
    // {
      nixpkgsRef = "mostly-coherent(nixos-24.05 gcc14)";
      notes = "Probe using the first-class manylinux_2_39 candidate env.";
      pythonAttr = "python312";
    };
  candidate239Probes = mkCandidateProbeSet {
    inherit (buildEnvs.manylinux_2_39_candidate) compilerCc;
    distPkgs = import inputs.nixpkgs-24_05.outPath {inherit system;};
    baseTarget = candidate239Target;
    inherit (buildEnvs.manylinux_2_39_candidate.target) stdcxxPkgs;
  };

  candidateProbeSets = {
    manylinux_2_28_candidate = {
      probes = candidate228Probes;
      expectedTag = "manylinux_2_28_x86_64";
      suite = probeSuites.modern;
      exactExpectations =
        lib.genAttrs probeSuites.modern (_: "manylinux_2_28_x86_64");
    };
    manylinux_2_34_candidate = {
      probes = candidate234Probes;
      expectedTag = "manylinux_2_34_x86_64";
      suite = probeSuites.modern;
      exactExpectations =
        lib.genAttrs probeSuites.modern (_: "manylinux_2_34_x86_64");
    };
    manylinux_2_39_candidate = {
      probes = candidate239Probes;
      expectedTag = "manylinux_2_39_x86_64";
      suite = probeSuites.modern239;
      exactExpectations = {
        glibc-239 = "manylinux_2_39_x86_64";
      };
    };
    manylinux2014_candidate = {
      probes = candidate2014Probes;
      expectedTag = "manylinux_2_17_x86_64";
      suite = probeSuites.legacy2014;
      exactExpectations =
        lib.genAttrs probeSuites.legacy2014 (_: "manylinux_2_17_x86_64");
    };
  };

  exportedCandidateProbeSets =
    lib.mapAttrs
    (
      _: value:
        value
        // {
          probes = lib.filterAttrs (probeName: _: builtins.elem probeName value.suite) value.probes;
        }
    )
    candidateProbeSets;

  showTargetsJson = pkgs.writeText "manylinux-targets.json" (
    builtins.toJSON (
      map (targetName: let
        target = targets.${targetName};
      in {
        inherit (target) name;
        inherit (target) nixpkgsRef;
        inherit (target) expectedGlibc;
        inherit (target) notes;
        inherit (target) pythonAttr;
      })
      targetNames
    )
  );

  showPolicyTargetsJson = pkgs.writeText "manylinux-policy-targets.json" (
    builtins.toJSON (
      map (targetName:
        policyTargets.${targetName}
        // {
          name = targetName;
        })
      policyTargetNames
    )
  );

  showConformanceJson =
    pkgs.runCommand "manylinux-conformance-summary.json"
    {nativeBuildInputs = [pkgs.jq];}
    ''
      jq -s '.' \
        ${lib.concatStringsSep " " (map (name: "${buildEnvs.${name}.conformanceReport}/report.json") buildEnvNames)} \
        > "$out"
    '';

  showBuildTargetsJson = pkgs.writeText "manylinux-build-targets.json" (
    builtins.toJSON (targetMatrixLib.toGithubActionsMatrix buildTargets)
  );

  mkProbeSuiteSummary = {
    name,
    targetTag,
    probeSet,
    suite,
    exactExpectations ? {},
  }:
    pkgs.runCommand "${name}-probe-suite-summary.json"
    {nativeBuildInputs = [pkgs.python3];}
    ''
      python ${../scripts/probe_suite_summary.py} \
        --target ${targetTag} \
        ${lib.concatStringsSep " " (lib.mapAttrsToList (probeName: expectedTag: "--exact ${probeName}=${expectedTag}") exactExpectations)} \
        --reports ${lib.concatStringsSep " " (map (probeName: "${probeSet.${probeName}.showReport}/report.txt") suite)} \
        --output "$out"
    '';

  candidateProbeSuiteSummaries =
    lib.mapAttrs
    (
      name: value:
        mkProbeSuiteSummary {
          inherit name;
          targetTag = value.expectedTag;
          probeSet = value.probes;
          inherit (value) suite;
          exactExpectations = value.exactExpectations or {};
        }
    )
    candidateProbeSets;

  mkCatApp = appName: path:
    pkgs.writeShellApplication {
      name = appName;
      text = ''
        cat ${path}
      '';
    };

  verifyWheelInContainer = pkgs.writeShellApplication {
    name = "verify-wheel-in-container";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.docker-client
      pkgs.findutils
    ];
    text = builtins.readFile ../scripts/verify_wheel_in_container.sh;
  };

  mkShowApp = {
    name,
    path,
    description,
  }: {
    type = "app";
    program = "${mkCatApp name path}/bin/${name}";
    meta.description = description;
  };

  apps =
    {
      default = mkShowApp {
        name = "show-manylinux-policy-targets";
        path = showPolicyTargetsJson;
        description = "Print manylinux policy metadata as JSON.";
      };
      show-targets = mkShowApp {
        name = "show-manylinux-probe-targets";
        path = showTargetsJson;
        description = "Print probe target metadata as JSON.";
      };
      show-policy-targets = mkShowApp {
        name = "show-manylinux-policy-targets";
        path = showPolicyTargetsJson;
        description = "Print manylinux policy metadata as JSON.";
      };
      show-build-targets = mkShowApp {
        name = "show-manylinux-build-targets";
        path = showBuildTargetsJson;
        description = "Print manylinux build target metadata as JSON.";
      };
      show-conformance = mkShowApp {
        name = "show-manylinux-conformance";
        path = showConformanceJson;
        description = "Print manylinux build environment conformance reports as JSON.";
      };
      verify-wheel-in-container = {
        type = "app";
        program = "${verifyWheelInContainer}/bin/verify-wheel-in-container";
        meta.description = "Install and import-test a wheel in a Python Docker container.";
      };
    }
    // lib.mapAttrs'
    (
      name: summary: let
        appName = "show-${builtins.replaceStrings ["_"] ["-"] name}-probe-suite";
      in
        lib.nameValuePair appName (mkShowApp {
          name = appName;
          path = summary;
          description = "Print the ${name} probe suite summary as JSON.";
        })
    )
    candidateProbeSuiteSummaries;

  probePackages =
    lib.mapAttrs'
    (targetName: _: lib.nameValuePair "${targetName}-probe-wheel" (mkProbe targetName).wheel)
    targets
    // lib.foldl' lib.mergeAttrs {} (
      lib.mapAttrsToList
      (
        candidateName: value:
          lib.mapAttrs'
          (probeName: probe: lib.nameValuePair "${candidateName}-${probeName}-probe-wheel" probe.wheel)
          value.probes
      )
      exportedCandidateProbeSets
    );

  buildEnvPackages =
    lib.mapAttrs' (targetName: value: lib.nameValuePair "${targetName}-runtime-libs" value.runtimeLibs) buildEnvs;

  buildEnvReports =
    lib.mapAttrs' (targetName: value: lib.nameValuePair "${targetName}-conformance-report" value.conformanceReport) buildEnvs;

  floorChecks =
    lib.mapAttrs' (targetName: _: lib.nameValuePair "${targetName}-auditwheel-show" (mkProbe targetName).showReport) targets
    // lib.foldl' lib.mergeAttrs {} (
      lib.mapAttrsToList
      (
        candidateName: value:
          lib.mapAttrs'
          (probeName: probe: lib.nameValuePair "${candidateName}-${probeName}-auditwheel-show" probe.showReport)
          value.probes
      )
      exportedCandidateProbeSets
    );

  conformanceChecks =
    lib.mapAttrs' (targetName: value: lib.nameValuePair "${targetName}-conformance" value.conformanceReport) buildEnvs;

  packages =
    {
      targets-json = showTargetsJson;
      policy-targets-json = showPolicyTargetsJson;
      build-targets-json = showBuildTargetsJson;
      conformance-summary-json = showConformanceJson;
      inherit verifyWheelInContainer;
      mk-manylinux-wheel-smoke = mkManylinuxWheelSmokes.cp312;
      mk-manylinux-wheel-smoke-cp313 = mkManylinuxWheelSmokes.cp313;
    }
    // lib.mapAttrs' (name: value: lib.nameValuePair "${name}-probe-suite-summary" value) candidateProbeSuiteSummaries
    // buildEnvPackages
    // buildEnvReports
    // probePackages;

  checks =
    floorChecks
    // conformanceChecks
    // {
      mk-manylinux-wheel-smoke = mkManylinuxWheelSmokes.cp312;
      mk-manylinux-wheel-smoke-cp313 = mkManylinuxWheelSmokes.cp313;
    }
    // lib.mapAttrs' (name: value: lib.nameValuePair "${name}-probe-suite" value) candidateProbeSuiteSummaries;

  devShells =
    {
      default = pkgs.mkShell {
        packages = [
          pkgs.jq
          pkgs.python3
        ];
      };
    }
    // lib.mapAttrs' (targetName: value: lib.nameValuePair targetName value.shell) buildEnvs;
in {
  inherit
    apps
    buildEnvs
    buildTargets
    checks
    devShells
    packages
    policyTargets
    probeSuites
    targets
    ;
}
