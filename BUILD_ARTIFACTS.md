# Morse Driver Build Artifacts - aarch64 Kernel 5.15.16

## Target Configuration

**Architecture**: aarch64 (ARM 64-bit)
**Kernel Version**: 5.15.16 (via armsr target)
**Target**: `armsr/armv8`
**Board Config**: `ekh-armsr_armv8`

## Build Artifacts Overview

### Primary Kernel Modules

When you build the morse driver with the TSF sync patch, you get these kernel modules:

#### 1. morse.ko
- **Description**: Main Morse Micro MM6108 HaLow driver with TSF sync support
- **Features Included**:
  - TSF timestamp capture from all management/beacon frames
  - Debugfs interfaces: `tsf_rx` and `tsf_current`
  - SDIO/SPI/USB transport support (depending on config)
  - 802.11ah S1G beacon processing
  - Vendor command interface
- **Size**: ~500KB - 1.2MB (varies with debug symbols)
- **Dependencies**: mac80211, cfg80211, dot11ah

#### 2. dot11ah/dot11ah.ko
- **Description**: 802.11ah (Wi-Fi HaLow) protocol support module
- **Features**: S1G operation classes, IE parsing, frequency management
- **Size**: ~100-200KB
- **Dependencies**: cfg80211

### Build Output Locations

#### During Build (Intermediate)
```
build_dir/target-aarch64_cortex-a53_musl/
└── linux-armsr_armv8/
    └── morse_driver-1.16.4/
        ├── morse.ko              # Main driver with TSF sync
        ├── dot11ah/
        │   └── dot11ah.ko        # 802.11ah support
        ├── *.o                   # Object files
        └── .*.cmd                # Build commands
```

#### After Build (Final Packages)
```
bin/targets/armsr/armv8/
├── packages/
│   └── kmod-morse_5.15.167+1.16.4-3_aarch64_cortex-a53.ipk
└── openwrt-armsr-armv8-generic-ext4-combined.img.gz  # Full image (if built)
```

## Detailed Artifact Information

### morse.ko Metadata

```bash
# Check module information
modinfo morse.ko

# Expected output includes:
filename:       morse.ko
license:        GPLv2
version:        0-1.16.4
description:    Morse Micro WIFI HaLow driver
depends:        mac80211,cfg80211,dot11ah
vermagic:       5.15.167 SMP preempt mod_unload aarch64
parm:           country:Country code (charp)
```

### dot11ah.ko Metadata

```bash
modinfo dot11ah.ko

# Expected output:
filename:       dot11ah.ko
license:        GPLv2
version:        0-1.16.4
description:    802.11ah (S1G) support module
depends:        cfg80211
vermagic:       5.15.167 SMP preempt mod_unload aarch64
```

## TSF Sync Patch Integration

### What's Included in morse.ko

The TSF sync patch adds these symbols to morse.ko:

```bash
# Check for TSF sync symbols
nm morse.ko | grep -i tsf

# You should see:
# - morse_capture_rx_tsf
# - morse_get_tsf_snapshot
# - last_rx_hw_tsf_us
# - last_rx_kernel_time_ns
# - tsf_sync_lock
# - tsf_rx_show
# - tsf_current_show
# - tsf_rx_fops
# - tsf_current_fops
```

### Debugfs Files Created at Runtime

When morse.ko is loaded with `CONFIG_MORSE_DEBUG=y`:

```
/sys/kernel/debug/ieee80211/phy0/morse/
├── tsf_rx              # Last received frame TSF (for Client)
├── tsf_current         # Current extrapolated TSF (for AP)
├── ps_offload_data
├── watchdog
└── ... (other debug files)
```

## File Sizes (Typical)

### With Debug Symbols (CONFIG_MORSE_DEBUG=y)
```
morse.ko:       ~1.2 MB
dot11ah.ko:     ~200 KB
Total:          ~1.4 MB
```

### Without Debug Symbols (stripped)
```
morse.ko:       ~500 KB
dot11ah.ko:     ~100 KB
Total:          ~600 KB
```

### IPK Package
```
kmod-morse_*.ipk:  ~600 KB - 1.5 MB (compressed)
```

## Build Command for aarch64 Kernel 5.15.16

```bash
cd /home/dzezula/openwrt

# Configure for aarch64 with kernel 5.15
./scripts/morse_setup.sh -i -b ekh-armsr_armv8

# This sets:
# - TARGET_SYSTEM: armsr
# - TARGET_SUBTARGET: armv8 (aarch64)
# - KERNEL_PATCHVER: 5.15
# - CONFIG_MORSE_DEBUG: y (for debugfs)

# Build just the driver
make package/feeds/morse/morse_driver/compile V=s

# Or build full image
make -j$(nproc) V=s
```

## Verification After Build

### 1. Check Artifacts Exist

```bash
# Find the kernel modules
find build_dir -name "morse.ko" -ls
find build_dir -name "dot11ah.ko" -ls

# Check architecture
file build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko
# Should output: ELF 64-bit LSB relocatable, ARM aarch64, version 1 (SYSV)...

# Verify kernel version
modinfo build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko | grep vermagic
# Should show: 5.15.167 ... aarch64
```

### 2. Check Patch Applied

```bash
# Verify TSF sync symbols are present
nm build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko | grep -E "tsf_rx|tsf_current"

# Expected output:
# 0000000000001234 t tsf_rx_show
# 0000000000001567 t tsf_current_show
# 0000000000001890 r tsf_rx_fops
# 00000000000018b0 r tsf_current_fops
```

