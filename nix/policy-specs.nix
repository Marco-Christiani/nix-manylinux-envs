{lib}: let
  rawPolicies = builtins.fromJSON (builtins.readFile ../data/manylinux-policy.json);

  findPolicy = name: let
    matches = lib.filter (policy: policy.name == name || builtins.elem name (policy.aliases or [])) rawPolicies;
  in
    if matches == []
    then throw "No auditwheel policy found for ${name}"
    else lib.head matches;

  mkSpec = policyName: let
    policy = findPolicy policyName;
    x86_64Symbols = policy.symbol_versions.x86_64 or {};
    symbolCeilings = lib.mapAttrs (_: versions:
      if versions == []
      then null
      else lib.last versions)
    x86_64Symbols;
  in {
    inherit (policy) name aliases priority blacklist;
    libWhitelist = policy.lib_whitelist;
    symbolVersions = x86_64Symbols;
    inherit symbolCeilings;
  };
in {
  manylinux2014 = mkSpec "manylinux2014";
  manylinux_2_28 = mkSpec "manylinux_2_28";
  manylinux_2_31 = mkSpec "manylinux_2_31";
  manylinux_2_34 = mkSpec "manylinux_2_34";
  manylinux_2_35 = mkSpec "manylinux_2_35";
  manylinux_2_39 = mkSpec "manylinux_2_39";
}
