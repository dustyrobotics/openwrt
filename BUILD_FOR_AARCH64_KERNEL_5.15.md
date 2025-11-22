# Quick Build Guide: aarch64 Kernel 5.15.16 with TSF Sync v2.0

## Target Configuration

- **Architecture**: aarch64 (ARM 64-bit Cortex-A53)
- **Kernel**: 5.15.167 (via armsr/armv8 target)
- **TSF Patch**: v2.0 (already in place)
- **Driver Version**: morse_driver 1.16.4

## Quick Start

### 1. Configure Build

```bash
cd /home/dzezula/openwrt

# Configure for aarch64 with kernel 5.15.16
./scripts/morse_setup.sh -i -b ekh-armsr_armv8

# This automatically:
# - Sets target to armsr/armv8 (aarch64)
# - Uses kernel 5.15.167
# - Enables CONFIG_MORSE_DEBUG=y (required for TSF debugfs)
# - Applies all patches including 999-tsf-sync.patch v2.0
```

### 2. Build the Driver

```bash
# Clean previous builds (if any)
make package/feeds/morse/morse_driver/clean

# Build just the morse driver (fastest - ~2-5 minutes)
make package/feeds/morse/morse_driver/compile V=s

# OR build full firmware image (~60-120 minutes)
make -j$(nproc) V=s
```

### 3. Locate Build Artifacts

```bash
# Find the kernel modules
find build_dir/target-aarch64* -name "morse.ko"
find build_dir/target-aarch64* -name "dot11ah.ko"

# Typical location:
# build_dir/target-aarch64_cortex-a53_musl/linux-armsr_armv8/morse_driver-1.16.4/morse.ko
# build_dir/target-aarch64_cortex-a53_musl/linux-armsr_armv8/morse_driver-1.16.4/dot11ah/dot11ah.ko
```

## Build Artifacts

### Primary Outputs

1. **morse.ko** (~1.2 MB with debug symbols)
   - Main HaLow driver with TSF sync v2.0
   - Includes `tsf_rx` and `tsf_current` debugfs support

2. **dot11ah.ko** (~200 KB)
   - 802.11ah protocol support

3. **kmod-morse_*.ipk** (optional, if full build)
   - IPK package in `bin/targets/armsr/armv8/packages/`

### Verify Build

```bash
# Check architecture
file build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko
# Should output: ELF 64-bit LSB relocatable, ARM aarch64

# Check kernel version
modinfo build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko | grep vermagic
# Should show: 5.15.167 ... aarch64

# Verify TSF sync v2.0 symbols
nm build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko | grep -E "tsf_rx_show|tsf_current_show"
# Should find both functions
```

## TSF Sync Patch v2.0 Status

✅ **Patch Location**:
- `/home/dzezula/openwrt/patches/morse_driver/999-tsf-sync.patch`
- `/home/dzezula/openwrt/feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch`

✅ **Auto-Applied During Build**: Yes (by OpenWRT build system)

✅ **Features**:
- Dual debugfs interface: `tsf_rx` + `tsf_current`
- Captures TSF from all management/beacon frames
- Works for both AP and Client with same driver
- Extrapolated current TSF for AP broadcasts

## Deploy to Target aarch64 Device

### Method 1: Copy Kernel Modules

```bash
# Copy to target device (Ubuntu 20.04 aarch64 with kernel 5.15.16)
scp build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko user@target:/tmp/
scp build_dir/target-aarch64*/linux-*/morse_driver-*/dot11ah/dot11ah.ko user@target:/tmp/

# On target device
sudo insmod /tmp/dot11ah.ko
sudo insmod /tmp/morse.ko country=US

# Verify
lsmod | grep morse
dmesg | tail -20
```

### Method 2: Install IPK Package

```bash
# If you built the full image
scp bin/targets/armsr/armv8/packages/kmod-morse*.ipk user@target:/tmp/

# On target (if OpenWRT-based)
opkg install /tmp/kmod-morse*.ipk
```

## Verify TSF Sync v2.0 Working

```bash
# On target device after loading driver
sudo mount -t debugfs none /sys/kernel/debug

# Check debugfs files exist
ls -l /sys/kernel/debug/ieee80211/phy0/morse/
# Should show: tsf_rx and tsf_current

# Test tsf_rx (for Client/Gateway)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
# Output format:
# TSF: 123456789012345
# SYS: 1700000000000000000

# Test tsf_current (for AP/Robot)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
# Output format:
# TSF: 123456789012567
# SYS: 1700000000001000000
```

## Build Troubleshooting

### Issue: Build Fails

```bash
# Clean everything and rebuild
make clean
./scripts/feeds update morse
./scripts/feeds install -a
./scripts/morse_setup.sh -i -b ekh-armsr_armv8
make package/feeds/morse/morse_driver/compile V=s 2>&1 | tee build.log
```

### Issue: Wrong Architecture

```bash
# Verify target config
grep "CONFIG_TARGET_armsr=y" .config
grep "CONFIG_TARGET_armsr_armv8=y" .config
# Both should exist and not be commented

# If wrong, reconfigure
./scripts/morse_setup.sh -i -b ekh-armsr_armv8
```

### Issue: TSF Symbols Missing

```bash
# Verify patch is in place
cat feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch | head -20
# Should show v2.0 patch with tsf_rx and tsf_current

# Verify debug is enabled
grep "CONFIG_MORSE_DEBUG=y" .config
# Must be enabled for debugfs support
```

## Expected Build Timeline

| Build Type | Clean Build | Incremental |
|------------|-------------|-------------|
| Driver only | 2-5 min | 30-60 sec |
| Full image | 60-120 min | 5-10 min |

## Build Environment Requirements

- **Disk Space**: ~15 GB minimum
- **RAM**: 4 GB minimum (8 GB recommended for parallel builds)
- **CPU**: Multi-core recommended (uses `make -j$(nproc)`)
- **OS**: Ubuntu 20.04 or similar (x86_64 build host, aarch64 target)

## Key Files Involved

### Patch Files
```
patches/morse_driver/999-tsf-sync.patch
feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch
```

### Configuration
```
boards/ekh-armsr_armv8              # Board config
target/linux/armsr/Makefile         # Kernel version: 5.15
target/linux/armsr/config-5.15      # Kernel config
feeds/morse/essentials/morse_driver/Makefile  # Driver package
```

### Build Outputs
```
build_dir/target-aarch64_cortex-a53_musl/linux-armsr_armv8/morse_driver-1.16.4/
├── morse.ko                        # Main driver
├── dot11ah/dot11ah.ko             # 802.11ah support
└── *.o                            # Object files

bin/targets/armsr/armv8/packages/
└── kmod-morse_5.15.167+1.16.4-3_aarch64_cortex-a53.ipk
```

## Documentation References

- **BUILD_ARTIFACTS.md**: Detailed artifact information
- **morse_tsf_sync_README.md**: TSF sync patch v2.0 technical docs
- **IMPLEMENTATION_SUMMARY.md**: Implementation overview
- **hack.md**: Original design specification

## Quick Reference Commands

```bash
# Configure
./scripts/morse_setup.sh -i -b ekh-armsr_armv8

# Build
make package/feeds/morse/morse_driver/compile V=s

# Find artifacts
find build_dir -name "morse.ko" -ls

# Verify
file build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko
modinfo build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko

# Deploy
scp build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko user@target:/tmp/
```

---

**Status**: ✅ Ready to Build
**Target**: aarch64 kernel 5.15.167
**TSF Patch**: v2.0 (dual debugfs)
**Build Time**: ~2-5 minutes (driver only)
