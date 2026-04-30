#!/bin/bash
set -e
# Decoupled & Cross-compile ready Debian package builder

PACKAGE_NAME="roboto-bms"
VERSION="1.2.3"
PREFIX="/opt/roboparty"
FIRMWARE_FILE="firmware/LB-13S2P_APP_v003_20260326-01.bin"

# 1. Determine Architecture (Allow override for cross-compiling)
if [ -z "$ARCH" ]; then
    ARCH=$(dpkg --print-architecture)
fi

DEB_DIR="${PACKAGE_NAME}_${VERSION}_${ARCH}"

# 2. Setup Compilers (Allow override via CROSS_PREFIX)
# Example: CROSS_PREFIX=aarch64-linux-gnu- ./build_deb.sh
if [ -n "$CROSS_PREFIX" ]; then
    CC="${CROSS_PREFIX}gcc"
    CXX="${CROSS_PREFIX}g++"
    CMAKE_OPTS="-DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=$ARCH"
    echo ">>> Cross-compiling for $ARCH using $CXX"
else
    echo ">>> Compiling natively for $ARCH"
fi

echo ">>> Starting compilation..."
rm -rf build && mkdir -p build
pushd build > /dev/null
cmake .. $CMAKE_OPTS \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
DESTDIR="$(pwd)/destdir" cmake --install .
popd > /dev/null

echo ">>> Preparing Debian package structure..."
rm -rf ${DEB_DIR} ${DEB_DIR}.deb
mkdir -p ${DEB_DIR}/DEBIAN
mkdir -p ${DEB_DIR}${PREFIX}
mkdir -p ${DEB_DIR}${PREFIX}/bin
mkdir -p ${DEB_DIR}${PREFIX}/lib/firmware
mkdir -p ${DEB_DIR}/etc/systemd/system
mkdir -p ${DEB_DIR}/etc/default

# Copy cmake installed files
if [ -d "build/destdir${PREFIX}" ]; then
    cp -a "build/destdir${PREFIX}/." "${DEB_DIR}${PREFIX}/"
fi

# Copy Binary and templates
cp scripts/bms_ota.py ${DEB_DIR}${PREFIX}/bin/
cp -a etc/systemd/system/* ${DEB_DIR}/etc/systemd/system/
cp etc/default/bms_daemon.default ${DEB_DIR}/etc/default/bms_daemon

if [ ! -f "${FIRMWARE_FILE}" ]; then
    echo ">>> Error: firmware file not found: ${FIRMWARE_FILE}"
    exit 1
fi
cp "${FIRMWARE_FILE}" ${DEB_DIR}${PREFIX}/lib/firmware/

# Copy DEBIAN maintainer scripts
cp debian/postinst ${DEB_DIR}/DEBIAN/
cp debian/prerm ${DEB_DIR}/DEBIAN/
cp debian/conffiles ${DEB_DIR}/DEBIAN/
chmod 755 ${DEB_DIR}/DEBIAN/postinst
chmod 755 ${DEB_DIR}/DEBIAN/prerm
chmod 755 ${DEB_DIR}${PREFIX}/bin/bms_ota.py

# Generate Control file (Replace placeholders)
sed -e "s/ARCH_PLACEHOLDER/${ARCH}/g" \
    -e "s/VERSION_PLACEHOLDER/${VERSION}/g" \
    debian/control > ${DEB_DIR}/DEBIAN/control

# 5. Build Package
echo ">>> Executing dpkg-deb build..."
# Use --root-owner-group to ensure correct permissions if building as non-root
dpkg-deb --root-owner-group --build ${DEB_DIR}

echo ">>> Success! Generated ${DEB_DIR}.deb"
