# MM6108 vs MM8108 Driver Compatibility

## Quick Answer: YES, They're Interchangeable!

**The same `morse_driver` v1.16.4 works for BOTH MM6108 and MM8108 chips.**

## How It Works

### Morse Micro Architecture

```
┌─────────────────────────────────────────────┐
│  morse_driver (v1.16.4) - SHARED            │
│  ├── morse.ko     (with TSF sync v2.0)      │
│  └── dot11ah.ko   (802.11ah support)        │
└─────────────────────────────────────────────┘
                    ↓
        ┌───────────┴───────────┐
        ↓                       ↓
┌───────────────┐       ┌───────────────┐
│  MM6108 Chip  │       │  MM8108 Chip  │
│  + FW-6108    │       │  + FW-8108    │
└───────────────┘       └───────────────┘
```

### What's Chip-Specific

**Only the FIRMWARE differs:**

| Firmware Package | Chip | Description |
|-----------------|------|-------------|
| `morse-fw-6108` | MM6108 | Standard firmware for 6108 |
| `morse-fw-6108-tlm` | MM6108 | Thin LMAC (large AP mode) |
| `morse-fw-8108` | MM8108 | Standard firmware for 8108 |
| `morse-fw-8108-tlm` | MM8108 | Thin LMAC (large AP mode) |
| `morse-fw-8108-flm` | MM8108 | FullMAC (offload mode) |

### What's Shared (Driver)

**Same driver for both chips:**
- `morse.ko` - Main driver (v1.16.4)
- `dot11ah.ko` - 802.11ah protocol support
- **TSF sync patch v2.0** - Works on both chips!

## Why TSF Sync Works on Both

### TSF is a Hardware Feature

Both MM6108 and MM8108 have:
- **TSF counter**: 1 MHz hardware clock (802.11 standard)
- **RX descriptors**: Include `rx_timestamp_us` field
- **Same driver interface**: `morse_skb_rx_status` structure

### Patch is Driver-Level, Not Chip-Level

The TSF sync patch modifies:
- ✅ `mac.c` - Generic RX processing (chip-agnostic)
- ✅ `debug.c` - Debugfs interface (chip-agnostic)
- ❌ **No chip-specific code touched**

## Your MM8108 System

### Current Setup (Assumed)
```
Your MM8108 Device:
├── morse.ko (v1.16.4) - WITHOUT TSF sync
├── dot11ah.ko (v1.16.4)
├── morse-fw-8108 (or 8108-tlm)
└── Kernel 5.15.16 aarch64
```

### After Applying TSF Sync Patch
```
Your MM8108 Device:
├── morse.ko (v1.16.4) - WITH TSF sync v2.0 ✨
├── dot11ah.ko (v1.16.4) - Same as before
├── morse-fw-8108 (unchanged)
└── Kernel 5.15.16 aarch64
```

## What You Need to Replace

### Option 1: Just morse.ko (Recommended)

**IF** your existing system has:
- ✅ Same driver version: 1.16.4
- ✅ Same kernel version: 5.15.x
- ✅ Working dot11ah.ko already loaded

**THEN** you can replace just morse.ko:

```bash
# On your MM8108 device
sudo rmmod morse        # Unload old morse.ko (keeps dot11ah)
sudo insmod morse.ko country=US  # Load new morse.ko with TSF sync

# Verify
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
```

### Option 2: Both Modules (Safest)

**IF** you're unsure about versions or want a clean state:

```bash
# On your MM8108 device
sudo rmmod morse        # Unload morse
sudo rmmod dot11ah      # Unload dot11ah
sudo insmod dot11ah.ko  # Load dot11ah
sudo insmod morse.ko country=US  # Load morse with TSF sync

# Verify
lsmod | grep morse
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
```

## Why dot11ah.ko Matters

### Dependency Chain

```
morse.ko
  ├── depends on → dot11ah.ko
  ├── depends on → mac80211
  └── depends on → cfg80211

dot11ah.ko
  └── depends on → cfg80211
```

