{
  description = "Oh My Pi flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      in
      {
        packages.default = self.packages.${system}.omp;
        packages.omp = pkgs.stdenv.mkDerivation {
          pname = "oh-my-pi";
          version = "16.4.0";

          src = let
            sources = {
              "x86_64-linux" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v16.4.0/omp-linux-x64";
                sha256 = "sha256-x6L6MoyWUTHA0O9ioHpP5jMG7Rt6kPu7kkx1YFxo04o=";
              };
              "aarch64-linux" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v16.4.0/omp-linux-arm64";
                sha256 = "sha256-a7jXb6JevqCLLOh6eTh8HdC8v/VWTvW8efJZWocKOmg=";
              };
              "x86_64-darwin" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v16.4.0/omp-darwin-x64";
                sha256 = "sha256-Y8JTn9ACQ0g/E/4Mfbxi9sOCqBOfTel+oQW8HKE9iUs=";
              };
              "aarch64-darwin" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v16.4.0/omp-darwin-arm64";
                sha256 = "sha256-+Y0j4T6O9QQxOScACr4N1kVP6aME90T0DIEw7cqqds0=";
              };
            };
            srcInfo = sources.${system} or (throw "Unsupported system: ${system}");
          in pkgs.fetchurl { inherit (srcInfo) url sha256; };

          dontUnpack = true;

          nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.bash
            pkgs.makeWrapper
            pkgs.patchelf
          ];

          installPhase = let
            libPath = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.glibc pkgs.openssl pkgs.zlib ];
          in if pkgs.stdenv.isLinux then ''
            install -Dm755 "$src" "$out/libexec/omp"
            patchelf --set-interpreter "${pkgs.stdenv.cc.bintools.dynamicLinker}" "$out/libexec/omp"
            makeWrapper "$out/libexec/omp" "$out/bin/omp" --prefix LD_LIBRARY_PATH : "${libPath}"
          '' else ''
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

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.omp}/bin/omp";
        };
      }
    ) // {

      # ── lib utilities ────────────────────────────────────────────────

      lib.mkNpmExtension = { pkgs, url, hash, sourcePath ? "package/dist/extension.js", stripComponents ? 2 }:
        pkgs.runCommand "omp-extension"
          { src = pkgs.fetchurl { inherit url hash; }; } ''
            mkdir -p $out
            tar xf $src --strip-components=${toString stripComponents} -C $out ${sourcePath}
          '';

      # ── Home Manager module ──────────────────────────────────────────

      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.oh-my-pi;

          # ── option types ──────────────────────────────────────────

          nullable = t: lib.types.nullOr t;

          modelRoleType = lib.types.attrsOf lib.types.str;
          enumType = values: nullable (lib.types.enum values);

          # ── config.yml generation helper ──────────────────────────
          buildConfigAttrs =
            let
              extensions' = cfg.extensions
                ++ map (plugin:
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
                      root=$(ls -d $src/*/ 2>/dev/null | head -1)
                      test -f $root/dist/extension.js && cp $root/dist/extension.js $out/extension.js
                      test -f $root/dist/extension.ts && cp $root/dist/extension.ts $out/extension.js
                      test -f $root/extension.js    && cp $root/extension.js    $out/extension.js
                      test -f $root/extension.ts    && cp $root/extension.ts    $out/extension.js
                      test -f $out/extension.js || { echo "No extension found" >&2; exit 1; }
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
                      cp $src/dist/extension.js $out/extension.js
                    ''}/extension.js"
                ) cfg.plugins;

              modelRoles =
                lib.optionalAttrs (cfg.models.default != null) { default = cfg.models.default; }
                // cfg.models.roles;

              toolsBlock = lib.filterAttrs (_: v: v != null && v != { }) {
                approvalMode = cfg.tools.approvalMode;
                approval = cfg.tools.approval;
                discoveryMode = cfg.tools.discoveryMode;
                intentTracing = cfg.tools.intentTracing;
                maxTimeout = cfg.tools.maxTimeout;
              };

              taskBlock =
                lib.filterAttrs (_: v: v != null) {
                  isolation = lib.optionalAttrs (cfg.task.isolation != null) { enabled = cfg.task.isolation; };
                  maxConcurrency = cfg.task.maxConcurrency;
                };

              themeBlock = lib.filterAttrs (_: v: v != null) { dark = cfg.theme.dark; light = cfg.theme.light; };
              memoryBlock = lib.filterAttrs (_: v: v != null) { backend = cfg.memory.backend; };
              compactionBlock = lib.filterAttrs (_: v: v != null) { enabled = cfg.compaction.enabled; };

            in
              lib.optionalAttrs (extensions' != [ ]) { extensions = extensions'; }
              // lib.optionalAttrs (cfg.disabledExtensions != [ ]) { inherit (cfg) disabledExtensions; }
              // lib.optionalAttrs (modelRoles != { }) { inherit modelRoles; }
              // lib.optionalAttrs (cfg.models.cycleOrder != [ ]) { cycleOrder = cfg.models.cycleOrder; }
              // lib.optionalAttrs (cfg.models.providerOrder != [ ]) { modelProviderOrder = cfg.models.providerOrder; }
              // lib.optionalAttrs (cfg.models.enabled != [ ]) { enabledModels = cfg.models.enabled; }
              // lib.optionalAttrs (cfg.models.disabledProviders != [ ]) { inherit (cfg.models) disabledProviders; }
              // lib.optionalAttrs (toolsBlock != { }) { tools = toolsBlock; }
              // lib.optionalAttrs (taskBlock != { }) { task = taskBlock; }
              // lib.optionalAttrs (cfg.symbolPreset != null) { inherit (cfg) symbolPreset; }
              // lib.optionalAttrs (cfg.npmCommand != null) { inherit (cfg) npmCommand; }
              // lib.optionalAttrs (themeBlock != { }) { theme = themeBlock; }
              // lib.optionalAttrs (compactionBlock != { }) { compaction = compactionBlock; }
              // lib.optionalAttrs (cfg.defaultThinkingLevel != null) { inherit (cfg) defaultThinkingLevel; }
              // lib.optionalAttrs (memoryBlock != { }) { memory = memoryBlock; }
              // { setupVersion = 1; }
              // cfg.settings;

        in
        {
          options.programs.oh-my-pi = {

            enable = lib.mkEnableOption "oh-my-pi";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.omp;
              description = "oh-my-pi package to install.";
            };

            # ── Agents ────────────────────────────────────────────────

            agents = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule {
                options = {
                  source = lib.mkOption {
                    type = nullable lib.types.path;
                    default = null;
                    description = "Path to a markdown agent file to install.";
                  };
                  text = lib.mkOption {
                    type = nullable lib.types.lines;
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
              description = "Agent .md files installed to ~/.omp/agents/agent/.";
            };

            # ── Extensions ────────────────────────────────────────────

            plugins = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extensions to install: npm name or github:owner/repo[#ref].";
            };

            extensions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extension paths registered in config.yml.";
            };

            disabledExtensions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extension module names to disable.";
            };

            # ── Models ────────────────────────────────────────────────

            models = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  default = lib.mkOption {
                    type = nullable lib.types.str;
                    default = null;
                    description = "Default model ID → modelRoles.default.";
                  };
                  roles = lib.mkOption {
                    type = modelRoleType;
                    default = { };
                    description = "modelRoles: { smol, slow, vision, plan, advisor, … }";
                  };
                  cycleOrder = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Model role cycle order for /cycle.";
                  };
                  providerOrder = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Provider preference order.";
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
              description = "Model selection and roles (→ config.yml).";
            };

            # ── Tools ─────────────────────────────────────────────────

            tools = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  approvalMode = lib.mkOption {
                    type = enumType [ "default" "yolo" "prompt" "write" ];
                    default = null;
                    description = "Tool approval mode.";
                  };
                  approval = lib.mkOption {
                    type = lib.types.attrsOf (lib.types.enum [ "allow" "prompt" "deny" ]);
                    default = { };
                    description = "Per-tool approval: { bash = \"prompt\"; edit = \"allow\"; }";
                  };
                  discoveryMode = lib.mkOption {
                    type = nullable lib.types.str;
                    default = null;
                    description = "Tool discovery mode.";
                  };
                  intentTracing = lib.mkOption {
                    type = nullable lib.types.bool;
                    default = null;
                    description = "Enable intent tracing.";
                  };
                  maxTimeout = lib.mkOption {
                    type = nullable lib.types.int;
                    default = null;
                    description = "Maximum tool timeout (ms).";
                  };
                };
              };
              default = { };
              description = "Tool execution and approval (→ config.yml).";
            };

            # ── Task ──────────────────────────────────────────────────

            task = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  isolation = lib.mkOption {
                    type = nullable lib.types.bool;
                    default = null;
                    description = "Enable isolated git worktrees for subagents.";
                  };
                  maxConcurrency = lib.mkOption {
                    type = nullable lib.types.int;
                    default = null;
                    description = "Maximum concurrent subagent tasks (default: 32).";
                  };
                };
              };
              default = { };
              description = "Task/subagent configuration (→ config.yml).";
            };

            # ── Theme ─────────────────────────────────────────────────

            theme = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  dark = lib.mkOption {
                    type = nullable lib.types.str;
                    default = null;
                    description = "Dark theme name.";
                  };
                  light = lib.mkOption {
                    type = nullable lib.types.str;
                    default = null;
                    description = "Light theme name.";
                  };
                };
              };
              default = { };
              description = "Theme configuration (→ config.yml theme.dark/theme.light).";
            };

            # ── Memory ────────────────────────────────────────────────

            memory = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  backend = lib.mkOption {
                    type = nullable lib.types.str;
                    default = null;
                    description = "Memory backend (e.g. \"mnemopi\").";
                  };
                };
              };
              default = { };
              description = "Memory configuration (→ config.yml).";
            };

            # ── Compaction ────────────────────────────────────────────

            compaction = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enabled = lib.mkOption {
                    type = nullable lib.types.bool;
                    default = null;
                    description = "Enable context compaction.";
                  };
                };
              };
              default = { };
              description = "Compaction settings (→ config.yml).";
            };

            # ── Singleton options ─────────────────────────────────────

            symbolPreset = lib.mkOption {
              type = enumType [ "unicode" "nerd" "ascii" ];
              default = null;
              description = "Glyph set for icons/symbols.";
            };

            npmCommand = lib.mkOption {
              type = nullable (lib.types.listOf lib.types.str);
              default = null;
              description = "npm command array for package management.";
            };

            defaultThinkingLevel = lib.mkOption {
              type = nullable lib.types.str;
              default = null;
              description = "Default thinking level.";
            };

            # ── Providers (models.yml) ──────────────────────────────

            providers = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = "Custom provider definitions → ~/.omp/agent/models.yml.";
            };

            # ── Escape hatch ──────────────────────────────────────────

            settings = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = "Extra config.yml keys. Merged last, can override anything above.";
            };

            extraPackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ pkgs.git pkgs.gh ];
              description = "Packages installed alongside omp (available to shell tools, bash, eval, etc.).";
            };

          };

          # ── config generation ──────────────────────────────────────

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ] ++ cfg.extraPackages;

            home.file = lib.mkMerge [
              # Agents
              (lib.mapAttrs'
                (name: agentCfg:
                  lib.nameValuePair ".omp/agents/agent/${name}" ({
                    inherit (agentCfg) executable;
                  } // lib.optionalAttrs (agentCfg.source != null) { source = agentCfg.source; }
                    // lib.optionalAttrs (agentCfg.text != null) { text = agentCfg.text; }))
                cfg.agents)

              # config.yml — always written when enabled so omp skips setup wizard
              {
                ".omp/agent/config.yml".text = builtins.toJSON buildConfigAttrs;
              }

              # models.yml
              (lib.mkIf (cfg.providers != { }) {
                ".omp/agent/models.yml".text = builtins.toJSON { providers = cfg.providers; };
              })
            ];

            assertions = [
              {
                assertion = lib.all
                  (agentCfg: (agentCfg.source == null) != (agentCfg.text == null))
                  (lib.attrValues cfg.agents);
                message = "Each programs.oh-my-pi.agents.<name> needs exactly one of source or text.";
              }
              {
                assertion = lib.all (name: lib.hasSuffix ".md" name) (lib.attrNames cfg.agents);
                message = "Each programs.oh-my-pi.agents.<name> must end with .md.";
              }
            ];
          };
        };

      # ── flake checks (tests) ────────────────────────────────────────

      checks = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
          lib = pkgs.lib;

          # Evaluate HM module with given config, return final home.file contents
          evalModule = ompConfig:
            let
              result = lib.evalModules {
                modules = [
                  self.homeManagerModules.default
                  { programs.oh-my-pi = ompConfig; }
                  {
                    _module.check = false;
                    home.homeDirectory = "/home/test";
                    home.username = "test";
                    home.stateVersion = "25.05";
                  }
                ];
              };
            in
              # Force evaluation, extract config
              builtins.deepSeq result.config.home.file result.config.home.file;

          files = evalModule {
            enable = true;
            plugins = [ "@baylarsadigov/omp-undo-redo" ];
            extensions = [ "/some/ext.js" ];
            disabledExtensions = [ "extension-module:bad-ext" ];
            models = {
              default = "claude-sonnet-4-5";
              roles.smol = "openai/gpt-4.1-mini";
              cycleOrder = [ "smol" "default" ];
              providerOrder = [ "anthropic" "openai" ];
              enabled = [ "claude-sonnet-4-5" ];
            };
            tools = {
              approvalMode = "write";
              approval.bash = "prompt";
              approval.read = "allow";
              intentTracing = true;
              maxTimeout = 120000;
            };
            task = {
              isolation = true;
              maxConcurrency = 16;
            };
            theme.dark = "titanium";
            symbolPreset = "nerd";
            npmCommand = [ "/bin/npm" ];
            compaction.enabled = true;
            defaultThinkingLevel = "medium";
            memory.backend = "mnemopi";
            providers = {
              aigate = {
                baseUrl = "https://api.aigate.dev/v1";
                api = "openai-completions";
                apiKey = "AIGATE_API_KEY";
                models = [{
                  id = "deepseek-v4-pro";
                  name = "DeepSeek V4 Pro";
                  contextWindow = 200000;
                  maxTokens = 8192;
                }];
              };
            };
            settings = {
              extraCustomKey = "yes";
            };
            agents."my-agent.md".text = "Hello";
          };

          configYml = builtins.fromJSON files.".omp/agent/config.yml".text;
          modelsYml = builtins.fromJSON files.".omp/agent/models.yml".text;

          check = name: cond: if cond then pkgs.runCommand "test-${name}" { } "mkdir $out" else throw "TEST FAILED: ${name}";

        in
        {
          "omp-config-extensions" = check "extensions" (
            lib.elem "/some/ext.js" configYml.extensions
          );

          "omp-config-disabledExtensions" = check "disabledExtensions" (
            lib.elem "extension-module:bad-ext" configYml.disabledExtensions
          );

          "omp-config-modelRoles" = check "modelRoles" (
            configYml.modelRoles.default == "claude-sonnet-4-5"
            && configYml.modelRoles.smol == "openai/gpt-4.1-mini"
          );

          "omp-config-cycleOrder" = check "cycleOrder" (
            configYml.cycleOrder == [ "smol" "default" ]
          );

          "omp-config-modelProviderOrder" = check "modelProviderOrder" (
            configYml.modelProviderOrder == [ "anthropic" "openai" ]
          );

          "omp-config-enabledModels" = check "enabledModels" (
            lib.elem "claude-sonnet-4-5" configYml.enabledModels
          );

          "omp-config-tools-approvalMode" = check "tools.approvalMode" (
            configYml.tools.approvalMode == "write"
          );

          "omp-config-tools-approval-bash" = check "tools.approval.bash" (
            configYml.tools.approval.bash == "prompt"
          );

          "omp-config-tools-intentTracing" = check "tools.intentTracing" (
            configYml.tools.intentTracing == true
          );

          "omp-config-tools-maxTimeout" = check "tools.maxTimeout" (
            configYml.tools.maxTimeout == 120000
          );

          "omp-config-task-isolation" = check "task.isolation" (
            configYml.task.isolation.enabled == true
          );

          "omp-config-task-maxConcurrency" = check "task.maxConcurrency" (
            configYml.task.maxConcurrency == 16
          );

          "omp-config-theme" = check "theme" (
            configYml.theme.dark == "titanium"
          );

          "omp-config-compaction" = check "compaction" (
            configYml.compaction.enabled == true
          );

          "omp-config-defaultThinkingLevel" = check "defaultThinkingLevel" (
            configYml.defaultThinkingLevel == "medium"
          );

          "omp-config-memory" = check "memory" (
            configYml.memory.backend == "mnemopi"
          );

          "omp-config-symbolPreset" = check "symbolPreset" (
            configYml.symbolPreset == "nerd"
          );

          "omp-config-npmCommand" = check "npmCommand" (
            configYml.npmCommand == [ "/bin/npm" ]
          );

          "omp-config-settings-merge" = check "settings" (
            configYml.extraCustomKey == "yes"
          );

          "omp-models-yml-has-aigate" = check "models.yml.aigate" (
            modelsYml.providers.aigate.baseUrl == "https://api.aigate.dev/v1"
          );

          "omp-models-yml-model" = check "models.yml.model" (
            (builtins.elemAt modelsYml.providers.aigate.models 0).id == "deepseek-v4-pro"
          );

          "omp-models-yml-model-contextWindow" = check "models.yml.contextWindow" (
            (builtins.elemAt modelsYml.providers.aigate.models 0).contextWindow == 200000
          );

          "omp-agents-file" = check "agents" (
            files.".omp/agents/agent/my-agent.md".text == "Hello"
          );
        }
      );
    };
}
