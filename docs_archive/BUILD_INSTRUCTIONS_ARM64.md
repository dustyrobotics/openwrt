# Building Morse Driver with TSF Sync Patch for Ubuntu 20.04 ARM64

This guide covers building the OpenWRT morse driver with the TSF sync patch on a brand new Ubuntu 20.04 ARM64 system.

## Prerequisites - Fresh Ubuntu 20.04 System

### Step 1: Install Build Dependencies

```bash
sudo apt update
sudo apt install -y build-essential clang flex g++ gawk gcc-multilib \
  git gettext libncurses5-dev libssl-dev python3-distutils rsync \
  unzip zlib1g-dev swig file wget time
```

### Step 2: Clone the OpenWRT Repository

```bash
cd ~
git clone https://github.com/dustyrobotics/openwrt.git
cd openwrt
git checkout 2.9-dev
```

### Step 3: Update Feeds and Add TSF Sync Patch

```bash
# Update feeds to get morse packages
./scripts/feeds update -a
./scripts/feeds install -a

# Create patches directory for morse_driver
mkdir -p feeds/morse/essentials/morse_driver/patches

# Create the TSF sync patch
cat > feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch << 'EOF'
--- a/mac.c
+++ b/mac.c
@@ -69,6 +69,13 @@ static struct ieee80211_supported_band mors_band_5ghz = {
 	.n_bitrates = ARRAY_SIZE(mors_rates),
 };

+/* Global variables for TSF synchronization */
+static u64 last_beacon_hw_tsf_us = 0;
+static u64 last_beacon_kernel_time_ns = 0;
+static DEFINE_SPINLOCK(tsf_sync_lock);
+
+/* Forward declaration for TSF sync function */
+static void morse_capture_beacon_tsf(const struct morse_skb_rx_status *hdr_rx_status);

 void morse_mac_process_rx_noa(struct ieee80211_vif *vif, struct sk_buff *skb, u8 *s1g_ie)
 {
@@ -5886,6 +5893,22 @@ static inline void morse_mac_preprocess_s1g_action(struct morse *mors,
 	}
 }

+/**
+ * morse_capture_beacon_tsf - Capture TSF timestamp from beacon frames
+ * @hdr_rx_status: RX status containing hardware TSF timestamp
+ *
+ * Safely stores the hardware TSF timestamp and corresponding kernel time
+ * for clock synchronization purposes.
+ */
+static void morse_capture_beacon_tsf(const struct morse_skb_rx_status *hdr_rx_status)
+{
+	unsigned long flags;
+
+	spin_lock_irqsave(&tsf_sync_lock, flags);
+	last_beacon_hw_tsf_us = le64_to_cpu(hdr_rx_status->rx_timestamp_us);
+	last_beacon_kernel_time_ns = ktime_get_real_ns();
+	spin_unlock_irqrestore(&tsf_sync_lock, flags);
+}

 static int morse_mac_process_s1g_mgmt_or_beacon(struct morse *mors,
 						struct ieee80211_vif *vif,
@@ -5947,6 +5970,9 @@ static int morse_mac_process_s1g_mgmt_or_beacon(struct morse *mors,
 		if (ret)
 			return ret;
 	} else if (is_s1g_beacon) {
+		/* Capture TSF timestamp for clock synchronization */
+		morse_capture_beacon_tsf(hdr_rx_status);
+
 		morse_mac_process_s1g_beacon(mors, vif, skb, ies_mask);
 #if KERNEL_VERSION(5, 1, 0) < LINUX_VERSION_CODE
 		if (morse_mbssid_ie_enabled(mors)) {
--- a/debug.c
+++ b/debug.c
@@ -39,6 +39,9 @@
 #define HOSTIF_LOG_BUFFER_SIZE 10000
 #define HOSTIF_LOG_MAX_LEN 500

+/* External TSF sync variables from mac.c */
+extern u64 last_beacon_hw_tsf_us;
+extern u64 last_beacon_kernel_time_ns;
+extern spinlock_t tsf_sync_lock;

 struct hostif_log_entry {
 	char msg[HOSTIF_LOG_MAX_LEN];
@@ -1034,6 +1037,32 @@ static const struct file_operations watchdog_fops = {
 	.llseek = generic_file_llseek,
 };

+/**
+ * tsf_sync_show - Display TSF synchronization data
+ *
+ * Shows the last captured hardware TSF timestamp (in microseconds)
+ * and corresponding kernel time (in nanoseconds) from beacon frames.
+ * These values can be used for clock synchronization.
+ */
+static int tsf_sync_show(struct seq_file *m, void *v)
+{
+	unsigned long flags;
+	u64 hw_tsf_us;
+	u64 kernel_time_ns;
+
+	spin_lock_irqsave(&tsf_sync_lock, flags);
+	hw_tsf_us = last_beacon_hw_tsf_us;
+	kernel_time_ns = last_beacon_kernel_time_ns;
+	spin_unlock_irqrestore(&tsf_sync_lock, flags);
+
+	seq_printf(m, "hw_tsf_us: %llu\n", hw_tsf_us);
+	seq_printf(m, "kernel_time_ns: %llu\n", kernel_time_ns);
+
+	return 0;
+}
+
+DEFINE_SHOW_ATTRIBUTE(tsf_sync);
+
 static void morse_debug_fw_init(struct morse *mors)
 {
 #ifdef CONFIG_MORSE_DEBUGFS
@@ -1161,6 +1190,10 @@ static void morse_debug_fw_init(struct morse *mors)
 	debugfs_create_file("ps_offload_data", 0600, mors->debug.debugfs_phy, mors,
 			    &ps_offload_fops);

+	/* TSF synchronization interface */
+	debugfs_create_file("tsf_sync", 0444, mors->debug.debugfs_phy, mors,
+			    &tsf_sync_fops);
+
 	morse_debug_init_logging(mors);
 #endif
 }
EOF

echo "TSF sync patch installed!"
```

