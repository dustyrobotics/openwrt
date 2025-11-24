# TSF Synchronization - Deployment Guide

## Quick Start

This guide shows how to build and deploy production Morse driver firmware with TSF synchronization support.

**Goal**: Production firmware (no DEBUG bugs) + DEBUGFS (TSF access)

## Prerequisites

- OpenWrt build environment for BCM27xx (Raspberry Pi 4)
- Target: `aarch64_cortex-a72` (bcm27xx/bcm2711)
- Kernel: 5.15.167
- Morse driver: 1.16.4

## Step 1: Configure Build

### 1.1 Disable DEBUG Mode

Edit `.config`:
```bash
# CONFIG_MORSE_DEBUG is not set
```

Or via menuconfig:
```bash
make menuconfig
# Navigate to: Kernel modules -> Wireless Drivers -> kmod-morse
# Uncheck "Enable DEBUG mode"
```

### 1.2 Enable DEBUGFS

Edit `feeds/morse/essentials/morse_driver/Makefile`:

```makefile
ifeq ($(CONFIG_MORSE_DEBUG),y)
  MORSE_MAKEDEFS += DEBUG=y
  MORSE_MAKEDEFS += CONFIG_MORSE_ENABLE_TEST_MODES=y
else
  MORSE_MAKEDEFS += DEBUG=n
endif

# Enable debugfs support for TSF synchronization (works in production mode)
MORSE_MAKEDEFS += CONFIG_MORSE_DEBUGFS=y
```

### 1.3 Verify TSF Patch is Applied

Check that the patch exists:
```bash
ls -la patches/morse_driver/999-tsf-sync.patch
```

Or check the feeds directory:
```bash
ls -la feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch
```

If missing, copy from this repository:
```bash
cp patches/morse_driver/999-tsf-sync.patch \
   feeds/morse/essentials/morse_driver/patches/
```

## Step 2: Build Firmware

### 2.1 Clean Previous Build
```bash
make package/feeds/morse/morse_driver/clean
```

### 2.2 Compile Driver
```bash
make package/feeds/morse/morse_driver/compile -j1 V=s 2>&1 | tee /tmp/morse_build_production.log
```

### 2.3 Verify Build

Check module size (production should be ~625K):
```bash
ls -lh build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/morse.ko
# Expected: -rw-r--r-- 1 user user 626K Nov 22 21:22 morse.ko
```

Check for TSF symbols:
```bash
nm build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/morse.ko | grep -E "tsf|TSF"
```

Expected output:
```
00000000000127e0 t morse_cmd_cfg_offset_tsf
0000000000007f90 t morse_get_tsf_snapshot
```

Check MD5 (should match known good build):
```bash
md5sum build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/morse.ko
# Expected: 390cdc98013c0bbae1254e7b28577feb
```

## Step 3: Create Deployment Scripts

### 3.1 AP Deployment Script

Create `/tmp/deploy_to_ap.sh`:
```bash
#!/bin/bash
AP_HOST="root@ap"
AP_PASS="YOUR_PASSWORD"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

MORSE_SRC="build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/morse.ko"
DOT11AH_SRC="build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/dot11ah.ko"

# Verify source files
if [ ! -f "$MORSE_SRC" ] || [ ! -f "$DOT11AH_SRC" ]; then
    echo "Error: Source modules not found"
    exit 1
fi

echo "=== Deploying Production + DEBUGFS to AP ==="
ls -lh "$MORSE_SRC" "$DOT11AH_SRC"

# Backup and deploy
sshpass -p "$AP_PASS" ssh $AP_HOST "
    mkdir -p /root/morse_backup_$TIMESTAMP
    cp /lib/modules/5.15.167/morse.ko /root/morse_backup_$TIMESTAMP/ 2>/dev/null || true
    cp /lib/modules/5.15.167/dot11ah.ko /root/morse_backup_$TIMESTAMP/ 2>/dev/null || true
    rmmod morse 2>/dev/null || true
    rmmod dot11ah 2>/dev/null || true
"

sshpass -p "$AP_PASS" scp "$MORSE_SRC" "$AP_HOST:/lib/modules/5.15.167/morse.ko"
sshpass -p "$AP_PASS" scp "$DOT11AH_SRC" "$AP_HOST:/lib/modules/5.15.167/dot11ah.ko"

# Reboot for clean initialization
sshpass -p "$AP_PASS" ssh $AP_HOST "reboot" || echo "Reboot sent"

echo "Waiting 40 seconds for reboot..."
sleep 40

# Verify
sshpass -p "$AP_PASS" ssh -o ConnectTimeout=10 $AP_HOST "
    iw wlan0 info
    echo ''
    lsmod | grep -E 'morse|dot11ah'
    echo ''
    ls -la /sys/kernel/debug/ieee80211/phy*/morse/tsf*
" || echo "AP not ready, check manually"

echo "=== Deployment Complete ==="
```

