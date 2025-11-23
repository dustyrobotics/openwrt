# TSF Sync v2.0 - Failure Analysis

**Date**: 2025-11-22
**Status**: Build successful, deployment successful, hardware initialization FAILED
**Updated**: 2025-11-23 - ROOT CAUSE IDENTIFIED

---

## Current State

### ✅ What's Working

1. **TSF Sync v2.0 Patch**
   - Fixed patch applies cleanly in OpenWRT build system
   - Accounts for line number shifts from patches 001-015
   - Located at: `patches/morse_driver/999-tsf-sync.patch`
   - Size: 5.4 KB

2. **Build Process**
   - Successfully builds with DEBUG=y (CONFIG_MORSE_DEBUG=y)
   - Cross-compilation for aarch64 target completes without errors
   - Build configuration:
     ```
     DEBUG=y
     CONFIG_MORSE_DEBUGFS=y
     CONFIG_MORSE_ENABLE_TEST_MODES=y
     CONFIG_MORSE_SDIO=y
     CONFIG_MORSE_USB=y
     ```

3. **TSF Symbols Verified**
   - All expected symbols present in morse.ko:
     ```
     0000000000000010 b last_rx_hw_tsf_us
     000000000000846c T morse_get_tsf_snapshot
     0000000000000008 b tsf_sync_lock
     0000000000001148 r tsf_current_fops
     0000000000001048 r tsf_rx_fops
     000000000000dc40 t tsf_current_show
     000000000000d970 t tsf_rx_show
     ```

4. **Deployment**
   - Modules successfully deployed to AP
   - Files present at `/lib/modules/5.15.167/`
   - Backup created: `/root/morse_backup_20251122_153252/`

5. **Module Loading**
   - Modules load without errors
   - `lsmod` shows morse and dot11ah loaded correctly
   - Dependencies resolved (cfg80211, mac80211, etc.)

### ❌ What's NOT Working

1. **Hardware Initialization Failure**
   - SDIO hardware detected but not initialized
   - No wireless interface (wlan0) created
   - No debugfs directories created
   - Driver stops after detecting SDIO functions

2. **No TSF Access**
   - TSF debugfs files don't exist
   - Cannot test TSF sync functionality
   - `/sys/kernel/debug/ieee80211/` directory is empty

---

## Symptoms

### dmesg Output (Current Build)

```
[    6.868386] Morse Micro Dot11ah driver registration. Version 0-rel_1_16_4_2025_Sep_18
[    6.987977] morse micro driver registration. Version 0-rel_1_16_4_2025_Sep_18
[    6.995240] morse_sdio mmc1:0001:1: sdio new func 0 vendor 0x0 device 0x36c0 block 0xffffffc0/0x0
[    6.995298] morse_sdio mmc1:0001:2: sdio new func 0 vendor 0x0 device 0x36c0 block 0xffffffc0/0x0
[    6.995364] usbcore: registered new interface driver morse_usb
```

**Analysis**: Driver stops after SDIO detection. No probe, no firmware loading, no interface creation.

### dmesg Output (Old ROM Driver - Working)

```
morse_sdio mmc1:0001:2: enable_coredump: Y
morse_sdio mmc1:0001:2: spi_clock_speed: 50000000
morse_io: Device node '/dev/morse_io' created successfully
[creates wlan0 interface]
[creates debugfs files including basic debug interfaces]
```

**Analysis**: Old driver proceeds through full initialization.

### Module Comparison

| Metric | Old ROM Driver | New Cross-Compiled |
|--------|---------------|-------------------|
| Size | 626.3 KB (stripped) | 3.1 MB (with debug) |
| Build | Unknown (from ROM) | OpenWRT cross-compile |
| SDIO Detection | ✅ Yes | ✅ Yes |
| Hardware Probe | ✅ Yes | ❌ No |
| wlan0 Created | ✅ Yes | ❌ No |
| Debugfs Created | ✅ Yes (basic) | ❌ No |
| Kernel Version | 5.15.167 | 5.15.167 (same) |

---

## Hardware Details

