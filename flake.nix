# Fragile development environment.
# Minimal. Reproducible. The compiler is fixed.

{
  description = "Fragile minimal dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pkgs.zig_0_15   # Zig 0.15.x fixed
        pkgs.wrk        # load testing
        pkgs.netcat     # raw TCP (nc)
        pkgs.jq         # JSON / log processing
      ];
    };
  };
}
