# Morse Driver Build Guide - TSF Sync v2.0

Complete guide for building morse.ko and dot11ah.ko with TSF synchronization support for Morse Micro HaLow devices (MM6108/MM8108).

**Target**: aarch64 kernel 5.15.16 (also works for other architectures)
**Driver Version**: morse_driver 1.16.4
**Patch Version**: v2.0 (dual debugfs interface)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Build Artifacts](#build-artifacts)
3. [Build Methods](#build-methods)
4. [Deployment](#deployment)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Option 1: Build on Target Device (FASTEST - 5-10 min) ✅ RECOMMENDED

If you already have a working MM8108 (or MM6108) device with kernel headers:

```bash
# On your target device (Ubuntu 20.04 aarch64 with kernel 5.15.16)
sudo apt install linux-headers-$(uname -r) build-essential git

# Clone morse driver
git clone https://github.com/MorseMicro/morse_driver.git
cd morse_driver
git checkout v1.16.4

# Apply TSF sync v2.0 patch
# (Copy from: /home/dzezula/openwrt/patches/morse_driver/999-tsf-sync.patch)
patch -p1 < 999-tsf-sync.patch

# Build for your exact kernel (5-10 minutes)
make KERNEL_SRC=/lib/modules/$(uname -r)/build

# Install
sudo rmmod morse 2>/dev/null
sudo rmmod dot11ah 2>/dev/null
sudo insmod dot11ah/dot11ah.ko
sudo insmod morse.ko country=US

# Verify TSF sync v2.0
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
```

### Option 2: Cross-Compile with OpenWRT (1-2 hours)

Full cross-compilation build for aarch64:

```bash
cd /home/dzezula/openwrt

# Configure for aarch64 kernel 5.15
./scripts/morse_setup.sh -i -b ekh-armsr_armv8

# Download sources
make download -j$(nproc)

# Build toolchain and kernel (first time: 60-90 min)
make toolchain/install target/linux/install -j$(nproc) V=s

# Build morse driver (2-5 min)
make package/feeds/morse/morse_driver/compile V=s

# Find artifacts
find build_dir -name "morse.ko"
find build_dir -name "dot11ah.ko"
```

---

## Build Artifacts

### What You Get

When building successfully, you'll have:

```
morse_driver-1.16.4/
├── morse.ko          ← Main driver with TSF sync v2.0
└── dot11ah/
    └── dot11ah.ko    ← 802.11ah protocol support
```

### File Details

#### morse.ko
- **Size**: ~1.2 MB (with debug symbols) or ~500 KB (stripped)
- **Type**: ELF 64-bit LSB relocatable, ARM aarch64
- **Kernel**: 5.15.167 SMP preempt mod_unload aarch64
- **Dependencies**: mac80211, cfg80211, dot11ah
- **TSF Features**: Includes `tsf_rx_show()`, `tsf_current_show()`, capture logic

#### dot11ah.ko
- **Size**: ~200 KB (with debug) or ~100 KB (stripped)
- **Type**: ELF 64-bit LSB relocatable, ARM aarch64
- **Kernel**: 5.15.167 SMP preempt mod_unload aarch64
- **Dependencies**: cfg80211
- **Purpose**: 802.11ah (S1G) protocol support

### Verification Commands

```bash
# Check architecture
file morse.ko
# Output: ELF 64-bit LSB relocatable, ARM aarch64

# Check kernel version
modinfo morse.ko | grep vermagic
# Output: 5.15.167 SMP preempt mod_unload aarch64

# Verify TSF sync v2.0 symbols
nm morse.ko | grep -E "tsf_rx_show|tsf_current_show"
# Should find both functions

# Check dependencies
modinfo morse.ko | grep depends
# Output: depends:        mac80211,cfg80211,dot11ah

# Check size
ls -lh morse.ko dot11ah/dot11ah.ko
```

---

## Build Methods

### Method 1: On-Device Build (Recommended)

**Requirements**:
- Target device with kernel 5.15.16
- Kernel headers installed
- Internet connection

**Advantages**:
- ✅ Fastest (5-10 minutes)
- ✅ Guaranteed kernel compatibility
- ✅ No cross-compilation issues
- ✅ Build exactly for your kernel

**Steps**:

```bash
# 1. Install prerequisites
sudo apt update
sudo apt install -y linux-headers-$(uname -r) build-essential git

# 2. Get morse driver source
git clone https://github.com/MorseMicro/morse_driver.git
cd morse_driver
git checkout v1.16.4

# 3. Apply patch
# Copy 999-tsf-sync.patch to device, then:
patch -p1 < 999-tsf-sync.patch

# 4. Verify patch applied
grep -n "tsf_rx_show" debug.c
# Should find the function

# 5. Build
make KERNEL_SRC=/lib/modules/$(uname -r)/build

# 6. Check build
ls -lh morse.ko dot11ah/dot11ah.ko
nm morse.ko | grep tsf

# 7. Install
sudo rmmod morse 2>/dev/null
sudo rmmod dot11ah 2>/dev/null
sudo insmod dot11ah/dot11ah.ko
sudo insmod morse.ko country=US

# 8. Verify
lsmod | grep morse
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
```

### Method 2: OpenWRT Cross-Compilation

**Requirements**:
- Ubuntu 20.04 or similar build host
- 15-20 GB free disk space
- 8 GB RAM (minimum 4 GB)
- Multi-core CPU recommended

**Advantages**:
- ✅ Can build for target without access to it
- ✅ Reproducible builds
- ✅ Can create full firmware images

**Disadvantages**:
- ⏱️ Time-consuming (1-2 hours first build)
- 💾 Requires significant disk space
- 🔧 Complex toolchain setup

**Prerequisites**:

```bash
# Install build dependencies
sudo apt update
sudo apt install -y build-essential clang flex g++ gawk gcc-multilib \
  git gettext libncurses5-dev libssl-dev python3-distutils rsync \
  unzip zlib1g-dev swig file wget time
```

**Build Steps**:

```bash
# 1. Navigate to OpenWRT directory
cd /home/dzezula/openwrt

# 2. Verify patch is in place
ls -l patches/morse_driver/999-tsf-sync.patch
# Should exist

# 3. Configure for aarch64
./scripts/morse_setup.sh -i -b ekh-armsr_armv8
# Sets target to armsr/armv8 (aarch64 kernel 5.15)

# 4. Download all sources (15-30 min)
make download -j$(nproc)

# 5. Build toolchain (30-60 min, only first time)
make toolchain/install -j$(nproc) V=s

# 6. Build kernel headers (10-20 min, only first time)
make target/linux/install -j$(nproc) V=s

# 7. Build morse driver (2-5 min)
make package/feeds/morse/morse_driver/compile V=s

# 8. Locate artifacts
find build_dir/target-aarch64* -name "morse.ko"
find build_dir/target-aarch64* -name "dot11ah.ko"

# Typical location:
# build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/morse.ko
# build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/dot11ah/dot11ah.ko
```

### Method 3: Docker Build (Alternative)

**Use OpenWRT SDK in Docker** (faster, isolated):

```bash
# Pull OpenWRT SDK for armsr-armv8
docker pull openwrt/sdk:armsr-armv8

# Run with your repo mounted
docker run -v $(pwd):/openwrt -it openwrt/sdk:armsr-armv8

# Inside container, build morse driver
cd /openwrt
make package/morse_driver/compile V=s
```

---

## Deployment

### Copy to Target Device

```bash
# Set your device details
DEVICE_IP="192.168.1.100"
DEVICE_USER="root"

# Method 1: Direct copy (if built on OpenWRT)
scp build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko \
    ${DEVICE_USER}@${DEVICE_IP}:/tmp/

scp build_dir/target-aarch64*/linux-*/morse_driver-*/dot11ah/dot11ah.ko \
    ${DEVICE_USER}@${DEVICE_IP}:/tmp/

# Method 2: Create tarball
mkdir -p /tmp/morse_tsf_v2
cp build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko /tmp/morse_tsf_v2/
cp build_dir/target-aarch64*/linux-*/morse_driver-*/dot11ah/dot11ah.ko /tmp/morse_tsf_v2/
tar -czf morse_tsf_v2.tar.gz -C /tmp morse_tsf_v2/

scp morse_tsf_v2.tar.gz ${DEVICE_USER}@${DEVICE_IP}:/tmp/
```

### Install on Target

```bash
# SSH to target device
ssh ${DEVICE_USER}@${DEVICE_IP}

# Option A: Install from /tmp (if copied directly)
sudo rmmod morse
sudo rmmod dot11ah  # Only if replacing both
sudo insmod /tmp/dot11ah.ko
sudo insmod /tmp/morse.ko country=US

# Option B: Install from tarball
cd /tmp
tar -xzf morse_tsf_v2.tar.gz
cd morse_tsf_v2
sudo rmmod morse
sudo rmmod dot11ah
sudo insmod dot11ah.ko
sudo insmod morse.ko country=US

# Verify loaded
lsmod | grep morse
dmesg | tail -20
```

### Make Permanent (Optional)

```bash
# Copy to system modules directory
KERNEL_VER=$(uname -r)
sudo cp morse.ko /lib/modules/${KERNEL_VER}/kernel/drivers/net/wireless/
sudo cp dot11ah.ko /lib/modules/${KERNEL_VER}/kernel/net/wireless/

# Update module dependencies
sudo depmod -a

# Load at boot (add to /etc/modules)
echo "dot11ah" | sudo tee -a /etc/modules
echo "morse country=US" | sudo tee -a /etc/modules

# Or create modprobe config
echo "options morse country=US" | sudo tee /etc/modprobe.d/morse.conf
```

---

## Verification

### Check Module Loading

```bash
# Verify modules loaded
lsmod | grep morse
# Should show: morse, dot11ah

lsmod | grep dot11ah
# Should show: dot11ah

# Check module info
modinfo morse | head -20
modinfo dot11ah | head -10

# Verify dependencies resolved
modinfo morse | grep depends
# Should show: depends:        mac80211,cfg80211,dot11ah
```

### Verify TSF Sync v2.0

```bash
# Mount debugfs (if not already mounted)
sudo mount -t debugfs none /sys/kernel/debug

# Check debugfs files exist
ls -l /sys/kernel/debug/ieee80211/phy0/morse/
# Should show: tsf_rx, tsf_current (among other files)

# Test tsf_rx (Client/Gateway use)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
# Output format:
# TSF: 123456789012345
# SYS: 1700000000000000000

# Test tsf_current (AP/Robot use)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
# Output format:
# TSF: 123456789012567
# SYS: 1700000000001000000

# Values should be non-zero after association
# If zero, wait for beacons or generate traffic
```

### Check Network Association

```bash
# Bring up interface
sudo ip link set wlan0 up

# Scan for networks
sudo iw dev wlan0 scan | grep -E "SSID|freq"

# For Client: Connect to AP
sudo iw dev wlan0 connect "YourSSID"

# For AP: Start hostapd
sudo hostapd /etc/hostapd/hostapd.conf

# Check link status
iw dev wlan0 link

# Check station info (if connected)
iw dev wlan0 station dump
```

### Monitor TSF Updates

```bash
# Watch TSF values change in real-time
watch -n 1 'cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current'

# Compare tsf_rx vs tsf_current
while true; do
    echo "=== $(date) ==="
    echo "tsf_rx:"; cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
    echo "tsf_current:"; cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
    sleep 1
done
```

---

## Troubleshooting

### Build Failures

#### Issue: Toolchain Build Fails

```bash
# Clean and rebuild
make toolchain/install/clean
make toolchain/install V=s

# Check disk space
df -h /home/dzezula/openwrt
# Need at least 15 GB free
```

#### Issue: Kernel Build Fails

```bash
# Clean kernel
make target/linux/clean
make target/linux/install V=s

# Check for missing dependencies
./scripts/feeds update -a
./scripts/feeds install -a
```

#### Issue: Morse Driver Build Fails

```bash
# Check patch applied correctly
grep "tsf_rx_show" feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch

# Clean and rebuild
make package/feeds/morse/morse_driver/clean
make package/feeds/morse/morse_driver/compile V=s 2>&1 | tee build.log

# Check build log for errors
grep -i error build.log
```

### Deployment Issues

#### Issue: Module Won't Load

```bash
# Check kernel version matches
modinfo morse.ko | grep vermagic
uname -r
# Must match!

# Check dependencies
modinfo morse.ko | grep depends
lsmod | grep mac80211
lsmod | grep cfg80211
lsmod | grep dot11ah

# Load dependencies manually if needed
sudo modprobe mac80211
sudo modprobe cfg80211
sudo insmod dot11ah.ko
sudo insmod morse.ko
```

#### Issue: Wrong Architecture

```bash
# Check module architecture
file morse.ko
# Should show: ARM aarch64 (for aarch64 target)

# Check system architecture
uname -m
# Should show: aarch64

# If mismatch, rebuild for correct architecture
```

#### Issue: Symbol Errors

```bash
# Check dmesg for symbol issues
dmesg | tail -50 | grep -i "unknown symbol"

# Usually means kernel version mismatch
# Rebuild for exact kernel version:
make KERNEL_SRC=/lib/modules/$(uname -r)/build
```

### Runtime Issues

#### Issue: Debugfs Files Don't Exist

```bash
# Verify debugfs mounted
mount | grep debugfs
sudo mount -t debugfs none /sys/kernel/debug

# Check driver built with DEBUG enabled
modinfo morse | grep -i debug
# Should show debug-related info

# Verify correct path
ls /sys/kernel/debug/ieee80211/
ls /sys/kernel/debug/ieee80211/phy0/morse/
```

#### Issue: TSF Values Always Zero

```bash
# Check association status
iw dev wlan0 link
# Must be associated

# Generate traffic to receive packets
ping -c 5 <gateway_ip>

# Watch for beacons
sudo tcpdump -i wlan0 -e -n type mgt subtype beacon

# Check beacon interval
iw dev wlan0 scan | grep -i "beacon interval"
```

---

## Build Time Estimates

| Phase | First Build | Incremental | Notes |
|-------|-------------|-------------|-------|
| **On-Device Build** | 5-10 min | 2-3 min | ✅ Fastest method |
| Download | 15-30 min | N/A | OpenWRT only |
| Toolchain | 30-60 min | N/A | Cached after first build |
| Kernel | 10-20 min | 2-5 min | OpenWRT only |
| Morse Driver | 2-5 min | 30-60 sec | Actual driver build |
| **Total (OpenWRT)** | **60-120 min** | **5-10 min** | For cross-compilation |

## System Requirements

### On-Device Build
- **Disk Space**: 1-2 GB
- **RAM**: 2 GB minimum
- **Prerequisites**: kernel-headers, build-essential

### OpenWRT Cross-Compilation
- **Disk Space**: 15-20 GB
- **RAM**: 8 GB recommended (4 GB minimum)
- **CPU**: Multi-core recommended
- **Network**: Stable connection for downloads

---

## Quick Reference

### Essential Commands

```bash
# Build on device
cd morse_driver
make KERNEL_SRC=/lib/modules/$(uname -r)/build

# Build with OpenWRT
make package/feeds/morse/morse_driver/compile V=s

# Install modules
sudo insmod dot11ah.ko
sudo insmod morse.ko country=US

# Check TSF sync
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current

# Monitor
watch -n 1 'cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current'
```

### File Locations

| Item | Location |
|------|----------|
| **Patch File** | `patches/morse_driver/999-tsf-sync.patch` |
| **On-Device Build** | `morse_driver/morse.ko`, `morse_driver/dot11ah/dot11ah.ko` |
| **OpenWRT Build** | `build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko` |
| **tsf_rx** | `/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx` |
| **tsf_current** | `/sys/kernel/debug/ieee80211/phy0/morse/tsf_current` |

---

## Summary

- ✅ **Recommended**: Build directly on target device (5-10 min)
- ⏱️ **Alternative**: OpenWRT cross-compilation (1-2 hours first time)
- 📦 **Artifacts**: morse.ko (~1.2 MB) + dot11ah.ko (~200 KB)
- 🎯 **Target**: aarch64 kernel 5.15.16 (MM8108/MM6108)
- ✨ **Features**: TSF sync v2.0 with dual debugfs interface

For technical details and usage, see **TSF_SYNC_GUIDE.md**
