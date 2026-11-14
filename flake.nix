{
  description = "Synth for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/ffb3c9b700e759be2ef13237c9d8f953b32a1e46";
    zig = {
      url = "github:mitchellh/zig-overlay/6b5e8a65de00723fae1f3c6d6434469ac754715c";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, zig, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      shell = pkgs.mkShellNoCC {
        packages = [
          zig.packages.${system}."0.16.0"
          pkgs.swiftlint
          pkgs.xcodegen
        ];
      };
    in
    {
      devShells.${system} = {
        default = shell;
        desktop = shell;
      };
    };
}
