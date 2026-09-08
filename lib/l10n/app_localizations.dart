import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hu.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hu')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MFK GeoMeasure'**
  String get appTitle;

  /// No description provided for @mapScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Map View'**
  String get mapScreenTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @changeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get changeLanguage;

  /// No description provided for @startRecording.
  ///
  /// In en, this message translates to:
  /// **'Start Recording'**
  String get startRecording;

  /// No description provided for @stopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop Recording'**
  String get stopRecording;

  /// No description provided for @gpsAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy: {accuracy} m'**
  String gpsAccuracy(String accuracy);

  /// No description provided for @currentAltitude.
  ///
  /// In en, this message translates to:
  /// **'Height (Ortho): {alt} m'**
  String currentAltitude(String alt);

  /// No description provided for @slogan.
  ///
  /// In en, this message translates to:
  /// **'Geography is the whole world!'**
  String get slogan;

  /// No description provided for @startMap.
  ///
  /// In en, this message translates to:
  /// **'Start Map'**
  String get startMap;

  /// No description provided for @startLearning.
  ///
  /// In en, this message translates to:
  /// **'Geodetic Exercises'**
  String get startLearning;

  /// No description provided for @uniName.
  ///
  /// In en, this message translates to:
  /// **'University of Miskolc, MFK'**
  String get uniName;

  /// No description provided for @institute.
  ///
  /// In en, this message translates to:
  /// **'Institute of Geography and Geoinformatics'**
  String get institute;

  /// No description provided for @noProject.
  ///
  /// In en, this message translates to:
  /// **'No Project'**
  String get noProject;

  /// No description provided for @noLayer.
  ///
  /// In en, this message translates to:
  /// **'No Layer'**
  String get noLayer;

  /// No description provided for @offlineMaps.
  ///
  /// In en, this message translates to:
  /// **'Offline Maps'**
  String get offlineMaps;

  /// No description provided for @manageDownloads.
  ///
  /// In en, this message translates to:
  /// **'Manage downloaded areas.'**
  String get manageDownloads;

  /// No description provided for @deleteStorage.
  ///
  /// In en, this message translates to:
  /// **'CLEAR STORAGE'**
  String get deleteStorage;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will delete all offline maps from the phone.'**
  String get deleteConfirmBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @newDownload.
  ///
  /// In en, this message translates to:
  /// **'NEW DOWNLOAD'**
  String get newDownload;

  /// No description provided for @saveArea.
  ///
  /// In en, this message translates to:
  /// **'Save Offline Area'**
  String get saveArea;

  /// No description provided for @selectDetail.
  ///
  /// In en, this message translates to:
  /// **'Select detail level!'**
  String get selectDetail;

  /// No description provided for @zoomLevels.
  ///
  /// In en, this message translates to:
  /// **'Zoom levels'**
  String get zoomLevels;

  /// No description provided for @tileCount.
  ///
  /// In en, this message translates to:
  /// **'Tile count'**
  String get tileCount;

  /// No description provided for @attentionHuge.
  ///
  /// In en, this message translates to:
  /// **'WARNING: This is huge (>200k)! Expect GBs of data and hours of download. Wi-Fi only!'**
  String get attentionHuge;

  /// No description provided for @attentionLarge.
  ///
  /// In en, this message translates to:
  /// **'This generates a lot of data (>50k). Download may take minutes.'**
  String get attentionLarge;

  /// No description provided for @braveDownload.
  ///
  /// In en, this message translates to:
  /// **'I AM BRAVE (DOWNLOAD)'**
  String get braveDownload;

  /// No description provided for @startDownload.
  ///
  /// In en, this message translates to:
  /// **'START DOWNLOAD'**
  String get startDownload;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get downloading;

  /// No description provided for @dontClose.
  ///
  /// In en, this message translates to:
  /// **'Please DO NOT close the app!'**
  String get dontClose;

  /// No description provided for @keepScreenOn.
  ///
  /// In en, this message translates to:
  /// **'Keep the screen on.'**
  String get keepScreenOn;

  /// No description provided for @abort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get abort;

  /// No description provided for @downloadDone.
  ///
  /// In en, this message translates to:
  /// **'Download finished!'**
  String get downloadDone;

  /// No description provided for @downloadAborted.
  ///
  /// In en, this message translates to:
  /// **'Download aborted.'**
  String get downloadAborted;

  /// No description provided for @storageCleared.
  ///
  /// In en, this message translates to:
  /// **'Storage cleared!'**
  String get storageCleared;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @noGps.
  ///
  /// In en, this message translates to:
  /// **'No GPS signal!'**
  String get noGps;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get done;

  /// No description provided for @projectsLayers.
  ///
  /// In en, this message translates to:
  /// **'Projects and Layers'**
  String get projectsLayers;

  /// No description provided for @newElement.
  ///
  /// In en, this message translates to:
  /// **'New Item'**
  String get newElement;

  /// No description provided for @createWhat.
  ///
  /// In en, this message translates to:
  /// **'What do you want to create'**
  String get createWhat;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'NEW PROJECT'**
  String get newProject;

  /// No description provided for @newLayer.
  ///
  /// In en, this message translates to:
  /// **'NEW LAYER'**
  String get newLayer;

  /// No description provided for @activeProject.
  ///
  /// In en, this message translates to:
  /// **'Active project'**
  String get activeProject;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @mapType.
  ///
  /// In en, this message translates to:
  /// **'Map Type'**
  String get mapType;

  /// No description provided for @satellite.
  ///
  /// In en, this message translates to:
  /// **'Satellite (Google)'**
  String get satellite;

  /// No description provided for @hiking.
  ///
  /// In en, this message translates to:
  /// **'Hiking Trails (Hu)'**
  String get hiking;

  /// No description provided for @osm.
  ///
  /// In en, this message translates to:
  /// **'OpenStreetMap'**
  String get osm;

  /// No description provided for @searchingGps.
  ///
  /// In en, this message translates to:
  /// **'Searching for GPS signal...'**
  String get searchingGps;

  /// No description provided for @point.
  ///
  /// In en, this message translates to:
  /// **'Point'**
  String get point;

  /// No description provided for @line.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get line;

  /// No description provided for @polygon.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get polygon;

  /// No description provided for @saveItem.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveItem;

  /// No description provided for @searchCoord.
  ///
  /// In en, this message translates to:
  /// **'Coordinate Search'**
  String get searchCoord;

  /// No description provided for @invalidCoord.
  ///
  /// In en, this message translates to:
  /// **'Invalid format! WGS84 or EOV required.'**
  String get invalidCoord;

  /// No description provided for @geodeticSettings.
  ///
  /// In en, this message translates to:
  /// **'Geodetic Settings'**
  String get geodeticSettings;

  /// No description provided for @antennaHeight.
  ///
  /// In en, this message translates to:
  /// **'Antenna height (m)'**
  String get antennaHeight;

  /// No description provided for @requiredAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Required accuracy (m)'**
  String get requiredAccuracy;

  /// No description provided for @fastRecord.
  ///
  /// In en, this message translates to:
  /// **'Fast record'**
  String get fastRecord;

  /// No description provided for @fastRecordDesc.
  ///
  /// In en, this message translates to:
  /// **'Instant save with current position'**
  String get fastRecordDesc;

  /// No description provided for @avgRecord.
  ///
  /// In en, this message translates to:
  /// **'Averaged measurement (15s)'**
  String get avgRecord;

  /// No description provided for @avgRecordDesc.
  ///
  /// In en, this message translates to:
  /// **'More accurate position with static measurement'**
  String get avgRecordDesc;

  /// No description provided for @measuringInProgress.
  ///
  /// In en, this message translates to:
  /// **'Measurement in progress...'**
  String get measuringInProgress;

  /// No description provided for @keepStill.
  ///
  /// In en, this message translates to:
  /// **'Please keep the device still!'**
  String get keepStill;

  /// No description provided for @stakeoutCheck.
  ///
  /// In en, this message translates to:
  /// **'Check measurement on point'**
  String get stakeoutCheck;

  /// No description provided for @ant.
  ///
  /// In en, this message translates to:
  /// **'Ant'**
  String get ant;

  /// No description provided for @searched.
  ///
  /// In en, this message translates to:
  /// **'Searched'**
  String get searched;

  /// No description provided for @recordedFromSearch.
  ///
  /// In en, this message translates to:
  /// **'Recorded from search'**
  String get recordedFromSearch;

  /// No description provided for @pointSaved.
  ///
  /// In en, this message translates to:
  /// **'Point saved to project!'**
  String get pointSaved;

  /// No description provided for @searchAndSave.
  ///
  /// In en, this message translates to:
  /// **'Search and Save'**
  String get searchAndSave;

  /// No description provided for @target.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get target;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @stakeout.
  ///
  /// In en, this message translates to:
  /// **'Stakeout'**
  String get stakeout;

  /// No description provided for @bestAcc.
  ///
  /// In en, this message translates to:
  /// **'Best accuracy:'**
  String get bestAcc;

  /// No description provided for @avgAcc.
  ///
  /// In en, this message translates to:
  /// **'Average accuracy:'**
  String get avgAcc;

  /// No description provided for @satellites.
  ///
  /// In en, this message translates to:
  /// **'Satellites'**
  String get satellites;

  /// No description provided for @ppkStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Start PPK Logging'**
  String get ppkStartTitle;

  /// No description provided for @ppkNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Session name'**
  String get ppkNameLabel;

  /// No description provided for @ppkNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get ppkNotesLabel;

  /// No description provided for @ppkStartBtn.
  ///
  /// In en, this message translates to:
  /// **'START'**
  String get ppkStartBtn;

  /// No description provided for @resection.
  ///
  /// In en, this message translates to:
  /// **'Resection'**
  String get resection;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area Calculation'**
  String get area;

  /// No description provided for @inverse.
  ///
  /// In en, this message translates to:
  /// **'Inverse Task'**
  String get inverse;

  /// No description provided for @angularIntersection.
  ///
  /// In en, this message translates to:
  /// **'Angular Intersection'**
  String get angularIntersection;

  /// No description provided for @distanceIntersection.
  ///
  /// In en, this message translates to:
  /// **'Distance Intersection'**
  String get distanceIntersection;

  /// No description provided for @result.
  ///
  /// In en, this message translates to:
  /// **'RESULT'**
  String get result;

  /// No description provided for @derivation.
  ///
  /// In en, this message translates to:
  /// **'Mathematical derivation'**
  String get derivation;

  /// No description provided for @derivationShow.
  ///
  /// In en, this message translates to:
  /// **'Show detailed calculation (derivation)'**
  String get derivationShow;

  /// No description provided for @derivationHide.
  ///
  /// In en, this message translates to:
  /// **'Hide derivation'**
  String get derivationHide;

  /// No description provided for @campusMiskolc.
  ///
  /// In en, this message translates to:
  /// **'Miskolc (ME MFK)'**
  String get campusMiskolc;

  /// No description provided for @campusSzekesfehervar.
  ///
  /// In en, this message translates to:
  /// **'Fehervar (ÓE AMK)'**
  String get campusSzekesfehervar;

  /// No description provided for @selectLocation.
  ///
  /// In en, this message translates to:
  /// **'Select location (Campus):'**
  String get selectLocation;

  /// No description provided for @taskGoal.
  ///
  /// In en, this message translates to:
  /// **'Task goal:'**
  String get taskGoal;

  /// No description provided for @taskSteps.
  ///
  /// In en, this message translates to:
  /// **'Solution steps:'**
  String get taskSteps;

  /// No description provided for @check.
  ///
  /// In en, this message translates to:
  /// **'CHECK'**
  String get check;

  /// No description provided for @excellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get excellent;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get good;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get retry;

  /// No description provided for @whatToCalculate.
  ///
  /// In en, this message translates to:
  /// **'What do you want to calculate?'**
  String get whatToCalculate;

  /// No description provided for @inverseDesc.
  ///
  /// In en, this message translates to:
  /// **'Two points → distance'**
  String get inverseDesc;

  /// No description provided for @angularDesc.
  ///
  /// In en, this message translates to:
  /// **'Two directions → point'**
  String get angularDesc;

  /// No description provided for @distanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Two distances → point'**
  String get distanceDesc;

  /// No description provided for @resectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Three points → station'**
  String get resectionDesc;

  /// No description provided for @areaDesc.
  ///
  /// In en, this message translates to:
  /// **'Points → area'**
  String get areaDesc;

  /// No description provided for @noTypeSelected.
  ///
  /// In en, this message translates to:
  /// **'No calculation type selected'**
  String get noTypeSelected;

  /// No description provided for @selectPointTarget.
  ///
  /// In en, this message translates to:
  /// **'Select: {point}'**
  String selectPointTarget(String point);

  /// No description provided for @distanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get distanceLabel;

  /// No description provided for @bearingLabel.
  ///
  /// In en, this message translates to:
  /// **'Bearing (WCB)'**
  String get bearingLabel;

  /// No description provided for @resultY.
  ///
  /// In en, this message translates to:
  /// **'Result Y'**
  String get resultY;

  /// No description provided for @resultX.
  ///
  /// In en, this message translates to:
  /// **'Result X'**
  String get resultX;

  /// No description provided for @intersection1Y.
  ///
  /// In en, this message translates to:
  /// **'Intersection 1 Y'**
  String get intersection1Y;

  /// No description provided for @intersection1X.
  ///
  /// In en, this message translates to:
  /// **'Intersection 1 X'**
  String get intersection1X;

  /// No description provided for @intersection2Y.
  ///
  /// In en, this message translates to:
  /// **'Intersection 2 Y'**
  String get intersection2Y;

  /// No description provided for @intersection2X.
  ///
  /// In en, this message translates to:
  /// **'Intersection 2 X'**
  String get intersection2X;

  /// No description provided for @areaLabel.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get areaLabel;

  /// No description provided for @radius1.
  ///
  /// In en, this message translates to:
  /// **'Radius 1 (m)'**
  String get radius1;

  /// No description provided for @radius2.
  ///
  /// In en, this message translates to:
  /// **'Radius 2 (m)'**
  String get radius2;

  /// No description provided for @bearing1.
  ///
  /// In en, this message translates to:
  /// **'Bearing 1 (WCB °)'**
  String get bearing1;

  /// No description provided for @bearing2.
  ///
  /// In en, this message translates to:
  /// **'Bearing 2 (WCB °)'**
  String get bearing2;

  /// No description provided for @measuredBearingP1.
  ///
  /// In en, this message translates to:
  /// **'Measured bearing to P1 (°)'**
  String get measuredBearingP1;

  /// No description provided for @measuredBearingP2.
  ///
  /// In en, this message translates to:
  /// **'Measured bearing to P2 (°)'**
  String get measuredBearingP2;

  /// No description provided for @measuredBearingP3.
  ///
  /// In en, this message translates to:
  /// **'Measured bearing to P3 (°)'**
  String get measuredBearingP3;

  /// No description provided for @areaPoints.
  ///
  /// In en, this message translates to:
  /// **'Area points'**
  String get areaPoints;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @newPoint.
  ///
  /// In en, this message translates to:
  /// **'New point'**
  String get newPoint;

  /// No description provided for @noPointsAdded.
  ///
  /// In en, this message translates to:
  /// **'No points added.'**
  String get noPointsAdded;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {src}'**
  String sourceLabel(String src);

  /// No description provided for @selectSourceFor.
  ///
  /// In en, this message translates to:
  /// **'Select source for {label}'**
  String selectSourceFor(String label);

  /// No description provided for @pickFromMap.
  ///
  /// In en, this message translates to:
  /// **'Select from map'**
  String get pickFromMap;

  /// No description provided for @pickFromMapDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap desired location on map'**
  String get pickFromMapDesc;

  /// No description provided for @currentGnss.
  ///
  /// In en, this message translates to:
  /// **'Current GNSS position'**
  String get currentGnss;

  /// No description provided for @currentGnssDesc.
  ///
  /// In en, this message translates to:
  /// **'Read phone GPS coordinates'**
  String get currentGnssDesc;

  /// No description provided for @pickFromProject.
  ///
  /// In en, this message translates to:
  /// **'Select from project'**
  String get pickFromProject;

  /// No description provided for @pickFromProjectDesc.
  ///
  /// In en, this message translates to:
  /// **'Load previously saved points'**
  String get pickFromProjectDesc;

  /// No description provided for @fetchingGps.
  ///
  /// In en, this message translates to:
  /// **'Fetching GPS position...'**
  String get fetchingGps;

  /// No description provided for @noPointsInActiveLayers.
  ///
  /// In en, this message translates to:
  /// **'No points on active layers!'**
  String get noPointsInActiveLayers;

  /// No description provided for @selectPointTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Point'**
  String get selectPointTitle;

  /// No description provided for @waitingForInput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for input data...'**
  String get waitingForInput;

  /// No description provided for @hideKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Hide keyboard'**
  String get hideKeyboard;

  /// No description provided for @mathDerivation.
  ///
  /// In en, this message translates to:
  /// **'Mathematical derivation'**
  String get mathDerivation;

  /// No description provided for @sourceMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get sourceMap;

  /// No description provided for @sourceGnss.
  ///
  /// In en, this message translates to:
  /// **'GNSS (GPS)'**
  String get sourceGnss;

  /// No description provided for @sourceProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get sourceProject;

  /// No description provided for @selectBtn.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectBtn;

  /// No description provided for @quadrantName.
  ///
  /// In en, this message translates to:
  /// **'{quadrant} quadrant'**
  String quadrantName(String quadrant);

  /// No description provided for @gisImportTooltip.
  ///
  /// In en, this message translates to:
  /// **'GIS Import (DXF, KML, GPX)'**
  String get gisImportTooltip;

  /// No description provided for @itemsImported.
  ///
  /// In en, this message translates to:
  /// **'{count} items imported!'**
  String itemsImported(int count);

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @templateLabel.
  ///
  /// In en, this message translates to:
  /// **'Data template'**
  String get templateLabel;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @skyplotTitle.
  ///
  /// In en, this message translates to:
  /// **'GNSS Skyplot'**
  String get skyplotTitle;

  /// No description provided for @skyplotAndroidOnly.
  ///
  /// In en, this message translates to:
  /// **'Skyplot is currently only available on Android devices.'**
  String get skyplotAndroidOnly;

  /// No description provided for @searchingSatellites.
  ///
  /// In en, this message translates to:
  /// **'Searching for satellite data...'**
  String get searchingSatellites;

  /// No description provided for @satUsedLegend.
  ///
  /// In en, this message translates to:
  /// **'Solid circle: Used in fix'**
  String get satUsedLegend;

  /// No description provided for @loadVectorMbtiles.
  ///
  /// In en, this message translates to:
  /// **'Load Vector MBTiles'**
  String get loadVectorMbtiles;

  /// No description provided for @notLoaded.
  ///
  /// In en, this message translates to:
  /// **'Not loaded'**
  String get notLoaded;

  /// No description provided for @vectorMode.
  ///
  /// In en, this message translates to:
  /// **'Vector mode'**
  String get vectorMode;

  /// No description provided for @invalidSavedCoord.
  ///
  /// In en, this message translates to:
  /// **'Error: Invalid saved coordinate!'**
  String get invalidSavedCoord;

  /// No description provided for @gpsErrorPerm.
  ///
  /// In en, this message translates to:
  /// **'GPS error: Please enable location in settings!'**
  String get gpsErrorPerm;

  /// No description provided for @measurementTime.
  ///
  /// In en, this message translates to:
  /// **'Measurement {time}'**
  String measurementTime(String time);

  /// No description provided for @taskSolveTitle.
  ///
  /// In en, this message translates to:
  /// **'Solve Task'**
  String get taskSolveTitle;

  /// No description provided for @givenData.
  ///
  /// In en, this message translates to:
  /// **'GIVEN DATA:'**
  String get givenData;

  /// No description provided for @calculatedResults.
  ///
  /// In en, this message translates to:
  /// **'CALCULATED RESULTS:'**
  String get calculatedResults;

  /// No description provided for @fillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields!'**
  String get fillAllFields;

  /// No description provided for @differences.
  ///
  /// In en, this message translates to:
  /// **'Differences (Measured - True):'**
  String get differences;

  /// No description provided for @gradeError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get gradeError;

  /// No description provided for @gradeExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get gradeExcellent;

  /// No description provided for @gradeGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get gradeGood;

  /// No description provided for @msgError.
  ///
  /// In en, this message translates to:
  /// **'Calculation inaccurate. Check formulas!'**
  String get msgError;

  /// No description provided for @msgExcellent.
  ///
  /// In en, this message translates to:
  /// **'Congratulations! Engineering level precision.'**
  String get msgExcellent;

  /// No description provided for @msgGood.
  ///
  /// In en, this message translates to:
  /// **'Close, but there is a slight rounding or calculation error.'**
  String get msgGood;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location: {campus}'**
  String locationLabel(String campus);

  /// No description provided for @templateGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get templateGeneral;

  /// No description provided for @templateWaterManhole.
  ///
  /// In en, this message translates to:
  /// **'Water Manhole'**
  String get templateWaterManhole;

  /// No description provided for @templateBoundaryStone.
  ///
  /// In en, this message translates to:
  /// **'Boundary Stone'**
  String get templateBoundaryStone;

  /// No description provided for @templateUtilityPole.
  ///
  /// In en, this message translates to:
  /// **'Utility Pole'**
  String get templateUtilityPole;

  /// No description provided for @fieldMaterial.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get fieldMaterial;

  /// No description provided for @fieldDiameter.
  ///
  /// In en, this message translates to:
  /// **'Diameter (mm)'**
  String get fieldDiameter;

  /// No description provided for @fieldDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth (m)'**
  String get fieldDepth;

  /// No description provided for @fieldCondition.
  ///
  /// In en, this message translates to:
  /// **'Cover condition'**
  String get fieldCondition;

  /// No description provided for @fieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get fieldType;

  /// No description provided for @fieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get fieldStatus;

  /// No description provided for @fieldVoltage.
  ///
  /// In en, this message translates to:
  /// **'Voltage'**
  String get fieldVoltage;

  /// No description provided for @fieldHasLamp.
  ///
  /// In en, this message translates to:
  /// **'Has lamp?'**
  String get fieldHasLamp;

  /// No description provided for @optConcrete.
  ///
  /// In en, this message translates to:
  /// **'Concrete'**
  String get optConcrete;

  /// No description provided for @optPlastic.
  ///
  /// In en, this message translates to:
  /// **'Plastic'**
  String get optPlastic;

  /// No description provided for @optBrick.
  ///
  /// In en, this message translates to:
  /// **'Brick'**
  String get optBrick;

  /// No description provided for @optCastIron.
  ///
  /// In en, this message translates to:
  /// **'Cast Iron'**
  String get optCastIron;

  /// No description provided for @optGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get optGood;

  /// No description provided for @optDamaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get optDamaged;

  /// No description provided for @optMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get optMissing;

  /// No description provided for @optConcreteStone.
  ///
  /// In en, this message translates to:
  /// **'Concrete Stone'**
  String get optConcreteStone;

  /// No description provided for @optGranite.
  ///
  /// In en, this message translates to:
  /// **'Granite'**
  String get optGranite;

  /// No description provided for @optIronPipe.
  ///
  /// In en, this message translates to:
  /// **'Iron Pipe'**
  String get optIronPipe;

  /// No description provided for @optPlasticPeg.
  ///
  /// In en, this message translates to:
  /// **'Plastic Peg'**
  String get optPlasticPeg;

  /// No description provided for @optIntact.
  ///
  /// In en, this message translates to:
  /// **'Intact'**
  String get optIntact;

  /// No description provided for @optTilted.
  ///
  /// In en, this message translates to:
  /// **'Tilted'**
  String get optTilted;

  /// No description provided for @optDisplaced.
  ///
  /// In en, this message translates to:
  /// **'Displaced'**
  String get optDisplaced;

  /// No description provided for @optUncertain.
  ///
  /// In en, this message translates to:
  /// **'Uncertain'**
  String get optUncertain;

  /// No description provided for @optWood.
  ///
  /// In en, this message translates to:
  /// **'Wood'**
  String get optWood;

  /// No description provided for @optIron.
  ///
  /// In en, this message translates to:
  /// **'Iron'**
  String get optIron;

  /// No description provided for @optYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get optYes;

  /// No description provided for @optNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get optNo;

  /// No description provided for @addCustomField.
  ///
  /// In en, this message translates to:
  /// **'Add Custom Field'**
  String get addCustomField;

  /// No description provided for @newFieldName.
  ///
  /// In en, this message translates to:
  /// **'New field name'**
  String get newFieldName;

  /// No description provided for @customFields.
  ///
  /// In en, this message translates to:
  /// **'Custom Fields'**
  String get customFields;

  /// No description provided for @addColumn.
  ///
  /// In en, this message translates to:
  /// **'Add Column'**
  String get addColumn;

  /// No description provided for @gnssSource.
  ///
  /// In en, this message translates to:
  /// **'GNSS Source'**
  String get gnssSource;

  /// No description provided for @internalGps.
  ///
  /// In en, this message translates to:
  /// **'Internal GPS'**
  String get internalGps;

  /// No description provided for @externalGnss.
  ///
  /// In en, this message translates to:
  /// **'External GNSS'**
  String get externalGnss;

  /// No description provided for @bluetoothClassic.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Classic'**
  String get bluetoothClassic;

  /// No description provided for @bluetoothBle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Low Energy'**
  String get bluetoothBle;

  /// No description provided for @usbSerial.
  ///
  /// In en, this message translates to:
  /// **'USB Serial'**
  String get usbSerial;

  /// No description provided for @scanningDevices.
  ///
  /// In en, this message translates to:
  /// **'Scanning for devices...'**
  String get scanningDevices;

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get noDevicesFound;

  /// No description provided for @deviceAddress.
  ///
  /// In en, this message translates to:
  /// **'Address: {address}'**
  String deviceAddress(String address);

  /// No description provided for @fixStatus.
  ///
  /// In en, this message translates to:
  /// **'Fix Status'**
  String get fixStatus;

  /// No description provided for @rtkStatus.
  ///
  /// In en, this message translates to:
  /// **'RTK Status'**
  String get rtkStatus;

  /// No description provided for @correctionAge.
  ///
  /// In en, this message translates to:
  /// **'Correction Age: {age} s'**
  String correctionAge(String age);

  /// No description provided for @ntripSettings.
  ///
  /// In en, this message translates to:
  /// **'NTRIP Settings'**
  String get ntripSettings;

  /// No description provided for @fetchMountpoints.
  ///
  /// In en, this message translates to:
  /// **'Fetch Mountpoints'**
  String get fetchMountpoints;

  /// No description provided for @selectMountpoint.
  ///
  /// In en, this message translates to:
  /// **'Select Mountpoint'**
  String get selectMountpoint;

  /// No description provided for @noMountpointsFound.
  ///
  /// In en, this message translates to:
  /// **'No mountpoints found'**
  String get noMountpointsFound;

  /// No description provided for @profiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profiles;

  /// No description provided for @addProfile.
  ///
  /// In en, this message translates to:
  /// **'Add Profile'**
  String get addProfile;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @deleteProfile.
  ///
  /// In en, this message translates to:
  /// **'Delete Profile'**
  String get deleteProfile;

  /// No description provided for @profileName.
  ///
  /// In en, this message translates to:
  /// **'Profile Name'**
  String get profileName;

  /// No description provided for @bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get bitrate;

  /// No description provided for @totalData.
  ///
  /// In en, this message translates to:
  /// **'Total Data'**
  String get totalData;

  /// No description provided for @requireStableFix.
  ///
  /// In en, this message translates to:
  /// **'Require stable RTK FIX'**
  String get requireStableFix;

  /// No description provided for @stabilityThreshold.
  ///
  /// In en, this message translates to:
  /// **'Stability threshold (s)'**
  String get stabilityThreshold;

  /// No description provided for @lastGgaSent.
  ///
  /// In en, this message translates to:
  /// **'Last GGA sent'**
  String get lastGgaSent;

  /// No description provided for @lastRtcmReceived.
  ///
  /// In en, this message translates to:
  /// **'Last correction received'**
  String get lastRtcmReceived;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get reconnecting;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hu'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hu':
      return AppLocalizationsHu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
