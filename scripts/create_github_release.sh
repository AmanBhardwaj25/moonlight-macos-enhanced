#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: GitHub CLI (gh) is not installed." >&2
  echo "Install it with: brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "error: GitHub CLI is not authenticated." >&2
  echo "Run: gh auth login" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "error: tracked working tree changes exist. Commit or stash them before releasing." >&2
  git status --short
  exit 1
fi

release_dir="${RELEASE_DIR:-/tmp/moonlight-release}"
derived_data="$release_dir/DerivedData"
dmg_root="$release_dir/dmg-root"

rm -rf "$release_dir"
mkdir -p "$dmg_root"

xcodebuild \
  -project Moonlight.xcodeproj \
  -scheme "Moonlight for macOS" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data" \
  clean build

app="$derived_data/Build/Products/Release/Moonlight.app"
if [[ ! -d "$app" ]]; then
  echo "error: Release build did not produce Moonlight.app at $app" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")"
tag="v${version}"
dmg_name="Moonlight-macOS-v${version}.dmg"
dmg_path="$repo_root/$dmg_name"

ditto "$app" "$dmg_root/Moonlight.app"
ln -s /Applications "$dmg_root/Applications"

hdiutil create \
  -volname "Moonlight" \
  -srcfolder "$dmg_root" \
  -ov \
  -format UDZO \
  "$dmg_path"

git push origin HEAD

if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  echo "Remote tag already exists: $tag"
elif git rev-parse "$tag" >/dev/null 2>&1; then
  git push origin "$tag"
else
  git tag "$tag"
  git push origin "$tag"
fi

if gh release view "$tag" >/dev/null 2>&1; then
  gh release upload "$tag" "$dmg_path" --clobber
else
  gh release create "$tag" "$dmg_path" \
    --title "Moonlight macOS ${tag}" \
    --notes "macOS release build ${build}."
fi

echo "Release published: ${tag}"
echo "Asset: ${dmg_path}"
