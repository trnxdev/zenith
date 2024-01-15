{
  pkgs,
  stdenv,

  glibc,
  zig,
}: let

  zigBuildFlags = "--global-cache-dir $(pwd)/.cache --cache-dir $(pwd)/zig-cache -Dcpu=baseline";

in stdenv.mkDerivation {
  name = "zenith";
  version = "main";

  src = ./..;

  packages = [ zig ];
  buildInputs = [ glibc ];

  dontConfigure = true;
  dontInstall = true;


  buildPhase = ''
    runHook preBuild

    mkdir --parents .cache
    # Uncomment when you actually add a zon.
    # When you do, create build.zig.zon.nix with zon2nix
    # and move it into this directory.
    # ln --symbolic $<delete this too so it evaluates it>{pkgs.callPackage ./build.zig.zon.nix {}} .cache/p

    zig build install        \
      ${zigBuildFlags}       \
      -Doptimize=ReleaseSafe \
      --prefix $out

    runHook postBuild
  '';
}