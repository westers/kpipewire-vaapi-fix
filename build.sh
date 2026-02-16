#!/bin/bash
set -e

KPIPEWIRE_VERSION="6.5.5"
KPIPEWIRE_DEB_VERSION="6.5.5-0ubuntu1"
PATCHED_VERSION="${KPIPEWIRE_DEB_VERSION}+vaapi1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== KPipeWire VAAPI Fix Builder ==="
echo "Building patched kpipewire ${PATCHED_VERSION}"
echo ""

# Check we're on a supported system
if ! grep -q "resolute\|26.04" /etc/os-release 2>/dev/null; then
    echo "WARNING: This script is designed for Ubuntu 26.04 (Resolute Raccoon)."
    echo "Your system may have a different kpipewire version."
    read -p "Continue anyway? [y/N] " -r
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# Check for required tools
for cmd in dpkg-buildpackage dpkg-source quilt; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found. Install build tools:"
        echo "  sudo apt install build-essential devscripts quilt"
        exit 1
    fi
done

WORKDIR=$(mktemp -d)
echo "Working directory: ${WORKDIR}"
cd "${WORKDIR}"

# Enable deb-src if needed
if ! apt-cache showsrc kpipewire &>/dev/null; then
    echo ""
    echo "ERROR: Source packages not available. Enable deb-src in your sources."
    echo "Edit /etc/apt/sources.list.d/ubuntu.sources and add 'deb-src' to the 'Types:' line:"
    echo "  Types: deb deb-src"
    echo "Then run: sudo apt update"
    exit 1
fi

# Install build dependencies
echo ""
echo "=== Installing build dependencies ==="
sudo apt-get build-dep -y kpipewire

# Download source package
echo ""
echo "=== Downloading kpipewire source ==="
apt-get source kpipewire

SRCDIR="${WORKDIR}/kpipewire-${KPIPEWIRE_VERSION}"
if [ ! -d "${SRCDIR}" ]; then
    echo "ERROR: Source directory not found at ${SRCDIR}"
    echo "Your system may have a different kpipewire version."
    ls "${WORKDIR}"
    exit 1
fi

cd "${SRCDIR}"

# Copy patches
echo ""
echo "=== Applying patches ==="
mkdir -p debian/patches
cp "${SCRIPT_DIR}/patches/01-fix-vaapi-hw-frames-ctx.patch" debian/patches/
cp "${SCRIPT_DIR}/patches/02-fix-software-encoder-filter-graph.patch" debian/patches/
cp "${SCRIPT_DIR}/patches/series" debian/patches/

# Update debian/rules for optimized build
cat > debian/rules << 'RULES'
#!/usr/bin/make -f

export DEB_BUILD_MAINT_OPTIONS = hardening=+all

%:
	dh $@

override_dh_auto_configure:
	dh_auto_configure -- -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=RelWithDebInfo

override_dh_strip:
	dh_strip --no-automatic-dbgsym
RULES
chmod +x debian/rules

# Update changelog
TIMESTAMP=$(date -R)
MAINTAINER="$(git config user.name) <$(git config user.email)>"
sed -i "1i\\
kpipewire (${PATCHED_VERSION}) resolute; urgency=medium\\
\\
  * Backport upstream fixes for VAAPI hardware encoding:\\
    - Fix VAAPI hw_frames_ctx initialization order (KDE Bug 515342)\\
    - Fix software encoder filter graph ordering (KDE Bug 513077)\\
\\
 -- ${MAINTAINER}  ${TIMESTAMP}\\
" debian/changelog

# Build
echo ""
echo "=== Building packages ==="
dpkg-buildpackage -us -uc -b

# Collect debs
echo ""
echo "=== Build complete ==="
OUTDIR="${SCRIPT_DIR}/debs"
mkdir -p "${OUTDIR}"
cp "${WORKDIR}"/*.deb "${OUTDIR}/"

echo ""
echo "Packages built successfully in ${OUTDIR}/:"
ls -1 "${OUTDIR}"/*.deb
echo ""
echo "Install with:"
echo "  sudo dpkg -i ${OUTDIR}/libkpipewire-data_*.deb ${OUTDIR}/libkpipewire6_*.deb ${OUTDIR}/libkpipewiredmabuf6_*.deb ${OUTDIR}/libkpipewirerecord6_*.deb"
echo ""
echo "Then restart services:"
echo "  systemctl --user restart xdg-desktop-portal plasma-xdg-desktop-portal-kde app-org.kde.krdpserver"

# Cleanup
rm -rf "${WORKDIR}"