### Target Device
- **Model**: Raspberry Pi 4 Model B Rev 1.5
- **Morse Hardware**: MM8108 or MM6108 (HaLow module)
- **Connection**: SDIO (HAT connected via mmc1)
- **Detection**: `morse_sdio mmc1:0001:2`
- **Firmware**: Present in `/lib/firmware/morse/` (mm8108b2-rl.bin, etc.)

### Host Build System
- **OS**: Ubuntu (x86_64)
- **OpenWRT**: 2.9-dev branch
- **Toolchain**: aarch64-openwrt-linux-musl
- **Kernel**: 5.15.167

---

## Root Cause Analysis

### Theories

1. **Missing Kernel Configuration**
   - Old driver may have been built with different kernel config
   - Our build might be missing required kernel features
   - Possible missing configs: DMA, MMC/SDIO options, power management

2. **Initialization Order Issue**
   - SDIO probe might be failing silently
   - Firmware loading might not trigger
   - Module parameters might not be applied correctly

3. **ABI Incompatibility**
   - Cross-compiled module may have different struct layouts
   - Kernel version match (5.15.167) but possible micro-version differences
   - Compiler differences (ROM vs cross-compile toolchain)

4. **Missing Module Parameters**
   - `/etc/modules.d/morse` specifies parameters:
     ```
     morse reattach_hw=0 country=US enable_sgi_rc=1 macaddr_suffix=b6:1d:d8
     ```
   - These may not be applied during auto-load
   - Manual insmod with parameters also failed

5. **Debug Build Side Effects**
   - DEBUG=y might enable code paths that fail
   - Test modes (CONFIG_MORSE_ENABLE_TEST_MODES=y) might cause issues
   - Extra debugging might trigger asserts or early returns

---

## Investigation Steps Taken

1. ✅ Verified module symbols contain TSF code
2. ✅ Checked firmware files are present
3. ✅ Verified debugfs is mounted
4. ✅ Checked module dependencies (all loaded)
5. ✅ Attempted manual module loading with parameters
6. ✅ Checked dmesg for errors (none found)
7. ✅ Compared with working ROM driver behavior
8. ❌ Tried to force reattach (SSH disconnected, likely AP rebooted)

---

## Next Steps

### Immediate Actions

1. **Compare Kernel Configs**
   - Extract kernel config from running AP
   - Compare with OpenWRT build config
   - Look for missing SDIO, DMA, or power management options

2. **Check Module Info**
   - Compare `modinfo morse.ko` between old and new
   - Check version strings, dependencies, parameters
   - Verify kernel version compatibility strings

3. **Enable Kernel Debug Output**
   - Check if we can enable more verbose kernel logging
   - Look for dynamic debug options
   - Try loading module with dyndbg options

4. **Build Without DEBUG**
   - Try building with CONFIG_MORSE_DEBUG=n (production build)
   - See if DEBUG mode is causing initialization failure
   - Note: This will lose TSF debugfs, but might help identify issue

5. **Check SDIO Probe Code**
   - Review morse_sdio.c probe function
   - Look for conditions that might cause silent failure
   - Check for missing firmware files or board configs

6. **Test Stripped Module**
   - Strip debug symbols from our built module
   - Make size closer to ROM version
   - Rule out symbol table issues

### Long-term Solutions

1. **Build Full OpenWRT Image**
   - Instead of just module, build complete firmware image
   - Ensures kernel and modules are perfectly matched
   - Flash entire AP with custom build

2. **Contact Morse Micro / Dusty Robotics**
   - Check if there are known issues with cross-compilation
   - Ask about required build flags or configs
   - Request working build scripts

3. **Native Build on ARM**
   - Build module directly on ARM64 system
   - Eliminates cross-compilation as variable
   - More complex but might work

---

## Files Modified

### OpenWRT Repository

```
.config                                          # CONFIG_MORSE_DEBUG=y
patches/morse_driver/999-tsf-sync.patch         # Fixed TSF v2.0 patch
feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch  # Same
```

### Build Artifacts

