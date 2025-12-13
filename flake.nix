{
  description = "FlashProfile - Syntactic profiling with Zig acceleration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            beam.packages.erlang_28.elixir_1_19
            beam.packages.erlang_28.erlang
            zig
            gnumake
            gcc
          ];

          shellHook = ''
            echo "FlashProfile dev environment"
            echo "Elixir: $(elixir --version | head -1)"
            echo "Zig: $(zig version)"
          '';
        };
      }
    );
}
