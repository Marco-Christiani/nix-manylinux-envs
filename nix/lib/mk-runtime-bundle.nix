{
  lib,
  pkgs,
}: let
  createLibraryBundle = name: libraryProviders: sonames: let
    libDirs =
      lib.unique
      (map (soname: "${lib.getLib libraryProviders.${soname}}/lib") sonames);
  in
    pkgs.runCommand name {} ''
      mkdir -p "$out/lib"
      for dir in ${lib.concatStringsSep " " libDirs}; do
        if [ -d "$dir" ]; then
          find "$dir" -maxdepth 1 -type f,l | while read -r candidate; do
            base=$(basename "$candidate")
            case " ${lib.concatStringsSep " " sonames} " in
              *" $base "*)
                if [ ! -e "$out/lib/$base" ]; then
                  ln -s "$candidate" "$out/lib/$base"
                fi
                ;;
            esac
          done
        fi
      done
    '';

  createLibraryBundleFromPaths = name: libraryPaths: sonames: let
    selectedPaths = map (soname: libraryPaths.${soname}) sonames;
  in
    pkgs.runCommand name {} ''
      mkdir -p "$out/lib"
      for path in ${lib.concatStringsSep " " selectedPaths}; do
        base=$(basename "$path")
        ln -s "$path" "$out/lib/$base"
      done
    '';
in {
  inherit createLibraryBundle createLibraryBundleFromPaths;
}
