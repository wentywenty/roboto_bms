#!/bin/bash
# One-click Debian package builder for bms-daemon

PACKAGE_NAME="bms-daemon"
VERSION="1.0.0"
ARCH=$(dpkg --print-architecture)
DEB_DIR="${PACKAGE_NAME}_${VERSION}_${ARCH}"

echo ">>> Starting compilation..."
mkdir -p build && cd build
cmake .. && make -j$(nproc)
if [ $? -ne 0 ]; then
    echo "Error: Compilation failed!"
    exit 1
fi
cd ..

echo ">>> Preparing Debian package structure..."
rm -rf ${DEB_DIR}
mkdir -p ${DEB_DIR}/DEBIAN
mkdir -p ${DEB_DIR}/usr/bin
mkdir -p ${DEB_DIR}/etc/systemd/system

# Copy binary to install directory
cp build/bms_daemon ${DEB_DIR}/usr/bin/

# Create Debian Control File
cat <<EOF > ${DEB_DIR}/DEBIAN/control
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: base
Priority: optional
Architecture: ${ARCH}
Maintainer: Robot Admin <admin@robot.com>
Description: BMS Heartbeat Daemon to prevent auto power-off.
 Provides a Unix Domain Socket (/tmp/bms.sock) for clients.
EOF

# Create Systemd Service File
cat <<EOF > ${DEB_DIR}/etc/systemd/system/bms.service
[Unit]
Description=BMS Heartbeat Daemon
After=network.target

[Service]
ExecStart=/usr/bin/bms_daemon /dev/ttyUSB0
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# Create Post-installation Script (Enables and starts service after install)
cat <<EOF > ${DEB_DIR}/DEBIAN/postinst
#!/bin/bash
systemctl daemon-reload
systemctl enable bms.service
systemctl start bms.service
EOF
chmod 755 ${DEB_DIR}/DEBIAN/postinst

# Execute Packaging
echo ">>> Executing dpkg-deb build..."
dpkg-deb --build ${DEB_DIR}

if [ $? -eq 0 ]; then
    echo ">>> Success! Generated ${DEB_DIR}.deb"
    echo ">>> You can install it using: sudo dpkg -i ${DEB_DIR}.deb"
else
    echo ">>> Error: Packaging failed!"
    exit 1
fi
