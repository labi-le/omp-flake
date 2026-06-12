{
  description = "Oh My Pi flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
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
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          sources = {
            "x86_64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.12.3/omp-linux-x64";
              sha256 = "sha256-UJS7H7fkBtiRNuSUSN6Yrp6cBf6xBmo5si00BgLTF90=";
            };
            "aarch64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.12.3/omp-linux-arm64";
              sha256 = "sha256-BjXWjM1P7L4rF1E80wD7gv90qJ+c26WgM8iR9VMFus8=";
            };
            "x86_64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.12.3/omp-darwin-x64";
              sha256 = "sha256-l2PWzE2CrGeOttPwLA3qZsh30AUCWhOhiEIrtydH4ao=";
            };
            "aarch64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.12.3/omp-darwin-arm64";
              sha256 = "sha256-P3V1TYNK+q/xf3lLD2XYVjQ11m9XxkXOEuP1J08V7Xg=";
            };
          };
          srcInfo = sources.${system} or (throw "Unsupported system: ${system}");
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "oh-my-pi";
            version = "15.12.3";

            src = pkgs.fetchurl {
              inherit (srcInfo) url sha256;
            };

            dontUnpack = true;

            nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.autoPatchelfHook
              pkgs.patchelf
            ];

            buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.stdenv.cc.cc.lib
              pkgs.openssl
              pkgs.zlib
            ];

            installPhase = ''
              install -Dm755 "$src" "$out/bin/omp"
            '';

            doInstallCheck = pkgs.stdenv.isLinux;
            installCheckPhase = ''
              patchelf --print-interpreter "$out/bin/omp" >/dev/null
              patchelf --print-needed "$out/bin/omp" >/dev/null
            '';

            meta = {
              mainProgram = "omp";
              homepage = "https://github.com/can1357/oh-my-pi";
              description = "Oh My Pi";
            };
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/omp";
        };
      });

      homeManagerModules = {
        default = { config, lib, pkgs, ... }:
          let
            cfg = config.programs.oh-my-pi;
          in
          {
            options.programs.oh-my-pi = {
              enable = lib.mkEnableOption "oh-my-pi";
              package = lib.mkOption {
                type = lib.types.package;
                default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
                description = "oh-my-pi package to install.";
              };
            };

            config = lib.mkIf cfg.enable {
              home.packages = [ cfg.package ];
            };
          };
      };
    };
}
