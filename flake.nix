{
  description = "Experimental Nix-native manylinux baseline builders";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-19_09 = {
      url = "github:NixOS/nixpkgs/nixos-19.09";
      flake = false;
    };
    nixpkgs-19_03 = {
      url = "github:NixOS/nixpkgs/nixos-19.03";
      flake = false;
    };
    nixpkgs-20_03.url = "github:NixOS/nixpkgs/nixos-20.03";
    nixpkgs-20_09.url = "github:NixOS/nixpkgs/nixos-20.09";
    nixpkgs-21_05.url = "github:NixOS/nixpkgs/nixos-21.05";
    nixpkgs-22_05.url = "github:NixOS/nixpkgs/nixos-22.05";
    nixpkgs-22_11.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixpkgs-24_05.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      perSystem = {
        system,
        pkgs,
        lib,
        ...
      }: let
        targets = import ./nix/targets.nix {inherit inputs system;};
        targetNames = builtins.attrNames targets;
        policyTargetMetadata = import ./nix/policy-targets.nix;
        policyTargetSpecs = import ./nix/policy-specs.nix {inherit lib;};
        policyTargets =
          lib.mapAttrs (
            name: metadata:
              metadata
              // (policyTargetSpecs.${name} or {})
          )
          policyTargetMetadata;
        policyTargetNames = builtins.attrNames policyTargets;
        buildEnvs = import ./nix/build-envs.nix {
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
        };

        mkProbe = targetName:
          import ./nix/probe-wheel.nix {
            inherit lib;
            hostPkgs = pkgs;
            pkgs = targets.${targetName}.pkgs;
            target = targets.${targetName};
            src = ./probe;
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
            nixpkgsRef = "official-manylinux2014-rootfs + nixos-22.05-gcc10-frontend";
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
          import ./nix/probe-wheel.nix {
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
            src = ./probe;
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
        candidate228ProbeNames = builtins.attrNames candidate228Probes;
        candidate234ProbeNames = builtins.attrNames candidate234Probes;
        candidate2014ProbeNames = builtins.attrNames candidate2014Probes;
        modernProbeNames = probeSuites.modern;
        legacy2014ProbeNames = probeSuites.legacy2014;

        probePackages =
          builtins.listToAttrs (
            map (targetName: {
              name = "${targetName}-probe-wheel";
              value = (mkProbe targetName).wheel;
            })
            targetNames
          )
          // builtins.listToAttrs (
            map (probeName: {
              name = "manylinux_2_28_candidate-${probeName}-probe-wheel";
              value = candidate228Probes.${probeName}.wheel;
            })
            candidate228ProbeNames
          )
          // builtins.listToAttrs (
            map (probeName: {
              name = "manylinux_2_34_candidate-${probeName}-probe-wheel";
              value = candidate234Probes.${probeName}.wheel;
            })
            candidate234ProbeNames
          )
          // builtins.listToAttrs (
            map (probeName: {
              name = "manylinux2014_candidate-${probeName}-probe-wheel";
              value = candidate2014Probes.${probeName}.wheel;
            })
            candidate2014ProbeNames
          );

        buildEnvPackages = builtins.listToAttrs (
          map (targetName: {
            name = "${targetName}-runtime-libs";
            value = buildEnvs.${targetName}.runtimeLibs;
          })
          buildEnvNames
        );

        buildEnvReports = builtins.listToAttrs (
          map (targetName: {
            name = "${targetName}-conformance-report";
            value = buildEnvs.${targetName}.conformanceReport;
          })
          buildEnvNames
        );

        floorChecks =
          builtins.listToAttrs (
            map (targetName: {
              name = "${targetName}-auditwheel-show";
              value = (mkProbe targetName).showReport;
            })
            targetNames
          )
          // builtins.listToAttrs (
            map (probeName: {
              name = "manylinux_2_28_candidate-${probeName}-auditwheel-show";
              value = candidate228Probes.${probeName}.showReport;
            })
            candidate228ProbeNames
          )
          // builtins.listToAttrs (
            map (probeName: {
              name = "manylinux_2_34_candidate-${probeName}-auditwheel-show";
              value = candidate234Probes.${probeName}.showReport;
            })
            candidate234ProbeNames
          )
          // builtins.listToAttrs (
            map (probeName: {
              name = "manylinux2014_candidate-${probeName}-auditwheel-show";
              value = candidate2014Probes.${probeName}.showReport;
            })
            candidate2014ProbeNames
          );

        conformanceChecks = builtins.listToAttrs (
          map (targetName: {
            name = "${targetName}-conformance";
            value = buildEnvs.${targetName}.conformanceReport;
          })
          buildEnvNames
        );

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

        showTargetsApp = pkgs.writeShellApplication {
          name = "show-manylinux-probe-targets";
          text = ''
            cat ${showTargetsJson}
          '';
        };

        showPolicyTargetsApp = pkgs.writeShellApplication {
          name = "show-manylinux-policy-targets";
          text = ''
            cat ${showPolicyTargetsJson}
          '';
        };

        showConformanceJson =
          pkgs.runCommand "manylinux-conformance-summary.json"
          {
            nativeBuildInputs = [
              pkgs.jq
            ];
          }
          ''
            jq -s '.' \
              ${lib.concatStringsSep " " (map (name: "${buildEnvs.${name}.conformanceReport}/report.json") buildEnvNames)} \
              > "$out"
          '';

        showConformanceApp = pkgs.writeShellApplication {
          name = "show-manylinux-conformance";
          text = ''
            cat ${showConformanceJson}
          '';
        };

        candidate228ProbeSuiteSummary =
          pkgs.runCommand "manylinux_2_28-candidate-probe-suite-summary.json"
          {
            nativeBuildInputs = [
              pkgs.python3
            ];
          }
          ''
            python ${./scripts/probe_suite_summary.py} \
              --target manylinux_2_28_x86_64 \
              --reports ${lib.concatStringsSep " " (map (name: "${candidate228Probes.${name}.showReport}/report.txt") modernProbeNames)} \
              --output "$out"
          '';
        candidate234ProbeSuiteSummary =
          pkgs.runCommand "manylinux_2_34-candidate-probe-suite-summary.json"
          {
            nativeBuildInputs = [
              pkgs.python3
            ];
          }
          ''
            python ${./scripts/probe_suite_summary.py} \
              --target manylinux_2_34_x86_64 \
              --reports ${lib.concatStringsSep " " (map (name: "${candidate234Probes.${name}.showReport}/report.txt") modernProbeNames)} \
              --output "$out"
          '';
        candidate2014ProbeSuiteSummary =
          pkgs.runCommand "manylinux2014-candidate-probe-suite-summary.json"
          {
            nativeBuildInputs = [
              pkgs.python3
            ];
          }
          ''
            python ${./scripts/probe_suite_summary.py} \
              --target manylinux_2_17_x86_64 \
              --reports ${lib.concatStringsSep " " (map (name: "${candidate2014Probes.${name}.showReport}/report.txt") legacy2014ProbeNames)} \
              --output "$out"
          '';

        showCandidateProbeSuiteApp = pkgs.writeShellApplication {
          name = "show-manylinux-2_28-candidate-probe-suite";
          text = ''
            cat ${candidate228ProbeSuiteSummary}
          '';
        };
        showCandidate234ProbeSuiteApp = pkgs.writeShellApplication {
          name = "show-manylinux-2_34-candidate-probe-suite";
          text = ''
            cat ${candidate234ProbeSuiteSummary}
          '';
        };
        showCandidate2014ProbeSuiteApp = pkgs.writeShellApplication {
          name = "show-manylinux2014-candidate-probe-suite";
          text = ''
            cat ${candidate2014ProbeSuiteSummary}
          '';
        };
      in {
        packages =
          {
            targets-json = showTargetsJson;
            policy-targets-json = showPolicyTargetsJson;
            conformance-summary-json = showConformanceJson;
            manylinux_2_28-candidate-probe-suite-summary = candidate228ProbeSuiteSummary;
            manylinux_2_34-candidate-probe-suite-summary = candidate234ProbeSuiteSummary;
            manylinux2014-candidate-probe-suite-summary = candidate2014ProbeSuiteSummary;
          }
          // buildEnvPackages
          // buildEnvReports
          // probePackages;

        checks =
          floorChecks
          // conformanceChecks
          // {
            manylinux_2_28_candidate-probe-suite = candidate228ProbeSuiteSummary;
            manylinux_2_34_candidate-probe-suite = candidate234ProbeSuiteSummary;
            manylinux2014_candidate-probe-suite = candidate2014ProbeSuiteSummary;
          };

        apps = {
          default = {
            type = "app";
            program = "${showPolicyTargetsApp}/bin/show-manylinux-policy-targets";
          };
          show-targets = {
            type = "app";
            program = "${showTargetsApp}/bin/show-manylinux-probe-targets";
          };
          show-policy-targets = {
            type = "app";
            program = "${showPolicyTargetsApp}/bin/show-manylinux-policy-targets";
          };
          show-conformance = {
            type = "app";
            program = "${showConformanceApp}/bin/show-manylinux-conformance";
          };
          show-manylinux_2_28-candidate-probe-suite = {
            type = "app";
            program = "${showCandidateProbeSuiteApp}/bin/show-manylinux-2_28-candidate-probe-suite";
          };
          show-manylinux_2_34-candidate-probe-suite = {
            type = "app";
            program = "${showCandidate234ProbeSuiteApp}/bin/show-manylinux-2_34-candidate-probe-suite";
          };
          show-manylinux2014-candidate-probe-suite = {
            type = "app";
            program = "${showCandidate2014ProbeSuiteApp}/bin/show-manylinux2014-candidate-probe-suite";
          };
        };

        devShells =
          {
            default = pkgs.mkShell {
              packages = [
                pkgs.jq
                pkgs.python3
              ];
            };
          }
          // builtins.listToAttrs (
            map (targetName: {
              name = targetName;
              value = buildEnvs.${targetName}.shell;
            })
            buildEnvNames
          );

        formatter = pkgs.alejandra;
      };
    };
}