### 3.2 Client Deployment Script

Create `/tmp/deploy_to_client.sh` (same structure, change IP):
```bash
CLIENT_HOST="root@192.168.1.97"
CLIENT_PASS="YOUR_PASSWORD"
# ... rest same as AP script
```

## Step 4: Deploy to Devices

### 4.1 Deploy to AP
```bash
chmod +x /tmp/deploy_to_ap.sh
/tmp/deploy_to_ap.sh
```

### 4.2 Deploy to Client
```bash
chmod +x /tmp/deploy_to_client.sh
/tmp/deploy_to_client.sh
```

## Step 5: Verify Deployment

### 5.1 Check Module Version

On each device:
```bash
ssh root@ap "ls -lh /lib/modules/5.15.167/morse.ko && md5sum /lib/modules/5.15.167/morse.ko"
ssh root@192.168.1.97 "ls -lh /lib/modules/5.15.167/morse.ko && md5sum /lib/modules/5.15.167/morse.ko"
```

Both should show:
- Size: 625.5K
- MD5: 390cdc98013c0bbae1254e7b28577feb

### 5.2 Check Interface Status

AP:
```bash
ssh root@ap "iw wlan0 info"
```

Expected:
```
Interface wlan0
	ifindex 6
	wdev 0x2
	addr 0c:bf:74:00:24:6e
	ssid ekh01-1dd8
	type AP
	wiphy 0
	channel 112 (5560 MHz), width: 160 MHz, center1: 5570 MHz
	txpower 20.00 dBm
```

Client:
```bash
ssh root@192.168.1.97 "iw wlan0 link"
```

Expected:
```
Connected to 0c:bf:74:00:24:6e (on wlan0)
	SSID: ekh01-1dd8
	freq: 5560
	signal: -22 dBm
	rx bitrate: 702.0 MBit/s VHT-MCS 8 160MHz VHT-NSS 1
	tx bitrate: 866.7 MBit/s VHT-MCS 9 160MHz short GI VHT-NSS 1
```

### 5.3 Check TSF Files Exist

On both devices:
```bash
ssh root@ap "ls -la /sys/kernel/debug/ieee80211/phy0/morse/tsf*"
ssh root@192.168.1.97 "ls -la /sys/kernel/debug/ieee80211/phy0/morse/tsf*"
```

Expected:
```
-r--r--r--    1 root     root             0 Nov 23 05:38 /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
-r--r--r--    1 root     root             0 Nov 23 05:38 /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
```

### 5.4 Test TSF Access

Read TSF values:
```bash
ssh root@ap "cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx"
ssh root@192.168.1.97 "cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx"
```

Expected output:
```
TSF: 771793980
SYS: 1763876412322289644
```

Verify values update:
```bash
ssh root@ap "cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx && sleep 1 && cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx"
```

TSF and SYS values should change between reads.

## Step 6: Usage Examples

### 6.1 Python - Read Last RX Time

```python
#!/usr/bin/env python3

def read_tsf_rx():
    """Read last received frame TSF and system time"""
    with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx') as f:
        lines = f.readlines()

    tsf_us = int(lines[0].split(': ')[1].strip())
    sys_ns = int(lines[1].split(': ')[1].strip())

    return tsf_us, sys_ns

# Example usage
hw_tsf, kernel_time = read_tsf_rx()
print(f"Last RX TSF: {hw_tsf} µs")
print(f"Kernel time: {kernel_time} ns")
```

### 6.2 Python - Read Current Time

```python
def read_tsf_current():
    """Read current extrapolated TSF and system time"""
    with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_current') as f:
        lines = f.readlines()

    tsf_us = int(lines[0].split(': ')[1].strip())
    sys_ns = int(lines[1].split(': ')[1].strip())

    return tsf_us, sys_ns

# Example usage
current_tsf, current_sys = read_tsf_current()
print(f"Current TSF: {current_tsf} µs")
print(f"System time: {current_sys} ns")
```

### 6.3 Bash - Monitor TSF Updates

