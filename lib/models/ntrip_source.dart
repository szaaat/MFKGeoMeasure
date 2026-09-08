class NtripSource {
  final String mountpoint;
  final String identifier;
  final String format;
  final String formatDetails;
  final String carrier;
  final String system;
  final String network;
  final String country;
  final double? latitude;
  final double? longitude;
  final bool needsNmea;
  final String solution;
  final String generator;
  final String compression;
  final String authentication;
  final String fee;
  final int? bitrate;

  NtripSource({
    required this.mountpoint,
    this.identifier = '',
    this.format = '',
    this.formatDetails = '',
    this.carrier = '',
    this.system = '',
    this.network = '',
    this.country = '',
    this.latitude,
    this.longitude,
    this.needsNmea = false,
    this.solution = '',
    this.generator = '',
    this.compression = '',
    this.authentication = '',
    this.fee = '',
    this.bitrate,
  });

  factory NtripSource.fromCsv(String line) {
    final parts = line.split(';');
    if (parts.length < 12) {
      return NtripSource(mountpoint: parts.length > 1 ? parts[1] : 'Unknown');
    }

    return NtripSource(
      mountpoint: parts[1],
      identifier: parts[2],
      format: parts[3],
      formatDetails: parts[4],
      carrier: parts[5],
      system: parts[6],
      network: parts[7],
      country: parts[8],
      latitude: double.tryParse(parts[9]),
      longitude: double.tryParse(parts[10]),
      needsNmea: parts[11] == '1',
      solution: parts.length > 12 ? parts[12] : '',
      generator: parts.length > 13 ? parts[13] : '',
      compression: parts.length > 14 ? parts[14] : '',
      authentication: parts.length > 15 ? parts[15] : '',
      fee: parts.length > 16 ? parts[16] : '',
      bitrate: parts.length > 17 ? int.tryParse(parts[17]) : null,
    );
  }

  @override
  String toString() => '$mountpoint ($format, $system)';
}
