// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hungarian (`hu`).
class AppLocalizationsHu extends AppLocalizations {
  AppLocalizationsHu([String locale = 'hu']) : super(locale);

  @override
  String get appTitle => 'MFK GeoMeasure';

  @override
  String get mapScreenTitle => 'Térképnézet';

  @override
  String get settingsTitle => 'Beállítások';

  @override
  String get changeLanguage => 'Nyelv váltása';

  @override
  String get startRecording => 'Rögzítés indítása';

  @override
  String get stopRecording => 'Rögzítés leállítása';

  @override
  String gpsAccuracy(String accuracy) {
    return 'Pontosság: $accuracy m';
  }

  @override
  String currentAltitude(String alt) {
    return 'Magasság (Ortho): $alt m';
  }

  @override
  String get slogan => 'Földrajz az egész világ!';

  @override
  String get startMap => 'Térkép Indítása';

  @override
  String get startLearning => 'Geodéziai Gyakorlatok';

  @override
  String get uniName => 'Miskolci Egyetem, MFK';

  @override
  String get institute => 'Földrajz-Geoinformatika Intézet';

  @override
  String get noProject => 'Nincs Projekt';

  @override
  String get noLayer => 'Nincs Réteg';

  @override
  String get offlineMaps => 'Offline Térképek';

  @override
  String get manageDownloads => 'Kezeld a letöltött területeket.';

  @override
  String get deleteStorage => 'TÁRHELY TÖRLÉSE';

  @override
  String get deleteConfirmTitle => 'Biztosan törlöd?';

  @override
  String get deleteConfirmBody =>
      'Ez az összes letöltött offline térképet törli a telefonról.';

  @override
  String get cancel => 'Mégse';

  @override
  String get delete => 'Törlés';

  @override
  String get download => 'Letöltés';

  @override
  String get newDownload => 'ÚJ LETÖLTÉS';

  @override
  String get saveArea => 'Offline terület mentése';

  @override
  String get selectDetail => 'Válaszd ki a részletességet!';

  @override
  String get zoomLevels => 'Zoom szintek';

  @override
  String get tileCount => 'Csempék száma';

  @override
  String get attentionHuge =>
      'FIGYELEM: Ez rendkívül sok (>200k)! Több GB tárhely és órákig tartó letöltés várható. Csak Wi-Fi-n ajánlott!';

  @override
  String get attentionLarge =>
      'Ez sok adatot (>50k) generál. A letöltés percekig tarthat.';

  @override
  String get braveDownload => 'BÁTOR VAGYOK (LETÖLTÉS)';

  @override
  String get startDownload => 'LETÖLTÉS INDÍTÁSA';

  @override
  String get downloading => 'Letöltés folyamatban...';

  @override
  String get dontClose => 'Kérlek NE zárd be az alkalmazást!';

  @override
  String get keepScreenOn => 'A képernyő bekapcsolva maradjon.';

  @override
  String get abort => 'Megszakítás';

  @override
  String get downloadDone => 'Letöltés kész!';

  @override
  String get downloadAborted => 'Letöltés megszakítva.';

  @override
  String get storageCleared => 'Tárhely felszabadítva!';

  @override
  String get error => 'Hiba';

  @override
  String get noGps => 'Nincs GPS jel!';

  @override
  String get save => 'Mentés';

  @override
  String get name => 'Név';

  @override
  String get description => 'Leírás';

  @override
  String get done => 'KÉSZ';

  @override
  String get projectsLayers => 'Projektek és Rétegek';

  @override
  String get newElement => 'Új elem';

  @override
  String get createWhat => 'Mit szeretnél létrehozni';

  @override
  String get newProject => 'ÚJ PROJEKT';

  @override
  String get newLayer => 'ÚJ RÉTEG';

  @override
  String get activeProject => 'Aktív projekt';

  @override
  String get export => 'Export';

  @override
  String get mapType => 'Térkép típusa';

  @override
  String get satellite => 'Műhold (Google)';

  @override
  String get hiking => 'Turistautak (Hu)';

  @override
  String get osm => 'OpenStreetMap';

  @override
  String get searchingGps => 'GPS jel keresése...';

  @override
  String get point => 'Pont';

  @override
  String get line => 'Vonal';

