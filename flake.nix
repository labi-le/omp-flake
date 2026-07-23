{
  description = "Oh My Pi flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }@inputs:
    let
      # Build config.yml, validating every key against omp's own settings
      # schema (`omp config list --json`). omp silently ignores unknown keys,
      # so a typo would otherwise be a no-op; this fails the build instead.
      # `expectReject` inverts the result for negative tests.
      mkOmpConfig = { pkgs, omp, name ? "omp-config.yml", attrs, expectReject ? false }:
        let
          validatorPy = pkgs.writeText "validate-omp-config.py" ''
            import json, sys

            config = json.load(open(sys.argv[1]))
            meta = json.load(open(sys.argv[2]))
            valid = set(meta)
            records = {k for k, v in meta.items() if v.get("type") == "record"}

            def under_record(path):
                parts = path.split(".")
                return any(".".join(parts[:i]) in records for i in range(1, len(parts)))

            unknown = []

            def walk(obj, prefix=""):
                for k, v in obj.items():
                    path = prefix + "." + k if prefix else k
                    if path in valid or under_record(path):
                        continue
                    if isinstance(v, dict):
                        walk(v, path)
                    else:
                        unknown.append(path)

            if not isinstance(config, dict):
                sys.stderr.write("omp config must be a mapping\n")
                sys.exit(1)

            walk(config)

            if unknown:
                sys.stderr.write("omp-flake: unknown config key(s) not in omp's settings schema:\n")
                for u in sorted(set(unknown)):
                    sys.stderr.write("  - " + u + "\n")
                sys.stderr.write("\nRun `omp config list` for valid keys, or nest it under a valid key.\n")
                sys.exit(1)
          '';
          configFile = pkgs.writeText "${name}.in.json" (builtins.toJSON attrs);
          preamble = ''
            export HOME="$TMPDIR"
            export XDG_CONFIG_HOME="$TMPDIR/.config" XDG_DATA_HOME="$TMPDIR/.local/share"
            export XDG_STATE_HOME="$TMPDIR/.local/state" XDG_CACHE_HOME="$TMPDIR/.cache"
            omp config list --json > valid.json || { echo "omp config list failed" >&2; exit 1; }
          '';
        in
        pkgs.runCommand name { nativeBuildInputs = [ omp pkgs.python3 ]; } (
          if expectReject then ''
            ${preamble}
            if python3 ${validatorPy} ${configFile} valid.json; then
              echo "mkOmpConfig: expected rejection but validation passed" >&2
              exit 1
            fi
            mkdir -p "$out"
          '' else ''
            ${preamble}
            python3 ${validatorPy} ${configFile} valid.json || exit 1
            cp ${configFile} "$out"
          ''
        );
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      in
      {
        packages.default = self.packages.${system}.omp;
        packages.omp = pkgs.stdenv.mkDerivation {
          pname = "oh-my-pi";
          version = "17.0.9";

          src = let
            sources = {
              "x86_64-linux" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v17.0.9/omp-linux-x64";
                sha256 = "sha256-SFzDAdb9/ya6tdOrRasTdjSnO3Gy7XqRxshUWEL/TAk=";
              };
              "aarch64-linux" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v17.0.9/omp-linux-arm64";
                sha256 = "sha256-wpkHIzEH/FeuGPgekYd0MfaSUroHGTa1xmclkthMyYQ=";
              };
              "x86_64-darwin" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v17.0.9/omp-darwin-x64";
                sha256 = "sha256-s/tuo0DV7sM63Nro4emSOSVZnBBoyDpR+ls6At1PLDI=";
              };
              "aarch64-darwin" = {
                url = "https://github.com/can1357/oh-my-pi/releases/download/v17.0.9/omp-darwin-arm64";
                sha256 = "sha256-3RQwukgJpV9Nby9kYhHO5RU1+WGetmcPG/z3SEwjuTE=";
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

      lib.mkOmpConfig = mkOmpConfig;

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
                intentTracing = cfg.tools.intentTracing;
                maxTimeout = cfg.tools.maxTimeout;
              };

              taskBlock =
                let
                  isolationBlock = lib.filterAttrs (_: v: v != null) {
                    mode = cfg.task.isolation.mode;
                    merge = cfg.task.isolation.merge;
                    commits = cfg.task.isolation.commits;
                  };
                in
                lib.filterAttrs (_: v: v != null && v != { }) {
                  isolation = isolationBlock;
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
                    type = lib.types.submodule {
                      options = {
                        mode = lib.mkOption {
                          type = enumType [ "none" "auto" "apfs" "btrfs" "zfs" "reflink" "overlayfs" "projfs" "block-clone" "rcopy" ];
                          default = null;
                          description = "Subagent isolation backend (→ task.isolation.mode).";
                        };
                        merge = lib.mkOption {
                          type = enumType [ "patch" "branch" ];
                          default = null;
                          description = "Isolation merge strategy (→ task.isolation.merge).";
                        };
                        commits = lib.mkOption {
                          type = enumType [ "generic" "ai" ];
                          default = null;
                          description = "Isolation commit attribution (→ task.isolation.commits).";
                        };
                      };
                    };
                    default = { };
                    description = "Subagent isolation settings.";
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

              # config.yml — always written when enabled so omp skips setup
              # wizard. Built through mkOmpConfig so unknown keys (typos in the
              # `settings` escape hatch) fail the build instead of being silently
              # ignored by omp.
              {
                ".omp/agent/config.yml".source = mkOmpConfig {
                  inherit pkgs;
                  omp = cfg.package;
                  name = "omp-config.yml";
                  attrs = buildConfigAttrs;
                };
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

      checks = (flake-utils.lib.eachDefaultSystem (system:
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
                    # Stub the home-manager options the module sets, so evalModules
                    # (without the real HM modules) exposes config.home.file.
                    options = {
                      home.file = lib.mkOption { type = lib.types.attrsOf lib.types.raw; default = { }; };
                      home.packages = lib.mkOption { type = lib.types.listOf lib.types.raw; default = [ ]; };
                      home.homeDirectory = lib.mkOption { type = lib.types.str; default = "/home/test"; };
                      home.username = lib.mkOption { type = lib.types.str; default = "test"; };
                      home.stateVersion = lib.mkOption { type = lib.types.str; default = "25.05"; };
                      assertions = lib.mkOption { type = lib.types.listOf lib.types.raw; default = [ ]; };
                    };
                  }
                  { _module.args.pkgs = pkgs; }
                ];
              };
            in
              result.config.home.file;

          files = evalModule {
            enable = true;
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
              isolation.mode = "auto";
              isolation.merge = "branch";
              maxConcurrency = 16;
            };
            theme.dark = "titanium";
            symbolPreset = "nerd";
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
              autoResume = true;
            };
            agents."my-agent.md".text = "Hello";
          };

          configYml = builtins.fromJSON (builtins.readFile files.".omp/agent/config.yml".source);
          modelsYml = builtins.fromJSON files.".omp/agent/models.yml".text;

          check = name: cond: if cond then pkgs.runCommand "test-${name}" { } "mkdir $out" else throw "TEST FAILED: ${name}";

        in
        { checks = {
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
            configYml.task.isolation.mode == "auto"
            && configYml.task.isolation.merge == "branch"
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

          "omp-config-settings-merge" = check "settings" (
            configYml.autoResume == true
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

          "omp-config-rejects-unknown" = mkOmpConfig {
            inherit pkgs;
            omp = self.packages.${system}.default;
            name = "omp-config-reject-test";
            attrs = { setupVersion = 1; totallyBogusKey = 123; };
            expectReject = true;
          };
        }; }
      )).checks;
    };
}
