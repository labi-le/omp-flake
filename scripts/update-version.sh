#!/usr/bin/env bash
set -euo pipefail

# update-version.sh — Update oh-my-pi version and platform hashes in flake.nix.
# Usage: ./scripts/update-version.sh <version>
#   version: tag without 'v' prefix (e.g. "16.2.0")

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

FLAKE="flake.nix"
REPO="can1357/oh-my-pi"
BASE_URL="https://github.com/$REPO/releases/download/v$VERSION"

declare -A PLATFORM_MAP=(
  ["x86_64-linux"]="omp-linux-x64"
  ["aarch64-linux"]="omp-linux-arm64"
  ["x86_64-darwin"]="omp-darwin-x64"
  ["aarch64-darwin"]="omp-darwin-arm64"
)

echo "Updating to version $VERSION"

# Update version string
sed -i "s/version = \"[^\"]*\";/version = \"$VERSION\";/" "$FLAKE"
echo "  version → $VERSION"

# Update each platform
for system in "${!PLATFORM_MAP[@]}"; do
  binary="${PLATFORM_MAP[$system]}"
  url="$BASE_URL/$binary"
  echo -n "  $system: fetching $url ... "

  hash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null) || {
    echo "FAILED"
    exit 1
  }

  # Replace the sha256 for this platform
  escaped_system=$(echo "$system" | sed 's/_/\\_/g')
  sed -i "/\"$escaped_system\" = {/,/};/{
    s|sha256 = \"[^\"]*\"|sha256 = \"$hash\"|
    s|url = \"[^\"]*\"|url = \"$url\"|
  }" "$FLAKE"
  echo "OK"
done

echo "Done. Run: nix flake check"
