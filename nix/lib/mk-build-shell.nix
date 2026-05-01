{pkgs}: {
  name,
  packages,
  env ? {},
  shellHook ? "",
}:
pkgs.mkShellNoCC {
  inherit name packages env shellHook;
}
