# MFK GeoMeasure: Scientific Evidence Verification Report

**Audit Date:** May 2024 / Verified Revision  
**Target Publication:** *Journal of Geosciences and Engineering*, University of Miskolc  
**Application:** MFK GeoMeasure (`hu.uni.miskolc.mfk_geomeasure`)  
**Package Version:** `1.1.1+11`  
**Git Commit SHA:** `2d0d4b7cc21dfb6b40256754cc8e73a1418d6f1c`  

---

## 1. Executive Summary

This report establishes the empirical and architectural evidence base for the scientific manuscript titled *"MFK GeoMeasure: A Mobile GIS Application for Field Data Collection, GNSS Integration and Geospatial Education"*.

All statements in this document are strictly partitioned into:
1. **Source-Code Observations:** Static architectural verification of the codebase.
2. **Executed Test Results:** Live verification from running the automated Flutter test suite.
3. **Targeted Code Modifications & Verification:** Verified bug fixes for export attribute mapping, GeoJSON height semantics, and persistence queue locking.
4. **Proposed Future Experiments:** Recommended empirical protocols for physical field trials.

---

## 2. Executed Test Results & Verified Code Fixes

### A. Test Suite Execution Summary
The Flutter unit and integration test suite (including the new regression test suite) was executed in the project environment using the official Flutter toolchain.

* **Execution Command:** `flutter test`
* **Exit Code:** `0` (Success)
* **Flutter Version:** `3.38.1` (channel stable, revision `b45fa18946`)
* **Dart Version:** `3.10.0`
* **DevTools Version:** `2.51.1`
* **Test Outcome:**
  * **Passed:** `96`
  * **Failed:** `0`
  * **Skipped:** `0`
  * **Total Test Suites Executed:** `25` test files

```
00:10 +96: All tests passed!
```

### B. Summary of Targeted Code Modifications & Verified Fixes

1. **EOV Attribute Mapping Corrected (`lib/services/project_service.dart`):**
   * **Previous Behavior:** In `_generateCsvString()` and `_buildGeoJson()`, `eov[1]` (Northing $X$) was assigned to `EOV_Y` and `eov[0]` (Easting $Y$) was assigned to `EOV_X`.
   * **Fix Implemented:** Remapped `EOV_Y` $\leftarrow$ `eov[0]` ($Y$, Easting) and `EOV_X` $\leftarrow$ `eov[1]` ($X$, Northing) in both CSV and GeoJSON export functions.
   * **Verified By Test:** `Export and Persistence Regression Tests 1. EOV_Y and EOV_X attribute mapping in CSV and GeoJSON exports` passed.

2. **GeoJSON Height Semantics Corrected (`lib/services/project_service.dart`):**
   * **Previous Behavior:** Third geometry coordinate in `geometry.coordinates` `[longitude, latitude, elevation]` was formatted as Baltic orthometric height $H$.
   * **Fix Implemented:** Updated `geoJsonCoordinate()` to write WGS 84 ellipsoidal height $h$ as the 3rd geometry coordinate (conforming to RFC 7946). Baltic orthometric height $H$ is retained in feature properties under `Baltic_Height`. If a valid height is unavailable, the 3rd coordinate is omitted, producing a 2D `[lon, lat]` array.
   * **Verified By Test:** `Export and Persistence Regression Tests 2. GeoJSON 3D height semantics (Ellipsoidal vs Baltic Orthometric)` passed.

3. **Project Save Serialization & Unique Temp Paths Implemented (`lib/services/project_service.dart`):**
   * **Previous Behavior:** Unawaited asynchronous calls to `_saveProjectsToDisk()` ran concurrently without locking, causing `PathNotFoundException` file-rename collisions on `.tmp` files during rapid edits.
   * **Fix Implemented:** Wrapped `_saveProjectsToDisk()` in a `Completer` chain lock queue (`_saveQueue`) and updated `_performSaveToDisk()` to write to process-unique temporary paths (`saved_projects_${microseconds}.tmp`). Added `flushPendingSaves()` and `lastSaveError` to enable explicit error detection in tests.
   * **Verified By Test:** `Export and Persistence Regression Tests 3. Rapid consecutive edits execute without race conditions or PathNotFoundException` passed (50 rapid sequential edits executed without file lock exceptions and verified via fresh `ProjectService` reload from disk).

---

## 3. Geodetic Unit Test Analysis & Computational Precision

Geodetic transformation accuracy and grid interpolation behavior were verified in `test/services/bme_grid_service_test.dart`, `test/services/gis_roundtrip_test.dart`, and `test/services/export_and_persistence_regression_test.dart`.

* **Reference Datasets:**
  * `assets/data/hu_bme_hd72corr.f32`: Binary grid containing $251 \times 121$ arc-second correction points for ETRF2000 ↔ HD72 horizontal shift.
  * `assets/data/hu_bme_geoid2014.f32`: Binary grid containing $268 \times 186$ undulation points for Baltic orthometric height calculation.