  @override
  String get polygon => 'Poligon';

  @override
  String get saveItem => 'mentése';

  @override
  String get searchCoord => 'Koordináta kereső';

  @override
  String get invalidCoord => 'Érvénytelen formátum! WGS84 vagy EOV szükséges.';

  @override
  String get geodeticSettings => 'Geodéziai Beállítások';

  @override
  String get antennaHeight => 'Antenna magasság (m)';

  @override
  String get requiredAccuracy => 'Elvárt pontosság (m)';

  @override
  String get fastRecord => 'Gyors rögzítés';

  @override
  String get fastRecordDesc => 'Azonnali mentés a jelenlegi pozícióval';

  @override
  String get avgRecord => 'Átlagolt mérés (15 mp)';

  @override
  String get avgRecordDesc => 'Pontosabb pozíció statikus méréssel';

  @override
  String get measuringInProgress => 'Mérés folyamatban...';

  @override
  String get keepStill => 'Kérjük, tartsa mozdulatlanul az eszközt!';

  @override
  String get stakeoutCheck => 'Ellenőrző mérés a ponton';

  @override
  String get ant => 'Ant';

  @override
  String get searched => 'Keresett';

  @override
  String get recordedFromSearch => 'Keresőből rögzítve';

  @override
  String get pointSaved => 'Pont elmentve a projektbe!';

  @override
  String get searchAndSave => 'Keresés és Mentés';

  @override
  String get target => 'Cél';

  @override
  String get close => 'Bezárás';

  @override
  String get stakeout => 'Kitűzés';

  @override
  String get bestAcc => 'Legjobb hiba:';

  @override
  String get avgAcc => 'Átlagos hiba:';

  @override
  String get satellites => 'Műholdak';

  @override
  String get ppkStartTitle => 'PPK Mérés Indítása';

  @override
  String get ppkNameLabel => 'Mérés neve';

  @override
  String get ppkNotesLabel => 'Jegyzet';

  @override
  String get ppkStartBtn => 'INDÍTÁS';

  @override
  String get resection => 'Hátrametszés';

  @override
  String get area => 'Területszámítás';

  @override
  String get inverse => 'Inverz feladat';

  @override
  String get angularIntersection => 'Iránymetszés';

  @override
  String get distanceIntersection => 'Ívmetszés';

  @override
  String get result => 'EREDMÉNY';

  @override
  String get derivation => 'Matematikai levezetés';

  @override
  String get derivationShow => 'Részletes számítás (levezetés) mutatása';

  @override
  String get derivationHide => 'Levezetés elrejtése';

  @override
  String get campusMiskolc => 'Miskolc (ME MFK)';

  @override
  String get campusSzekesfehervar => 'Fehérvár (ÓE AMK)';

  @override
  String get selectLocation => 'Válassz helyszínt (Campust):';

  @override
  String get taskGoal => 'Feladat célja:';

  @override
  String get taskSteps => 'Megoldás menete:';

  @override
  String get check => 'ELLENŐRZÉS';

  @override
  String get excellent => 'Kiváló';

  @override
  String get good => 'Jó';

  @override
  String get retry => 'JAVÍTÁS';

  @override
  String get whatToCalculate => 'Mit szeretnél meghatározni?';

  @override
  String get inverseDesc => 'Két pont → távolság';

  @override
  String get angularDesc => 'Két irány → pont';

  @override
  String get distanceDesc => 'Két távolság → pont';

  @override
  String get resectionDesc => 'Három pont → álláspont';

  @override
  String get areaDesc => 'Pontok → terület';

  @override
  String get noTypeSelected => 'Nincs kiválasztott típus';

  @override
  String selectPointTarget(String point) {
    return 'Válassz: $point';
  }

  @override
  String get distanceLabel => 'Távolság';

  @override
  String get bearingLabel => 'Irányszög (WCB)';

  @override
  String get resultY => 'Eredmény Y';

  @override
  String get resultX => 'Eredmény X';

  @override
  String get intersection1Y => 'Metszéspont 1 Y';

  @override
  String get intersection1X => 'Metszéspont 1 X';

  @override
  String get intersection2Y => 'Metszéspont 2 Y';

  @override
  String get intersection2X => 'Metszéspont 2 X';

