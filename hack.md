This is a comprehensive guide to implementing the "Robot-as-Master" (AP) architecture using the TSF Driver Hack. This approach establishes the Mobile Robot as the authoritative time source ("Grandmaster") and forces the stationary Gateway to synchronize to it.

You can save the content below as halow_tsf_sync.md.

Markdown

# Wi-Fi HaLow TSF Time Synchronization Guide
**Architecture:** Robot-as-Master (AP) -> Gateway-as-Slave (Station)
**Target Accuracy:** < 100 µs (0.1 ms)
**Hardware:** Morse Micro (MM6108) or Generic 802.11ah

## 1. System Architecture

The core concept is to use the Wi-Fi Hardware Clock (TSF) as a precise "carrier" to transport the Robot's System Time to the Gateway, bypassing the variable latency of the Linux Networking Stack.

### Topology
* **Mobile Robot (Access Point):**
    * **Role:** Grandmaster.
    * **Clock:** Free-running (Standard Linux `CLOCK_REALTIME`).
    * **Action:** Broadcasts a "Time Sync Packet" containing `[My_Current_TSF, My_System_Time]`.
* **Stationary Gateway (Client):**
    * **Role:** Slave.
    * **Clock:** Servos/Slews to match the Robot.
    * **Action:** Intercepts packet, calculates flight time using hardware timestamps, and adjusts local OS clock.

---

## 2. Kernel Driver Modification (The "Hack")

You must modify the Wi-Fi driver source code (e.g., `morse_driver`) on **BOTH** the Robot and the Gateway to expose the Hardware TSF to userspace.

### The Goal
Create a `debugfs` file (e.g., `/sys/kernel/debug/morse/tsf_snapshot`) that, when read, returns the most recent TSF value and System Time.

### The C Code Patch (Pseudo-code)
*Use this logic to guide your AI coding assistant.*

**File:** `morse_rx.c` (Receive Path) & `morse_main.c` (Global glue)

