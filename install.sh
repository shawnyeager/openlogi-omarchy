#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="openlogi-omarchy"
OLD_PLUGIN_ID="openlogi.bar"
OPENLOGI_VERSION="${OPENLOGI_VERSION:-0.7.4}"
ARCH="$(uname -m)"

case "$ARCH" in
x86_64) PKG_ARCH="amd64" ;;
aarch64 | arm64) PKG_ARCH="arm64" ;;
*)
  echo "Unsupported architecture: $ARCH" >&2
  exit 1
  ;;
esac

install_package_from_github() {
  local pkg="openlogi-v${OPENLOGI_VERSION}-linux-${PKG_ARCH}.pkg.tar.zst"
  local url="https://github.com/AprilNEA/OpenLogi/releases/download/v${OPENLOGI_VERSION}/${pkg}"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading ${pkg} from GitHub releases..."
  curl -fL -o "$tmp/$pkg" "$url"
  echo "Installing OpenLogi package..."
  sudo pacman -U --needed "$tmp/$pkg"
}

install_package() {
  if pacman -Q openlogi &>/dev/null; then
    echo "OpenLogi package already installed: $(pacman -Q openlogi)"
    return
  fi

  if command -v omarchy &>/dev/null; then
    echo "Installing openlogi from Omarchy package mirror..."
    if omarchy pkg add openlogi; then
      return
    fi
    echo "omarchy pkg add failed — falling back to GitHub release" >&2
  fi

  install_package_from_github
}

configure_openlogi() {
  echo "Syncing OpenLogi config for Omarchy..."
  mkdir -p "${HOME}/.local/share/omarchy-openlogi"
  cp "${ROOT}/lib/openlogi_sync.py" "${HOME}/.local/share/omarchy-openlogi/"
  "${ROOT}/bin/omarchy-openlogi-sync"
}

remove_legacy_plugin() {
  local legacy="${HOME}/.config/omarchy/plugins/${OLD_PLUGIN_ID}"
  [[ -e $legacy || -L $legacy ]] || return 0
  echo "Removing previous ${OLD_PLUGIN_ID} plugin..."
  if command -v omarchy &>/dev/null; then
    omarchy plugin remove "$OLD_PLUGIN_ID" --yes || rm -rf "$legacy"
  else
    rm -rf "$legacy"
  fi
}

install_plugin() {
  echo "Validating plugin at ${ROOT}..."
  omarchy plugin validate "$ROOT"

  local dest="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
  if [[ -e $dest || -L $dest ]]; then
    echo "Plugin ${PLUGIN_ID} is already installed at ${dest}"
    omarchy plugin validate "$dest"
    omarchy plugin enable "$PLUGIN_ID" --section right
    return
  fi

  echo "Adding plugin with omarchy plugin add..."
  omarchy plugin add "$ROOT" --enable --yes
}

install_package
configure_openlogi
remove_legacy_plugin
install_plugin

echo
echo "OpenLogi is ready."
echo "  Configure devices: openlogi-desktop"
echo "  Bar plugin id: ${PLUGIN_ID}"
echo "  Re-sync config: ${ROOT}/bin/omarchy-openlogi-sync"
echo "  Remove plugin: omarchy plugin remove ${PLUGIN_ID}"
