#!/bin/zsh
set -euo pipefail

# Builds, packages, and publishes a tagged GitHub release from main.
# Usage: zsh Scripts/release.sh v0.2.0 [--publish-site]

if (( $# < 1 || $# > 2 )); then
  print -u2 "Usage: zsh Scripts/release.sh vX.Y.Z [--publish-site]"
  exit 64
fi

version="$1"
publish_site=false
if (( $# == 2 )); then
  if [[ "$2" != "--publish-site" ]]; then
    print -u2 "Unknown option: $2"
    exit 64
  fi
  publish_site=true
fi

if [[ ! "$version" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "Version must use vX.Y.Z format, for example v0.2.0."
  exit 64
fi

project_dir="${0:A:h:h}"
cd "$project_dir"

if [[ "$(uname)" != "Darwin" ]]; then
  print -u2 "Cinema Player releases must be built on macOS."
  exit 69
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  print -u2 "Switch to main before releasing."
  exit 65
fi

if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "Commit or stash your changes before releasing."
  exit 65
fi

git fetch origin main --tags
if ! git diff --quiet HEAD origin/main; then
  print -u2 "Local main is not aligned with origin/main. Run: git pull --ff-only origin main"
  exit 65
fi

if gh release view "$version" >/dev/null 2>&1; then
  print -u2 "A GitHub release for $version already exists."
  exit 65
fi

if git rev-parse --verify --quiet "refs/tags/$version" >/dev/null; then
  print -u2 "The local tag $version already exists."
  exit 65
fi

gh auth status >/dev/null

print "→ Testing"
swift test

print "→ Building signed app bundle"
zsh Scripts/build-app.sh

app_bundle="$project_dir/build/Cinema Player.app"
if [[ ! -d "$app_bundle" ]]; then
  print -u2 "Build did not produce Cinema Player.app."
  exit 70
fi

release_dir="$(mktemp -d "${TMPDIR:-/tmp}/cinema-player-release.XXXXXX")"
archive="$release_dir/Cinema-Player-macOS.zip"
trap 'rm -rf "$release_dir"' EXIT

print "→ Packaging"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"

print "→ Publishing GitHub release $version"
gh release create "$version" "$archive#Cinema-Player-macOS.zip" \
  --target main \
  --title "Cinema Player $version" \
  --generate-notes

if [[ "$publish_site" == true ]]; then
  print "→ Publishing GitHub Pages"
  zsh Scripts/publish-site.sh
fi

print "✓ Published Cinema Player $version"
print "  Release: https://github.com/hessennasser/cinema-player/releases/tag/$version"
if [[ "$publish_site" == true ]]; then
  print "  Website: https://hessennasser.github.io/cinema-player/"
fi