## Building for ARM64 Target

### Step 4: Configure for Your Target Board

Choose your target board. For ARM64, common options are:

```bash
# For generic ARM64 (armv8)
./scripts/morse_setup.sh -i -b ekh-armsr_armv8

# OR for Raspberry Pi 4
./scripts/morse_setup.sh -i -b ekh-bcm2711

# OR for other ARM64 boards - see boards/ directory for options
```

This will configure the build and enable the morse driver with DEBUG mode (needed for debugfs).

### Step 5: Verify morse_driver Debug is Enabled

```bash
# Optional: Check configuration
make menuconfig
# Navigate to: Kernel modules -> Wireless Drivers -> kmod-morse
# Ensure "morse debug" option is selected [*]
# Save and exit
```

### Step 6: Build the Driver

For just the driver module (faster):

```bash
# Build only the morse driver package
make package/feeds/morse/morse_driver/compile V=s
```

For full image (includes everything):

```bash
# Build complete firmware image (takes 1-2 hours first time)
make -j$(nproc) V=s
```

### Step 7: Locate Build Output

After successful build:

```bash
# Driver module location:
ls -lh build_dir/target-*/linux-*/morse_driver-*/morse.ko
ls -lh build_dir/target-*/linux-*/morse_driver-*/dot11ah/dot11ah.ko

# Full firmware images (if you built complete image):
ls -lh bin/targets/*/
```

## Loading the Driver on Target ARM64 Ubuntu 20.04 System

### On Your Target ARM64 System

#### Option A: If You Built Just the Driver Module

```bash
# Copy the .ko files to your ARM64 system
scp build_dir/target-*/linux-*/morse_driver-*/morse.ko user@arm64-target:/tmp/
scp build_dir/target-*/linux-*/morse_driver-*/dot11ah/dot11ah.ko user@arm64-target:/tmp/

# On the target system
sudo su
insmod /tmp/dot11ah.ko
insmod /tmp/morse.ko

# Verify driver loaded
lsmod | grep morse
dmesg | tail -20
```

#### Option B: If You Built Full OpenWRT Image

Flash the complete image to your device according to the board-specific instructions, then the driver will be loaded automatically.

### Installing Prerequisites on Target

```bash
# On target ARM64 Ubuntu 20.04 system
sudo apt update
sudo apt install -y wireless-tools iw

# Mount debugfs (if not already mounted)
sudo mount -t debugfs none /sys/kernel/debug
```

## Using the TSF Sync Feature

### Step 1: Configure WiFi Interface

