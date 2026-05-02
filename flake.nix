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

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      flake.lib = {
        mkManylinuxWheel = import ./nix/lib/mk-manylinux-wheel.nix;
      };

      perSystem = {
        system,
        pkgs,
        ...
      }: let
        outputs = pkgs.callPackage ./nix/outputs.nix {
          inherit inputs system;
        };
      in {
        inherit
          (outputs)
          apps
          checks
          devShells
          packages
          ;

        formatter = pkgs.alejandra;
      };
    };
}