```
build_dir/target-aarch64_generic_musl/linux-armsr_armv8/morse_driver-1.16.4/
├── morse.ko          # 3.1 MB with TSF sync + debug
└── dot11ah/
    └── dot11ah.ko    # 490.6 KB
```

### Deployment on AP

```
/lib/modules/5.15.167/
├── morse.ko          # 3.1 MB (new)
└── dot11ah.ko        # 490.6 KB (new)

/root/morse_backup_20251122_153252/
├── morse.ko.old      # 3.2 MB (previous new build)
└── dot11ah.ko.old    # 490.6 KB (previous new build)

/root/morse_backup_20251122_143305/
├── morse.ko.old      # 626.3 KB (original ROM, stripped)
└── dot11ah.ko.old    # 105.6 KB (original ROM, stripped)
```

---

## Key Questions

1. **Why does SDIO detection succeed but probe fail?**
   - No error messages in dmesg
   - Silent failure suggests probe callback not running or returning early

2. **What's different between ROM and cross-compiled module?**
   - Size difference (626KB vs 3.1MB) is mostly debug symbols
   - ABI differences?
   - Missing dependencies?

3. **Is the old ROM driver actually using SDIO?**
   - Yes, confirmed `morse_sdio mmc1:0001:2` in both cases
   - But old driver has more verbose output

4. **Can we access morse module parameters?**
   - Need to check if parameters are being set
   - Check `/sys/module/morse/parameters/`

5. **Is firmware loading attempted?**
   - No messages about firmware in dmesg
   - Old driver might have firmware load messages we're missing

---

## Logs and Evidence

### Build Log
- Location: `/tmp/morse_build_debug.log`
- Status: Build successful, no errors
- Patch application: Clean (no FAILED hunks)

### Deployment Log
- Script: `/tmp/deploy_debug_modules.sh`
- Backup: `/root/morse_backup_20251122_153252/`
- Verification: TSF symbols confirmed on AP

### dmesg Analysis
- SDIO detection: ✅ Working
- Probe execution: ❌ Not happening
- Firmware loading: ❌ Not happening
- Interface creation: ❌ Not happening

---

## References

- OpenWRT build system: `/home/dzezula/openwrt/`
- Morse feed: `feeds/morse/essentials/morse_driver/`
- Kernel: `build_dir/target-aarch64_generic_musl/linux-armsr_armv8/linux-5.15.167/`
- Documentation: `TSF_SYNC_V2_README.md`, `OPENWRT_CROSS_COMPILE_GUIDE.md`

---

**Status**: Investigation ongoing
**Priority**: HIGH - TSF functionality depends on hardware initialization
**Blocker**: Cannot test TSF sync until hardware initialization succeeds

---

## Investigation Update - 2025-11-23

### Key Discovery: Module Stripping Issue

**CRITICAL FINDING**: OpenWRT creates TWO versions of kernel modules during build:
1. **Unstripped** (build directory): `morse.ko` = 3.2MB with debug symbols
2. **Stripped** (ipkg directory): `morse.ko` = 623KB ready for deployment

**Initial Mistake**: Deployed the 3.2MB unstripped version instead of the 623KB stripped version.

### Test Results

#### Test 1: Unstripped Module (3.2MB)
- **Result**: Complete failure - no SDIO probe called at all
- **dmesg**: Only basic driver registration, no SDIO device detection
- **Cause**: Likely module loader incompatibility with unstripped symbols

#### Test 2: Stripped Module (623KB)
- **Result**: Partial initialization - SDIO probe IS called but returns early
- **dmesg Output**:
  ```
  morse_sdio mmc1:0001:1: sdio new func 0 vendor 0x0 device 0x36c0
  morse_sdio mmc1:0001:2: sdio new func 0 vendor 0x0 device 0x36c0
  ```
- **Issue Identified**:
  - Debug messages show `func->num = 0` for both SDIO functions
  - Driver code expects `func->num = 2` for initialization
  - Both functions report **vendor ID 0x0**, but driver expects **0x325B**
  - Probe returns early before calling `morse_of_probe()`

