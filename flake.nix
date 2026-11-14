{
  description = "framework-fingerprint-led-blink for NixOS - blink the Framework power-button LED while fprintd waits for a finger";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    upstream = {
      url = "github:alejandroqh/framework-fingerprint-led-blink";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      upstream,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # tracks upstream main, not its v* tags
      d = upstream.lastModifiedDate;
      version = "0-unstable-${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
      srcArgs = {
        src = upstream;
        inherit version;
      };
    in
    {
      # adds pkgs.framework-fingerprint-led-blink; uses the consumer's nixpkgs
      overlays.default = final: _prev: {
        framework-fingerprint-led-blink = final.callPackage ./package.nix srcArgs;
      };

      packages = forAllSystems (
        pkgs:
        let
          drv = pkgs.callPackage ./package.nix srcArgs;
        in
        {
          framework-fingerprint-led-blink = drv;
          default = drv;
        }
      );

      # services.framework-fingerprint-led-blink.*
      nixosModules.default = import ./module.nix srcArgs;

      # `nix flake check`: package with default and non-default tunables, plus
      # the unit file the module renders (cheap - no full system build)
      checks = forAllSystems (
        pkgs:
        let
          inherit (pkgs.stdenv.hostPlatform) system;
          drv = self.packages.${system}.default;
          eval = nixpkgs.lib.nixosSystem {
            modules = [
              self.nixosModules.default
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.05";
                services.framework-fingerprint-led-blink = {
                  enable = true;
                  onSeconds = 0.1;
                  maxBlinkSeconds = 30;
                };
              }
            ];
          };
        in
        {
          default = drv;
          tuned = drv.override {
            led = "chromeos:multicolor:charging";
            onSeconds = 0.1;
            offSeconds = 0.4;
            maxBlinkSeconds = 30;
          };
          module = eval.config.systemd.units."framework-fingerprint-led-blink.service".unit;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
