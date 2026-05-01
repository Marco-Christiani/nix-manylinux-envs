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
      pkgs = targets.${targetName}.pkgs;
      target = targets.${targetName};
      src = ../probe;
    };

  candidate228Target =
    buildEnvs.manylinux_2_28_candidate.target
    // {
      nixpkgsRef = "hybrid(glibc-2.28, gcc14-frontend, gcc8-runtime, fs-compat)";
      notes = "Probe using the first-class manylinux_2_28 candidate env.";
      pythonAttr = "python3";
    };
  candidate234Target =
    buildEnvs.manylinux_2_34_candidate.target
    // {
      nixpkgsRef = "mostly-coherent(nixos-22.05 + zlib-1.2.9)";
      notes = "Probe using the first-class manylinux_2_34 candidate env.";
      pythonAttr = "python3";
    };
  candidate2014Target =
    buildEnvs.manylinux2014_candidate.target
    // {
      nixpkgsRef = "official-manylinux2014-rootfs + devtoolset10-frontend";
      notes = "Probe using the first-class manylinux2014 candidate env.";
      pythonAttr = "python3";
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
    compilerCc = buildEnvs.manylinux_2_28_candidate.compilerCc;
    distPkgs = import inputs.nixpkgs-20_03.outPath {inherit system;};
    baseTarget = candidate228Target;
    stdcxxPkgs = buildEnvs.manylinux_2_28_candidate.target.stdcxxPkgs;
  };
  candidate234Probes = mkCandidateProbeSet {
    compilerCc = buildEnvs.manylinux_2_34_candidate.compilerCc;
    distPkgs = import inputs.nixpkgs-22_05.outPath {inherit system;};
    baseTarget = candidate234Target;
    stdcxxPkgs = buildEnvs.manylinux_2_34_candidate.target.stdcxxPkgs;
  };
  candidate2014Probes = mkCandidateProbeSet {
    compilerCc = buildEnvs.manylinux2014_candidate.compilerCc;
    distPkgs = import inputs.nixpkgs-22_05.outPath {inherit system;};
    baseTarget = candidate2014Target;
    stdcxxPkgs = null;
  };
  candidate239Target =
    buildEnvs.manylinux_2_39_candidate.target
    // {
      nixpkgsRef = "mostly-coherent(nixos-24.05 gcc14)";
      notes = "Probe using the first-class manylinux_2_39 candidate env.";
      pythonAttr = "python3";
    };
  candidate239Probes = mkCandidateProbeSet {
    compilerCc = buildEnvs.manylinux_2_39_candidate.compilerCc;
    distPkgs = import inputs.nixpkgs-24_05.outPath {inherit system;};
    baseTarget = candidate239Target;
    stdcxxPkgs = buildEnvs.manylinux_2_39_candidate.target.stdcxxPkgs;
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
        name = target.name;
        nixpkgsRef = target.nixpkgsRef;
        expectedGlibc = target.expectedGlibc;
        notes = target.notes;
        pythonAttr = target.pythonAttr;
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
          suite = value.suite;
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

  apps =
    {
      default = {
        type = "app";
        program = "${mkCatApp "show-manylinux-policy-targets" showPolicyTargetsJson}/bin/show-manylinux-policy-targets";
      };
      show-targets = {
        type = "app";
        program = "${mkCatApp "show-manylinux-probe-targets" showTargetsJson}/bin/show-manylinux-probe-targets";
      };
      show-policy-targets = {
        type = "app";
        program = "${mkCatApp "show-manylinux-policy-targets" showPolicyTargetsJson}/bin/show-manylinux-policy-targets";
      };
      show-conformance = {
        type = "app";
        program = "${mkCatApp "show-manylinux-conformance" showConformanceJson}/bin/show-manylinux-conformance";
      };
    }
    // lib.mapAttrs'
    (
      name: summary:
        lib.nameValuePair "show-${builtins.replaceStrings ["_"] ["-"] name}-probe-suite" {
          type = "app";
          program = "${mkCatApp "show-${builtins.replaceStrings ["_"] ["-"] name}-probe-suite" summary}/bin/show-${builtins.replaceStrings ["_"] ["-"] name}-probe-suite";
        }
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
      conformance-summary-json = showConformanceJson;
    }
    // lib.mapAttrs' (name: value: lib.nameValuePair "${name}-probe-suite-summary" value) candidateProbeSuiteSummaries
    // buildEnvPackages
    // buildEnvReports
    // probePackages;

  checks =
    floorChecks
    // conformanceChecks
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
    checks
    devShells
    packages
    policyTargets
    probeSuites
    targets
    ;
}
