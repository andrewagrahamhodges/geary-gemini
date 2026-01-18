#!/bin/bash
# Build Debian package for Geary-Gemini
set -e

echo '=== Creating Debian Package ==='

if [ ! -d /build/meson ]; then
  echo 'Build not found. Running build first...'
  meson setup /build/meson --prefix=/usr --buildtype=release -Dprofile=release
  ninja -C /build/meson
fi

echo '=== Installing to staging directory ==='
rm -rf /build/staging
DESTDIR=/build/staging meson install -C /build/meson

echo '=== Bundling Node.js and gemini-cli ==='
NODE_VERSION="v22.12.0"
NODE_TARBALL="node-${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_TARBALL}"
GEMINI_BUNDLE_DIR="/build/staging/usr/share/geary-gemini"

echo "Downloading Node.js ${NODE_VERSION}..."
curl -fsSL "${NODE_URL}" -o "/tmp/${NODE_TARBALL}"

echo "Extracting Node.js..."
mkdir -p "${GEMINI_BUNDLE_DIR}/node"
tar -xf "/tmp/${NODE_TARBALL}" -C "${GEMINI_BUNDLE_DIR}/node" --strip-components=1

echo "Installing gemini-cli..."
export PATH="${GEMINI_BUNDLE_DIR}/node/bin:$PATH"
npm install --prefix "${GEMINI_BUNDLE_DIR}" @google/gemini-cli

echo "Cleaning up to reduce package size..."
rm "/tmp/${NODE_TARBALL}"
rm -rf "${GEMINI_BUNDLE_DIR}/node/share/doc"
rm -rf "${GEMINI_BUNDLE_DIR}/node/share/man"
rm -rf "${GEMINI_BUNDLE_DIR}/node/include"

echo '=== Building .deb package ==='
mkdir -p /build/staging/DEBIAN

# Extract version from meson.build
VERSION=$(awk -F"'" '/version:/{print $2; exit}' /src/meson.build)
echo "Extracted version: ${VERSION}"

# Create control file
cat > /build/staging/DEBIAN/control << EOF
Package: geary-gemini
Version: ${VERSION}
Section: mail
Priority: optional
Architecture: amd64
Depends: libgtk-3-0t64, libwebkit2gtk-4.1-0, libgee-0.8-2, libgmime-3.0-0t64, libsqlite3-0, libsecret-1-0, libhandy-1-0, libfolks26, libgoa-1.0-0b, libgspell-1-3, libgsound0t64, libpeas-2-0, libenchant-2-2, libytnef0
Maintainer: Andrew Hodges <andrew@example.com>
Description: Geary email client with Gemini AI integration
 Geary is a modern email client for GNOME, enhanced with
 Gemini AI capabilities for translation, summarization,
 and natural language email management.
EOF

echo "=== Control file contents ==="
cat /build/staging/DEBIAN/control

dpkg-deb --build /build/staging /output/geary-gemini_${VERSION}_amd64.deb

# Make the .deb world-readable so apt can access it without warnings
chmod 644 /output/geary-gemini_${VERSION}_amd64.deb

echo '=== Package created ==='
ls -la /output/*.deb