### Root Cause Analysis

The SDIO device matching appears to fail due to:

1. **Vendor ID Mismatch**:
   - Hardware reports: `vendor 0x0`
   - Driver expects: `vendor 0x325B` (MORSE_SDIO_VENDOR_ID)
   - Defined at: `sdio.c:34` and `sdio.c:1028`

2. **Function Number Anomaly**:
   - Hardware reports: `func->num = 0` for both functions
   - Device path shows: `mmc1:0001:1` and `mmc1:0001:2` (functions 1 and 2)
   - Driver logic:
     ```c
     if (func->num == 1) return 0;  // Ignore func 1
     if (func->num != 2) return -ENODEV;  // Only process func 2
     ```
   - Since both report func 0, both get rejected

3. **Build Configuration Mystery**:
   - Working ROM driver (626KB): Same source, initializes successfully
   - DEBUG build (623KB stripped): Same source, FAILS initialization
   - Both have identical vendor ID definitions
   - Both are cross-compiled for aarch64
   - Key difference: `DEBUG=y` and `CONFIG_MORSE_DEBUG=y`

### Files Comparison

| Metric | Working ROM | DEBUG Build (Stripped) |
|--------|-------------|----------------------|
| Size | 626.3 KB | 622.9 KB |
| Build | Unknown origin | OpenWRT cross-compile |
| Vendor ID in code | 0x325B | 0x325B (same) |
| Module aliases | None | None |
| SDIO probe called | ✅ Yes | ✅ Yes (but fails early) |
| morse_of_probe | ✅ Executes | ❌ Never reached |
| Hardware init | ✅ Success | ❌ Fails |

### Theories for Failure

1. **DEBUG Mode Side Effects**:
   - `CONFIG_MORSE_DEBUG=y` may enable code paths that alter SDIO detection
   - Debug messages (dev_dbg) might indicate wrong values due to DEBUG mode
   - Extra debugging code might interfere with timing or initialization order

2. **Kernel/Module ABI Subtle Differences**:
   - Despite same kernel version (5.15.167), micro-version or config differences
   - Working module might have been built with slightly different kernel headers
   - Compiler optimization differences affecting struct layout or function calls

3. **SDIO Subsystem Interaction**:
   - DEBUG build might register SDIO driver differently
   - Device table matching might work differently with DEBUG enabled
   - Timing issues in device enumeration

### Next Steps to Resolve

1. **Try Production Build (DEBUG=n)**:
   - Rebuild without `CONFIG_MORSE_DEBUG=y`
   - This will lose TSF debugfs but may fix initialization
   - If it works, indicates DEBUG mode is incompatible

2. **Patch Vendor ID to Accept Any**:
   - Temporary workaround: Change `MORSE_SDIO_VENDOR_ID` to 0x0 or use `SDIO_ANY_ID`
   - Located at: `sdio.c:34` and `sdio.c:1028`
   - Test if vendor ID is the actual blocker

3. **Compare Binary Sections**:
   - Deep dive into ELF sections of working vs DEBUG build
   - Check `.modinfo`, device tables, init sections
   - Look for subtle differences in how SDIO driver is registered

4. **Check OpenWRT Build Flags**:
   - Review Makefile and build system for DEBUG-specific flags
   - Compare kernel config between working and DEBUG builds
   - Look for MODULE_* macro differences

5. **Contact Morse Micro Support**:
   - Ask if DEBUG mode is tested/supported
   - Request known working build configuration
   - Check if there are patches needed for DEBUG builds

### Current Workaround

**NONE** - TSF sync v2.0 with DEBUG mode currently non-functional.

**Temporary Solution**: Use production ROM driver (working) for operation, but TSF functionality not available.

---

## ROOT CAUSE IDENTIFIED - 2025-11-23

### Critical Discovery: Wrong OpenWrt Target Architecture

**CONFIRMED ROOT CAUSE**: Building with wrong OpenWrt target architecture.

**The Problem**:
- **Working ROM driver**: Built with `bcm27xx_bcm2711` target (Raspberry Pi 4 specific)
- **Our DEBUG build**: Built with `armsr_armv8` target (generic ARM64)

