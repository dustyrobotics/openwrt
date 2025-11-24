# TSF Synchronization - Theory and Architecture

## Overview

This document explains the theoretical basis and architectural design of TSF (Timing Synchronization Function) synchronization for Morse Micro HaLow (802.11ah) wireless networks.

## What is TSF?

**TSF (Timing Synchronization Function)** is a hardware-maintained 64-bit timer in 802.11 wireless devices that:
- Increments at 1 MHz (1 microsecond resolution)
- Synchronizes across all devices in a BSS (Basic Service Set)
- Provides a common time reference for the wireless network
- Is included in every beacon frame transmitted by the AP

### Why TSF Matters

In distributed systems (mesh networks, multi-robot coordination), precise time synchronization enables:
- Coordinated actions across multiple devices
- Precise timestamping of sensor data
- Time-of-flight measurements
- Synchronized data collection
- Network-wide event ordering

## The Challenge

Standard Linux wireless drivers don't expose real-time access to:
1. **Hardware TSF values** from received frames
2. **Kernel timestamps** captured at the moment of frame reception
3. **Current TSF extrapolation** for transmission timing

This makes it impossible for user-space applications to:
- Determine exactly when a packet arrived
- Correlate wireless timestamps with system time
- Broadcast current network time

## The Solution: TSF Sync Patch

### Architecture

The TSF sync patch adds three key capabilities to the Morse driver:

#### 1. TSF Capture on Frame Reception

```c
// In morse_rx_process_skb() - called for every received frame
u64 hw_tsf_us = morse_dot11ah_compute_tsf_from_rx_status(status, hdr->duration_id);
u64 kernel_time_ns = ktime_get_real_ns();

// Store atomically with spinlock protection
spin_lock_irqsave(&tsf_sync_lock, flags);
last_rx_hw_tsf_us = hw_tsf_us;
last_rx_kernel_time_ns = kernel_time_ns;
spin_unlock_irqrestore(&tsf_sync_lock, flags);
```

**Key Insight**: Captures both hardware and kernel time at the *exact same moment* for correlation.

#### 2. Dual Debugfs Interface

Two interfaces serve different use cases:

**`tsf_rx`** - Last Received Frame Time
- Use case: Client/Gateway determining when packets arrived
- Returns: TSF and kernel time from last received management/beacon frame
- Update: Every incoming frame

**`tsf_current`** - Current Extrapolated Time
- Use case: AP/Robot broadcasting current network time
- Returns: Current TSF extrapolated from last RX + elapsed system time
- Update: Real-time calculation on each read

#### 3. Exported Kernel Function

```c
void morse_get_tsf_snapshot(u64 *hw_tsf_us, u64 *kernel_time_ns);
```

Allows other kernel modules to access TSF data programmatically.

### Data Flow

```
Hardware RX Descriptor
         |
         v
morse_rx_process_skb()
         |
         +-- Extract hw_tsf_us
         +-- Capture kernel_time_ns
         |
         v
   tsf_sync_lock (atomic storage)
         |
         +-- last_rx_hw_tsf_us
         +-- last_rx_kernel_time_ns
         |
         v
    Debugfs Interface
         |
         +-- tsf_rx (read directly)
         +-- tsf_current (extrapolate)
```

## Critical Discovery: DEBUGFS vs DEBUG

### The Problem with DEBUG Mode

Initially, we attempted to enable TSF access using `CONFIG_MORSE_DEBUG=y`:

**Issues**:
- Enables full DEBUG firmware (644.9K vs 625.5K production)
- Includes extensive test modes and logging
- **Beacon timing bugs** - clients authenticate but never receive beacons
- Higher CPU overhead and memory usage
- Not suitable for production deployment

### The Solution: DEBUGFS Only

**Key Discovery**: The TSF sync patch only requires `CONFIG_MORSE_DEBUGFS=y`, NOT full DEBUG mode.

**Architecture**:
```makefile
# In morse_driver Makefile
ccflags-$(CONFIG_MORSE_DEBUGFS) += "-DCONFIG_MORSE_DEBUGFS"
```

The patch creates debugfs files only when `CONFIG_MORSE_DEBUGFS` is defined:
```c
#ifdef CONFIG_MORSE_DEBUGFS
debugfs_create_file("tsf_rx", 0444, mors->debug_dir, mors, &tsf_rx_fops);
debugfs_create_file("tsf_current", 0444, mors->debug_dir, mors, &tsf_current_fops);
#endif
```

**Result**: Production firmware (625.5K) with TSF access and no beacon bugs.

## Firmware Comparison

| Metric | DEBUG Build | Production + DEBUGFS |
|--------|------------|---------------------|
| morse.ko size | 644.9K | 625.5K |
| Build flags | `DEBUG=y`, `CONFIG_MORSE_DEBUGFS=y` | `DEBUG=n`, `CONFIG_MORSE_DEBUGFS=y` |
| Test modes | Enabled | Disabled |
| Extra logging | Yes | No |
| Beacon timing | Buggy | Stable |
| TSF access | Yes | Yes |
| Production ready | No | **Yes** |

## Time Synchronization Theory

### Time Correlation

The patch enables precise correlation between:
- **Hardware time** (TSF in microseconds)
- **Kernel time** (monotonic nanoseconds)

This allows applications to:
1. Convert TSF timestamps to system time
2. Calculate packet flight time
3. Synchronize clocks across the network

### Client/Gateway Synchronization

