# Claude Development Notes

## Patch Development Workflow

### CRITICAL: Correct Patch Location for Morse Driver

**⚠️ IMPORTANT:** Patches for the morse_driver package must be placed in:

```
/home/dzezula/openwrt/feeds/morse/essentials/morse_driver/patches/
```

**NOT** in `/home/dzezula/openwrt/patches/morse_driver/`

The OpenWrt build system applies patches from the **feeds directory**, not from the top-level patches directory for feed packages. This is different from kernel patches.

To verify which patches are being applied, check build output:
```bash
make package/feeds/morse/morse_driver/compile V=s 2>&1 | grep "Applying.*patch"
```

### RECOMMENDED: Quilt-Based Patch Development

**Use OpenWrt's native `quilt` tool for creating patches.** This ensures correct line numbers by tracking the actual state after each patch is applied.

#### Quilt Workflow (Recommended):

1. **Install quilt:**
   ```bash
   sudo apt-get install quilt
   ```

2. **Prepare source with existing patches:**
   ```bash
   make package/feeds/morse/morse_driver/clean
   make package/feeds/morse/morse_driver/prepare QUILT=1
   cd build_dir/target-aarch64_cortex-a72_musl/linux-bcm27xx_bcm2711/morse_driver-1.16.4/
   ```

3. **Apply all existing patches:**
   ```bash
   quilt push -a
   # This applies patches 001-015 (or however many exist)
   ```

4. **Create your new patch:**
   ```bash
   quilt new 990-my-feature.patch
   quilt add mac.c  # Add files you'll modify
   # Make your edits to mac.c
   quilt refresh  # Generates patch with correct line numbers!
   ```

5. **Copy to feeds directory:**
   ```bash
   cp patches/990-my-feature.patch /home/dzezula/openwrt/feeds/morse/essentials/morse_driver/patches/
   ```

6. **Test clean build:**
   ```bash
   cd /home/dzezula/openwrt
   make package/feeds/morse/morse_driver/clean
   make package/feeds/morse/morse_driver/compile V=s
   ```

**Why quilt?**
- Automatically handles line number shifts from previous patches
- Tracks which files belong to which patch
- Generates patches with correct context
- OpenWrt-native tool, designed for this workflow

### Patch Numbering

Patches apply in lexicographic order (string sort, not numeric):
- `001-015`: Upstream patches
- `990-999`: Custom patches
- **Note:** `"1000"` sorts BEFORE `"999"` (string comparison)!

## Build System Notes

### Manual Edits Are Lost on Clean Builds

OpenWrt's build system:
1. Extracts source tarball
2. Applies patches from `patches/` directory
3. Compiles

**Every `make clean` wipes out manual edits!**

To persist changes:
- ✅ Create patch files in `patches/morse_driver/`
- ❌ Never rely on manual edits to `build_dir/`

### Patch Naming Convention

- `001-015` - Upstream patches
- `990-991` - TSF sync patches (mac.c core + debugfs interfaces)
- `992-999` - Reserved for future custom patches

Patches are applied in lexicographic (ASCII) sort order.

### Disabling Patches

To temporarily disable a patch:
```bash
mv patches/morse_driver/999-foo.patch patches/morse_driver/999-foo.patch.disabled
```

## Deployment Scripts

Deploy scripts are in the repo root:
- `deploy_prod_debugfs_to_ap.sh` - Deploy to AP (192.168.1.133)
- `deploy_prod_debugfs_to_client.sh` - Deploy to Client (192.168.1.97)

These handle:
- Module backup
- Unload/reload
- Reboot
- Status verification

## Configuration

### Production Build with DEBUGFS

In `feeds/morse/essentials/morse_driver/Makefile`:
```makefile
MORSE_MAKEDEFS += DEBUG=n
MORSE_MAKEDEFS += CONFIG_MORSE_DEBUGFS=y
```

This gives us:
- Production firmware (625K) - no beacon timing bugs
- debugfs interfaces for TSF and debugging

## TSF Sync Architecture

### Current Implementation

**Patches:**
- `990-tsf-mac-core.patch` - Core TSF capture in mac.c
- `991-tsf-debugfs.patch` - Debugfs interfaces in debug.c

**Key Insight:** TSF must be captured from **ALL frames** (data + management), not just beacons.

**Implementation location:** `morse_mac_skb_recv()` - entry point for ALL received frames

**How it works:**
1. Every frame calls `morse_capture_rx_tsf()` with hardware TSF timestamp
2. Spinlock-protected globals store: `last_rx_hw_tsf_us` and `last_rx_kernel_time_ns`
3. `morse_get_tsf_snapshot()` provides atomic read of both values
4. Debugfs interfaces expose TSF to userspace

**Debugfs interfaces:**
- `/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx` - Last captured TSF from RX frame
- `/sys/kernel/debug/ieee80211/phy0/morse/tsf_current` - Extrapolated current TSF

### Testing TSF Updates

```bash
# On client, verify TSF updates with ping traffic
ssh root@192.168.1.97 'ping -c 5 192.168.1.133 > /dev/null & \
  for i in 1 2 3 4 5; do \
    cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx; \
    sleep 0.2; \
  done'
```

TSF values should update with each ping packet (data frames).

## Git Workflow

Patches are tracked in git under `patches/morse_driver/`.

When modifying patches:
1. Edit patch file
2. Test clean build
3. Commit the patch file change
4. Document in commit message what the patch does

## Key Takeaways

1. **Use quilt for patch development** - Handles line number shifts automatically
2. **Test clean builds** - Verify patches apply correctly from clean state
3. **Lexicographic ordering matters** - `"1000"` sorts before `"999"`
4. **TSF capture location is critical** - Must be in `morse_mac_skb_recv()` to capture ALL frames
