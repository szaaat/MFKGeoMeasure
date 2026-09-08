# MFK GeoMeasure 1.1.0 - Release Baseline

This document records the stable baseline of the MFK GeoMeasure application as of version 1.1.0, including architecture details and validation status.

## Current Version
- **App Version:** 1.1.0
- **Build Number:** 10
- **Release Date:** 2026-09-08

## GNSS Architecture
The application uses a unified, provider-based architecture for location services.

### Supported Sources
1.  **Internal GNSS:** High-level position data via the phone's internal location services (using `geolocator`).
2.  **External GNSS:** Professional-grade external receivers connected via the unified `GnssProvider` interface.
3.  **Hybrid (Skeleton):** Architectural preparation for merged internal/external positioning (currently disabled).

### Connectivity & Transport
- **Bluetooth Classic:** Supported (Android).
- **Bluetooth Low Energy (BLE):** Supported (Nordic UART Service protocol).
- **USB-Serial:** Supported (Android).
- **NMEA Engine:** Custom parser for GGA, RMC, GSA, and GSV sentences.

## RTK & NTRIP Implementation
- **NTRIP Client:** Supports multiple profiles, Basic Authentication, and Sourcetable browsing.
- **RTCM Flow:** Correction data is received via TCP/IP and forwarded transparently to the external GNSS hardware.
- **RTK Status:** Real-time monitoring and recording of FIXED, FLOAT, DGPS, and Autonomous solutions.
- **Correction Age:** Precise tracking of time since last received RTCM packet (displayed and color-coded on the Map Screen).
- **GGA Feedback:** Configurable position reporting to NTRIP casters for VRS support.

## Data & Geodesy
- **Coordinate Systems:** Full support for WGS84 and Hungarian EOV (Y, X).
- **Height Handling:** 
    - Ellipsoidal height tracking.
    - Baltic/MSL height derived from the integrated EHT2014 geoid model.
- **Precision Timing:** UTC time and date extracted directly from GNSS (RMC/GGA) for all precision measurements.
- **Raw Logging:** Unified abstraction for raw satellite observations (Android Internal API ready, External prep).

## Validation Status

### Real Hardware Validated (Field Tested)
- **Device:** ArduSimple RTK Portable Bluetooth Kit (AS-STARTKIT-BTCASE-L1L2-0-03).
- **Flow Verified:** NTRIP → RTCM → Bluetooth → ArduSimple → NMEA → **RTK FIX**.
- **Evidence:** Verified 1s correction age, 12+ satellites, and Quality 4 status in actual field conditions.

### Software Validated
- Unit tests for NMEA parsing, UTC stitching, and midnight rollover.
- Regression tests for project persistence and multi-profile migration.
- Smoke tests for UI rendering and provider initialization.
- Release build verification for iOS (IPA) and Android (AAB).

## Known Limitations & Future Preparation
- **Hybrid Mode:** The `HybridGnssProvider` is implemented as an architectural skeleton and is currently **disabled**. It does not perform automatic source switching in this release.
- **External Raw Data:** External raw measurement support (e.g., UBX) is prepared in the interface but requires specific hardware transport implementation.
- **Skyplot:** Currently available on Android only (Internal GNSS).

---
*Authorized for Release 1.1.0 Production Baseline.*
