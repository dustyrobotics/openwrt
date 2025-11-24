# OpenWRT Cross-Compilation Guide for Morse Driver with TSF Sync v2.0

This guide covers cross-compiling the morse_driver with TSF sync v2.0 patch using OpenWRT for aarch64 targets.

## What This Guide Provides

- **Cross-compilation** from x86_64 → aarch64 (ARM 64-bit)
- **TSF sync v2.0** with dual debugfs interface
- **OpenWRT build system** integration
- **Patch fix** that applies correctly after other OpenWRT patches

## Prerequisites

### Build System Requirements

- **OS**: Ubuntu 20.04 LTS or newer (x86_64)
- **CPU**: 12+ cores recommended
- **RAM**: 16 GB minimum
- **Disk**: 400 GB free space
- **Time**: 45-90 minutes for first build

### Install Dependencies

```bash
sudo apt update
sudo apt install -y build-essential clang flex g++ gawk gcc-multilib \
  git gettext libncurses5-dev libssl-dev python3-distutils rsync \
  unzip zlib1g-dev swig file wget time
```

## Quick Start

### 1. Clone OpenWRT Repository

```bash
git clone https://github.com/dustyrobotics/openwrt.git
cd openwrt
git checkout 2.9-dev
```

### 2. Update Feeds

```bash
./scripts/feeds update -a
./scripts/feeds install -a
```

### 3. Install TSF Sync v2.0 Patch

The fixed TSF sync v2.0 patch is already in this repo at:
```bash
patches/morse_driver/999-tsf-sync.patch
```

Copy it to the OpenWRT morse_driver patches directory:

```bash
cp patches/morse_driver/999-tsf-sync.patch \
   feeds/morse/essentials/morse_driver/patches/
```

### 4. Configure Build

```bash
# For generic ARM64 (armv8)
./scripts/morse_setup.sh -i -b ekh-armsr_armv8

# OR for specific boards:
# ./scripts/morse_setup.sh -i -b ekh-bcm2711  # Raspberry Pi 4
```

### 5. Build

#### Option A: Build Just morse_driver (Fastest)

```bash
make package/feeds/morse/morse_driver/compile V=s 2>&1 | tee build_morse.log
```

Build time: ~5-10 minutes (after toolchain is built)

#### Option B: Complete Three-Phase Build (Recommended First Time)

```bash
# Phase 1: Toolchain (30-60 min)
make toolchain/install -j12 V=s 2>&1 | tee build_toolchain.log

# Phase 2: Kernel (10-20 min)
make target/linux/install -j12 V=s 2>&1 | tee build_kernel.log

# Phase 3: Morse Driver (2-5 min)
make package/feeds/morse/morse_driver/compile V=s 2>&1 | tee build_morse.log
```

Total time: ~45-90 minutes

### 6. Verify Build Success

```bash
# Check that patch applied successfully
grep "patching file debug.c" build_morse.log
grep "patching file mac.c" build_morse.log

# Should see NO "FAILED" messages

# Find built modules
find build_dir -name "morse.ko" -o -name "dot11ah.ko"
```

Expected output:
```
build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/morse.ko
build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/dot11ah/dot11ah.ko
```

### 7. Verify TSF Symbols

```bash
# Check for TSF sync v2.0 symbols
nm build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/morse.ko \
  | grep -E "tsf|morse_get_tsf_snapshot|morse_capture_rx_tsf"
```

Expected symbols:
- `last_rx_hw_tsf_us` - TSF timestamp storage
- `tsf_sync_lock` - Spinlock for synchronization
- `morse_get_tsf_snapshot` - Exported function to get TSF values

## TSF Sync v2.0 Features

### Dual Debugfs Interface

The v2.0 patch creates **two** debugfs files:

1. **`tsf_rx`** - For Clients/Gateways (Slave role)
   - Shows TSF from last received management/beacon frame
   - Use this to calculate packet arrival time
   - Python reads this to determine time offset

2. **`tsf_current`** - For APs/Robots (Master role)
   - Shows current extrapolated TSF timestamp
   - Calculated from last RX + time delta
   - Use this to get current hardware time for broadcasting

### What Changed from v1.0

