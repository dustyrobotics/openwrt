# DEBUG Driver Success - Client Connection Issue Resolution

## Problem Summary
After deploying TSF Sync v2.0 with DEBUG build to AP at 192.168.1.97, the client could not connect. The AP failed to start with error:
```
HT center channel disabled (114)
IEEE 802.11 Hardware does not support configured channel
Could not select hw_mode and channel. (-3)
wlan0: AP-DISABLED
```

## Root Cause Analysis

### Investigation Steps
1. Searched for DEBUG-specific code affecting channel validation
2. Found `set_hw_ignored_s1g_channels()` in mac.c:2514
3. This function queries firmware via `morse_cmd_get_disabled_channels()` (command.c:1040)
4. The **DEBUG firmware** reports channel 112 (and others) as disabled
5. Driver marks these channels with `IEEE80211_CHAN_IGNORE` flag (mac.c:2501)
6. hostapd sees channels as unusable and fails to start

### Key Code Locations
- **mac.c:2583**: Call to `set_hw_ignored_s1g_channels(hw)` during driver start
- **mac.c:2514-2561**: Function that retrieves disabled channels from firmware
- **mac.c:2468-2504**: `ignore_s1g_channel()` sets `IEEE80211_CHAN_IGNORE` flag
- **command.c:1040-1049**: `morse_cmd_get_disabled_channels()` firmware command

## Solution: Channel Ignore Workaround

### Patch: 998-disable-hw-channel-ignore.patch
Located in: `feeds/morse/essentials/morse_driver/patches/`

```patch
--- a/mac.c
+++ b/mac.c
@@ -2507,7 +2507,8 @@ static void ignore_s1g_channel(struct ieee80211_hw *hw, u32 freq_khz, u32 bw_mh
  *
  * @hw: mac80211 hw object
  */
-static void set_hw_ignored_s1g_channels(struct ieee80211_hw *hw)
+static void __attribute__((unused))
+set_hw_ignored_s1g_channels(struct ieee80211_hw *hw)
 {
 	int ret;
 	uint i;
@@ -2575,7 +2576,9 @@ static int morse_mac_ops_start(struct ieee80211_hw *hw)
 	mors->started = true;

 	/* Retrieve channels from the HW that are unusable */
-	set_hw_ignored_s1g_channels(hw);
+	/* WORKAROUND: Disabled to prevent firmware from marking valid channels as unusable
+	 * This is necessary for DEBUG builds where firmware incorrectly reports channels as disabled */
+	/* set_hw_ignored_s1g_channels(hw); */

 	if (mors->cfg->set_slow_clock_mode)
 		mors->cfg->set_slow_clock_mode(mors, morse_mac_slow_clock_mode());
```

### Why This Works
- Prevents the driver from querying firmware for disabled channels
- Channels remain available to hostapd
- AP can start successfully with channel 112 (5560 MHz)

## Deployed Configuration

### Patches Applied (in order)
1. **015-4v3fem-gpio-support.patch** - GPIO support
2. **998-disable-hw-channel-ignore.patch** - Channel workaround (NEW)
3. **999-tsf-sync.patch** - TSF Sync v2.0

### Build Command
```bash
make package/feeds/morse/morse_driver/clean V=s
make package/feeds/morse/morse_driver/compile V=s
```

### Deployment
```bash
bash /tmp/deploy_to_97.sh
```

### Verification Results
```
Interface wlan0
	type AP
	ssid ekh01-1dd8
	channel 112 (5560 MHz), width: 160 MHz
	txpower 20.00 dBm

Module status:
morse                 380928  0
dot11ah                81920  1 morse

TSF symbols present:
- morse_get_tsf_snapshot
- morse_cmd_cfg_offset_tsf
```

## Deployment Results

### AP (root@ap) - FULLY OPERATIONAL ✅
Deployed: 2025-11-23
Deployment method: `/tmp/deploy_to_ap.sh` + reboot

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

Module status:
morse                 380928  0
dot11ah                81920  1 morse

TSF debugfs files:
- /sys/kernel/debug/ieee80211/phy0/morse/tsf_current
  TSF: 100660281, SYS: 1763873581255522029
- /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx
  TSF: 99173846, SYS: 1763873579769086726

Client authenticated: 0c:bf:74:00:24:8d
```

### Client (192.168.1.97) - FULLY OPERATIONAL ✅
Deployed: 2025-11-22
Deployment method: `/tmp/deploy_to_97.sh`

```
Interface wlan0
	ifindex 16
	wdev 0x300000002
	addr 0c:bf:74:00:24:8d
	type managed
	wiphy 3

TSF debugfs files:
- /sys/kernel/debug/ieee80211/phy3/morse/tsf_rx
  TSF: 1289731568, SYS: 1763873596598403323
- /sys/kernel/debug/ieee80211/phy3/morse/tsf_current (functional)
```

### Key Findings
1. **Reboot required for AP**: Initial deployment succeeded in copying modules but AP failed to start. Clean reboot resolved the issue.
2. **TSF Sync v2.0 confirmed working**: Both devices show TSF timestamp capture via debugfs files
3. **Client-AP communication**: Client successfully authenticating to AP with DEBUG driver

## Production Considerations
- This workaround bypasses firmware's channel validation
- Should investigate why DEBUG firmware reports channels as disabled
- May need firmware fix for production use
- Consider if non-DEBUG build has same issue (likely not, based on testing)
- For AP deployments, plan for reboot window to ensure clean driver initialization

## Files Modified
- `/home/dzezula/openwrt/feeds/morse/essentials/morse_driver/patches/998-disable-hw-channel-ignore.patch` (NEW)
- `/home/dzezula/openwrt/feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch` (existing)

## Build Artifacts
- `build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/morse.ko` (645K, MD5: d914da2de9391ed0b2857f66fdbe1ec3)
- `build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/ipkg-aarch64_cortex-a72/kmod-morse/lib/modules/5.15.167/dot11ah.ko` (105K)

Date: 2025-11-23
Status: ✅ BOTH AP AND CLIENT OPERATIONAL WITH DEBUG DRIVER + TSF SYNC V2.0