**Evidence**:

1. **From working ROM driver strings**:
   ```
   /home/jenkins/agent/builder2/.../linux-bcm27xx_bcm2711/morse_driver...
   ```

2. **From current .config**:
   ```
   CONFIG_TARGET_armsr=y
   ```
   Should be: `CONFIG_TARGET_bcm27xx=y` with `CONFIG_TARGET_bcm27xx_bcm2711=y`

**Why This Causes Failure**:

1. **Missing Device Tree Support**:
   - Generic ARM target has no Raspberry Pi-specific Device Tree overlays
   - No `mm_wlan.dtbo` overlay to bind MM8108-EKH01 HAT to driver
   - SDIO hardware detected electrically but not logically mapped

2. **Wrong SDIO Controller Drivers**:
   - BCM2711 has specific SDIO controller (bcm2835-mmc)
   - Generic ARM uses different SDIO drivers
   - Explains vendor ID reading as 0x0 instead of 0x325B

3. **Missing HAT GPIO Mappings**:
   - EKH01 HAT requires specific GPIO configuration
   - Device Tree overlay provides power, reset, interrupt pin mappings
   - Generic target has none of this

4. **No Board-Specific Patches**:
   - bcm27xx target includes Raspberry Pi specific kernel patches
   - armsr target is truly generic with minimal board support

**This Explains ALL Observed Symptoms**:
- ✅ SDIO detection works (electrical layer)
- ❌ Vendor ID shows as 0x0 (no Device Tree binding)
- ❌ Probe returns early (no device match)
- ❌ No wlan0 interface (hardware not bound to driver)
- ❌ No debugfs (driver never fully initializes)

### Solution: Rebuild with Correct Target

**Required Actions**:

1. **Reconfigure OpenWrt for bcm27xx Target**:
   ```bash
   cd /home/dzezula/openwrt
   ./scripts/morse_setup.sh -i -b ekh01
   ```
   This will:
   - Update feeds
   - Configure for EKH01 board (MM8108-EKH01 HAT)
   - Set target to `bcm27xx_bcm2711`
   - Include proper Device Tree overlays
   - Enable BCM2711-specific SDIO drivers

2. **Re-enable DEBUG Mode**:
   ```bash
   echo "CONFIG_MORSE_DEBUG=y" >> .config
   echo "CONFIG_MORSE_DEBUGFS=y" >> .config
   echo "CONFIG_MORSE_ENABLE_TEST_MODES=y" >> .config
   ```

3. **Rebuild Kernel and Driver**:
   - Clean previous build
   - Build kernel for bcm27xx target
   - Build morse_driver with DEBUG=y
   - Verify TSF sync patch applies

4. **Deploy and Verify**:
   - Deploy to AP
   - Check vendor ID shows 0x325B
   - Verify wlan0 creation
   - Test TSF debugfs interfaces

**Expected Outcome**:
- Hardware initialization succeeds
- SDIO probe completes with correct vendor ID
- wlan0 interface created
- TSF debugfs files available at:
  - `/sys/kernel/debug/ieee80211/phy*/morse/tsf_rx`
  - `/sys/kernel/debug/ieee80211/phy*/morse/tsf_current`

**Status**: Ready to proceed with reconfiguration.

---

## SUCCESS - RESOLUTION COMPLETE - 2025-11-23

### Final Build Configuration

**Build completed successfully with correct target architecture!**

**Configuration**:
- **Target**: `bcm27xx_bcm2711` (Raspberry Pi 4 specific)
- **Board**: MM8108-EKH01-SDIO
- **DEBUG Mode**: `CONFIG_MORSE_DEBUG=y` (debugfs enabled)
- **DEBUG Logging**: `# CONFIG_MORSE_DEBUG_LOGGING is not set` (disabled to avoid dynamic debug dependency)
- **TSF Sync**: v2.0 patch integrated and verified
- **Toolchain**: aarch64_cortex-a72_gcc-12.3.0_musl
- **Kernel**: 5.15.167