### 3. Check IPK Package

```bash
# Find the package
ls -lh bin/targets/armsr/armv8/packages/kmod-morse*.ipk

# Extract and examine
mkdir -p /tmp/check_morse
tar -xzf bin/targets/armsr/armv8/packages/kmod-morse*.ipk -C /tmp/check_morse
tar -xzf /tmp/check_morse/data.tar.gz -C /tmp/check_morse

# Check contents
ls -lh /tmp/check_morse/lib/modules/5.15.*/
```

## Deployment Options

### Option 1: Copy Kernel Modules Only

```bash
# Copy to target aarch64 device
scp build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko user@target:/tmp/
scp build_dir/target-aarch64*/linux-*/morse_driver-*/dot11ah/dot11ah.ko user@target:/tmp/

# On target (Ubuntu 20.04 aarch64 with kernel 5.15.16):
sudo insmod /tmp/dot11ah.ko
sudo insmod /tmp/morse.ko country=US

# Verify
lsmod | grep morse
ls /sys/kernel/debug/ieee80211/phy0/morse/tsf_*
```

### Option 2: Install IPK Package

```bash
# Copy IPK to target
scp bin/targets/armsr/armv8/packages/kmod-morse*.ipk user@target:/tmp/

# On target (if OpenWRT-based):
opkg install /tmp/kmod-morse*.ipk
```

### Option 3: Flash Full Image

```bash
# Use the complete firmware image
bin/targets/armsr/armv8/openwrt-armsr-armv8-generic-ext4-combined.img.gz

# Flash to SD card or boot device according to your board
```

## Build Dependencies (Already in morse.ko)

The following are linked into morse.ko:
- **mac80211**: Linux wireless stack
- **cfg80211**: Configuration API
- **dot11ah**: 802.11ah protocol support (separate module)

External firmware files (separate package):
- `morse-fw` package provides firmware binaries
- Located in `/lib/firmware/morse/` on target

## Cross-Compilation Details

### Toolchain Used
```
Target: aarch64-openwrt-linux-musl
GCC: 11.x or 12.x (depending on OpenWRT version)
Binutils: 2.37+
Kernel Headers: 5.15.167
```

### Compiler Flags (from Makefile)
```makefile
MORSE_MAKEDEFS += \
  CONFIG_MORSE_DEBUGFS=y       # Enables debugfs (tsf_rx, tsf_current)
  CONFIG_MORSE_SDIO=y          # SDIO transport (if enabled)
  DEBUG=y                      # Debug symbols
  KERNEL_SRC=$(LINUX_DIR)      # Kernel 5.15 source
```

## Expected Build Time

- **Clean build (first time)**:
  - Driver only: ~2-5 minutes
  - Full image: ~60-120 minutes

- **Incremental build** (patch change):
  - Driver only: ~30-60 seconds

## Build Output Summary

After successful build for **aarch64 kernel 5.15.16**:

| Artifact | Path | Size | Architecture | Purpose |
|----------|------|------|--------------|---------|
| morse.ko | `build_dir/.../morse.ko` | ~1.2MB | aarch64 | Main driver with TSF sync |
| dot11ah.ko | `build_dir/.../dot11ah.ko` | ~200KB | aarch64 | 802.11ah support |
| kmod-morse*.ipk | `bin/targets/armsr/armv8/packages/` | ~800KB | aarch64 | Installable package |
| firmware image | `bin/targets/armsr/armv8/` | ~50-100MB | aarch64 | Complete system (optional) |

## Next Steps After Build

1. **Verify artifacts**:
   ```bash
   file build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko
   # Confirm: ELF 64-bit LSB relocatable, ARM aarch64
   ```

2. **Check kernel version match**:
   ```bash
   modinfo build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko | grep vermagic
   # Must match target kernel: 5.15.167
   ```

3. **Deploy to target device** using one of the options above

4. **Load and test**:
   ```bash
   # On target
   sudo insmod dot11ah.ko
   sudo insmod morse.ko
   cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
   cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
   ```

## Troubleshooting Build Issues

### Issue: Wrong Architecture
```bash
# Check target config
grep CONFIG_TARGET .config | grep -v "^#"
# Should show: CONFIG_TARGET_armsr=y, CONFIG_TARGET_armsr_armv8=y
```

### Issue: Wrong Kernel Version
```bash
# Check kernel version
grep LINUX_VERSION include/kernel-5.15
# Should show: 5.15.167 or similar
```

### Issue: TSF Symbols Missing
```bash
# Verify patch was applied
grep -r "tsf_rx_show" build_dir/target-aarch64*/linux-*/morse_driver-*/debug.c
# Should find the function

# Check if DEBUG is enabled
grep CONFIG_MORSE_DEBUG .config
# Should show: CONFIG_MORSE_DEBUG=y
```

## Build Validation Checklist

- [ ] Target architecture: aarch64 ✓
- [ ] Kernel version: 5.15.16x ✓
- [ ] morse.ko exists and is aarch64 ELF
- [ ] dot11ah.ko exists and is aarch64 ELF
- [ ] TSF sync symbols present in morse.ko
- [ ] IPK package created (if full build)
- [ ] File sizes reasonable (~1.4MB total with debug)
- [ ] vermagic matches target kernel

---

**Build Target**: aarch64 (ARM 64-bit)
**Kernel**: 5.15.16x (armsr target)
**Driver Version**: 1.16.4
**TSF Sync Patch**: v2.0 (dual debugfs interface)
**Output**: morse.ko + dot11ah.ko (kernel modules)
