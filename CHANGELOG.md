# Changelog - MFK GeoMeasure

## [1.1.0] - 2026-09-08

### Professional GNSS & Geodetic Field Measurement

#### Features
- **Professional Line Leveling:** Fully implemented session management and calculations.
- **EOV Coordinate Support:** Native Hungarian EOV X/Y transformation and real-time display.
- **Advanced Height Handling:** Support for both ellipsoidal and Baltic heights (derived from EHT2014 geoid).
- **Unified GNSS Architecture:** Abstracted provider layer supporting internal and high-precision external receivers.
- **External GNSS Connectivity:** Support for Bluetooth Classic, BLE, and USB-Serial receivers.
- **NMEA Engine:** Full parser for GGA, RMC, GSA, and GSV sentences.
- **NTRIP & RTCM:** 
  - Network correction streaming (RTCM).
  - NTRIP Profiles: Management of multiple caster configurations.
  - Sourcetable Browser: Integrated mountpoint selection.
  - GGA Feedback: Automatic position reporting for VRS services.
- **RTK Monitoring:** Real-time FLOAT and FIX status tracking with Correction Age diagnostics.
- **Data Export:** Support for CSV, GeoJSON, and ESRI Shapefile (SHP).
- **Project Reliability:** Secure NTRIP credential storage, automated format migration, and atomic save operations.

#### Real Hardware Validation
This release has been successfully field-tested with the **ArduSimple RTK Portable Bluetooth Kit** (SKU: AS-STARTKIT-BTCASE-L1L2-0-03).

The field test verified:
- Stable Bluetooth Classic connection to the ArduSimple receiver.
- Successful NTRIP handshake and authentication.
- Continuous RTCM data reception and forwarding to the hardware.
- Receiver reaching **RTK FIX** (NMEA Quality 4) with ~1s correction age and high satellite count.

*Note: Real-world RTK performance depends on GNSS hardware compatibility and NTRIP service availability.*

---
Version: 1.1.0+10
