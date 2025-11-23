# MorseMicro OpenWrt
## Dependencies

To build the Morse Micro OpenWrt, you need a working Linux environment. This has been tested with Ubuntu 20.04 and higher.

Install build environment packages with
```
> sudo apt update
> sudo apt install build-essential clang flex g++ gawk gcc-multilib git gettext \
  libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev swig
```

## Usage

Run the `./scripts/morse_setup.sh` script to configure the build for your board of choice. Custom boards can be added to the `boards` folder and used as a target. See an existing board for the information which should be contained in the diffconfigs.

For example, to build for a HaLowLink1
```
> ./scripts/morse_setup.sh -i -b halowlink1
```

Some targets provided by this repository include

| Board              | Target                    |
|--------------------|-------------------------- |
| MMx108-EKH01 (SDIO)| `mmx108-ekh01-sdio`       |
| MM6108-EKH01 (SPI) | `mm6108-ekh01-spi`        |
| MM8108-EKH01 (SPI) | `mm8108-ekh01-spi`        |
| HaLowLink1         | `halowlink1`              |
| MM8108-EKH19       | `ekh19`                   |

See the `boards/` folder for other targets and families.


After configuration is complete, run the build with
```
> make -j8
```

For verbose compilation, consider using
```
> make -j8 V=sc 2>&1 | tee log.txt
```

Once the build is complete a compiled image can be found in `bin/target/<platform>/<target>/`

## TSF Synchronization

This repository includes TSF (Timing Synchronization Function) support for precise time synchronization in HaLow mesh networks.

**Documentation**:
- [TSF_SYNC_THEORY.md](TSF_SYNC_THEORY.md) - Explains the architecture, design decisions, and technical concepts
- [TSF_SYNC_DEPLOYMENT.md](TSF_SYNC_DEPLOYMENT.md) - Step-by-step guide to build and deploy production firmware with TSF support

**Quick Summary**:
- Production firmware with DEBUGFS (no DEBUG bugs)
- Real-time TSF access via `/sys/kernel/debug/ieee80211/phy0/morse/tsf_*`
- Tested on BCM27xx (Raspberry Pi 4) with kernel 5.15.167
- Dual interface: `tsf_rx` (last RX time) and `tsf_current` (extrapolated current time)