  @override
  String get areaLabel => 'Terület';

  @override
  String get radius1 => 'Sugár 1 (m)';

  @override
  String get radius2 => 'Sugár 2 (m)';

  @override
  String get bearing1 => 'Irányszög 1 (WCB °)';

  @override
  String get bearing2 => 'Irányszög 2 (WCB °)';

  @override
  String get measuredBearingP1 => 'Mért irány P1-re (°)';

  @override
  String get measuredBearingP2 => 'Mért irány P2-re (°)';

  @override
  String get measuredBearingP3 => 'Mért irány P3-re (°)';

  @override
  String get areaPoints => 'Terület pontjai';

  @override
  String get add => 'Hozzáadás';

  @override
  String get newPoint => 'Új pont';

  @override
  String get noPointsAdded => 'Nincsenek pontok felvéve.';

  @override
  String sourceLabel(String src) {
    return 'Forrás: $src';
  }

  @override
  String selectSourceFor(String label) {
    return '$label forrásának kiválasztása';
  }

  @override
  String get pickFromMap => 'Térképről választok';

  @override
  String get pickFromMapDesc => 'Bökj rá a kívánt helyre a térképen';

  @override
  String get currentGnss => 'Jelenlegi GNSS pozíció';

  @override
  String get currentGnssDesc => 'A telefon GPS koordinátáinak beolvasása';

  @override
  String get pickFromProject => 'Választás projektből';

  @override
  String get pickFromProjectDesc => 'Már elmentett pontok betöltése';

  @override
  String get fetchingGps => 'GPS pozíció lekérése...';

  @override
  String get noPointsInActiveLayers => 'Nincsenek pontok az aktív rétegeken!';

  @override
  String get selectPointTitle => 'Pont kiválasztása';

  @override
  String get waitingForInput => 'Várom a bemeneti adatokat...';

  @override
  String get hideKeyboard => 'Billentyűzet elrejtése';

  @override
  String get mathDerivation => 'Matematikai levezetés';

  @override
  String get sourceMap => 'Térkép';

  @override
  String get sourceGnss => 'GNSS (GPS)';

  @override
  String get sourceProject => 'Projekt';

  @override
  String get selectBtn => 'Kiválasztás';

  @override
  String quadrantName(String quadrant) {
    return '$quadrant síknegyed';
  }

  @override
  String get gisImportTooltip => 'GIS Import (DXF, KML, GPX)';

  @override
  String itemsImported(int count) {
    return '$count elem importálva!';
  }

  @override
  String get settingsTooltip => 'Beállítások';

  @override
  String get templateLabel => 'Adatlap sablon';

  @override
  String get takePhoto => 'Fotó készítése';

  @override
  String get skyplotTitle => 'GNSS Skyplot';

  @override
  String get skyplotAndroidOnly =>
      'A Skyplot jelenleg csak Android eszközökön érhető el.';

  @override
  String get searchingSatellites => 'Műhold adatok keresése...';

  @override
  String get satUsedLegend => 'Teli kör: Mérésben használt';

  @override
  String get loadVectorMbtiles => 'Vektoros MBTiles betöltése';

  @override
  String get notLoaded => 'Nincs betöltve';

  @override
  String get vectorMode => 'Vektoros mód';

  @override
  String get invalidSavedCoord => 'Hiba: Érvénytelen mentett koordináta!';

  @override
  String get gpsErrorPerm =>
      'GPS hiba: Kérlek engedélyezd a helymeghatározást a beállításokban!';

  @override
  String measurementTime(String time) {
    return 'Mérés $time';
  }

  @override
  String get taskSolveTitle => 'Feladat Megoldása';

  @override
  String get givenData => 'ADOTT ADATOK:';

  @override
  String get calculatedResults => 'SZÁMÍTOTT EREDMÉNYEK:';

  @override
  String get fillAllFields => 'Kérlek töltsd ki az összes mezőt!';

  @override
  String get differences => 'Eltérések (Mért - Valós):';

  @override
  String get gradeError => 'Hiba';

  @override
  String get gradeExcellent => 'Kiváló';

  @override
  String get gradeGood => 'Jó';

  @override
  String get msgError => 'A számítás pontatlan. Ellenőrizd a képleteket!';