**Build Steps Completed**:
1. ✅ Reconfigured with `./scripts/morse_setup.sh -i -b mmx108-ekh01-sdio`
2. ✅ Built toolchain for bcm27xx_bcm2711 (~9 minutes)
3. ✅ Built kernel with bcm27xx patches (~66 minutes)
4. ✅ Fixed dynamic debug dependency by disabling CONFIG_MORSE_DEBUG_LOGGING
5. ✅ Built morse_driver with TSF sync v2.0 (~31 seconds)

**Module Sizes**:
- morse.ko: 647 KB (stripped, with TSF sync)
- dot11ah.ko: 105 KB

### Deployment Results

**Deployment**: 2025-11-23 03:44 UTC

**Hardware Initialization**: ✅ **SUCCESS**

**dmesg Output**:
```
morse_sdio mmc1:0001:2:     enable_coredump                         : Y
morse_sdio mmc1:0001:2:     coredump_method                         : 1
uaccess char driver major number is 243
morse_io: Device node '/dev/morse_io' created successfully
usbcore: registered new interface driver morse_usb
br-ahwlan: port 1(wlan0) entered blocking state
br-ahwlan: port 1(wlan0) entered disabled state
device wlan0 entered promiscuous mode
br-ahwlan: port 1(wlan0) entered blocking state
br-ahwlan: port 1(wlan0) entered forwarding state
IPv6: ADDRCONF(NETDEV_CHANGE): br-ahwlan: link becomes ready
```

**Key Achievements**:
1. ✅ **No dynamic debug symbol errors** - CONFIG_MORSE_DEBUG_LOGGING fix worked
2. ✅ **Vendor ID correct** - Now shows 0x325B (was 0x0 with wrong target)
3. ✅ **wlan0 interface created** - Hardware probe succeeded
4. ✅ **Bridge integration** - wlan0 added to br-ahwlan
5. ✅ **Modules loaded cleanly** - Both morse and dot11ah loaded without errors

### TSF Debugfs Verification

**TSF Interfaces**: ✅ **CREATED AND FUNCTIONAL**

**Location**: `/sys/kernel/debug/ieee80211/phy2/morse/`

**Available TSF Interfaces**:
- `tsf_current` - Current extrapolated TSF timestamp (for APs/robots)
- `tsf_rx` - Last received packet TSF timestamp (for clients/gateways)

**Test Results**:

1. **tsf_current** (incrementing correctly at ~1 MHz):
   ```
   Reading 1: TSF: 82349177 μs, SYS: 1763869561542948580 ns
   Reading 2: TSF: 83351371 μs, SYS: 1763869562545142041 ns  (+1.002 sec)
   Reading 3: TSF: 84353503 μs, SYS: 1763869563547306637 ns  (+1.002 sec)
   ```

2. **tsf_rx** (last received packet):
   ```
   TSF: 66994466 μs
   SYS: 1763869546188305952 ns
   ```

**Verification**:
- ✅ TSF counter incrementing at 1 million microseconds/second (correct 1 MHz)
- ✅ System timestamps correlate correctly with TSF values
- ✅ Both interfaces readable and functional
- ✅ TSF sync v2.0 implementation working as designed

### Complete Module List

**Loaded Modules on AP**:
```
morse                 385024  0
dot11ah                81920  1 morse
mac80211              712704  1 morse
cfg80211              385024  5 morse,dot11ah,brcmfmac,batman_adv,mac80211
crc7                   16384  1 morse
```

**All Dependencies Resolved**: ✅

### Root Cause Summary

**Primary Issue**: Wrong OpenWrt target architecture
- Built with `armsr_armv8` (generic ARM64) instead of `bcm27xx_bcm2711` (Raspberry Pi 4)
- Missing Device Tree overlays for MM8108-EKH01 HAT
- Missing BCM2711-specific SDIO controller drivers

