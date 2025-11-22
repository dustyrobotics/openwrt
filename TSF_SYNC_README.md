# Morse Driver TSF Synchronization - Documentation Index

High-precision time synchronization for Morse Micro MM6108/MM8108 HaLow devices.

**Version**: 2.0
**Driver**: morse_driver 1.16.4
**Target Accuracy**: < 100 µs

---

## 📚 Documentation Files

### Essential Reading

1. **[TSF_SYNC_GUIDE.md](TSF_SYNC_GUIDE.md)** - Complete technical guide
   - Architecture and design
   - How TSF sync works
   - MM6108/MM8108 compatibility
   - Python code examples
   - Troubleshooting

2. **[BUILD_GUIDE.md](BUILD_GUIDE.md)** - Build and deployment
   - On-device build (fastest - 5-10 min) ✅ RECOMMENDED
   - OpenWRT cross-compilation (1-2 hours)
   - Deployment instructions
   - Verification steps

### Reference

3. **[hack.md](hack.md)** - Original design specification
   - Robot-as-Master architecture rationale
   - Detailed system design
   - Historical context

4. **[QUICKSTART.md](QUICKSTART.md)** - Quick start guide (if exists)

---

## 🚀 Quick Start

### Get the Patch

**TSF Sync v2.0 Patch**:
```
patches/morse_driver/999-tsf-sync.patch
```

**What it adds**:
- `tsf_rx` - For Client/Gateway
- `tsf_current` - For AP/Robot

### Build (Recommended Method)

**On your MM8108 device**:

```bash
# Install prerequisites
sudo apt install linux-headers-$(uname -r) build-essential git

# Clone and patch
git clone https://github.com/MorseMicro/morse_driver.git
cd morse_driver && git checkout v1.16.4
patch -p1 < /path/to/999-tsf-sync.patch

# Build (5-10 minutes)
make KERNEL_SRC=/lib/modules/$(uname -r)/build

# Install
sudo insmod dot11ah/dot11ah.ko
sudo insmod morse.ko country=US

# Verify
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
```

---

## 📁 File Structure

```
/home/dzezula/openwrt/
├── TSF_SYNC_README.md              ← You are here (navigation)
├── TSF_SYNC_GUIDE.md               ← Technical guide & usage
├── BUILD_GUIDE.md                  ← Build instructions
├── hack.md                         ← Original design spec
│
├── patches/morse_driver/
│   └── 999-tsf-sync.patch          ← The patch file v2.0
│
└── feeds/morse/essentials/morse_driver/patches/
    └── 999-tsf-sync.patch          ← Applied during OpenWRT build
```

---

## 🔑 Key Concepts

### Dual Debugfs Interface

| File | Purpose | Used By | Updates |
|------|---------|---------|---------|
| `tsf_rx` | Last RX packet TSF | Client/Gateway | Every RX frame |
| `tsf_current` | Current TSF (extrapolated) | AP/Robot | Real-time |

### Output Format

Both files use the same format:
```
TSF: <microseconds>
SYS: <nanoseconds>
```

Example:
```bash
$ cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
TSF: 123456789012345
SYS: 1700000000000000000
```

---

## 🎯 Use Cases

### Robot (AP - Master)

```python
# Read current TSF for broadcasting
with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_current') as f:
    lines = f.read().split('\n')
    tsf_us = int(lines[0].split(': ')[1])
    sys_ns = int(lines[1].split(': ')[1])
```

### Gateway (Client - Slave)

```python
# Read last received packet TSF
with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx') as f:
    tsf_us = int(f.read().split('\n')[0].split(': ')[1])
```

---

## ✅ Compatibility

### Hardware

- ✅ **MM6108** - Morse Micro 6108 chip
- ✅ **MM8108** - Morse Micro 8108 chip (newer)
- ✅ **Same driver for both** - Only firmware differs

### Software

- **Driver**: morse_driver v1.16.4
- **Kernel**: 5.15.x (tested), should work on 4.x, 5.x, 6.x
- **OS**: Ubuntu 20.04, OpenWRT, or any Linux with kernel headers
- **Architecture**: aarch64 (ARM 64-bit), also adaptable to other architectures

---

## 🛠️ Troubleshooting

### Quick Checks

```bash
# 1. Check modules loaded
lsmod | grep morse

# 2. Check debugfs mounted
mount | grep debugfs

# 3. Check files exist
ls -l /sys/kernel/debug/ieee80211/phy0/morse/tsf_*

# 4. Test reading
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current

# 5. Check values non-zero (requires association)
iw dev wlan0 link
```

### Common Issues

| Problem | Solution |
|---------|----------|
| Files don't exist | Mount debugfs, verify DEBUG build |
| Values always zero | Associate to network, wait for beacons |
| Module won't load | Check kernel version match, install dependencies |

See **[TSF_SYNC_GUIDE.md](TSF_SYNC_GUIDE.md#troubleshooting)** for detailed troubleshooting.

---

## 📖 Documentation Overview

### TSF_SYNC_GUIDE.md (Technical)
- ✅ Architecture explanation
- ✅ How TSF sync works
- ✅ MM6108/MM8108 compatibility
- ✅ Python code examples (master & slave)
- ✅ Technical details (capture mechanism, extrapolation)
- ✅ Troubleshooting guide

### BUILD_GUIDE.md (Build & Deploy)
- ✅ On-device build (recommended, 5-10 min)
- ✅ OpenWRT cross-compilation (1-2 hours)
- ✅ Docker build option
- ✅ Deployment instructions
- ✅ Verification steps
- ✅ Build troubleshooting

### hack.md (Design Rationale)
- ✅ Original "Robot-as-Master" architecture
- ✅ Why use TSF vs NTP/PTP
- ✅ Detailed system design
- ✅ Kernel driver hack explanation

---

## 🎓 Learning Path

**New to TSF Sync?**
1. Start with **hack.md** for the "why"
2. Read **TSF_SYNC_GUIDE.md** for the "what" and "how"
3. Follow **BUILD_GUIDE.md** to build and deploy

**Already understand it?**
1. Go straight to **BUILD_GUIDE.md**
2. Build on-device (fastest method)
3. Use examples from **TSF_SYNC_GUIDE.md**

**Just need the patch?**
1. Get `patches/morse_driver/999-tsf-sync.patch`
2. Apply to morse_driver v1.16.4
3. Build and deploy

---

## 📞 Support

**Build Issues**: See [BUILD_GUIDE.md - Troubleshooting](BUILD_GUIDE.md#troubleshooting)
**Runtime Issues**: See [TSF_SYNC_GUIDE.md - Troubleshooting](TSF_SYNC_GUIDE.md#troubleshooting)
**Design Questions**: See [hack.md](hack.md) for architectural details

---

## ✨ What's New in v2.0

**Dual Debugfs Interface**:
- ✅ `tsf_rx` for clients (last RX packet TSF)
- ✅ `tsf_current` for APs (extrapolated current TSF)
- ✅ Single driver works for both AP and Client
- ✅ Captures all management/beacon frames (not just beacons)

**Improvements from v1.0**:
- ❌ v1.0: Single `tsf_sync` file, beacon-only capture
- ✅ v2.0: Dual files, all management frames, AP + Client support

---

**Status**: ✅ Ready for production use
**Tested**: morse_driver 1.16.4, kernel 5.15.x, aarch64
**Accuracy**: < 100 µs achievable with proper tuning