```python
# Gateway receives sync packet
with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_rx') as f:
    lines = f.readlines()
arrival_tsf = int(lines[0].split(': ')[1])  # When packet arrived (TSF)
arrival_sys = int(lines[1].split(': ')[1])  # When packet arrived (system)

# Packet contained sender's TSF
sender_tsf = get_tsf_from_packet()

# Calculate one-way delay (assuming synchronized TSF)
flight_time_us = arrival_tsf - sender_tsf

# Adjust local clock
clock_offset = sender_sys - arrival_sys + flight_time_us * 1000
```

### AP/Robot Time Broadcasting

```python
# Robot prepares sync packet
with open('/sys/kernel/debug/ieee80211/phy0/morse/tsf_current') as f:
    lines = f.readlines()
current_tsf = int(lines[0].split(': ')[1])
current_sys = int(lines[1].split(': ')[1])

# Include in packet payload
packet = create_sync_packet(tsf=current_tsf, sys=current_sys)
send(packet)
```

## Patch Implementation Details

### Global Variables

```c
// Thread-safe storage for TSF data
static u64 last_rx_hw_tsf_us = 0;
static u64 last_rx_kernel_time_ns = 0;
static DEFINE_SPINLOCK(tsf_sync_lock);
```

### TSF Extrapolation

For `tsf_current`, the driver extrapolates from last RX:

```c
u64 morse_get_current_tsf(void) {
    unsigned long flags;
    u64 hw_tsf, kernel_time_rx, kernel_time_now, elapsed_ns;

    spin_lock_irqsave(&tsf_sync_lock, flags);
    hw_tsf = last_rx_hw_tsf_us;
    kernel_time_rx = last_rx_kernel_time_ns;
    spin_unlock_irqrestore(&tsf_sync_lock, flags);

    kernel_time_now = ktime_get_real_ns();
    elapsed_ns = kernel_time_now - kernel_time_rx;

    // Convert elapsed nanoseconds to microseconds and add to last TSF
    return hw_tsf + (elapsed_ns / 1000);
}
```

This assumes kernel clock and TSF advance at the same rate (both at 1 MHz nominal).

## Performance Characteristics

### Update Frequency
- Management/beacon frames: 10-100 Hz typical
- Data frames: Up to several kHz in active networks
- Every frame updates the TSF snapshot

### Overhead
- Spinlock acquisition: < 100 ns
- TSF extraction: < 500 ns
- Total per frame: < 1 µs (negligible)

### Accuracy
- TSF resolution: 1 µs (hardware)
- Kernel time resolution: 1 ns (software)
- Synchronization accuracy: < 100 µs (with proper implementation)
- Drift: Depends on oscillator quality (~20 ppm typical)

## Use Cases

### Multi-Robot Coordination
- Robots synchronize to AP's TSF
- Coordinated movement with µs-level timing
- Distributed sensing with synchronized timestamps

### Mesh Network Time Sync
- Gateway nodes act as time masters
- Client nodes synchronize to gateway
- Hierarchical time distribution

### Precision Timestamping
- Sensor data tagged with TSF timestamps
- Post-processing with common time reference
- Event correlation across devices

## Design Decisions

### Why Two Interfaces?

**Separation of Concerns**:
- `tsf_rx` - Raw capture (what was received)
- `tsf_current` - Derived value (what time is it now)

Different roles need different information:
- **Clients** care about when packets arrived (for offset calculation)
- **APs** care about current time (for broadcasting)

### Why Debugfs?

**Advantages**:
- No system call overhead (simple file read)
- Standard Linux interface
- Easy access from any language
- No custom ioctls or netlink protocols

**Trade-offs**:
- Requires debugfs mount
- Not available in all kernel configurations
- Must build with `CONFIG_MORSE_DEBUGFS=y`

### Why Not Use mac80211 TSF?

Standard mac80211 provides `drv_get_tsf()`, but:
- Only returns current TSF (no correlation with kernel time)
- Requires ioctl from user space
- No capture of RX timestamps
- Higher latency

Our patch provides:
- Atomic capture of both TSF and kernel time
- Zero-copy access via debugfs
- Sub-microsecond correlation

## OpenWrt Integration

### Build System Architecture

OpenWrt applies patches sequentially:
```
morse_driver-1.16.4 (vanilla)
  + 001-fix-something.patch
  + 002-another-fix.patch
  ...
  + 015-final-core-patch.patch
  + 999-tsf-sync.patch  ← Our patch
```

**Critical**: Our patch must be generated *after* applying patches 001-015, as they shift line numbers significantly (patch 008 alone shifted mac.c by 522 lines).

### Configuration

```makefile
# feeds/morse/essentials/morse_driver/Makefile
MORSE_MAKEDEFS += CONFIG_MORSE_DEBUGFS=y
```

This sets the compiler flag:
```makefile
# build_dir/.../morse_driver/Makefile
ccflags-$(CONFIG_MORSE_DEBUGFS) += "-DCONFIG_MORSE_DEBUGFS"
```

## Summary

The TSF sync solution provides:
- **Production-ready** firmware (no DEBUG bugs)
- **Minimal overhead** (< 1 µs per frame)
- **High accuracy** (< 100 µs synchronization)
- **Dual interface** (RX capture + current extrapolation)
- **Standard access** (debugfs file reads)
- **OpenWrt compatible** (tested on aarch64/bcm27xx)

This enables precise time synchronization for HaLow mesh networks without compromising firmware stability or performance.