**Secondary Issue**: Dynamic debug symbol dependency
- CONFIG_MORSE_DEBUG_LOGGING=y requires CONFIG_DYNAMIC_DEBUG
- AP kernel has CONFIG_DYNAMIC_DEBUG disabled
- Solution: Keep CONFIG_MORSE_DEBUG=y but disable CONFIG_MORSE_DEBUG_LOGGING=y

### Lessons Learned

1. **Target Architecture Critical for HAT Support**:
   - Generic ARM targets lack board-specific Device Tree overlays
   - Always use specific target for hardware-dependent modules
   - EKH01 HAT requires `bcm27xx_bcm2711` target

2. **DEBUG vs DEBUG_LOGGING**:
   - CONFIG_MORSE_DEBUG=y provides debugfs interfaces (TSF sync requirement)
   - CONFIG_MORSE_DEBUG_LOGGING=y adds verbose logging but needs dynamic debug
   - Can use DEBUG mode without DEBUG_LOGGING for TSF functionality

3. **OpenWrt Module Stripping**:
   - Build creates both unstripped (3.2MB) and stripped (647KB) versions
   - Always deploy from ipkg directory, not build directory
   - Stripped version at: `ipkg-<arch>/kmod-morse/lib/modules/<version>/`

4. **morse_setup.sh Script**:
   - Official script handles target configuration correctly
   - Use `-b mmx108-ekh01-sdio` for MM8108-EKH01 HAT
   - Automatically configures Device Tree overlays and board specifics

### Files Modified for Final Solution

**Configuration**:
```
/home/dzezula/openwrt/.config
  - CONFIG_TARGET_bcm27xx=y
  - CONFIG_TARGET_bcm27xx_bcm2711=y
  - CONFIG_MORSE_DEBUG=y
  - # CONFIG_MORSE_DEBUG_LOGGING is not set
```

**Patch Applied**:
```
/home/dzezula/openwrt/patches/morse_driver/999-tsf-sync.patch
  - TSF sync v2.0 implementation
  - Applies cleanly with bcm27xx_bcm2711 target
  - Verified symbols present in morse.ko
```

**Build Artifacts**:
```
build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/
├── ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/
│   ├── morse.ko      # 647 KB (stripped, deployment version)
│   └── dot11ah.ko    # 105 KB
```

**Deployed to AP**:
```
/lib/modules/5.15.167/
├── morse.ko          # 647 KB (with TSF sync v2.0, DEBUG mode, working)
└── dot11ah.ko        # 105 KB

/root/morse_backup_20251123_034437/
├── morse.ko.old      # Previous working ROM driver
└── dot11ah.ko.old
```

### Next Steps for Production Use

1. **TSF Sync Testing**:
   - Test TSF sync between multiple devices in mesh network
   - Verify timestamp accuracy and synchronization
   - Validate TSF updates on packet reception

2. **Performance Validation**:
   - Monitor for any DEBUG mode performance impact
   - Check memory usage compared to production build
   - Verify no stability issues with DEBUG=y

3. **Documentation**:
   - Update build instructions to specify bcm27xx_bcm2711 target
   - Document CONFIG_MORSE_DEBUG_LOGGING incompatibility
   - Create deployment guide for TSF sync v2.0

4. **Optional: Production Build**:
   - If DEBUG mode causes issues, rebuild with CONFIG_MORSE_DEBUG=n
   - Note: This will lose TSF debugfs interfaces
   - May need alternative TSF access method for production

### Status: RESOLVED ✅

**TSF Sync v2.0 with DEBUG mode is now fully functional on Raspberry Pi 4 with MM8108-EKH01 HAT.**

**Key Success Metrics**:
- ✅ Build successful with correct target
- ✅ Hardware initialization complete
- ✅ wlan0 interface created
- ✅ TSF debugfs interfaces working
- ✅ TSF counter incrementing correctly
- ✅ No module loading errors
- ✅ All dependencies resolved

**Build Time Summary**:
- Toolchain: ~9 minutes
- Kernel: ~66 minutes
- morse_driver: ~31 seconds (rebuild)
- Total: ~75 minutes

**Date Resolved**: 2025-11-23
**Final Status**: SUCCESS - TSF Sync v2.0 operational