### What dot11ah.ko Does

- 802.11ah (S1G) frequency management
- S1G operation class support
- S1G IE (Information Element) parsing
- **Not modified by TSF sync patch**

### When You Can Skip Replacing dot11ah.ko

✅ Same driver version (1.16.4)
✅ Same kernel ABI (5.15.167)
✅ Already working on your system

**The TSF patch doesn't touch dot11ah/**

## MM8108-Specific Notes

### MM8108 Advantages Over MM6108

| Feature | MM6108 | MM8108 |
|---------|--------|--------|
| **TSF Hardware** | ✅ Yes | ✅ Yes (same) |
| **Max Throughput** | ~7 Mbps | ~15 Mbps |
| **FullMAC Firmware** | ❌ No | ✅ Yes (FLM) |
| **Power Efficiency** | Good | Better |
| **TSF Sync Patch** | ✅ Works | ✅ Works |

### FullMAC Mode (8108-flm)

**Important**: If you're using `morse-fw-8108-flm` (FullMAC):
- The driver still works the same way
- TSF timestamps still captured in RX descriptors
- **BUT**: Some processing happens on-chip
- TSF sync should still work (RX path in driver)

## Verification After Install

### Check Driver Version

```bash
modinfo /tmp/morse.ko | grep version
# Should show: version:        0-1.16.4
```

### Check Chip Detection

```bash
dmesg | grep -i morse | grep -i "chip"
# Will show: MM8108 detected (or similar)
```

### Test TSF Sync v2.0

```bash
# AP/Robot (reads current TSF)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
# Output:
# TSF: 123456789012345
# SYS: 1700000000000000000

# Client/Gateway (reads last RX TSF)
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
# Output:
# TSF: 123456789012000
# SYS: 1699999999500000000
```

### Verify Chip-Specific Behavior

```bash
# The firmware handles chip-specific features
# Driver just passes commands to firmware

# Check which firmware is loaded
ls /lib/firmware/morse/
# Should show: morse_8108*.bin (or similar)
```

## Build for MM8108

### No Special Configuration Needed

```bash
# Same build command for MM6108 or MM8108
cd /home/dzezula/openwrt
./scripts/morse_setup.sh -i -b ekh-armsr_armv8
make package/feeds/morse/morse_driver/compile V=s

# The SAME morse.ko works for both chips!
```

### Firmware Selection

During build or at runtime, select appropriate firmware:

```bash
# In menuconfig (optional):
# Morse Micro → Essentials →
#   [*] morse-fw-8108  (for your MM8108 chip)
```

## Summary for Your MM8108 System

| Question | Answer |
|----------|--------|
| **Will TSF sync work on MM8108?** | ✅ Yes, same as MM6108 |
| **Need to replace dot11ah.ko?** | ⚠️ Recommended, but not required if same version |
| **Need different build for MM8108?** | ❌ No, same driver |
| **Need different firmware?** | ✅ Yes, but firmware is separate from driver |
| **TSF accuracy affected?** | ❌ No, same TSF hardware (1 MHz) |

## Quick Reference

```bash
# Minimal update for working MM8108 system:

# 1. Build morse.ko with TSF sync patch
cd /home/dzezula/openwrt
./scripts/morse_setup.sh -i -b ekh-armsr_armv8
make package/feeds/morse/morse_driver/compile V=s

# 2. Copy to MM8108 device
scp build_dir/target-aarch64*/linux-*/morse_driver-*/morse.ko user@mm8108:/tmp/

# 3. Replace just morse.ko (if same version)
ssh user@mm8108
sudo rmmod morse
sudo insmod /tmp/morse.ko country=US

# 4. Verify TSF sync working
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_current

# Done! ✅
```

---

**Bottom Line**: The documentation mentions MM6108 as an example, but the driver works for the entire Morse Micro chip family (6108, 8108, etc.). You can use the same TSF-patched driver on your MM8108. Just replace morse.ko, and optionally dot11ah.ko if you want to be safe.
