#!/bin/bash
# Deploy Production + DEBUGFS + TSF Sync to Client

CLIENT_HOST="root@192.168.1.97"
CLIENT_PASS="Dusty123"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Deploying Production + DEBUGFS + TSF Sync to Client ==="
echo "Target: Client (root@192.168.1.97)"
echo ""

# Source modules (production with debugfs)
MORSE_SRC="build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/morse.ko"
DOT11AH_SRC="build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/dot11ah.ko"

# Verify source files exist
if [ ! -f "$MORSE_SRC" ]; then
    echo "Error: morse.ko not found at $MORSE_SRC"
    exit 1
fi

if [ ! -f "$DOT11AH_SRC" ]; then
    echo "Error: dot11ah.ko not found at $DOT11AH_SRC"
    exit 1
fi

# Check source module sizes and TSF symbols
echo "Source modules:"
ls -lh "$MORSE_SRC" "$DOT11AH_SRC"
echo ""
echo "TSF symbols in morse.ko:"
nm "$MORSE_SRC" | grep -E "tsf|TSF" | head -5
echo ""
echo "Build type: PRODUCTION with DEBUGFS"
echo ""

# Deploy to Client
echo "Deploying to Client..."
sshpass -p "$CLIENT_PASS" ssh $CLIENT_HOST "
    # Create backup of current modules
    mkdir -p /root/morse_backup_$TIMESTAMP
    cp /lib/modules/5.15.167/morse.ko /root/morse_backup_$TIMESTAMP/morse.ko.old 2>/dev/null || true
    cp /lib/modules/5.15.167/dot11ah.ko /root/morse_backup_$TIMESTAMP/dot11ah.ko.old 2>/dev/null || true
    echo 'Backup created at /root/morse_backup_$TIMESTAMP/'

    # Unload modules
    rmmod morse 2>/dev/null || true
    rmmod dot11ah 2>/dev/null || true
    echo 'Modules unloaded'
"

# Copy new modules
echo ""
echo "Copying new modules..."
sshpass -p "$CLIENT_PASS" scp "$MORSE_SRC" "$CLIENT_HOST:/lib/modules/5.15.167/morse.ko"
sshpass -p "$CLIENT_PASS" scp "$DOT11AH_SRC" "$CLIENT_HOST:/lib/modules/5.15.167/dot11ah.ko"

# Verify deployment and reload
sshpass -p "$CLIENT_PASS" ssh $CLIENT_HOST "
    echo ''
    echo 'Deployed modules:'
    ls -lh /lib/modules/5.15.167/morse.ko /lib/modules/5.15.167/dot11ah.ko

    echo ''
    echo 'Rebooting Client for clean driver initialization...'
"

# Reboot Client
sshpass -p "$CLIENT_PASS" ssh $CLIENT_HOST "reboot" || echo "Reboot command sent"

echo ""
echo "=== Client Rebooting ==="
echo "Waiting 40 seconds for Client to come back online..."
sleep 40

# Check Client status after reboot
echo ""
echo "Checking Client status..."
sshpass -p "$CLIENT_PASS" ssh -o ConnectTimeout=10 $CLIENT_HOST "
    echo 'Client Interface Status:'
    iw wlan0 info

    echo ''
    echo 'Module status:'
    lsmod | grep -E 'morse|dot11ah'

    echo ''
    echo 'TSF debugfs files:'
    ls -la /sys/kernel/debug/ieee80211/phy*/morse/tsf*

    echo ''
    echo 'Attempting to connect to AP...'
    sleep 5

    echo ''
    echo 'Connection status:'
    iw wlan0 link
" || echo "Client not ready yet, check manually"

echo ""
echo "=== Deployment Complete ==="
echo "TSF debugfs files should be at: /sys/kernel/debug/ieee80211/phy0/morse/"
