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
              url = "https://github.com/can1357/oh-my-pi/releases/download/v16.1.19/omp-linux-x64";
              sha256 = "sha256-nL7lP9OAespK6StzUbYN5KG3agWHbU3Y59vClBbaSt8=";
            };
            "aarch64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v16.1.19/omp-linux-arm64";
              sha256 = "sha256-YYNKFpjqSuDNMROe5KfBvIqB2X1So2KV47XoeBjhCs8=";
            };
            "x86_64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v16.1.19/omp-darwin-x64";
              sha256 = "sha256-ShOZmfS936/1Ktl7+cY9G2P4WauV9hspmHAjepbBJ08=";
            };
            "aarch64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v16.1.19/omp-darwin-arm64";
              sha256 = "sha256-eQySjDVZH4YRz6t74pXOhpwmAkniRWutxMgJsX6tQL4=";
            };
          };
          srcInfo = sources.${system} or (throw "Unsupported system: ${system}");
          linuxLibPath = pkgs.lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.glibc
            pkgs.openssl
            pkgs.zlib
          ];
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "oh-my-pi";
            version = "16.1.19";

            src = pkgs.fetchurl {
              inherit (srcInfo) url sha256;
            };

            dontUnpack = true;

            # Bun-compiled omp binaries on Linux break when auto-patched/stripped by stdenv.
            nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.bash
              pkgs.makeWrapper
              pkgs.patchelf
            ];

            installPhase =
              if pkgs.stdenv.isLinux then
                ''
                  install -Dm755 "$src" "$out/libexec/omp"
                  patchelf --set-interpreter "${pkgs.stdenv.cc.bintools.dynamicLinker}" "$out/libexec/omp"
                  makeWrapper "$out/libexec/omp" "$out/bin/omp" \
                    --prefix LD_LIBRARY_PATH : "${linuxLibPath}"
                ''
              else
                ''
                  install -Dm755 "$src" "$out/bin/omp"
                '';

            dontStrip = pkgs.stdenv.isLinux;
            dontPatchELF = pkgs.stdenv.isLinux;
            doInstallCheck = pkgs.stdenv.isLinux;
            installCheckPhase = ''
              export HOME="$TMPDIR"
              "$out/bin/omp" --version >/dev/null
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

      lib.mkNpmExtension = { pkgs, url, hash, sourcePath ? "package/dist/extension.js", stripComponents ? 2 }:
        pkgs.runCommand "omp-extension"
          {
            src = pkgs.fetchurl { inherit url hash; };
          } ''
            mkdir -p $out
            tar xf $src --strip-components=${toString stripComponents} -C $out ${sourcePath}
          '';

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
              agents = lib.mkOption {
                type = lib.types.attrsOf (lib.types.submodule {
                  options = {
                    source = lib.mkOption {
                      type = lib.types.nullOr lib.types.path;
                      default = null;
                      description = "Path to a markdown agent file to install.";
                    };
                    text = lib.mkOption {
                      type = lib.types.nullOr lib.types.lines;
                      default = null;
                      description = "Inline markdown agent file content to install.";
                    };
                    executable = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Whether the installed agent file should be executable.";
                    };
                  };
                });
                default = { };
                description = "Agent markdown files installed to ~/.omp/agents/agent/, where each attribute name becomes the filename.";
              };

              plugins = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Extensions to install and register.
                  npm package:  "@scope/name" or "name"
                  GitHub repo:  "github:owner/repo" or "github:owner/repo#branch"
                '';
              };

              extensions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Extension paths registered in config.yml.";
              };

              disabledExtensions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Extension module names to disable (e.g. 'extension-module:my-ext').";
              };

              models = lib.mkOption {
                type = lib.types.submodule {
                  options = {
                    default = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Default model ID. Sets modelRoles.default.";
                    };
                    roles = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                      description = "Model role mapping (smol, slow, vision, plan, advisor, …).";
                    };
                    cycleOrder = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      description = "Model role cycle order for /cycle.";
                    };
                    providerOrder = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      description = "Provider preference order (e.g. [\"anthropic\" \"openai\"]).";
                    };
                    enabled = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      description = "Enabled model IDs.";
                    };
                    disabledProviders = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      description = "Disabled provider names.";
                    };
                  };
                };
                default = { };
                description = "Model selection and role configuration.";
              };

              tools = lib.mkOption {
                type = lib.types.submodule {
                  options = {
                    approvalMode = lib.mkOption {
                      type = lib.types.nullOr (lib.types.enum [ "default" "yolo" "prompt" "write" ]);
                      default = null;
                      description = "Tool approval mode.";
                    };
                    approval = lib.mkOption {
                      type = lib.types.attrsOf (lib.types.enum [ "allow" "prompt" "deny" ]);
                      default = { };
                      description = "Per-tool approval overrides (e.g. bash = \"prompt\").";
                    };
                    intentTracing = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      default = null;
                      description = "Enable intent tracing for tools.";
                    };
                    maxTimeout = lib.mkOption {
                      type = lib.types.nullOr lib.types.int;
                      default = null;
                      description = "Maximum tool timeout in milliseconds.";
                    };
                  };
                };
                default = { };
                description = "Tool execution and approval configuration.";
              };

              task = lib.mkOption {
                type = lib.types.submodule {
                  options = {
                    isolation = lib.mkOption {
                      type = lib.types.nullOr lib.types.bool;
                      default = null;
                      description = "Enable isolated git worktrees for subagent tasks.";
                    };
                  };
                };
                default = { };
                description = "Task and subagent configuration.";
              };

              symbolPreset = lib.mkOption {
                type = lib.types.nullOr (lib.types.enum [ "unicode" "nerd" "ascii" ]);
                default = null;
                description = "Glyph set for icons and symbols.";
              };

              npmCommand = lib.mkOption {
                type = lib.types.nullOr (lib.types.listOf lib.types.str);
                default = null;
                description = "npm command array for package management.";
              };

              settings = lib.mkOption {
                type = lib.types.attrs;
                default = { };
                description = "Extra config.yml keys not covered by typed options. Merged last so it can override anything.";
              };
            };

            config = lib.mkIf cfg.enable {
              home.packages = [ cfg.package ];

              home.file = lib.mkMerge [
                (lib.mapAttrs'
                  (name: agentCfg:
                    lib.nameValuePair ".omp/agents/agent/${name}" ({
                      inherit (agentCfg) executable;
                    } // lib.optionalAttrs (agentCfg.source != null) {
                      source = agentCfg.source;
                    } // lib.optionalAttrs (agentCfg.text != null) {
                      text = agentCfg.text;
                    }))
                  cfg.agents)
                (let
                  mkPluginDrv = plugin:
                    if lib.hasPrefix "github:" plugin then
                      let
                        repoRef = lib.removePrefix "github:" plugin;
                        parts = lib.splitString "#" repoRef;
                        repo = builtins.elemAt parts 0;
                        ref = if builtins.length parts > 1 then builtins.elemAt parts 1 else "main";
                        tarball = builtins.fetchTarball "https://github.com/${repo}/archive/${ref}.tar.gz";
                        repoName = builtins.elemAt (lib.splitString "/" repo) 1;
                        src = tarball;
                      in
                      "${pkgs.runCommand "omp-plugin-${repoName}" { inherit src; } ''
                        mkdir -p $out
                        if [ -f $src/dist/extension.js ]; then
                          cp $src/dist/extension.js $out/extension.js
                        elif [ -f $src/dist/extension.ts ]; then
                          cp $src/dist/extension.ts $out/extension.js
                        elif [ -f $src/extension.js ]; then
                          cp $src/extension.js $out/extension.js
                        elif [ -f $src/extension.ts ]; then
                          cp $src/extension.ts $out/extension.js
                        else
                          echo "No extension entry point found in $src" >&2
                          exit 1
                        fi
                      ''}/extension.js"
                    else
                      let
                        metaJson = builtins.readFile (builtins.fetchurl "https://registry.npmjs.org/${plugin}");
                        meta = builtins.fromJSON metaJson;
                        version = meta."dist-tags".latest;
                        tarballUrl = meta.versions.${version}.dist.tarball;
                        plainName = if lib.hasPrefix "@" plugin then
                          let parts = lib.splitString "/" plugin; in builtins.elemAt parts 1
                        else plugin;
                        src = builtins.fetchTarball tarballUrl;
                      in
                      "${pkgs.runCommand "omp-plugin-${plainName}" { inherit src; } ''
                        mkdir -p $out
                        tar xf $src --strip-components=2 -C $out package/dist/extension.js
                      ''}/extension.js";

                  pluginPaths = map mkPluginDrv cfg.plugins;
                  allExtensions = cfg.extensions ++ pluginPaths;
                in
                (lib.mkIf
                  (allExtensions != [ ]
                    || cfg.disabledExtensions != [ ]
                    || cfg.models.default != null || cfg.models.roles != { }
                    || cfg.models.cycleOrder != [ ] || cfg.models.providerOrder != [ ]
                    || cfg.models.enabled != [ ] || cfg.models.disabledProviders != [ ]
                    || cfg.tools.approvalMode != null || cfg.tools.approval != { }
                    || cfg.tools.intentTracing != null || cfg.tools.maxTimeout != null
                    || cfg.task.isolation != null
                    || cfg.symbolPreset != null || cfg.npmCommand != null
                    || cfg.settings != { })
                  {
                    ".omp/agent/config.yml".text =
                    let
                      inherit (cfg) disabledExtensions symbolPreset npmCommand settings;

                      modelRoles =
                        lib.optionalAttrs (cfg.models.default != null) { default = cfg.models.default; }
                        // cfg.models.roles;

                      configAttrs =
                        lib.optionalAttrs (allExtensions != [ ]) { extensions = allExtensions; }
                        // lib.optionalAttrs (disabledExtensions != [ ]) { inherit disabledExtensions; }
                        // lib.optionalAttrs (modelRoles != { }) { inherit modelRoles; }
                        // lib.optionalAttrs (cfg.models.cycleOrder != [ ]) { cycleOrder = cfg.models.cycleOrder; }
                        // lib.optionalAttrs (cfg.models.providerOrder != [ ]) { modelProviderOrder = cfg.models.providerOrder; }
                        // lib.optionalAttrs (cfg.models.enabled != [ ]) { enabledModels = cfg.models.enabled; }
                        // lib.optionalAttrs (cfg.models.disabledProviders != [ ]) { inherit (cfg.models) disabledProviders; }
                        // lib.optionalAttrs (cfg.tools.approvalMode != null || cfg.tools.approval != { } || cfg.tools.intentTracing != null || cfg.tools.maxTimeout != null) {
                          tools =
                            lib.filterAttrs (_: v: v != null && v != { })
                              {
                                approvalMode = cfg.tools.approvalMode;
                                approval = cfg.tools.approval;
                                intentTracing = cfg.tools.intentTracing;
                                maxTimeout = cfg.tools.maxTimeout;
                              };
                        }
                        // lib.optionalAttrs (cfg.task.isolation != null) {
                          task = {
                            isolation = {
                              enabled = cfg.task.isolation;
                            };
                          };
                        }
                        // lib.optionalAttrs (symbolPreset != null) { inherit symbolPreset; }
                        // lib.optionalAttrs (npmCommand != null) { inherit npmCommand; }
                        // settings;
                    in
                    builtins.toJSON configAttrs;
                }))
              ];

              assertions = [
                {
                  assertion = lib.all
                    (agentCfg: (agentCfg.source == null) != (agentCfg.text == null))
                    (lib.attrValues cfg.agents);
                  message = "Each programs.oh-my-pi.agents.<name> must set exactly one of `source` or `text`.";
                }
                {
                  assertion = lib.all (name: lib.hasSuffix ".md" name) (lib.attrNames cfg.agents);
                  message = "Each programs.oh-my-pi.agents.<name> must end with `.md`.";
                }
              ];
            };
          };
      };
    };
}