**v1.0** (old - don't use):
- Only captured beacons
- Single `tsf_sync` interface
- Required being connected to AP

**v2.0** (current):
- Captures ALL management/beacon frames (more frequent updates)
- Dual interface (`tsf_rx` + `tsf_current`)
- Works for both AP and Client roles
- Exported `morse_get_tsf_snapshot()` function
- More accurate extrapolation

## Deployment to Target Device

### Copy Modules to Target

```bash
# From build system
scp build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/morse.ko \
    user@target-device:/tmp/

scp build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/dot11ah/dot11ah.ko \
    user@target-device:/tmp/
```

### Load on Target Device

```bash
# On target aarch64 device (MM8108/MM6108)
sudo rmmod morse 2>/dev/null || true
sudo rmmod dot11ah 2>/dev/null || true

sudo insmod /tmp/dot11ah.ko
sudo insmod /tmp/morse.ko country=US

# Verify loaded
lsmod | grep morse
dmesg | tail -20
```

### Mount Debugfs (if needed)

```bash
sudo mount -t debugfs none /sys/kernel/debug
```

### Verify TSF Debugfs Files

```bash
ls -la /sys/kernel/debug/ieee80211/phy0/morse/tsf_*
```

Expected:
```
-r--r--r-- 1 root root 0 tsf_rx
-r--r--r-- 1 root root 0 tsf_current
```

### Test TSF Sync

```bash
# On Client/Gateway - read last RX packet TSF
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx

# On AP/Robot - read current extrapolated TSF
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
```

Output format:
```
TSF: 123456789012345
SYS: 1700000000000000000
```

## Troubleshooting

### Patch Fails to Apply

**Problem**: Build log shows "Hunk #X FAILED"

**Cause**: The 999-tsf-sync.patch doesn't account for other OpenWRT patches applied first.

**Solution**: Use the fixed patch from this repo at `patches/morse_driver/999-tsf-sync.patch`

This patch was regenerated to apply correctly AFTER patches 001-015, accounting for line number shifts (up to 522 lines in some cases).

### Patch Already Applied Error

**Problem**: "patch unexpectedly ends in middle of line"

**Solution**: Clean and rebuild

```bash
make package/feeds/morse/morse_driver/clean
make package/feeds/morse/morse_driver/compile V=s
```

### No TSF Symbols in morse.ko

**Problem**: `nm morse.ko | grep tsf` shows nothing

**Cause**: Old patch was applied or build failed

**Solution**:
1. Verify correct patch: `cat feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch`
2. Should show `morse_get_tsf_snapshot` and `last_rx_hw_tsf_us`
3. Clean and rebuild

### TSF Files Don't Exist

**Problem**: `/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx` not found

**Cause**: Driver not built with DEBUG enabled

**Solution**: Check build config

```bash
make menuconfig
# Navigate to: Kernel modules -> Wireless Drivers -> kmod-morse
# Ensure DEBUG is enabled
```

Or check if debugfs is mounted:
```bash
mount | grep debugfs
sudo mount -t debugfs none /sys/kernel/debug
```

### TSF Values Always Zero

**Problem**: TSF reads as `TSF: 0` and `SYS: 0`

**Cause**: No management/beacon frames received yet

**Solution**:
1. Ensure wireless interface is UP: `ip link set wlan0 up`
2. Connect to AP or start as AP
3. Generate traffic: `ping <gateway>`
4. Wait for beacons (sent every 100ms typically)

## Patch Technical Details

### What the Patch Does

The 999-tsf-sync.patch modifies two files:

#### mac.c Changes

1. **Adds global variables** (after line ~78):
   ```c
   static u64 last_rx_hw_tsf_us = 0;
   static u64 last_rx_kernel_time_ns = 0;
   static DEFINE_SPINLOCK(tsf_sync_lock);
   ```

2. **Adds capture function** (before `morse_mac_process_s1g_mgmt_or_beacon`):
   ```c
   static void morse_capture_rx_tsf(const struct morse_skb_rx_status *hdr_rx_status)
   {
       unsigned long flags;
       spin_lock_irqsave(&tsf_sync_lock, flags);
       last_rx_hw_tsf_us = le64_to_cpu(hdr_rx_status->rx_timestamp_us);
       last_rx_kernel_time_ns = ktime_get_real_ns();
       spin_unlock_irqrestore(&tsf_sync_lock, flags);
   }
   ```

3. **Adds export function**:
   ```c
   void morse_get_tsf_snapshot(u64 *hw_tsf_us, u64 *kernel_time_ns)
   {
       // Thread-safe read of TSF values
   }
   ```

4. **Calls capture** in `morse_mac_process_s1g_mgmt_or_beacon`:
   - Captures TSF from ALL received management and beacon frames
   - Called early in frame processing

#### debug.c Changes

1. **Adds extern declaration** (after includes):
   ```c
   extern void morse_get_tsf_snapshot(u64 *hw_tsf_us, u64 *kernel_time_ns);
   ```

2. **Adds tsf_rx_show()** function:
   - Shows last RX packet TSF
   - For Client/Gateway use

3. **Adds tsf_current_show()** function:
   - Extrapolates current TSF from last RX
   - For AP/Robot use
   - Formula: `current_tsf = last_rx_tsf + (current_time - last_rx_time)`

4. **Creates debugfs files** in `morse_debug_fw_init()`:
   ```c
   debugfs_create_file("tsf_rx", 0444, ...);
   debugfs_create_file("tsf_current", 0444, ...);
   ```

### Why the Patch Needed Fixing

**Original patch**: Created against pristine morse_driver v1.16.4

**Problem**: OpenWRT applies 9 patches (001-015) BEFORE 999-tsf-sync.patch:
- Patch 008 shifted mac.c by 522 lines!
- Line numbers in original patch no longer matched
- All hunks failed to apply

**Fix**: Regenerated patch by:
1. Extracting morse_driver v1.16.4
2. Applying patches 001-015 sequentially
3. Making TSF modifications on patched source
4. Creating new diff with correct line numbers

**Result**: Patch now applies cleanly in OpenWRT build system

## Build Artifacts

### File Sizes

```
morse.ko:     ~3.2 MB (main driver with TSF sync v2.0)
dot11ah.ko:   ~491 KB (802.11ah support)
```

### File Locations After Build

```
build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/
├── morse.ko          - Main module
├── dot11ah/
│   └── dot11ah.ko    - 802.11ah module
└── ipkg-aarch64_generic/kmod-morse/lib/modules/5.15.167/
    ├── morse.ko      - Packaged module
    └── dot11ah.ko    - Packaged module
```

## Usage Examples

### Python Script for Client (Gateway)

```python
#!/usr/bin/env python3
"""Read TSF from last received packet (Client/Gateway role)"""

def read_tsf_rx():
    with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx', 'r') as f:
        lines = f.readlines()

    tsf_us = int(lines[0].split(': ')[1])
    sys_ns = int(lines[1].split(': ')[1])

    return tsf_us, sys_ns

# Read when packet arrives
hw_tsf_us, kernel_time_ns = read_tsf_rx()

print(f"Packet arrived at:")
print(f"  Hardware TSF: {hw_tsf_us} µs")
print(f"  Kernel time:  {kernel_time_ns} ns")

# Calculate packet flight time, sync clocks, etc.
```

### Python Script for AP (Robot)

```python
#!/usr/bin/env python3
"""Get current TSF for broadcasting (AP/Robot role)"""

def read_tsf_current():
    with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_current', 'r') as f:
        lines = f.readlines()

    tsf_us = int(lines[0].split(': ')[1])
    sys_ns = int(lines[1].split(': ')[1])

    return tsf_us, sys_ns

# Get current time for sync packet
current_tsf_us, current_sys_ns = read_tsf_current()

print(f"Broadcasting time:")
print(f"  Current TSF: {current_tsf_us} µs")
print(f"  System time: {current_sys_ns} ns")

# Include in time sync broadcast packet
```

## Quick Reference

### Build Commands

```bash
# Clean build
make package/feeds/morse/morse_driver/clean
make package/feeds/morse/morse_driver/compile V=s

# Find modules
find build_dir -name "morse.ko"

# Check symbols
nm build_dir/*/linux-*/morse_driver-*/morse.ko | grep tsf
```

### Target Commands

```bash
# Load modules
sudo insmod dot11ah.ko
sudo insmod morse.ko country=US

# Read TSF (Client)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx

# Read TSF (AP)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current

# Monitor updates
watch -n 0.1 'cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx'
```

## Files in This Repository

```
openwrt/
├── patches/morse_driver/
│   └── 999-tsf-sync.patch                 ← Fixed patch for OpenWRT
├── OPENWRT_CROSS_COMPILE_GUIDE.md         ← This file
├── BUILD_INSTRUCTIONS_ARM64.md            ← Native ARM64 build guide
├── QUICKSTART.md                          ← Quick start guide
└── morse_tsf_sync_README.md               ← Technical documentation
```

## Summary

This guide showed you how to:
- ✅ Cross-compile morse_driver for aarch64 using OpenWRT
- ✅ Apply TSF sync v2.0 patch correctly after other OpenWRT patches
- ✅ Build and verify kernel modules with TSF support
- ✅ Deploy to target devices
- ✅ Use dual debugfs interface for both AP and Client roles

The TSF sync v2.0 patch enables high-precision (< 100 µs) time synchronization for HaLow mesh networks.
