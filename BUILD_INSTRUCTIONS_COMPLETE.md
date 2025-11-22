# Complete Build Instructions for Morse Driver with TSF Sync v2.0

## Current Status

✅ **Build Environment**: Configured for aarch64 kernel 5.15
✅ **TSF Patch v2.0**: Already in place at `patches/morse_driver/999-tsf-sync.patch`
✅ **Dependencies**: gawk, ncurses installed
✅ **Target**: armsr/armv8 (aarch64)

## Quick Build (Driver Only - ~1-2 hours first time)

```bash
cd /home/dzezula/openwrt

# Download all package sources (15-30 min)
make download -j$(nproc)

# Build toolchain (30-60 min first time)
make toolchain/install -j$(nproc) V=s

# Build kernel headers (10-20 min)
make target/linux/compile -j$(nproc) V=s

# Build morse driver with TSF sync patch (2-5 min)
make package/feeds/morse/morse_driver/compile V=s

# Find your modules
find build_dir/target-aarch64* -name "morse.ko"
find build_dir/target-aarch64* -name "dot11ah.ko"
```

## What Gets Built

After successful build:

```
build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/
├── morse.ko          ← Main driver with TSF sync v2.0 (for your MM8108)
└── dot11ah/
    └── dot11ah.ko    ← 802.11ah support
```

## Alternative: Incremental Build (Faster)

If the build fails or takes too long, you can build prerequisites separately:

### Step 1: Build Toolchain
```bash
make toolchain/install -j$(nproc) V=99 2>&1 | tee build_toolchain.log
```

### Step 2: Build Kernel
```bash
make target/linux/install -j$(nproc) V=99 2>&1 | tee build_kernel.log
```

### Step 3: Build Dependencies
```bash
make package/kernel/mac80211/compile -j$(nproc) V=s
```

### Step 4: Build Morse Driver
```bash
make package/feeds/morse/morse_driver/compile V=s 2>&1 | tee build_morse.log
```

## Troubleshooting Build Issues

### Issue: Toolchain Build Fails

```bash
# Clean and retry
make clean
rm -rf build_dir/toolchain-*
make toolchain/install V=s
```

### Issue: Out of Disk Space

```bash
# Check space
df -h .

# Clean unnecessary files
make clean
rm -rf build_dir/target-*/root-*
```

### Issue: Network Download Failures

```bash
# Retry downloads
rm -rf dl/
make download -j1 V=s  # Single threaded for reliability
```

## Verify Build Success

```bash
# Check files exist
ls -lh build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko
ls -lh build_dir/target-aarch64*/linux-*/morse_driver-*/dot11ah/dot11ah.ko

# Verify architecture
file build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko
# Should show: ELF 64-bit LSB relocatable, ARM aarch64

# Check kernel version
modinfo build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko | grep vermagic
# Should show: 5.15.167 ... aarch64

# Verify TSF sync patch applied
nm build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko | grep -E "tsf_rx_show|tsf_current_show"
# Should find both functions
```

## Deploy to Your MM8108 Device

### Copy Files

```bash
# Set your device IP
DEVICE_IP="192.168.1.100"
DEVICE_USER="root"

# Copy both modules
scp build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko ${DEVICE_USER}@${DEVICE_IP}:/tmp/
scp build_dir/target-aarch64*/linux-*/morse_driver-*/dot11ah/dot11ah.ko ${DEVICE_USER}@${DEVICE_IP}:/tmp/
```

### Install on MM8108

```bash
# SSH to your MM8108 device
ssh ${DEVICE_USER}@${DEVICE_IP}

# Unload old modules
sudo rmmod morse
sudo rmmod dot11ah  # Only if replacing both

# Load new modules with TSF sync
sudo insmod /tmp/dot11ah.ko
sudo insmod /tmp/morse.ko country=US

# Verify loaded
lsmod | grep morse

# Check TSF sync interfaces exist
ls -l /sys/kernel/debug/ieee80211/phy0/morse/tsf_*

# Test (should show TSF timestamps)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
```

## Expected Output

### tsf_rx (for Client/Gateway)
```
TSF: 123456789012345
SYS: 1700000000000000000
```

### tsf_current (for AP/Robot)
```
TSF: 123456789012567
SYS: 1700000000001000000
```

## Build Time Estimates

| Task | First Build | Incremental |
|------|-------------|-------------|
| Download | 15-30 min | N/A |
| Toolchain | 30-60 min | N/A (cached) |
| Kernel | 10-20 min | 2-5 min |
| Morse Driver | 2-5 min | 30-60 sec |
| **Total** | **60-120 min** | **5-10 min** |

## System Requirements

- **Disk Space**: 15-20 GB free
- **RAM**: 8 GB recommended (4 GB minimum)
- **CPU**: Multi-core recommended for `-j$(nproc)`
- **Network**: Stable connection for downloads

## If Build Still Fails

### Option 1: Use Docker

```bash
# Use OpenWRT SDK in Docker (faster, isolated)
docker pull openwrt/sdk:armsr-armv8

# Mount your repo and build
docker run -v $PWD:/openwrt -it openwrt/sdk:armsr-armv8
```

### Option 2: Manual Kernel Module Build

If you have access to the morse_driver source and kernel headers on your MM8108 device:

```bash
# On your MM8108 device
git clone https://github.com/MorseMicro/morse_driver.git
cd morse_driver

# Apply TSF sync patch
patch -p1 < /path/to/999-tsf-sync.patch

# Build directly (if kernel headers installed)
make KERNEL_SRC=/lib/modules/$(uname -r)/build

# Result: morse.ko and dot11ah/dot11ah.ko built for your exact kernel
```

### Option 3: Pre-built Modules

If you can provide:
- Exact kernel version: `uname -r`
- Kernel config: `zcat /proc/config.gz`
- Existing morse.ko: `modinfo morse`

I can help identify if pre-built modules exist or guide you to build directly on your device.

## Files Ready for You

All TSF sync v2.0 files are in this repo:

```
/home/dzezula/openwrt/
├── patches/morse_driver/999-tsf-sync.patch           ← v2.0 patch
├── feeds/morse/essentials/morse_driver/patches/
│   └── 999-tsf-sync.patch                            ← Applied during build
├── morse_tsf_sync_README.md                          ← Technical docs
├── MM6108_vs_MM8108_COMPATIBILITY.md                 ← MM8108 compatibility
├── BUILD_FOR_AARCH64_KERNEL_5.15.md                  ← Build guide
├── BUILD_ARTIFACTS.md                                ← Artifact details
└── IMPLEMENTATION_SUMMARY.md                         ← Implementation overview
```

## Next Steps

1. **Run the build** (expect 1-2 hours first time):
   ```bash
   make toolchain/install target/linux/install -j$(nproc)
   make package/feeds/morse/morse_driver/compile V=s
   ```

2. **Or build on your MM8108 directly** (if kernel headers available)

3. **Or let me know** if you prefer another approach

The build environment is ready - just needs time to compile! 🚀
