{
  inputs,
  system,
}: let
  mkTarget = {
    name,
    nixpkgsInput,
    nixpkgsRef,
    compilerPkgsInput ? null,
    compilerRef ? null,
    compilerStdenvAttr ? null,
    stdcxxPkgsInput ? null,
    stdcxxRef ? null,
    expectedGlibc ? null,
    notes ? "",
    pythonAttr ? "python3",
  }: {
    inherit
      name
      nixpkgsRef
      compilerRef
      compilerStdenvAttr
      stdcxxRef
      expectedGlibc
      notes
      pythonAttr
      ;
    pkgs = import nixpkgsInput.outPath {inherit system;};
    compilerPkgs =
      if compilerPkgsInput == null
      then null
      else import compilerPkgsInput.outPath {inherit system;};
    stdcxxPkgs =
      if stdcxxPkgsInput == null
      then null
      else import stdcxxPkgsInput.outPath {inherit system;};
  };
in {
  nixos-19_09 = mkTarget {
    name = "nixos-19_09";
    nixpkgsInput = inputs.nixpkgs-19_09;
    nixpkgsRef = "nixos-19.09";
    expectedGlibc = "2.27";
    notes = "Pre-20.x baseline candidate for 2.2x manylinux-style experiments.";
  };

  nixos-20_03 = mkTarget {
    name = "nixos-20_03";
    nixpkgsInput = inputs.nixpkgs-20_03;
    nixpkgsRef = "nixos-20.03";
    expectedGlibc = "2.30";
    notes = "Oldest flake-friendly release line in this first pass.";
  };

  nixos-20_03-gcc8_19_09 = mkTarget {
    name = "nixos-20_03-gcc8_19_09";
    nixpkgsInput = inputs.nixpkgs-20_03;
    nixpkgsRef = "nixos-20.03";
    compilerPkgsInput = inputs.nixpkgs-19_09;
    compilerRef = "nixos-19.09";
    expectedGlibc = "2.30";
    notes = "Mixed candidate: 20.03 runtime baseline with 19.09-era GCC 8 compiler/runtime.";
  };

  nixos-20_03-stdcxx19_09 = mkTarget {
    name = "nixos-20_03-stdcxx19_09";
    nixpkgsInput = inputs.nixpkgs-20_03;
    nixpkgsRef = "nixos-20.03";
    stdcxxPkgsInput = inputs.nixpkgs-19_09;
    stdcxxRef = "nixos-19.09";
    expectedGlibc = "2.30";
    notes = "Mixed candidate: 20.03 runtime baseline with 19.09-era libstdc++/libgcc runtime.";
  };

  nixos-20_03-stdcxx19_03 = mkTarget {
    name = "nixos-20_03-stdcxx19_03";
    nixpkgsInput = inputs.nixpkgs-20_03;
    nixpkgsRef = "nixos-20.03";
    stdcxxPkgsInput = inputs.nixpkgs-19_03;
    stdcxxRef = "nixos-19.03";
    expectedGlibc = "2.30";
    notes = "Mixed candidate: 20.03 runtime baseline with 19.03-era libstdc++/libgcc runtime.";
  };

  nixos-20_03-gcc14-stdcxx19_09 = mkTarget {
    name = "nixos-20_03-gcc14-stdcxx19_09";
    nixpkgsInput = inputs.nixpkgs-20_03;
    nixpkgsRef = "nixos-20.03";
    compilerPkgsInput = inputs.nixpkgs;
    compilerRef = "nixos-unstable";
    compilerStdenvAttr = "gcc14Stdenv";
    stdcxxPkgsInput = inputs.nixpkgs-19_09;
    stdcxxRef = "nixos-19.09";
    expectedGlibc = "2.30";
    notes = "Mixed candidate: 20.03 runtime baseline with modern compiler frontend and 19.09-era libstdc++/libgcc runtime.";
  };

  nixos-20_09 = mkTarget {
    name = "nixos-20_09";
    nixpkgsInput = inputs.nixpkgs-20_09;
    nixpkgsRef = "nixos-20.09";
    expectedGlibc = "2.31";
    notes = "Candidate for early manylinux-style baseline experiments.";
  };

  nixos-20_09-gcc8_19_09 = mkTarget {
    name = "nixos-20_09-gcc8_19_09";
    nixpkgsInput = inputs.nixpkgs-20_09;
    nixpkgsRef = "nixos-20.09";
    compilerPkgsInput = inputs.nixpkgs-19_09;
    compilerRef = "nixos-19.09";
    expectedGlibc = "2.31";
    notes = "Mixed candidate: 20.09 runtime baseline with 19.09-era GCC 8 compiler/runtime.";
  };

  nixos-20_09-stdcxx19_09 = mkTarget {
    name = "nixos-20_09-stdcxx19_09";
    nixpkgsInput = inputs.nixpkgs-20_09;
    nixpkgsRef = "nixos-20.09";
    stdcxxPkgsInput = inputs.nixpkgs-19_09;
    stdcxxRef = "nixos-19.09";
    expectedGlibc = "2.31";
    notes = "Mixed candidate: 20.09 runtime baseline with 19.09-era libstdc++/libgcc runtime.";
  };

  nixos-20_09-stdcxx19_03 = mkTarget {
    name = "nixos-20_09-stdcxx19_03";
    nixpkgsInput = inputs.nixpkgs-20_09;
    nixpkgsRef = "nixos-20.09";
    stdcxxPkgsInput = inputs.nixpkgs-19_03;
    stdcxxRef = "nixos-19.03";
    expectedGlibc = "2.31";
    notes = "Mixed candidate: 20.09 runtime baseline with 19.03-era libstdc++/libgcc runtime.";
  };

  nixos-20_09-gcc14-stdcxx19_09 = mkTarget {
    name = "nixos-20_09-gcc14-stdcxx19_09";
    nixpkgsInput = inputs.nixpkgs-20_09;
    nixpkgsRef = "nixos-20.09";
    compilerPkgsInput = inputs.nixpkgs;
    compilerRef = "nixos-unstable";
    compilerStdenvAttr = "gcc14Stdenv";
    stdcxxPkgsInput = inputs.nixpkgs-19_09;
    stdcxxRef = "nixos-19.09";
    expectedGlibc = "2.31";
    notes = "Mixed candidate: 20.09 runtime baseline with modern compiler frontend and 19.09-era libstdc++/libgcc runtime.";
  };

  nixos-21_05 = mkTarget {
    name = "nixos-21_05";
    nixpkgsInput = inputs.nixpkgs-21_05;
    nixpkgsRef = "nixos-21.05";
    expectedGlibc = "2.32";
    notes = "Intermediate baseline between 20.09 and 22.11.";
  };

  nixos-22_11 = mkTarget {
    name = "nixos-22_11";
    nixpkgsInput = inputs.nixpkgs-22_11;
    nixpkgsRef = "nixos-22.11";
    expectedGlibc = "2.35";
    notes = "Modern-enough baseline with a noticeably older libc/toolchain floor.";
  };

  nixos-24_05 = mkTarget {
    name = "nixos-24_05";
    nixpkgsInput = inputs.nixpkgs-24_05;
    nixpkgsRef = "nixos-24.05";
    expectedGlibc = null;
    notes = "Near-current baseline for comparison against unstable.";
  };

  unstable = mkTarget {
    name = "unstable";
    nixpkgsInput = inputs.nixpkgs;
    nixpkgsRef = "nixos-unstable";
    expectedGlibc = null;
    notes = "Control case matching the current local/default build world.";
  };
}