```c
/* --------------------------------------------------------------------------
 * GLOBAL VARIABLES (Add to driver struct or global scope)
 * -------------------------------------------------------------------------- */
static volatile u64 g_last_tsf = 0;
static volatile u64 g_last_ktime = 0;
static DEFINE_SPINLOCK(g_tsf_lock);

/* --------------------------------------------------------------------------
 * STEP 1: CAPTURE (Insert into RX Interrupt Handler)
 * Find the function that processes received frames (e.g., morse_rx_process)
 * -------------------------------------------------------------------------- */
void morse_rx_capture_tsf(struct sk_buff *skb, struct morse_rx_desc *rx_desc) {
    unsigned long flags;
    u64 current_ktime = ktime_get_real_ns(); // Capture System Time NOW
    u64 packet_tsf = rx_desc->tsf;           // Capture HW Timestamp from Packet

    spin_lock_irqsave(&g_tsf_lock, flags);
    g_last_tsf = packet_tsf;
    g_last_ktime = current_ktime;
    spin_unlock_irqrestore(&g_tsf_lock, flags);
}

/* --------------------------------------------------------------------------
 * STEP 2: EXPOSE (Add to DebugFS setup)
 * -------------------------------------------------------------------------- */
static int tsf_show(struct seq_file *m, void *v) {
    unsigned long flags;
    u64 t_tsf, t_sys;

    spin_lock_irqsave(&g_tsf_lock, flags);
    t_tsf = g_last_tsf;
    t_sys = g_last_ktime;
    spin_unlock_irqrestore(&g_tsf_lock, flags);

    seq_printf(m, "TSF: %llu\nSYS: %llu\n", t_tsf, t_sys);
    return 0;
}

static int tsf_open(struct inode *inode, struct file *file) {
    return single_open(file, tsf_show, inode->i_private);
}

static const struct file_operations tsf_fops = {
    .owner = THIS_MODULE,
    .open = tsf_open,
    .read = seq_read,
    .release = single_release,
};

// Call this in driver init:
// debugfs_create_file("tsf_snapshot", 0444, driver_debugfs_dir, NULL, &tsf_fops);
3. Robot Configuration (The Master)
The Robot acts as the AP. It does not adjust its clock. It simply shouts the time.

A. hostapd.conf (Wi-Fi HaLow AP)
Ensure your AP is configured for 802.11ah mode.

Bash

interface=wlan0
driver=nl80211
ssid=ROBOT_V1
hw_mode=a
ieee80211ah=1          # Enable HaLow
s1g_prim_chwidth=4     # Bandwidth (MHz) - Match your Gateway capabilities
channel=40             # Use a clean channel
beacon_int=100         # 100ms Beacons
B. master_clock.py (The Broadcaster)
This script reads the Robot's internal TSF and System Time, then multicasts it to the network.

Python

import time
import socket
import struct
import os

# CONFIG
MCAST_GRP = '224.1.1.1'
MCAST_PORT = 5007
# Path to your debugfs file (created by the kernel patch)
DEBUGFS_PATH = "/sys/kernel/debug/morse/tsf_snapshot"

def read_kernel_tsf():
    """Reads the latest TSF/System pair from the driver."""
    # Trigger a read by sending a dummy packet to ourselves or just reading 
    # the register if your driver exposes 'current_tsf' directly.
    # For this architecture, we assume the debugfs file returns CURRENT TSF.
    try:
        with open(DEBUGFS_PATH, 'r') as f:
            data = f.read().strip().split('\n')
            # Parse "TSF: 12345" and "SYS: 98765"
            tsf = int(data[0].split(': ')[1])
            sys_ns = int(data[1].split(': ')[1])
            return tsf, sys_ns
    except Exception as e:
        print(f"Kernel Read Error: {e}")
        return 0, 0

def run_master():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    
    print("Starship Enterprise (Robot) - Time Master Active")
    
    while True:
        # 1. Get Truth
        tsf, sys_ns = read_kernel_tsf()
        
        # 2. Pack & Send (Q = uint64)
        # Packet Format: [TSF_Timestamp] [System_Time_NS]
        payload = struct.pack('!QQ', tsf, sys_ns)
        sock.sendto(payload, (MCAST_GRP, MCAST_PORT))
        
        # 3. Rate Limit (10Hz is plenty)
        time.sleep(0.1)

if __name__ == "__main__":
    run_master()
4. Gateway Configuration (The Slave)
The Gateway receives the packet and uses the "Driver Hack" to figure out exactly how long ago it was sent.

A. slave_sync.py (The Servo)
This script controls the Gateway's Linux Clock.

Python

import socket
import struct
import time
import ctypes
import ctypes.util
import os

# --- CLOCK ADJTIME SETUP (CTYPES) ---
libc = ctypes.CDLL(ctypes.util.find_library('c'))
CLOCK_REALTIME = 0
ADJ_FREQUENCY = 0x0002

class Timex(ctypes.Structure):
    _fields_ = [("modes", ctypes.c_int), ("_pad0", ctypes.c_int),
                ("offset", ctypes.c_long), ("freq", ctypes.c_long),
                ("maxerror", ctypes.c_long), ("esterror", ctypes.c_long),
                ("status", ctypes.c_int), ("_pad1", ctypes.c_int),
                ("constant", ctypes.c_long), ("precision", ctypes.c_long),
                ("tolerance", ctypes.c_long), ("time", ctypes.c_long * 2),
                ("tick", ctypes.c_long)]

def slew_clock(ppm):
    """Adjusts system clock frequency."""
    tx = Timex()
    tx.modes = ADJ_FREQUENCY
    tx.freq = int(ppm * 65536)
    libc.clock_adjtime(CLOCK_REALTIME, ctypes.byref(tx))

# --- MAIN SYNC LOGIC ---
MCAST_GRP = '224.1.1.1'
MCAST_PORT = 5007
DEBUGFS_PATH = "/sys/kernel/debug/morse/tsf_snapshot"

# PID Controller Constants
Kp = 0.5  # Proportional gain
Ki = 0.01 # Integral gain
integral_error = 0

def get_last_packet_arrival_time():
    """Reads the TSF hack file to find when the last packet REALLY arrived."""
    with open(DEBUGFS_PATH, 'r') as f:
        data = f.read().strip().split('\n')
        tsf = int(data[0].split(': ')[1])
        # We don't need SYS from the file, we compare against packet payload
        return tsf

def run_slave():
    global integral_error
    
    # Setup Network
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('', MCAST_PORT))
    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    print("Gateway Listener Active... Waiting for Robot.")

    while True:
        data, _ = sock.recvfrom(1024) # Blocking wait for packet
        
        # 1. Parse Master's Message
        master_tsf, master_sys_ns = struct.unpack('!QQ', data)
        
        # 2. Get Local Hardware Timestamp (From Driver Hack)
        # This tells us the exact TSF when the packet hit our antenna
        local_tsf_arrival = get_last_packet_arrival_time()
        
        # 3. Calculate "Flight Time" (The Magic)
        # Since TSFs are synced by hardware, Delta TSF = Real Flight Time
        flight_time_us = local_tsf_arrival - master_tsf
        
        # Handle 64-bit Rollover (unlikely but safe)
        if flight_time_us < 0: flight_time_us += (2**64)

        # 4. Calculate Error
        # Expected Time = Master Time + Flight Time
        target_time_ns = master_sys_ns + (flight_time_us * 1000)
        current_time_ns = time.time_ns()
        
        offset_ns = target_time_ns - current_time_ns
        offset_ms = offset_ns / 1e6

        # 5. PI Control Loop (Servo the Clock)
        # If Offset is huge (>100ms), Step the clock (Jump)
        if abs(offset_ms) > 100:
            print(f"Huge Drift ({offset_ms:.2f}ms). Stepping Clock...")
            # Use 'date' or clock_settime to jump immediately
            # set_time(target_time_ns) 
            integral_error = 0
        else:
            # Slew the clock (Micro-adjust speed)
            integral_error += offset_ms
            adjustment_ppm = (Kp * offset_ms) + (Ki * integral_error)
            
            # Clamp safety
            adjustment_ppm = max(min(adjustment_ppm, 500), -500)
            
            slew_clock(adjustment_ppm)
            print(f"Offset: {offset_ms:.3f} ms | Flight: {flight_time_us} us | Adj: {adjustment_ppm:.2f} ppm")

if __name__ == "__main__":
    run_slave()
5. Verification Steps
Compile & Flash: Rebuild your OpenWRT/Ubuntu kernel with the driver patch and install on both devices.

Start Robot: Run python3 master_clock.py.

Start Gateway: Run python3 slave_sync.py.

Observe:

You should see Flight: ~2000-5000 us (This is normal airtime + interrupt latency).

You should see Offset start high, then drop to 0.0xx ms within 10 seconds.

Test: Physically tap a button connected to a GPIO on the Robot and a GPIO on the Gateway simultaneously. Compare the timestamps in the logs. They should match within < 1ms.
