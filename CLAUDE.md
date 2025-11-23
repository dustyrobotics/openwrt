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

### CRITICAL: Line Number Management

When creating patches for the OpenWrt build system, patches are applied **sequentially in alphabetical/numerical order**. Each patch modifies the source, which shifts line numbers for subsequent patches.

#### Step-by-Step Patch Development Process:

1. **Start with clean source**
   ```bash
   make package/feeds/morse/morse_driver/clean
   ```

2. **Apply patches incrementally and verify line numbers**
   - Patches in `patches/morse_driver/` are applied in order (001, 002, 998, 999, etc.)
   - After each patch, line numbers shift
   - **NEVER assume line numbers from the original source**

3. **To create a new patch:**

   a. **Prepare source with existing patches:**
   ```bash
   make package/feeds/morse/morse_driver/prepare
   ```

   b. **Verify current state and line numbers:**
   ```bash
   # Check actual line numbers after existing patches
   grep -n "function_name" build_dir/.../morse_driver-X.X.X/file.c
   ```

   c. **Make your changes manually to the prepared source**
   - Edit files in `build_dir/target-*/linux-*/morse_driver-*/`
   - Use actual line numbers from the prepared (patched) source

   d. **Generate the patch:**
   ```bash
   # From inside build_dir/.../morse_driver-X.X.X/
   diff -Naur original_file.c modified_file.c > /tmp/new.patch
   ```

   e. **Verify line numbers in patch file:**
   - Open the patch and check `@@ -XXX,YYY +AAA,BBB @@` lines
   - These should match the **post-patch** line numbers

4. **Test the complete patch sequence:**
   ```bash
   make package/feeds/morse/morse_driver/clean
   make package/feeds/morse/morse_driver/compile V=s
   ```

   - Check build log for patch application messages
   - Look for "Hunk #N succeeded at XXXX (offset Y lines)" - this indicates line number mismatch
   - If you see offset warnings, line numbers need adjustment

### Common Pitfalls:

❌ **WRONG:** Creating patches based on original source line numbers
❌ **WRONG:** Assuming line numbers stay the same across patches
❌ **WRONG:** Not testing clean builds after adding patches

✅ **CORRECT:** Always use line numbers from prepared (patched) source
✅ **CORRECT:** Test full clean build after each new patch
✅ **CORRECT:** Account for cumulative line shifts from all previous patches

### Example: TSF Sync Patch Development

Our current patches:
- `998-disable-hw-channel-ignore.patch` - Applied first
- `999-tsf-sync-with-debug.patch` - Applied second (our new patch)

When creating `999-tsf-sync-with-debug.patch`:
1. The source already has changes from `998-*`
2. Line numbers must reflect the state **after** patch 998 is applied
3. To find correct lines: `make prepare`, then check actual line numbers

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

- `0XX-*.patch` - Core functionality patches
- `9XX-*.patch` - Custom/experimental patches
- `999-*.patch` - Our TSF sync and debug instrumentation

Patches are applied in ASCII sort order.

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

### Current Implementation (999-tsf-sync-with-debug.patch)

**Key Insight:** TSF must be captured from **ALL frames** (data + management), not just beacons.

**Correct location:** `morse_mac_skb_recv()` - entry point for ALL received frames

**Wrong location:** `morse_rx_process_skb()` - only processes management/beacon frames

### Debug Counters

Added to trace execution flow:
- `morse_mac_skb_recv_calls` - Count all RX frames
- `morse_capture_rx_tsf_calls` - Count TSF captures
- `morse_mac_skb_recv_early_returns` - Count early exits

Exposed via: `/sys/kernel/debug/ieee80211/phy0/morse/rx_debug_counters`

### Testing TSF Updates

```bash
# On client, check TSF updates with data traffic
ssh root@192.168.1.97 'ping -c 5 192.168.1.133 > /dev/null & \
  for i in 1 2 3 4 5; do \
    cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_rx; \
    sleep 0.2; \
  done'
```

If TSF values are identical across reads → not capturing from data frames.

## Git Workflow

Patches are tracked in git under `patches/morse_driver/`.

When modifying patches:
1. Edit patch file
2. Test clean build
3. Commit the patch file change
4. Document in commit message what the patch does

## Lessons Learned

1. **Always verify patch application order** - Use `make package/.../prepare V=s` to see patch sequence
2. **Line numbers shift** - Each patch changes subsequent line numbers
3. **Test clean builds** - Manual edits are ephemeral, patches are permanent
4. **Fuzzy matching is dangerous** - Patches can apply to wrong locations if context is similar
5. **One patch at a time** - Incremental development prevents cascading failures

## Future Improvements

- [ ] Automated testing of patch application
- [ ] Script to verify TSF updates with data frames
- [ ] Comprehensive test suite for TSF sync functionality