* **Reference Test Coordinates (Eger / Miskolc area benchmark point):**
  * Input ETRF2000: $\phi = 47.97801236^\circ \text{ N}, \lambda = 20.43002679^\circ \text{ E}, h = 233.625\text{ m}$
  * Expected EOV Coordinates: $Y = 753218.9656450956\text{ m}$ (Easting), $X = 293622.2580149178\text{ m}$ (Northing)
  * Expected Geoid Undulation: $N = 42.345627\text{ m}$
  * Expected Baltic Orthometric Height: $H = 191.279373063\text{ m}$
* **Comparison Tolerances & Code Assertions:**
  * EOV Coordinate Assertion: `expect(result[0], closeTo(753218.9656450956, 0.00001));` ($0.01\text{ mm}$ mathematical tolerance).
  * EOV Inverse Assertion: `expect(inverse[0], closeTo(47.97801236, 0.00000005));` ($5 \times 10^{-8}$ degrees).
  * Geoid Undulation Assertion: `expect(undulation, closeTo(42.345627, 0.00001));` ($0.01\text{ mm}$).
  * Shapefile Binary Export Assertion: `expect(xInFile, closeTo(originalEovY, 0.001));` ($1.0\text{ mm}$).

* **Clarification of Sub-Millimetre Figure:**
  * **Numerical Precision:** The sub-millimetre ($< 0.1\text{ mm}$) figures represent **software calculation precision** of $64\text{-bit}$ float arithmetic interpolating $32\text{-bit}$ float grid shift files relative to PROJ reference outputs.
  * **Demonstrated Transformation Accuracy vs. Physical Field Accuracy:** Proves mathematical algorithm equivalence to PROJ, NOT physical field measurement accuracy (which depends on physical GNSS hardware, baseline length, antenna phase center, and RTK solution state, typically $1\text{--}2\text{ cm}$).

---

## 4. Source-Code Observations & Architectural Constraints

### A. Complete Project Persistence Lifecycle
1. **Trigger Events:** `_saveProjectsToDisk()` is called following all project, layer, feature, and attribute edits in `ProjectService`.
2. **Sequential Lock:** `_saveQueue` ensures async save requests execute sequentially.
3. **Crash-Safe Atomic File Replacement:**
   * Creates `saved_projects.json.bak` if existing file is present.
   * Serializes JSON string to `saved_projects.json.tmp`.
   * Replaces `saved_projects.json` with `saved_projects.json.tmp` (using `rename` with `copy` fallback).
   * Deletes `saved_projects.json.bak` upon successful completion.

### B. iOS Background Execution Inspection
1. **Declared iOS Permissions (`ios/Runner/Info.plist`):**
   * `NSLocationWhenInUseUsageDescription`: Present (Foreground location prompt).
   * `NSBluetoothAlwaysUsageDescription`: Present (Bluetooth prompt).
   * **`UIBackgroundModes` Key:** **NOT PRESENT** in `ios/Runner/Info.plist`.
2. **Technical Consequence:** On iOS, location updates (CoreLocation) and Bluetooth notification streams (CoreBluetooth) are suspended when the application is backgrounded or screen locks. MFK GeoMeasure operates as a **foreground-active application**.

---

## 5. Proposed Future Experiments (Recommended Protocol)

### A. QGIS Interoperability Verification Protocol
1. **Dataset Generation:** Create project in MFK GeoMeasure with points, lines, polygons, and custom attributes. Export to Shapefile (`.zip`), GeoPackage (`.gpkg`), and GeoJSON (`.geojson`).
2. **QGIS Verification Steps:**
   * **Shapefile (`.shp`):** Verify native CRS assignment `EPSG:23700` and coordinate values ($Y$ Easting, $X$ Northing) in meters ($\le 1\text{ mm}$ deviation).
   * **GeoPackage (`.gpkg`):** Verify OGC GeoPackage table metadata (`srs_id = 23700`), WKB binary geometries, and attribute data types.
   * **GeoJSON (`.geojson`):** Verify WGS 84 geographic geometry coordinates `[longitude, latitude, ellipsoidal_height]` (`EPSG:4326`) and feature properties `EOV_Y`, `EOV_X`, `Baltic_Height`, `Source_Height`.

### B. Physical Geodetic Benchmark Calibration Protocol
* **Objective:** Establish physical 2D RMSE and vertical accuracy over calibrated geodetic control points (ÖK pillars).
* **Protocol:** Position MFKRTK receiver on a benchmark pillar, record 180 RTK FIXED epochs via `ControlPointCheckService`, and compute $2\text{D RMSE} = \sqrt{\text{RMSE}_E^2 + \text{RMSE}_N^2}$ and $\Delta H$.
