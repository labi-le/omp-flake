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

  programs.oh-my-pi.enable = true;
}
```

## Development

Validate flake outputs:

```bash
nix flake check
```
