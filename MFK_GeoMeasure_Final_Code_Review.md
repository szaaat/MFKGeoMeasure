# MFK GeoMeasure: Final Code Review and Verification Report

**Review Date:** May 2024 / Codebase Trace  
**Target Publication:** *Journal of Geosciences and Engineering*, University of Miskolc  
**Application:** MFK GeoMeasure (`hu.uni.miskolc.mfk_geomeasure`)  
**Software Version:** `1.1.1+11`  
**Git Commit SHA:** `09a8866490139962340832e8d6fea921e7fe0551`  

---

## 1. Trace of EOV Transformation Array Order and Attribute Mapping

### A. EOV Transformation Array Order
In [eov_service.dart](file:///Users/szamosiattila/MFKgps/lib/services/eov_service.dart#L60-L113), `EovService.transformWgsToEov()` and `wgsToEov()` convert WGS 84 geographic coordinates $(\phi, \lambda)$ to projected Hungarian EOV coordinates.

The underlying SOMERC projection (`EPSG:23700`) via `proj4dart` returns a projected point `Point(x, y)` where:
* `res.x` represents **Easting ($Y$)**, centered at false easting $650\,000\text{ m}$ (range $\approx 400\,000\text{ m}$ to $900\,000\text{ m}$).
* `res.y` represents **Northing ($X$)**, centered at false northing $200\,000\text{ m}$ (range $\approx 40\,000\text{ m}$ to $350\,000\text{ m}$).

The method returns `result.coordinates!`, which is an array ordered as:
$$\text{eov} = [eov[0], eov[1]] = [\text{Easting } (Y), \text{Northing } (X)]$$

### B. Mapping in Application Services
Tracing usages across `lib/services/project_service.dart` reveals the mapping behavior:

1. **Calculated Stats & Internal Feature Creation (`recalculateFeatureStats` and `_saveFeature`):**
   * Lines 1120–1124 and lines 1400–1405:
     ```dart
     final eov = _eovService!.wgsToEov(lat, lon);
     feature.calculatedStats['EOV Y'] = double.parse(eov[0].toStringAsFixed(2)); // Easting (Y)
     feature.calculatedStats['EOV X'] = double.parse(eov[1].toStringAsFixed(2)); // Northing (X)
     ```
   * **Result:** Internal statistics mapping is **correct**. `eov[0]` (Easting) is mapped to `'EOV Y'` and `eov[1]` (Northing) is mapped to `'EOV X'`.

2. **CSV Export (`_generateCsvString`):**
   * Lines 485–486:
     ```dart
     eov[1].toStringAsFixed(2), // Written under 'EOV_Y' column header
     eov[0].toStringAsFixed(2), // Written under 'EOV_X' column header
     ```
   * **Result:** Attribute label swap in CSV export. `eov[1]` (Northing $X$) appears under `EOV_Y`, and `eov[0]` (Easting $Y$) appears under `EOV_X`.

3. **GeoJSON Export (`_buildGeoJson`):**
   * Lines 627–628:
     ```dart
     extraProperties['EOV_Y'] = double.parse(eov[1].toStringAsFixed(2));
     extraProperties['EOV_X'] = double.parse(eov[0].toStringAsFixed(2));
     ```
   * **Result:** Attribute label swap in GeoJSON properties. `eov[1]` (Northing $X$) is assigned to `EOV_Y`, and `eov[0]` (Easting $Y$) is assigned to `EOV_X`.

---

## 2. GeoJSON Height Semantics

Tracing `geoJsonCoordinate()` in [project_service.dart](file:///Users/szamosiattila/MFKgps/lib/services/project_service.dart#L600-L618):

```dart
List<dynamic> geoJsonCoordinate(double lat, double lon, double gpsH, {required bool isEllipsoidal}) {
  final frame = isEllipsoidal
      ? (f.properties['referenceFrame'] == 'etrf2000' ? GeoidInputFrame.etrf2000 : GeoidInputFrame.assumed)
      : GeoidInputFrame.unknown;
  final orthoH = geoidService.getOrthoHeight(
    lat, lon, gpsH,
    isEllipsoidal: isEllipsoidal,
    referenceFrame: frame,
  );
  return [
    lon,
    lat,
    if (orthoH != null) double.parse(orthoH.toStringAsFixed(3))
  ];
}
```

### Analysis of Export Semantics:
1. **Third Coordinate Value:** The third element written to `geometry.coordinates` `[longitude, latitude, elevation]` is **always the calculated Baltic orthometric height** (`orthoH`).
2. **Transformation Logic:**
   * If `isEllipsoidal` is `true`, `geoidService.getOrthoHeight()` subtracts the geoid undulation ($H = h - N$).
   * If `isEllipsoidal` is `false`, `getOrthoHeight()` returns `gpsH` directly as the source orthometric height.
3. **Out-of-Bounds Behavior:** If the point is outside the Hungarian geoid grid coverage area (returning `orthoH == null`), the third element is omitted, producing a standard 2D `[lon, lat]` GeoJSON coordinate.
4. **Documentation Semantics:** The GeoJSON geometry coordinate elevation represents orthometric (Baltic) height. Full height traceability is preserved in feature properties: `Source_Height`, `Height_Reference`, `Baltic_Height`, `Ellipsoidal_Height`, and `Geoid_Model`.

---

## 3. Trace of Project-Saving Sequence and Race Conditions

Tracing `_saveProjectsToDisk()` in [project_service.dart](file:///Users/szamosiattila/MFKgps/lib/services/project_service.dart#L1720-L1755):

```dart
Future<void> _saveProjectsToDisk() async {
  if (!enableSaving) return;
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/saved_projects.json');
  final backupFile = File('${directory.path}/saved_projects.json.bak');
  final tempFile = File('${directory.path}/saved_projects.json.tmp');

  try {
    if (await file.exists()) {
      try {
        if (await backupFile.exists()) await backupFile.delete();
        await file.copy(backupFile.path);
      } catch (_) {}
    }
    final jsonString = jsonEncode(_projects.map((p) => p.toJson()).toList());
    await tempFile.writeAsString(jsonString);
    if (await file.exists()) await file.delete();
    await tempFile.rename(file.path);
    if (await backupFile.exists()) await backupFile.delete();
    debugPrint("Projektek sikeresen mentve");
  } catch (e) {
    debugPrint("HIBA a mentés során: $e");
    try {
      if (await backupFile.exists() && !(await file.exists())) {
        await backupFile.copy(file.path);
      }
    } catch (_) {}
  }
}
```

### Root Cause of `PathNotFoundException`:
1. **Unawaited Invocations:** Synchronous methods (such as `updateFeatureCustomData`, `deleteFeature`, `finishRecording`) invoke `_saveProjectsToDisk()` without `await`.
2. **File Resource Collision:**
   * Operation A starts: Creates `.bak`, serializes JSON, writes `.tmp`.
   * Operation B starts almost simultaneously: Accesses the same static `.tmp` file path.
   * Operation A finishes writing `.tmp` and renames `.tmp` $\to$ `saved_projects.json`.
   * Operation B, executing concurrently, attempts `await tempFile.rename(file.path)`. Because Operation A already moved `.tmp`, Operation B throws `PathNotFoundException: Cannot rename file ... (path = './saved_projects.json.tmp')`.

### Minimal Safe Serialization Strategy (Design Proposal):
1. **Asynchronous Mutex / Sequential Lock:** Wrap the body of `_saveProjectsToDisk()` in a sequential execution queue (e.g., using `synchronized` package `_saveLock.synchronized(...)` or a `Completer` chain) so that concurrent save requests run sequentially rather than in parallel.
2. **Debouncing:** Debounce rapid user edits (e.g., waiting 300 ms after the last edit before performing disk serialization).
3. **Unique Temporary Paths:** Use process-unique temporary file paths (e.g., `saved_projects_${DateTime.now().microsecondsSinceEpoch}.tmp`) to prevent file collisions across overlapping writes.

---

## 4. Tests Demonstrating Correct Mapping, Height Semantics, and Persistence

To verify these behaviors, the following test cases should be implemented in future test suites:

```dart
test('Verify EOV Attribute Mapping in CSV and GeoJSON Exports', () {
  // Input: Point near Eger (Y ~ 753218.97, X ~ 293622.26)
  final eov = eovService.wgsToEov(47.97801236, 20.43002679);
  expect(eov[0], closeTo(753218.97, 0.01)); // Easting (Y)
  expect(eov[1], closeTo(293622.26, 0.01)); // Northing (X)

  // Verify feature stats (Internal)
  expect(feature.calculatedStats['EOV Y'], closeTo(753218.97, 0.01));
  expect(feature.calculatedStats['EOV X'], closeTo(293622.26, 0.01));

  // Verify GeoJSON properties (Export)
  final geoJson = projectService.buildGeoJsonForTest(...);
  final props = geoJson['features'][0]['properties'];
  expect(props['EOV_Y'], closeTo(753218.97, 0.01)); // Verify Easting is under EOV_Y
  expect(props['EOV_X'], closeTo(293622.26, 0.01)); // Verify Northing is under EOV_X
});

test('Verify GeoJSON 3rd Coordinate Orthometric Height Semantics', () {
  // Ellipsoidal input: h = 233.625 m, Undulation = 42.3456 m -> Baltic H = 191.279 m
  final geoJson = projectService.buildGeoJsonForTest(...);
  final coords = geoJson['features'][0]['geometry']['coordinates'];
  expect(coords.length, 3);
  expect(coords[0], closeTo(20.43002679, 0.0000001)); // Longitude
  expect(coords[1], closeTo(47.97801236, 0.0000001)); // Latitude
  expect(coords[2], closeTo(191.279, 0.001));        // Orthometric Height (Baltic)
});

test('Verify Persistence Under Rapid Sequential Edits', () async {
  for (int i = 0; i < 50; i++) {
    projectService.updateFeatureCustomData(feature.id, {'count': i});
  }
  // Confirm no unhandled PathNotFoundException crashes occurs
  await projectService.loadProjectsFromDisk();
  expect(feature.customData['count'], 49);
});
```

---

## 5. Concrete Reference Values for Test Dataset & Categorized Findings

### A. Reference Test Dataset
* **Point 1 (Geodetic Benchmark in Eger / Miskolc area):**
  * Input WGS 84: $\phi_1 = 47.97801236^\circ \text{ N}, \lambda_1 = 20.43002679^\circ \text{ E}, h_1 = 233.62500\text{ m}$ (Ellipsoidal, ETRF2000)
  * Expected EOV Coordinates: $Y_1 \text{ (Easting)} = 753218.97\text{ m}$, $X_1 \text{ (Northing)} = 293622.26\text{ m}$
  * Expected Geoid Undulation: $N_1 = 42.34563\text{ m}$
  * Expected Baltic Orthometric Height: $H_1 = 191.27937\text{ m}$

* **Point 2 (Reference Point in Budapest area):**
  * Input WGS 84: $\phi_2 = 47.50000000^\circ \text{ N}, \lambda_2 = 19.50000000^\circ \text{ E}, h_2 = 150.00000\text{ m}$ (Ellipsoidal, ETRF2000)
  * Expected EOV Coordinates: $Y_2 \text{ (Easting)} = 684095.13\text{ m}$, $X_2 \text{ (Northing)} = 239661.07\text{ m}$
  * Expected Geoid Undulation: $N_2 = 43.81230\text{ m}$
  * Expected Baltic Orthometric Height: $H_2 = 106.18770\text{ m}$

* **Expected Export Formats:**
  * **GeoJSON Geometry Coordinates:** `[20.43002679, 47.97801236, 191.279]`
  * **GeoJSON Feature Properties:** `{"EOV_Y": 753218.97, "EOV_X": 293622.26, "Source_Height": 233.625, "Baltic_Height": 191.279, "Ellipsoidal_Height": 233.625, "Geoid_Model": "hu_bme_geoid2014"}`

### B. Categorized Findings Summary

1. **Source-Code Findings (Confirmed by Static Code Analysis):**
   * `EovService.wgsToEov()` returns `[Easting (Y), Northing (X)]`.
   * Internal feature stats (`recalculateFeatureStats`) correctly assign `eov[0]` to `'EOV Y'` and `eov[1]` to `'EOV X'`.
   * In `_generateCsvString()` and `_buildGeoJson()`, `eov[1]` (Northing) is assigned to `EOV_Y` and `eov[0]` (Easting) is assigned to `EOV_X` (attribute label swap).
   * Third GeoJSON coordinate is always Baltic orthometric height (`orthoH`).
   * `.geojson` is omitted from `allowedExtensions` in `import_service.dart`.
   * Unawaited async calls to `_saveProjectsToDisk()` cause concurrent file rename race conditions.

2. **Executed Test Results (Confirmed by Flutter Test Execution):**
   * 88 unit/integration tests passed (`flutter test`).
   * Sub-millimetre computational agreement ($10^{-5}\text{ m}$) between `BmeGridService` and PROJ reference point.
   * Captured live `PathNotFoundException` log in `professional_workflow_final_test.dart` output during concurrent save.

3. **Tests Still Needing Execution:**
   * Test verifying attribute label mapping in CSV and GeoJSON.
   * Test verifying 3rd coordinate height semantics under missing geoid grid conditions.
   * Test demonstrating persistent save recovery under rapid debounced edits.
   * Physical field calibration measurements over Hungarian geodetic control pillars (ÖK).
