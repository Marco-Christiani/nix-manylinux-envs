{lib}: let
  policyToRustTarget = policy: "x86_64-unknown-linux-gnu.${policy.glibcFloor}";
  policyToPlatformTag = policy: "${policy.policy}_x86_64";

  publicTargetAttrs = target:
    builtins.removeAttrs target [
      "shell"
      "targetShell"
      "runtimeLibs"
      "stdcxxPkgs"
      "policy"
    ];
in {
  inherit policyToRustTarget policyToPlatformTag publicTargetAttrs;

  mkBuildTarget = {
    name,
    buildEnv,
    rustTarget ? policyToRustTarget buildEnv.target,
    ...
  } @ args: let
    inherit (buildEnv) target runtimeLibs;
  in
    {
      inherit name rustTarget runtimeLibs;
      targetAttr = name;
      targetShell = buildEnv.shell;
      policyName = target.policy;
      platformTag = policyToPlatformTag target;
      inherit (target) glibcFloor;
      policy = target;
    }
    // (builtins.removeAttrs args [
      "name"
      "buildEnv"
      "rustTarget"
    ]);

  mkBuildTargets = buildEnvs:
    lib.mapAttrs (
      name: buildEnv: let
        inherit (buildEnv) runtimeLibs;
        inherit (buildEnv) target;
      in {
        inherit name runtimeLibs;
        targetAttr = name;
        targetShell = buildEnv.shell;
        rustTarget = policyToRustTarget target;
        policyName = target.policy;
        platformTag = policyToPlatformTag target;
        inherit (target) glibcFloor;
        policy = target;
      }
    )
    buildEnvs;

  cartesianTargets = axes: f: let
    axisNames = builtins.attrNames axes;
    go = index: acc:
      if index == builtins.length axisNames
      then [acc]
      else let
        axisName = builtins.elemAt axisNames index;
        axisValues = axes.${axisName};
      in
        lib.concatMap (
          valueName:
            go (index + 1) (
              acc
              // {
                ${axisName} =
                  axisValues.${valueName}
                  // {
                    name = valueName;
                  };
              }
            )
        )
        (builtins.attrNames axisValues);
  in
    builtins.listToAttrs (
      map f (go 0 {})
    );

  toGithubActionsMatrix = targets:
    map (
      name:
        publicTargetAttrs (
          targets.${name}
          // {
            inherit name;
          }
        )
    )
    (builtins.attrNames targets);
}
