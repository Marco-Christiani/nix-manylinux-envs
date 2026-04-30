{
  manylinux2014 = {
    policy = "manylinux_2_17";
    aliases = ["manylinux2014"];
    glibcFloor = "2.17";
    preferredCompilerAttr = null;
    officialImageStatus = "supported";
    officialBaseDistro = "CentOS 7";
    officialToolchain = "GCC 10";
    officialImageArchitectures = ["x86_64" "i686" "aarch64" "ppc64le" "s390x"];
    policyArchitectures = ["x86_64" "i686" "aarch64" "armv7l" "ppc64" "ppc64le" "s390x"];
    notes = "Policy alias for manylinux_2_17. Official image set is narrower than policy arch coverage.";
  };

  manylinux_2_28 = {
    policy = "manylinux_2_28";
    aliases = [];
    glibcFloor = "2.28";
    preferredCompilerAttr = "gcc14Stdenv";
    officialImageStatus = "supported";
    officialBaseDistro = "AlmaLinux 8";
    officialToolchain = "GCC 14";
    officialImageArchitectures = ["x86_64" "i686" "aarch64" "ppc64le" "s390x"];
    policyArchitectures = ["x86_64" "i686" "aarch64" "armv7l" "ppc64le" "s390x"];
    notes = "Good likely first real x86_64 target for Nix-native builder envs.";
  };

  manylinux_2_31 = {
    policy = "manylinux_2_31";
    aliases = [];
    glibcFloor = "2.31";
    preferredCompilerAttr = "gcc9Stdenv";
    officialImageStatus = "supported";
    officialBaseDistro = "Ubuntu 20.04";
    officialToolchain = "GCC 9";
    officialImageArchitectures = ["armv7l"];
    policyArchitectures = ["x86_64" "i686" "aarch64" "armv7l" "ppc64le" "riscv64" "s390x"];
    notes = "Official manylinux project only ships armv7l images for this target.";
  };

  manylinux_2_34 = {
    policy = "manylinux_2_34";
    aliases = [];
    glibcFloor = "2.34";
    preferredCompilerAttr = "gcc14Stdenv";
    officialImageStatus = "alpha";
    officialBaseDistro = "AlmaLinux 9";
    officialToolchain = "GCC 14";
    officialImageArchitectures = ["x86_64" "i686" "aarch64" "ppc64le" "s390x"];
    policyArchitectures = ["x86_64" "i686" "aarch64" "armv7l" "ppc64le" "riscv64" "s390x"];
    notes = "RHEL 9 derivatives default to x86-64-v2 on x86_64; upstream documents this as a caveat.";
  };

  manylinux_2_35 = {
    policy = "manylinux_2_35";
    aliases = [];
    glibcFloor = "2.35";
    preferredCompilerAttr = "gcc11Stdenv";
    officialImageStatus = "supported";
    officialBaseDistro = "Ubuntu 22.04";
    officialToolchain = "GCC 11";
    officialImageArchitectures = ["armv7l"];
    policyArchitectures = ["x86_64" "i686" "aarch64" "armv7l" "ppc64le" "riscv64" "s390x"];
    notes = "Official manylinux project only ships armv7l images for this target.";
  };

  manylinux_2_39 = {
    policy = "manylinux_2_39";
    aliases = [];
    glibcFloor = "2.39";
    preferredCompilerAttr = "gcc14Stdenv";
    officialImageStatus = "alpha";
    officialBaseDistro = "AlmaLinux 10 / RockyLinux 10";
    officialToolchain = "GCC 14";
    officialImageArchitectures = ["aarch64" "riscv64"];
    policyArchitectures = ["x86_64" "i686" "aarch64" "armv7l" "loongarch64" "ppc64le" "riscv64" "s390x"];
    notes = "Official image coverage is intentionally narrow so far.";
  };
}
