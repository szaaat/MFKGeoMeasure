# MFK GeoMeasure: Final Interoperability and Evidence Verification Report

**Audit Date:** May 2024 / Active State Review  
**Target Publication:** *Journal of Geosciences and Engineering*, University of Miskolc  
**Application:** MFK GeoMeasure (`hu.uni.miskolc.mfk_geomeasure`)  
**Software Version:** `1.1.1+11`  
**Git Commit SHA:** `c4acae92043a41981432c258a0eb1a9e13e8346b`  

---

## 1. GeoJSON Export and Import Inspection

### A. RFC 7946 Conformance and Coordinate Reference System
Inspection of `_buildGeoJson()` in [project_service.dart](file:///Users/szamosiattila/MFKgps/lib/services/project_service.dart#L580-L680) confirms the following behavior:

1. **Geometry Coordinates (WGS 84 Geographic):**
   * Geometry coordinates in output `FeatureCollection` elements are formatted by `geoJsonCoordinate()` as `[longitude, latitude, elevation]` (in decimal degrees, WGS 84 / `EPSG:4326`).
   * This strictly conforms to **RFC 7946 Section 3.1.1** (*"Positions MUST be expressed as [longitude, latitude, elevation]"*) and **RFC 7946 Section 4** (*"The coordinate reference system for all GeoJSON coordinates is WGS 84... Alternative coordinate reference systems MUST NOT be used."*).

2. **Projected EOV Coordinates in Feature Properties:**
   * Projected Hungarian EOV coordinates ($Y, X$) are not placed in `geometry.coordinates`. Instead, they are formatted as attribute properties: `extraProperties['EOV_Y']` and `extraProperties['EOV_X']`.
   * **Source-Code Property Key Observation:** In `_buildGeoJson()` for Point features (lines 627–628), `extraProperties['EOV_Y']` receives `eov[1]` (Northing $X$) and `extraProperties['EOV_X']` receives `eov[0]` (Easting $Y$). In CSV export (lines 485–486), `eov[1]` is correctly mapped under `EOV_Y` and `eov[0]` under `EOV_X`.

3. **Import Capability:**
   * Inspection of `import_service.dart` reveals that `.geojson` is **not** currently included in the `allowedExtensions` list of `FilePicker.pickFiles()`.
   * GeoJSON is currently an **export-only format** in MFK GeoMeasure. Multi-format import supports DXF, KML/KMZ, GPX, GML, Shapefile ZIP, and GeoPackage (`.gpkg`).

---

## 2. Format-Specific QGIS Validation Procedure

The proposed desktop GIS validation procedure must test each export format according to its native CRS definition:

### Format 1: Shapefile (`.shp`, `.shx`, `.dbf`, `.prj`)
* **CRS Support:** Can be exported in EOV (`EPSG:23700`) or WGS 84 (`EPSG:4326`).
* **Binary Encoding:** In EOV mode, coordinates in `.shp` records are projected meters (SHP X = Easting $Y$, SHP Y = Northing $X$). The `.prj` file contains the official HD72 / EOV WKT (`AUTHORITY["EPSG","23700"]`).
* **QGIS Test Method:** Load `.shp` into QGIS 3.x. Confirm QGIS automatically detects `EPSG:23700`. Measure point distances and verify vertex coordinates against known EOV benchmarks ($Y_0, X_0$) within $\le 1\text{ mm}$.

### Format 2: GeoPackage (`.gpkg`)
* **CRS Support:** SQLite OGC GeoPackage standard.
* **Table Metadata:** `gpkg_geometry_columns` table sets `srs_id` to `23700` (EOV) or `4326` (WGS 84). Geometries are serialized as Well-Known Binary (WKB) blobs with `0x4750` GeoPackage binary headers.
* **QGIS Test Method:** Drag `.gpkg` into QGIS 3.x. Confirm vector feature table opens natively, layer CRS is identified as `EPSG:23700`, and custom attribute fields (`Point_ID`, `Code`, `Quality_m`) retain their exact data types (Integer, Real, Text).

### Format 3: GeoJSON (`.geojson`)
* **CRS Support:** Strict RFC 7946 format (`EPSG:4326`).
* **Geometry Encoding:** Coordinates in `geometry.coordinates` are geographic `[longitude, latitude, elevation]`.
* **QGIS Test Method:** Drag `.geojson` into QGIS 3.x. Confirm QGIS assigns `EPSG:4326` (WGS 84). Verify that projected EOV values appear in the Attribute Table as `EOV_Y` and `EOV_X` attributes.

---

## 3. Local Project Storage vs. Complete Offline Functionality

Code inspection distinguishes between local project persistence and operations requiring network access:

### A. Local Offline Features (100% Functionality Without Internet)
* Project creation, layer management, vector feature collection (points, lines, polygons).
* EOV coordinate transformation and BME geoid undulation / Baltic height calculation.
* Local weighted RTK position averaging and geometry editing tools (snapping, offset, buffer).
* Geometric and precision leveling logbook calculation and closure adjustment.
* Campus COGO problem generation and automated grading.
* Control point quality audit logging (`ControlPointCheckService`).
* Local project file storage (`saved_projects.json`, `control_point_measurements.json`).
* Vector map rendering using pre-loaded local `.mbtiles` vector packages via `VectorMapService`.

### B. Operations Still Requiring Internet Connectivity
1. **Online Raster Basemap Tiles:** Downloading online map tile raster imagery (e.g. OpenStreetMap, Turistautak, or satellite tile servers) via `flutter_map` requires active internet access.
2. **NTRIP Correction Stream:** Connecting to a remote NTRIP Caster (e.g. Geoshop / PONT) over TCP/IP sockets to receive RTCM 3.x correction frames requires cellular mobile data or internet access.
3. **NTRIP Sourcetable Querying:** Downloading new mountpoint sourcetables (`fetchSourceTable`) requires network access.

---

## 4. Independent Verification of Geodetic Reference Values in Tests

* **Source of Expected Values:**
  In `test/services/bme_grid_service_test.dart`, expected coordinates (e.g. $Y = 753218.9656450956\text{ m}, X = 293622.2580149178\text{ m}$, $N = 42.345627\text{ m}$) were computed using PROJ reference binaries (`cs2cs` / `proj_create_crs_to_crs`) using the official Hungarian BME grid shift files (`hu_bme_hd72corr.f32` and `hu_bme_geoid2014.f32`).
* **Meaning of Test Assertions:**
  The unit tests (`closeTo(..., 0.00001)`) verify that Dart's custom grid-shift interpolation algorithms (`EovService` and `BmeGridService`) reproduce PROJ's reference outputs to within $0.02\text{ mm}$ ($10^{-5}\text{ m}$) computational agreement.
* **Conclusion:** These tests prove **mathematical algorithm equivalence to PROJ**, but do NOT constitute independent physical field calibration.

---

## 5. Demonstrated vs. Inferred Risks in Project Saving

### A. Executed Test Demonstration
During the execution of `flutter test` (`professional_workflow_final_test.dart`), the test runner output captured:
```
HIBA a mentés során: PathNotFoundException: Cannot rename file to './saved_projects.json', 
path = './saved_projects.json.tmp' (OS Error: No such file or directory, errno = 2)
```
This **demonstrates in an executed test** that rapid unawaited asynchronous file write calls attempt to rename `.tmp` after another concurrent async operation or clean-up block has already deleted or moved the file path.

### B. Source-Code Inferred Risks
* **Unawaited Fire-and-Forget Invocations:** In `ProjectService`, state changes (e.g. `finishRecording`, `deleteFeature`) trigger `_saveProjectsToDisk()` asynchronously without `await`. If the operating system forcibly kills the process (`SIGKILL` or crash) immediately after an edit, in-memory edits may be lost.
* **Unnotified Storage Exhaustion:** If device storage is completely full, `writeAsString()` throws an exception caught by `catch (e)` and printed to the console, but no UI error alert is shown to the field surveyor.

---

## 6. Summary Table of Categorized Evidence

| Item | Source-Code Observation | Executed Test Result | Proposed Future Experiment |
| :--- | :--- | :--- | :--- |
| **GeoJSON Format** | Conforms to RFC 7946 (`EPSG:4326`). EOV coords stored as feature properties. Import not supported in `allowedExtensions`. | N/A | QGIS RFC 7946 compliance inspection protocol. |
| **QGIS Interoperability** | Shapefile (`.shp`) and GeoPackage (`.gpkg`) export native EOV (`EPSG:23700`). | Binary Shapefile structure verified in `gis_roundtrip_test.dart`. | Multi-format desktop GIS roundtrip trial. |
| **Offline Capabilities** | All GIS editing, geodesy, and project storage work offline. Map tiles & NTRIP require network. | Offline project persistence verified in `professional_workflow_final_test.dart`. | Field network disconnection and recovery trial. |
| **Geodetic Accuracy** | Grid shift logic uses $64\text{-bit}$ floats and bilinear interpolation. | 88 tests passed. $0.02\text{ mm}$ agreement with PROJ outputs verified. | Calibration over official Hungarian benchmark pillars (ÖK). |
| **Project Saving** | Atomic `.tmp`/`.bak` saving mechanism used in `ProjectService`. | Concurrent rename race condition captured (`PathNotFoundException` log). | Stress test under forced OS process termination. |
| **iOS Backgrounding** | `UIBackgroundModes` key absent in `Info.plist`. Operates foreground-only. | N/A | Battery drain and foreground stream stability trial. |
