// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MFK GeoMeasure';

  @override
  String get mapScreenTitle => 'Map View';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get changeLanguage => 'Change Language';

  @override
  String get startRecording => 'Start Recording';

  @override
  String get stopRecording => 'Stop Recording';

  @override
  String gpsAccuracy(String accuracy) {
    return 'Accuracy: $accuracy m';
  }

  @override
  String currentAltitude(String alt) {
    return 'Height (Ortho): $alt m';
  }

  @override
  String get slogan => 'Geography is the whole world!';

  @override
  String get startMap => 'Start Map';

  @override
  String get startLearning => 'Geodetic Exercises';

  @override
  String get uniName =>
      'University of Miskolc\nFaculty of Earth Science and Engineering';

  @override
  String get institute => 'Institute of Geography and Geoinformatics';

  @override
  String get noProject => 'No Project';

  @override
  String get noLayer => 'No Layer';

  @override
  String get offlineMaps => 'Offline Maps';

  @override
  String get manageDownloads => 'Manage downloaded areas.';

  @override
  String get deleteStorage => 'CLEAR STORAGE';

  @override
  String get deleteConfirmTitle => 'Are you sure?';

  @override
  String get deleteConfirmBody =>
      'This will delete all offline maps from the phone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get download => 'Download';

  @override
  String get newDownload => 'NEW DOWNLOAD';

  @override
  String get saveArea => 'Save Offline Area';

  @override
  String get selectDetail => 'Select detail level!';

  @override
  String get zoomLevels => 'Zoom levels';

  @override
  String get tileCount => 'Tile count';

  @override
  String get attentionHuge =>
      'WARNING: This is huge (>200k)! Expect GBs of data and hours of download. Wi-Fi only!';

  @override
  String get attentionLarge =>
      'This generates a lot of data (>50k). Download may take minutes.';

  @override
  String get braveDownload => 'I AM BRAVE (DOWNLOAD)';

  @override
  String get startDownload => 'START DOWNLOAD';

  @override
  String get downloading => 'Downloading...';

  @override
  String get dontClose => 'Please DO NOT close the app!';

  @override
  String get keepScreenOn => 'Keep the screen on.';

  @override
  String get abort => 'Abort';

  @override
  String get downloadDone => 'Download finished!';

  @override
  String get downloadAborted => 'Download aborted.';

  @override
  String get storageCleared => 'Storage cleared!';

  @override
  String get error => 'Error';

  @override
  String get noGps => 'No GPS signal!';

  @override
  String get save => 'Save';

  @override
  String get name => 'Name';

  @override
  String get description => 'Description';

  @override
  String get done => 'DONE';

  @override
  String get projectsLayers => 'Projects and Layers';

  @override
  String get newElement => 'New Item';

  @override
  String get createWhat => 'What do you want to create';

  @override
  String get newProject => 'NEW PROJECT';

  @override
  String get newLayer => 'NEW LAYER';

  @override
  String get activeProject => 'Active project';

  @override
  String get export => 'Export';

  @override
  String get mapType => 'Map Type';

  @override
  String get satellite => 'Satellite (Google)';

  @override
  String get hiking => 'Hiking Trails (Hu)';

  @override
  String get osm => 'OpenStreetMap';

  @override
  String get searchingGps => 'Searching for GPS signal...';

  @override
  String get point => 'Point';

  @override
  String get line => 'Line';

  @override
  String get polygon => 'Polygon';

  @override
  String get saveItem => 'Save';

  @override
  String get searchCoord => 'Coordinate Search';

  @override
  String get invalidCoord => 'Invalid format! WGS84 or EOV required.';

  @override
  String get geodeticSettings => 'Geodetic Settings';

  @override
  String get antennaHeight => 'Antenna height (m)';

  @override
  String get requiredAccuracy => 'Required accuracy (m)';

  @override
  String get fastRecord => 'Fast record';

  @override
  String get fastRecordDesc => 'Instant save with current position';

  @override
  String get avgRecord => 'Averaged measurement (15s)';

  @override
  String get avgRecordDesc => 'More accurate position with static measurement';

  @override
  String get measuringInProgress => 'Measurement in progress...';

  @override
  String get keepStill => 'Please keep the device still!';

  @override
  String get stakeoutCheck => 'Check measurement on point';

  @override
  String get ant => 'Ant';

  @override
  String get searched => 'Searched';

  @override
  String get recordedFromSearch => 'Recorded from search';

  @override
  String get pointSaved => 'Point saved to project!';

  @override
  String get searchAndSave => 'Search and Save';

  @override
  String get target => 'Target';

  @override
  String get close => 'Close';

  @override
  String get stakeout => 'Stakeout';

  @override
  String get bestAcc => 'Best accuracy:';

  @override
  String get avgAcc => 'Average accuracy:';

  @override
  String get satellites => 'Satellites';

  @override
  String get ppkStartTitle => 'Start PPK Logging';

  @override
  String get ppkNameLabel => 'Session name';

  @override
  String get ppkNotesLabel => 'Notes';

  @override
  String get ppkStartBtn => 'START';

  @override
  String get resection => 'Resection';

  @override
  String get area => 'Area Calculation';

  @override
  String get inverse => 'Inverse Task';

  @override
  String get angularIntersection => 'Angular Intersection';

  @override
  String get distanceIntersection => 'Distance Intersection';

  @override
  String get result => 'RESULT';

  @override
  String get derivation => 'Mathematical derivation';

  @override
  String get derivationShow => 'Show detailed calculation (derivation)';

  @override
  String get derivationHide => 'Hide derivation';

  @override
  String get campusMiskolc => 'Miskolc (ME MFK)';

  @override
  String get campusSzekesfehervar => 'Fehervar (ÓE AMK)';

  @override
  String get selectLocation => 'Select location (Campus):';

  @override
  String get taskGoal => 'Task goal:';

  @override
  String get taskSteps => 'Solution steps:';

  @override
  String get check => 'CHECK';

  @override
  String get excellent => 'Excellent';

  @override
  String get good => 'Good';

  @override
  String get retry => 'RETRY';

  @override
  String get whatToCalculate => 'What do you want to calculate?';

  @override
  String get inverseDesc => 'Two points → distance';

  @override
  String get angularDesc => 'Two directions → point';

  @override
  String get distanceDesc => 'Two distances → point';

  @override
  String get resectionDesc => 'Three points → station';

  @override
  String get areaDesc => 'Points → area';

  @override
  String get noTypeSelected => 'No calculation type selected';

  @override
  String selectPointTarget(String point) {
    return 'Select: $point';
  }

  @override
  String get distanceLabel => 'Distance';

  @override
  String get bearingLabel => 'Bearing (WCB)';

  @override
  String get resultY => 'Result Y';

  @override
  String get resultX => 'Result X';

  @override
  String get intersection1Y => 'Intersection 1 Y';

  @override
  String get intersection1X => 'Intersection 1 X';

  @override
  String get intersection2Y => 'Intersection 2 Y';

  @override
  String get intersection2X => 'Intersection 2 X';

  @override
  String get areaLabel => 'Area';

  @override
  String get radius1 => 'Radius 1 (m)';

  @override
  String get radius2 => 'Radius 2 (m)';

  @override
  String get bearing1 => 'Bearing 1 (WCB °)';

  @override
  String get bearing2 => 'Bearing 2 (WCB °)';

  @override
  String get measuredBearingP1 => 'Measured bearing to P1 (°)';

  @override
  String get measuredBearingP2 => 'Measured bearing to P2 (°)';

  @override
  String get measuredBearingP3 => 'Measured bearing to P3 (°)';

  @override
  String get areaPoints => 'Area points';

  @override
  String get add => 'Add';

  @override
  String get newPoint => 'New point';

  @override
  String get noPointsAdded => 'No points added.';

  @override
  String sourceLabel(String src) {
    return 'Source: $src';
  }

  @override
  String selectSourceFor(String label) {
    return 'Select source for $label';
  }

  @override
  String get pickFromMap => 'Select from map';

  @override
  String get pickFromMapDesc => 'Tap desired location on map';

  @override
  String get currentGnss => 'Current GNSS position';

  @override
  String get currentGnssDesc => 'Read phone GPS coordinates';

  @override
  String get pickFromProject => 'Select from project';

  @override
  String get pickFromProjectDesc => 'Load previously saved points';

  @override
  String get fetchingGps => 'Fetching GPS position...';

  @override
  String get noPointsInActiveLayers => 'No points on active layers!';

  @override
  String get selectPointTitle => 'Select Point';

  @override
  String get waitingForInput => 'Waiting for input data...';

  @override
  String get hideKeyboard => 'Hide keyboard';

  @override
  String get mathDerivation => 'Mathematical derivation';

  @override
  String get sourceMap => 'Map';

  @override
  String get sourceGnss => 'GNSS (GPS)';

  @override
  String get sourceProject => 'Project';

  @override
  String get selectBtn => 'Select';

  @override
  String quadrantName(String quadrant) {
    return '$quadrant quadrant';
  }

  @override
  String get gisImportTooltip => 'GIS Import (DXF, KML, GPX)';

  @override
  String itemsImported(int count) {
    return '$count items imported!';
  }

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get templateLabel => 'Data template';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get skyplotTitle => 'GNSS Skyplot';

  @override
  String get skyplotAndroidOnly =>
      'Skyplot is currently only available on Android devices.';

  @override
  String get searchingSatellites => 'Searching for satellite data...';

  @override
  String get satUsedLegend => 'Solid circle: Used in fix';

  @override
  String get loadVectorMbtiles => 'Load Vector MBTiles';

  @override
  String get notLoaded => 'Not loaded';

  @override
  String get vectorMode => 'Vector mode';

  @override
  String get invalidSavedCoord => 'Error: Invalid saved coordinate!';

  @override
  String get gpsErrorPerm => 'GPS error: Please enable location in settings!';

  @override
  String measurementTime(String time) {
    return 'Measurement $time';
  }

  @override
  String get taskSolveTitle => 'Solve Task';

  @override
  String get givenData => 'GIVEN DATA:';

  @override
  String get calculatedResults => 'CALCULATED RESULTS:';

  @override
  String get fillAllFields => 'Please fill in all fields!';

  @override
  String get differences => 'Differences (Measured - True):';

  @override
  String get gradeError => 'Error';

  @override
  String get gradeExcellent => 'Excellent';

  @override
  String get gradeGood => 'Good';

  @override
  String get msgError => 'Calculation inaccurate. Check formulas!';

  @override
  String get msgExcellent => 'Congratulations! Engineering level precision.';

  @override
  String get msgGood =>
      'Close, but there is a slight rounding or calculation error.';

  @override
  String locationLabel(String campus) {
    return 'Location: $campus';
  }

  @override
  String get templateGeneral => 'General';

  @override
  String get templateWaterManhole => 'Water Manhole';

  @override
  String get templateBoundaryStone => 'Boundary Stone';

  @override
  String get templateUtilityPole => 'Utility Pole';

  @override
  String get fieldMaterial => 'Material';

  @override
  String get fieldDiameter => 'Diameter (mm)';

  @override
  String get fieldDepth => 'Depth (m)';

  @override
  String get fieldCondition => 'Cover condition';

  @override
  String get fieldType => 'Type';

  @override
  String get fieldStatus => 'Status';

  @override
  String get fieldVoltage => 'Voltage';

  @override
  String get fieldHasLamp => 'Has lamp?';

  @override
  String get optConcrete => 'Concrete';

  @override
  String get optPlastic => 'Plastic';

  @override
  String get optBrick => 'Brick';

  @override
  String get optCastIron => 'Cast Iron';

  @override
  String get optGood => 'Good';

  @override
  String get optDamaged => 'Damaged';

  @override
  String get optMissing => 'Missing';

  @override
  String get optConcreteStone => 'Concrete Stone';

  @override
  String get optGranite => 'Granite';

  @override
  String get optIronPipe => 'Iron Pipe';

  @override
  String get optPlasticPeg => 'Plastic Peg';

  @override
  String get optIntact => 'Intact';

  @override
  String get optTilted => 'Tilted';

  @override
  String get optDisplaced => 'Displaced';

  @override
  String get optUncertain => 'Uncertain';

  @override
  String get optWood => 'Wood';

  @override
  String get optIron => 'Iron';

  @override
  String get optYes => 'Yes';

  @override
  String get optNo => 'No';

  @override
  String get addCustomField => 'Add Custom Field';

  @override
  String get newFieldName => 'New field name';

  @override
  String get customFields => 'Custom Fields';

  @override
  String get addColumn => 'Add Column';

  @override
  String get gnssSource => 'GNSS Source';

  @override
  String get internalGps => 'Internal GPS';

  @override
  String get externalGnss => 'External GNSS';

  @override
  String get bluetoothClassic => 'Bluetooth Classic';

  @override
  String get bluetoothBle => 'Bluetooth Low Energy';

  @override
  String get usbSerial => 'USB Serial';

  @override
  String get scanningDevices => 'Scanning for devices...';

  @override
  String get noDevicesFound => 'No devices found';

  @override
  String deviceAddress(String address) {
    return 'Address: $address';
  }

  @override
  String get fixStatus => 'Fix Status';

  @override
  String get rtkStatus => 'RTK Status';

  @override
  String correctionAge(String age) {
    return 'Correction Age: $age s';
  }

  @override
  String get ntripSettings => 'NTRIP Settings';

  @override
  String get fetchMountpoints => 'Fetch Mountpoints';

  @override
  String get selectMountpoint => 'Select Mountpoint';

  @override
  String get noMountpointsFound => 'No mountpoints found';

  @override
  String get profiles => 'Profiles';

  @override
  String get addProfile => 'Add Profile';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get deleteProfile => 'Delete Profile';

  @override
  String get profileName => 'Profile Name';

  @override
  String get bitrate => 'Bitrate';

  @override
  String get totalData => 'Total Data';

  @override
  String get requireStableFix => 'Require stable RTK FIX';

  @override
  String get stabilityThreshold => 'Stability threshold (s)';

  @override
  String get allowFloatSave => 'Allow Float Save';

  @override
  String get allowFloatSaveSub =>
      'Off: Point saving requires RTK FIX. On: Point saving allowed in RTK Float state.';

  @override
  String get lastGgaSent => 'Last GGA sent';

  @override
  String get lastRtcmReceived => 'Last correction received';

  @override
  String get reconnecting => 'Reconnecting...';

  @override
  String waitingStableFix(String seconds) {
    return 'Waiting for stable RTK FIX (${seconds}s)...';
  }

  @override
  String get rtkStatusWaiting => 'Stable FIX required';

  @override
  String get rtkStatusMeasuring => 'Measuring stability...';

  @override
  String get rtkStatusNoFix => 'GNSS FIX required';

  @override
  String get ntripProvider => 'NTRIP Provider';

  @override
  String get providerCentipede => 'Centipede-RTK';

  @override
  String get providerGnssNet => 'GNSSnet.hu';

  @override
  String get providerCustom => 'Custom / Manual';

  @override
  String get mountpointNear => 'Nearest (NEAR)';

  @override
  String get mountpointNear4 => 'Nearest (NEAR4)';

  @override
  String get battery => 'Battery';

  @override
  String get firmwareVersion => 'Firmware Version';

  @override
  String get positionSource => 'Position Source';

  @override
  String get insStatus => 'INS Status';

  @override
  String get rtkStatusLabel => 'RTK Status';

  @override
  String get insAlignment => 'INS ALIGNMENT';

  @override
  String get insState => 'INS State';

  @override
  String get m21Position => 'M21 Position';

  @override
  String get noData => 'No data';

  @override
  String get age => 'age:';

  @override
  String get packets => 'Packets:';

  @override
  String get bytes => 'Bytes:';

  @override
  String get compass => 'Compass';

  @override
  String get rtcmRefresh => 'Refresh RTCM';

  @override
  String get m21Configure => 'Configure M21';

  @override
  String get saveM21Config => 'Save M21 Config';

  @override
  String receiverResponse(String msg) {
    return 'Receiver response: $msg';
  }

  @override
  String get rawDiagnosticsLogger => 'RAW DIAGNOSTICS & LOGGER';

  @override
  String get firmwareUpdateOta => 'FIRMWARE UPDATE (OTA)';

  @override
  String get noMountpoint => 'no mountpoint';

  @override
  String get connect => 'Connect';

  @override
  String get correctionAgeLabel => 'Correction Age';

  @override
  String get never => 'Never';

  @override
  String get connectedWait => 'Connected (Wait)';

  @override
  String get dataActive => 'Data Active';

  @override
  String get connecting => 'Connecting...';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get notConfigured => 'Not Configured';

  @override
  String get passwordLeaveEmpty => 'Password (leave empty if unchanged)';

  @override
  String get ggaInterval => 'GGA Interval (s)';

  @override
  String get searching => 'Searching...';

  @override
  String get controlPointCheckTitle => 'Control Point Check';

  @override
  String get noPointLayerImportShp =>
      'No point layer. Please import a control point SHP into the project.';

  @override
  String get unsupportedCrsMsg =>
      'Unsupported or unknown CRS. EOV EPSG:23700 or WGS84 EPSG:4326 is required.';

  @override
  String get measurement => 'Measurement: ';

  @override
  String get startMeasurement => 'START MEASUREMENT';

  @override
  String get connectToMfkRtk => 'Connect to MFKRTK receiver.';

  @override
  String get nonFixedWarning =>
      'Non-FIXED epochs will be kept, but marked with a warning.';

  @override
  String get refLayerAndPoint => 'Reference layer and point';

  @override
  String get pointLayer => 'Point layer';

  @override
  String get controlPoint => 'Control Point';

  @override
  String get eovFromAttributes => 'EOV E/N from attribute fields';

  @override
  String get eovFromAttributesSub =>
      'Off: projects geometry from WGS84 to EOV.';

  @override
  String get pointIdField => 'Point ID field';

  @override
  String get pointNameField => 'Point Name field';

  @override
  String get heightSource => 'Height source';

  @override
  String get refHeightSystem => 'Reference height system';

  @override
  String get unknownNoDh => 'Unknown — no ΔH';

  @override
  String get ellipsoidal => 'Ellipsoidal';

  @override
  String get orthometricBaltic => 'Orthometric / Baltic';

  @override
  String get currentMfkRtkPosition => 'Current MFKRTK position';

  @override
  String get waitingForMfkRtk => 'Waiting for MFKRTK position…';

  @override
  String get aggregatedResults => 'Aggregated results — all sessions';

  @override
  String sessionsCount(int count) {
    return 'Sessions ($count)';
  }

  @override
  String get controlPointSummary => 'Control Point Summary';

  @override
  String get noExportableMeasurements => 'No measurements available to export.';

  @override
  String csvExportError(String error) {
    return 'CSV export error: $error';
  }

  @override
  String get levelingLogTitle => 'Leveling Log';

  @override
  String get noSavedProtocols => 'No saved leveling protocols.';

  @override
  String modeLabel(String mode) {
    return 'Mode: $mode';
  }

  @override
  String get modePrecision => 'Precision';

  @override
  String get modeLine => 'Line';

  @override
  String stationsCount(int count) {
    return 'Stations: $count';
  }

  @override
  String startingPoint(String point) {
    return 'Start point: $point';
  }

  @override
  String pdfExportFailed(String error) {
    return 'PDF export failed: $error';
  }

  @override
  String get editResume => 'Edit/Resume';

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String confirmDeleteBody(String name) {
    return 'Are you sure you want to delete \"$name\" protocol?';
  }

  @override
  String get noActiveProject => 'No active project.';

  @override
  String get cardView => 'Card view';

  @override
  String get protocolView => 'Protocol view';

  @override
  String get selectAdjustmentMode => 'Select adjustment mode';

  @override
  String get heightLabel => 'Height (m)';

  @override
  String get newLeveling => 'New Leveling';

  @override
  String get startLevelingLine => 'Start Leveling Line';

  @override
  String get lineName => 'Line Name';

  @override
  String get startPointName => 'Start Point Name';

  @override
  String get startHeightM => 'Start Height (m)';

  @override
  String get precisionMode => 'Precision Mode (double scale rod)';

  @override
  String get precisionModeSub => 'Off: Line leveling';

  @override
  String get selectPointFromProject => 'Select point from project';

  @override
  String get newIntermediatePoint => 'New Intermediate Point';

  @override
  String get noActiveLevelingLine => 'No active leveling line';

  @override
  String get startNewLine => 'START NEW LINE';

  @override
  String get finishAndSave => 'Finish Measurement and Save';

  @override
  String get discardMeasurement => 'Discard Measurement';

  @override
  String get reviewLog => 'REVIEW MEASUREMENTS (LOG)';

  @override
  String get noIntermediatePoints => 'No intermediate points recorded';

  @override
  String get saveHeightToPoint => 'SAVE HEIGHT TO POINT';

  @override
  String get missingBacksightError => 'Error: Missing backsight reading!';

  @override
  String get finishMeasurement => 'FINISH MEASUREMENT';

  @override
  String get negativeReadingError => 'Error: Negative reading!';

  @override
  String get measurementOrder => 'Measurement order (e.g. BS-FS / BS-IS...)';

  @override
  String get updateHeight => 'Update Height';

  @override
  String get heightSaved => 'Height saved.';

  @override
  String get measurementFinishedSaved => 'Measurement finished and saved.';

  @override
  String get precisionLeveling => 'Precision Leveling';

  @override
  String get missingProjectOrStation => 'Error: No active project or station';

  @override
  String get saveAnyway => 'Save anyway';

  @override
  String get photos => 'Photos:';

  @override
  String get takePhotoLabel => 'Take Photo';

  @override
  String get dataTemplate => 'Data template';

  @override
  String get readyToMeasure => 'Ready to measure';

  @override
  String get rtcmLost => 'RTCM lost — check NTRIP connection.';

  @override
  String get waitingInsAlignMsg =>
      'RTK FIX acquired — specify rod direction in RTK settings.';

  @override
  String get waitingRtkFix => 'Waiting for RTK FIX';

  @override
  String get rtkAndInsRequired =>
      'RTK FIX and completed INS alignment required to measure.';

  @override
  String get noPointsOnLayer => 'No point layer.';

  @override
  String get importShpTooltip =>
      'Please import a control point SHP into the project.';
}
