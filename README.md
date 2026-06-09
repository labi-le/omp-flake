# omp-flake

Nix flake packaging for [Oh My Pi](https://github.com/can1357/oh-my-pi).

## What this flake provides

- A default package (`packages.<system>.default`) that installs the `omp` binary.
- A default app (`apps.<system>.default`) for `nix run`.
- A Home Manager module (`homeManagerModules.default`) exposing `programs.oh-my-pi`.

Supported systems:

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

## Usage

Run directly:

```bash
nix run github:cernoh/omp-flake
```

Build package:

```bash
nix build github:cernoh/omp-flake
```

Use in another flake:

```nix
{
  inputs.omp-flake.url = "github:cernoh/omp-flake";

  outputs = { self, nixpkgs, omp-flake, ... }: {
    # Example: expose package
    packages.x86_64-linux.omp = omp-flake.packages.x86_64-linux.default;
  };
}
```

Home Manager module example:

```nix
{
  imports = [ omp-flake.homeManagerModules.default ];

  programs.oh-my-pi = {
    enable = true;
    agents = {
      "my-agent.lua".text = ''
        -- agent content
      '';
    };
  };
}
```

Available Home Manager options:

- `programs.oh-my-pi.enable`: Enables installation of Oh My Pi through Home Manager.
- `programs.oh-my-pi.package`: Overrides which `oh-my-pi` package gets installed. By default, this uses `omp-flake.packages.<system>.default`.
- `programs.oh-my-pi.agents`: Attribute set of agent files installed to `~/.omp/agents/agent/`.
  - `<name>.source`: Path to a file copied into `~/.omp/agents/agent/<name>`.
  - `<name>.text`: Inline file contents written to `~/.omp/agents/agent/<name>`.
  - `<name>.executable`: Marks the installed file as executable (default: `false`).

## Development

Validate flake outputs:

```bash
nix flake check
```