```bash
#!/bin/bash
# Monitor TSF values in real-time

while true; do
    clear
    echo "=== TSF Monitor ==="
    echo ""
    echo "Last RX:"
    cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
    echo ""
    echo "Current:"
    cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
    sleep 0.1
done
```

## Troubleshooting

### Issue: Beacon Timing Bug (Client Can't Connect)

**Symptom**:
```
wlan0: authenticated
wlan0: waiting for beacon from 0c:bf:74:00:24:6e
[repeats indefinitely]
```

**Cause**: DEBUG firmware on one or both devices

**Solution**:
1. Verify both devices have production firmware (625.5K, not 644.9K)
2. Check MD5 matches: `390cdc98013c0bbae1254e7b28577feb`
3. Rebuild with `CONFIG_MORSE_DEBUG` disabled
4. Redeploy to both devices

### Issue: TSF Files Don't Exist

**Symptom**: `ls /sys/kernel/debug/ieee80211/phy0/morse/tsf*` returns nothing

**Possible Causes**:
1. DEBUGFS not enabled in Makefile
2. Patch didn't apply correctly
3. Driver not loaded

**Solution**:
```bash
# Check driver is loaded
lsmod | grep morse

# Check debugfs is mounted
mount | grep debugfs

# Rebuild with DEBUGFS enabled
make package/feeds/morse/morse_driver/{clean,compile} V=s

# Verify patch applied
grep -r "tsf_rx" build_dir/target-*/linux-*/morse_driver-*/
```

### Issue: TSF Values Are Zero

**Symptom**: TSF reads as `TSF: 0` and `SYS: 0`

**Cause**: No frames received yet

**Solution**:
```bash
# Ensure interface is up
ip link set wlan0 up

# For client, connect to AP
wpa_supplicant -i wlan0 -c /etc/wpa_supplicant.conf

# Wait for beacon/management frames
# TSF will update within 100ms
```

### Issue: Module Won't Load After Deployment

**Symptom**: `insmod morse.ko` fails or kernel panics

**Possible Causes**:
1. Kernel version mismatch
2. Module built for wrong architecture
3. Missing dependencies

**Solution**:
```bash
# Check kernel version
uname -r
# Should be: 5.15.167

# Check module info
modinfo morse.ko

# Ensure dot11ah loads first
insmod /lib/modules/5.15.167/dot11ah.ko
insmod /lib/modules/5.15.167/morse.ko
```

### Issue: Filesystem Full During Deployment

**Symptom**: `scp` fails with "No space left on device"

**Solution**:
```bash
# Check space
ssh root@ap "df -h"

# Clean up old backups
ssh root@ap "rm -rf /root/morse_backup_*"

# Remove old logs
ssh root@ap "rm -f /tmp/*.log"
```

## Known Good Configuration

### Build Artifacts
- **morse.ko**: 625.5K, MD5: `390cdc98013c0bbae1254e7b28577feb`
- **dot11ah.ko**: 104.7K
- **Build date**: 2025-11-22/23
- **Build flags**: `DEBUG=n`, `CONFIG_MORSE_DEBUGFS=y`

### Runtime Configuration
- **Target**: BCM27xx BCM2711 (Raspberry Pi 4)
- **Kernel**: 5.15.167
- **Architecture**: aarch64_cortex-a72
- **Channel**: 112 (5560 MHz), 160 MHz width
- **SSID**: ekh01-1dd8 (or your network)

### Verified Devices
- **AP**: MAC 0c:bf:74:00:24:6e
- **Client**: MAC 0c:bf:74:00:24:8d
- **Connection**: 700+ Mbps, -22 dBm signal

## Patches Applied

1. **998-disable-hw-channel-ignore.patch** - Channel workaround (optional, kept for safety)
2. **999-tsf-sync.patch** - TSF synchronization (required)

## File Locations

### Build System
- **Source**: `build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/`
- **Patch**: `feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch`
- **Makefile**: `feeds/morse/essentials/morse_driver/Makefile`
- **Config**: `.config`

### Target Device
- **Modules**: `/lib/modules/5.15.167/morse.ko`, `/lib/modules/5.15.167/dot11ah.ko`
- **TSF files**: `/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx`, `/sys/kernel/debug/ieee80211/phy0/morse/tsf_current`
- **Backup**: `/root/morse_backup_TIMESTAMP/`

## Summary

This deployment provides:
- Production firmware (no DEBUG bugs)
- TSF synchronization via debugfs
- Stable beacon timing
- High-speed wireless (700+ Mbps)
- Real-time TSF access for user applications

The system is production-ready for HaLow mesh time synchronization applications.
