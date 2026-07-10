# omp-flake

Nix flake packaging for [Oh My Pi](https://github.com/can1357/oh-my-pi) (`omp`).

## What this flake provides

- A default package (`packages.<system>.default`) that installs the `omp` binary.
- A default app (`apps.<system>.default`) for `nix run`.
- A Home Manager module (`homeManagerModules.default`) exposing `programs.oh-my-pi`, which
  generates `~/.omp/agent/config.yml`, `~/.omp/agent/models.yml`, and installs agent files.

Supported systems: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`.

## Quick start

Run directly, or build the package:

```bash
nix run   github:labi-le/omp-flake
nix build github:labi-le/omp-flake
```

Use in another flake:

```nix
{
  inputs.omp-flake.url = "github:labi-le/omp-flake";

  outputs = { self, nixpkgs, omp-flake, ... }: {
    packages.x86_64-linux.omp = omp-flake.packages.x86_64-linux.default;
  };
}
```

## Home Manager

Import the module and enable it. With `enable = true` the flake always writes a
`config.yml` (including `setupVersion`), so `omp` skips the onboarding wizard on first run.

```nix
{
  imports = [ omp-flake.homeManagerModules.default ];
  programs.oh-my-pi.enable = true;
}
```

### Full example

A representative configuration touching most option groups:

```nix
programs.oh-my-pi = {
  enable = true;

  # Models & roles → config.yml modelRoles / enabledModels / …
  models = {
    default = "anthropic/claude-sonnet-4-5";
    roles = {
      smol    = "openai/gpt-4.1-mini";
      slow    = "openai/gpt-5.5";
      plan    = "anthropic/claude-opus-4-8";
      advisor = "openai-codex/gpt-5.5";
    };
    cycleOrder    = [ "smol" "default" "slow" ];
    providerOrder = [ "anthropic" "openai" ];
    enabled       = [ "anthropic/claude-sonnet-4-5" "openai/gpt-5.5" ];
    disabledProviders = [ "mistral" ];
  };

  # Appearance
  theme = { dark = "titanium"; light = "github-light"; };
  symbolPreset = "nerd";              # "unicode" | "nerd" | "ascii"
  defaultThinkingLevel = "medium";    # minimal | low | medium | high | xhigh

  # Tools & approval
  tools = {
    approvalMode  = "write";          # "default" | "yolo" | "prompt" | "write"
    approval      = { bash = "prompt"; edit = "allow"; };
    intentTracing = true;
    maxTimeout    = 120000;           # ms
  };

  # Subagents
  task = { isolation = true; maxConcurrency = 16; };

  # Memory & context
  memory.backend = "mnemopi";
  compaction.enabled = true;

  # Tools available to omp only (added to home.packages)
  extraPackages = with pkgs; [ jq ripgrep python3 ];
};
```

### Models and roles

Roles route work by intent (`default`, `smol`, `slow`, `plan`, `advisor`, `commit`, `vision`, …).
`models.default` maps to `modelRoles.default`; `models.roles` fills the rest.

```nix
programs.oh-my-pi.models = {
  default = "anthropic/claude-sonnet-4-5";
  roles.smol = "openai/gpt-4.1-mini";
  roles.plan = "anthropic/claude-opus-4-8";
  cycleOrder = [ "smol" "default" ];   # Ctrl+P cycle order
};
```

### Custom providers (models.yml)

`providers` is written verbatim to `~/.omp/agent/models.yml`. Declare anything speaking
`openai-completions`, `openai-responses`, `anthropic-messages`, `google-generative-ai`, etc.
Use an env var **name** for `apiKey` — omp resolves it at runtime; never inline the secret.

```nix
programs.oh-my-pi.providers = {
  aigate = {
    baseUrl = "https://api.aigate.dev/v1";
    api     = "openai-completions";
    apiKey  = "AIGATE_API_KEY";        # name of the env var, not the key itself
    models = [{
      id            = "deepseek-v4-pro";
      name          = "DeepSeek V4 Pro";
      contextWindow = 200000;
      maxTokens     = 8192;
    }];
  };
};
```

### Extensions and plugins

- `plugins` — installed from npm or `github:owner/repo[#ref]`, built at eval time and
  registered automatically.
- `extensions` — extra extension paths to register as-is.
- `disabledExtensions` — extension module names to turn off.

```nix
programs.oh-my-pi = {
  plugins = [
    "@baylarsadigov/omp-undo-redo"      # npm
    "github:someone/omp-ext#main"       # github repo (optional #ref)
  ];
  extensions = [ "/absolute/path/to/extension.js" ];
  disabledExtensions = [ "extension-module:some-builtin" ];
};
```

### Agent files

Installed to `~/.omp/agents/agent/<name>`; each name must end with `.md`, and exactly one of
`text` or `source` is required.

```nix
programs.oh-my-pi.agents = {
  "reviewer.md".text = ''
    # Reviewer
    Focus on correctness, security, and edge cases.
  '';
  "deploy.md" = {
    source = ./agents/deploy.md;
    executable = true;
  };
};
```

### Extra packages for omp

`extraPackages` are added to `home.packages`, so `omp` finds them on `PATH` (for `bash`,
`eval`, shell tools). Defaults to `[ pkgs.git pkgs.gh ]` — the only binaries omp shells out to;
everything else (grep, find, LSP, debug) is built into the binary.

```nix
programs.oh-my-pi.extraPackages = with pkgs; [
  git gh          # defaults — repeat only if adding more
  jq ripgrep fd
  python3 nodejs
];
```

### Escape hatch: `settings`

Only the common options are typed above. Any other `config.yml` key goes through `settings`,
which is merged last and can override anything. Dotted keys are quoted strings.

```nix
programs.oh-my-pi.settings = {
  temperature          = 0.7;
  "providers.webSearch" = "perplexity";
  "lsp.enabled"         = true;
  "startup.checkUpdate" = false;
  "read.summarize.enabled" = true;
};
```

## Options reference

| Option | Type | Notes |
| --- | --- | --- |
| `enable` | bool | Install omp and write `config.yml`. |
| `package` | package | Override the omp package. |
| `agents.<name>` | submodule | `.md` agents → `~/.omp/agents/agent/`; one of `text`/`source`, plus `executable`. |
| `plugins` | list of str | npm names or `github:owner/repo[#ref]`; built and registered. |
| `extensions` | list of str | Extra extension paths for `config.yml`. |
| `disabledExtensions` | list of str | Extension module names to disable. |
| `models.default` | str | → `modelRoles.default`. |
| `models.roles` | attrs | Role → model ID map. |
| `models.cycleOrder` | list of str | Role cycle order. |
| `models.providerOrder` | list of str | Provider preference order. |
| `models.enabled` | list of str | Enabled model IDs. |
| `models.disabledProviders` | list of str | Disabled providers. |
| `tools.approvalMode` | enum | `default` \| `yolo` \| `prompt` \| `write`. |
| `tools.approval` | attrs | Per-tool: `allow` \| `prompt` \| `deny`. |
| `tools.discoveryMode` | str | Tool discovery mode. |
| `tools.intentTracing` | bool | Enable intent tracing. |
| `tools.maxTimeout` | int | Max tool timeout (ms). |
| `task.isolation` | bool | Isolated git worktrees for subagents. |
| `task.maxConcurrency` | int | Max concurrent subagents (default 32). |
| `theme.dark` / `theme.light` | str | Theme names. |
| `symbolPreset` | enum | `unicode` \| `nerd` \| `ascii`. |
| `defaultThinkingLevel` | str | e.g. `minimal`…`xhigh`. |
| `compaction.enabled` | bool | Context compaction. |
| `memory.backend` | str | e.g. `mnemopi`. |
| `npmCommand` | list of str | npm command array. |
| `providers` | attrs | → `~/.omp/agent/models.yml`. |
| `extraPackages` | list of package | Added to `PATH`; default `[ git gh ]`. |
| `settings` | attrs | Any extra `config.yml` key; merged last. |

## Development

Validate flake outputs (also runs the module's config-generation tests):

```bash
nix flake check
```
