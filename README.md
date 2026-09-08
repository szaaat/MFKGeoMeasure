# MFK GeoMeasure

A professional mobile geodetic/GNSS field measurement application for Android and iOS.

**Version: 1.1.0**

## Major Capabilities

*   **Platform Support:** Native experience on both Android and iOS.
*   **GNSS Positioning:** High-precision location tracking with support for various coordinate systems.
*   **EOV Support:** Full Hungarian EOV X/Y coordinate transformation and display.
*   **Height Handling:**
    *   Ellipsoidal height tracking.
    *   Baltic/MSL height derived from the EHT2014 geoid model.
*   **Geodetic Tools:**
    *   **COGO:** Coordinate geometry calculations (Inverses, Intersections, etc.).
    *   **Leveling:** Professional leveling session management and calculations.
*   **External GNSS Connectivity:**
    *   Support for high-precision external receivers via Bluetooth Classic, BLE, and USB-Serial.
    *   NMEA parser for GGA, RMC, GSA, and GSV sentences.
*   **RTK & NTRIP:**
    *   Real-time Kinematic (RTK) support with FLOAT and FIX status monitoring.
    *   NTRIP/RTCM client for receiving network corrections.
    *   NTRIP Profiles: Save and manage multiple caster configurations.
    *   Sourcetable Browser: Fetch and select mountpoints from the caster.
    *   GGA Feedback: Configurable VRS support with periodic position feedback.
    *   RTK FIX Stability Control: Optional measurement gating based on fix stability.
*   **Real-time Diagnostics:**
    *   Correction Age monitoring (precisely tracking time since last RTCM packet).
    *   RTCM bitrate and traffic monitoring.
    *   Skyplot visualization (Android).
*   **Data Export:**
    *   CSV, GeoJSON, and ESRI Shapefile (SHP) export formats.
*   **Project Management:**
    *   Typed attributes and feature templates.
    *   Safe project persistence with automated migration/versioning.

---

> [!NOTE]
> RTK/NTRIP support is implemented and software-tested; real-world RTK validation requires compatible external GNSS hardware and an active NTRIP service.

## Security

NTRIP credentials and other sensitive information are stored securely using device-level encryption (Keychain/Keystore) and are never included in project files or exported metadata.

## License

(License details if available)
