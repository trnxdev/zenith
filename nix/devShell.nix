
{
  zig,
  zls,
  zon2nix,

  mkShell,
}:

mkShell {
  name = "zenith";

  buildInputs = [
    zig
    zls
    zon2nix
  ];
}