  @override
  String get msgExcellent => 'Gratulálunk! Mérnöki pontosságú megoldás.';

  @override
  String get msgGood =>
      'Közel jársz, de van egy kis kerekítési vagy számítási pontatlanság.';

  @override
  String locationLabel(String campus) {
    return 'Helyszín: $campus';
  }

  @override
  String get templateGeneral => 'Általános';

  @override
  String get templateWaterManhole => 'Vízmű akna';

  @override
  String get templateBoundaryStone => 'Határkő';

  @override
  String get templateUtilityPole => 'Elektromos oszlop';

  @override
  String get fieldMaterial => 'Anyaga';

  @override
  String get fieldDiameter => 'Átmérő (mm)';

  @override
  String get fieldDepth => 'Mélység (m)';

  @override
  String get fieldCondition => 'Fedlap állapota';

  @override
  String get fieldType => 'Típusa';

  @override
  String get fieldStatus => 'Állapota';

  @override
  String get fieldVoltage => 'Feszültség';

  @override
  String get fieldHasLamp => 'Lámpatest van?';

  @override
  String get optConcrete => 'Beton';

  @override
  String get optPlastic => 'Műanyag';

  @override
  String get optBrick => 'Tégla';

  @override
  String get optCastIron => 'Öntöttvas';

  @override
  String get optGood => 'Jó';

  @override
  String get optDamaged => 'Sérült';

  @override
  String get optMissing => 'Hiányzik';

  @override
  String get optConcreteStone => 'Beton kő';

  @override
  String get optGranite => 'Gránit';

  @override
  String get optIronPipe => 'Vascső';

  @override
  String get optPlasticPeg => 'Műanyag szeg';

  @override
  String get optIntact => 'Ép';

  @override
  String get optTilted => 'Megdőlt';

  @override
  String get optDisplaced => 'Kifordult';

  @override
  String get optUncertain => 'Bizonytalan';

  @override
  String get optWood => 'Fa';

  @override
  String get optIron => 'Vas';

  @override
  String get optYes => 'Igen';

  @override
  String get optNo => 'Nem';

  @override
  String get addCustomField => 'Egyedi mező hozzáadása';

  @override
  String get newFieldName => 'Új mező neve';

  @override
  String get customFields => 'Egyedi mezők';

  @override
  String get addColumn => 'Oszlop hozzáadása';

  @override
  String get gnssSource => 'GNSS Forrás';

  @override
  String get internalGps => 'Telefon GPS';

  @override
  String get externalGnss => 'Külső GNSS';

  @override
  String get bluetoothClassic => 'Bluetooth Classic';

  @override
  String get bluetoothBle => 'Bluetooth Low Energy';

  @override
  String get usbSerial => 'USB Serial';

  @override
  String get scanningDevices => 'Eszközök keresése...';

  @override
  String get noDevicesFound => 'Nem található eszköz';

  @override
  String deviceAddress(String address) {
    return 'Cím: $address';
  }

  @override
  String get fixStatus => 'Fix Állapot';

  @override
  String get rtkStatus => 'RTK Állapot';

  @override
  String correctionAge(String age) {
    return 'Korrekció kora: $age s';
  }

  @override
  String get ntripSettings => 'NTRIP Beállítások';

  @override
  String get fetchMountpoints => 'Mountpointok lekérése';

  @override
  String get selectMountpoint => 'Válassz mountpointot';

  @override
  String get noMountpointsFound => 'Nem található mountpoint';

  @override
  String get profiles => 'Profilok';

  @override
  String get addProfile => 'Új profil';

  @override
  String get editProfile => 'Profil szerkesztése';

  @override
  String get deleteProfile => 'Profil törlése';

  @override
  String get profileName => 'Profil neve';

  @override
  String get bitrate => 'Adatsebesség';

  @override
  String get totalData => 'Összes adat';

  @override
  String get requireStableFix => 'Stabil RTK FIX elvárása';

  @override
  String get stabilityThreshold => 'Stabilitási küszöb (s)';

  @override
  String get lastGgaSent => 'Utolsó GGA küldve';

  @override
  String get lastRtcmReceived => 'Utolsó korrekció érkezett';

  @override
  String get reconnecting => 'Újracsatlakozás...';
}
