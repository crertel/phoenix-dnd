{
  description = "Development environment for a Phoenix LiveView drag-and-drop component";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Unlike bare nixfmt, this traverses the source tree when `nix fmt` is
      # invoked without explicit file arguments.
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          beamPackages = with pkgs.beam; packagesWith interpreters.erlang_28;
        in
        {
          default = pkgs.mkShell {
            packages = [
              beamPackages.erlang
              beamPackages.elixir_1_19
              beamPackages.hex
              beamPackages.rebar3
              pkgs.nodejs_24
              pkgs.git
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.inotify-tools
            ];

            ERL_AFLAGS = "-kernel shell_history enabled";
            ERL_INCLUDE_PATH = "${beamPackages.erlang}/lib/erlang/usr/include";
          };
        }
      );
    };
}