```bash
# Bring up the wireless interface
sudo ip link set wlan0 up

# Scan for networks
sudo iw dev wlan0 scan | grep -E "SSID|freq"

# Connect to an AP (or start as AP)
sudo iw dev wlan0 connect "YourSSID"
# OR configure as AP - beacons must be received for TSF capture
```

### Step 2: Read TSF Sync Data

```bash
# Read TSF synchronization data
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_sync
```

Expected output:
```
hw_tsf_us: 123456789012345
kernel_time_ns: 1700000000000000000
```

### Step 3: Continuous Monitoring

```bash
# Monitor TSF updates in real-time
watch -n 1 'cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_sync'
```

### Step 4: Clock Synchronization Script

Create a sync script:

```bash
cat > ~/tsf_sync.sh << 'SCRIPT'
#!/bin/bash

# Read TSF sync data
TSF_FILE="/sys/kernel/debug/ieee80211/phy0/morse/tsf_sync"

if [ ! -f "$TSF_FILE" ]; then
    echo "Error: TSF sync file not found. Is the driver loaded with DEBUG enabled?"
    exit 1
fi

# Parse values
HW_TSF_US=$(grep hw_tsf_us "$TSF_FILE" | awk '{print $2}')
KERNEL_TIME_NS=$(grep kernel_time_ns "$TSF_FILE" | awk '{print $2}')

if [ "$HW_TSF_US" = "0" ]; then
    echo "Warning: No beacons captured yet. Connect to an AP first."
    exit 1
fi

echo "Hardware TSF:  $HW_TSF_US microseconds"
echo "Kernel Time:   $KERNEL_TIME_NS nanoseconds"
echo ""
echo "TSF in seconds: $((HW_TSF_US / 1000000))"
echo "Kernel time:    $(date -d @$((KERNEL_TIME_NS / 1000000000)))"

# Calculate offset (example)
# Add your synchronization logic here
SCRIPT

chmod +x ~/tsf_sync.sh
./tsf_sync.sh
```

## Troubleshooting

### Driver Not Loading

```bash
# Check kernel messages
dmesg | grep morse

# Check dependencies
lsmod | grep mac80211
lsmod | grep cfg80211

# Load dependencies if missing
modprobe mac80211
modprobe cfg80211
```

### Debugfs File Not Found

```bash
# Verify debugfs is mounted
mount | grep debugfs

# Mount if needed
sudo mount -t debugfs none /sys/kernel/debug

# Check if driver was built with DEBUG
modinfo morse | grep debug

# Verify morse debugfs directory exists
ls -la /sys/kernel/debug/ieee80211/phy0/morse/
```

### TSF Values Always Zero

```bash
# Ensure you're connected or associated
iw dev wlan0 link

# Check if beacons are being received
iw dev wlan0 station dump

# Watch for beacon reception
sudo tcpdump -i wlan0 type mgt subtype beacon
```

### Build Errors

```bash
# If ncurses or awk errors during feeds update
export FORCE=1
./scripts/feeds update morse

# Clean and rebuild
make package/feeds/morse/morse_driver/clean
make package/feeds/morse/morse_driver/compile V=s 2>&1 | tee build.log
```

## Quick Reference Commands

```bash
# Build
cd ~/openwrt
./scripts/morse_setup.sh -i -b ekh-armsr_armv8
make package/feeds/morse/morse_driver/compile V=s

# Load on target
insmod dot11ah.ko
insmod morse.ko country=US

# Read TSF
cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_sync

# Monitor
watch -n 1 'cat /sys/kernel/debug/ieee80211/phy0/morse/tsf_sync'
```

## Files Modified by This Build

- `feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch` - The TSF sync patch
- Applied automatically during build to:
  - `mac.c` - Adds beacon TSF capture
  - `debug.c` - Adds debugfs interface

## What Gets Built

1. **morse.ko** - Main Morse driver kernel module with TSF sync
2. **dot11ah.ko** - 802.11ah support module
3. **morse-fw** - Firmware files (from separate package)
4. **morsecli** - CLI tools for configuration

## Next Steps

After successfully building and loading:

1. Configure your wireless interface
2. Connect to an AP or start as AP
3. Read TSF sync data from debugfs
4. Implement your clock synchronization logic
5. Monitor TSF drift over time

For more details on the patch implementation, see `morse_tsf_sync_README.md`.
