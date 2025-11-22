# TSF Sync Patch - Quick Start Guide

## What's Been Done

✅ TSF sync patch created and installed at:
- `feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch`

✅ Documentation created:
- `BUILD_INSTRUCTIONS_ARM64.md` - Complete build guide for Ubuntu 20.04 ARM64
- `morse_tsf_sync_README.md` - Technical details about the patch

## For a Brand New Ubuntu 20.04 ARM64 System

### 1. Install Dependencies (5 minutes)
```bash
sudo apt update
sudo apt install -y build-essential clang flex g++ gawk gcc-multilib \
  git gettext libncurses5-dev libssl-dev python3-distutils rsync \
  unzip zlib1g-dev swig file wget time
```

### 2. Clone and Setup (10 minutes)
```bash
cd ~
git clone https://github.com/dustyrobotics/openwrt.git
cd openwrt
git checkout 2.9-dev
./scripts/feeds update -a
./scripts/feeds install -a
```

### 3. Add the TSF Sync Patch (1 minute)
```bash
mkdir -p feeds/morse/essentials/morse_driver/patches

cat > feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch << 'EOF'
[Copy the patch content from morse_tsf_sync.patch]
EOF
```

**OR** if you're on this system already:
```bash
# Patch is already installed at:
ls -la feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch
```

### 4. Configure for Your Board (2 minutes)
```bash
# For generic ARM64
./scripts/morse_setup.sh -i -b ekh-armsr_armv8

# OR for Raspberry Pi 4
./scripts/morse_setup.sh -i -b ekh-bcm2711
```

### 5. Build (30-120 minutes first time)
```bash
# Just the driver (faster - ~30 min)
make package/feeds/morse/morse_driver/compile V=s

# OR full image (complete - ~2 hours)
make -j$(nproc) V=s
```

### 6. On Target ARM64 System

#### Load the Driver
```bash
sudo modprobe mac80211
sudo insmod dot11ah.ko
sudo insmod morse.ko country=US
```

#### Configure Interface
```bash
sudo ip link set wlan0 up
sudo iw dev wlan0 connect "YourAP"
```

#### Read TSF Data
```bash
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_sync
```

Output:
```
hw_tsf_us: 123456789012345
kernel_time_ns: 1700000000000000000
```

## Current System Status

**Your system** (`/home/dzezula/openwrt`):
- ✅ Branch: 2.9-dev
- ✅ Feeds: Updated (morse feed cloned)
- ✅ Patch: Installed in `feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch`
- ⏳ Ready to configure and build

## What the Patch Does

1. **Captures** hardware TSF timestamp from beacon RX descriptor
2. **Captures** kernel time (`ktime_get_real_ns()`) at same moment
3. **Stores** both values safely with spinlock protection
4. **Exposes** via debugfs at `/sys/kernel/debug/ieee80211/phy0/morse/tsf_sync`

## Next Steps

1. **Configure your build** for your target board
2. **Build** the driver or full image
3. **Load** on your ARM64 Ubuntu 20.04 target
4. **Connect** to an AP (to receive beacons)
5. **Read** TSF sync data from debugfs

## Files Reference

```
/home/dzezula/openwrt/
├── morse_tsf_sync.patch                      # Original patch
├── QUICKSTART.md                             # This file
├── BUILD_INSTRUCTIONS_ARM64.md               # Complete build guide
├── morse_tsf_sync_README.md                  # Technical documentation
└── feeds/morse/essentials/morse_driver/
    └── patches/
        └── 999-tsf-sync.patch               # Installed patch ✓
```

## Quick Commands

```bash
# On build system
cd ~/openwrt
./scripts/morse_setup.sh -i -b ekh-armsr_armv8
make package/feeds/morse/morse_driver/compile V=s

# On target system
sudo insmod morse.ko
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_sync
```

## Get Help

See detailed documentation:
- **BUILD_INSTRUCTIONS_ARM64.md** - Complete step-by-step build guide
- **morse_tsf_sync_README.md** - Patch details and troubleshooting
