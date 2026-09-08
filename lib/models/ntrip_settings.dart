import 'ntrip_profile.dart';

class NtripSettings {
  bool enabled;
  String? activeProfileId;
  List<NtripProfile> profiles;
  bool autoStopAfterMeasurement;
  bool requireStableFix;
  int stabilityThresholdSeconds;

  NtripSettings({
    this.enabled = false,
    this.activeProfileId,
    this.profiles = const [],
    this.autoStopAfterMeasurement = false,
    this.requireStableFix = false,
    this.stabilityThresholdSeconds = 5,
  });

  NtripProfile? get activeProfile {
    if (activeProfileId == null || profiles.isEmpty) return null;
    return profiles.firstWhere((p) => p.id == activeProfileId, orElse: () => profiles.first);
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'activeProfileId': activeProfileId,
    'profiles': profiles.map((p) => p.toJson()).toList(),
    'autoStopAfterMeasurement': autoStopAfterMeasurement,
    'requireStableFix': requireStableFix,
    'stabilityThresholdSeconds': stabilityThresholdSeconds,
  };

  factory NtripSettings.fromJson(Map<String, dynamic> json) {
    // Migration logic for legacy flat settings
    List<NtripSourceProfile>? migratedProfiles;
    String? migratedActiveId;

    if (json.containsKey('host') && !json.containsKey('profiles')) {
      // Old format detected
      final legacyProfile = NtripProfile(
        id: 'default_legacy',
        name: 'Default',
        host: json['host'] ?? '',
        port: json['port'] ?? 2101,
        mountpoint: json['mountpoint'] ?? '',
        username: json['username'] ?? '',
        ggaInterval: json['ggaInterval'] ?? 10,
      );
      migratedProfiles = [legacyProfile];
      migratedActiveId = legacyProfile.id;
    }

    return NtripSettings(
      enabled: json['enabled'] ?? false,
      activeProfileId: json['activeProfileId'] ?? migratedActiveId,
      profiles: json.containsKey('profiles') 
          ? (json['profiles'] as List).map((p) => NtripProfile.fromJson(p)).toList()
          : (migratedProfiles ?? []),
      autoStopAfterMeasurement: json['autoStopAfterMeasurement'] ?? false,
      requireStableFix: json['requireStableFix'] ?? false,
      stabilityThresholdSeconds: json['stabilityThresholdSeconds'] ?? 5,
    );
  }
}
typedef NtripSourceProfile = NtripProfile;
