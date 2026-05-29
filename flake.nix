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
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.5.12/omp-linux-x64";
              sha256 = "sha256-feKqv68rm7G8TQCngBUYUbqZgkXJnsS2AcRRGsHqsr0=";
            };
            "aarch64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.5.12/omp-linux-arm64";
              sha256 = "sha256-a+i0EWKu9bEm7ogKsLeoGS4YCdTVMVV/ybD3gCHR5ok=";
            };
            "x86_64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.5.12/omp-darwin-x64";
              sha256 = "sha256-7BAlLx+mjnVE2VxW04S/Oy5ckZZLsh8Q4RxI0oEIQ0E=";
            };
            "aarch64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v15.5.12/omp-darwin-arm64";
              sha256 = "sha256-BZHsn+Wp0qVnVShean/1T+xGsVXWdZsFpPLYtFLq+zw=";
            };
          };
          srcInfo = sources.${system} or (throw "Unsupported system: ${system}");
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "oh-my-pi";
            version = "15.5.12";

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
