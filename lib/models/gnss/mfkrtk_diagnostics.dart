class MfkRtkDiagnostics {
  final bool isConnected;
  final String deviceName;
  final String? firmwareVersion;
  
  final int totalRxBytes;
  final double rxBytesPerSecond;
  
  final int nmeaMessages;
  final double nmeaMessagesPerSecond;
  
  final int binaryBytes;
  final int unknownBytes;
  
  final int rtcmTxBytes;
  final int rtcmPacketsSent;
  final int rtcmErrors;
  
  final DateTime? lastMessageTime;
  final String? lastNmeaSentence;
  final String? lastAsciiPreview;
  final String? lastRawHex;
  
  final int reconnectCount;
  final int writeErrors;
  
  final bool isLogging;
  final String? logFilePath;
  final int logFileSize;
  final Duration logDuration;

  MfkRtkDiagnostics({
    this.isConnected = false,
    this.deviceName = 'Unknown',
    this.firmwareVersion,
    this.totalRxBytes = 0,
    this.rxBytesPerSecond = 0.0,
    this.nmeaMessages = 0,
    this.nmeaMessagesPerSecond = 0.0,
    this.binaryBytes = 0,
    this.unknownBytes = 0,
    this.rtcmTxBytes = 0,
    this.rtcmPacketsSent = 0,
    this.rtcmErrors = 0,
    this.lastMessageTime,
    this.lastNmeaSentence,
    this.lastAsciiPreview,
    this.lastRawHex,
    this.reconnectCount = 0,
    this.writeErrors = 0,
    this.isLogging = false,
    this.logFilePath,
    this.logFileSize = 0,
    this.logDuration = Duration.zero,
  });

  MfkRtkDiagnostics copyWith({
    bool? isConnected,
    String? deviceName,
    String? firmwareVersion,
    int? totalRxBytes,
    double? rxBytesPerSecond,
    int? nmeaMessages,
    double? nmeaMessagesPerSecond,
    int? binaryBytes,
    int? unknownBytes,
    int? rtcmTxBytes,
    int? rtcmPacketsSent,
    int? rtcmErrors,
    DateTime? lastMessageTime,
    String? lastNmeaSentence,
    String? lastAsciiPreview,
    String? lastRawHex,
    int? reconnectCount,
    int? writeErrors,
    bool? isLogging,
    String? logFilePath,
    int? logFileSize,
    Duration? logDuration,
  }) {
    return MfkRtkDiagnostics(
      isConnected: isConnected ?? this.isConnected,
      deviceName: deviceName ?? this.deviceName,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      totalRxBytes: totalRxBytes ?? this.totalRxBytes,
      rxBytesPerSecond: rxBytesPerSecond ?? this.rxBytesPerSecond,
      nmeaMessages: nmeaMessages ?? this.nmeaMessages,
      nmeaMessagesPerSecond: nmeaMessagesPerSecond ?? this.nmeaMessagesPerSecond,
      binaryBytes: binaryBytes ?? this.binaryBytes,
      unknownBytes: unknownBytes ?? this.unknownBytes,
      rtcmTxBytes: rtcmTxBytes ?? this.rtcmTxBytes,
      rtcmPacketsSent: rtcmPacketsSent ?? this.rtcmPacketsSent,
      rtcmErrors: rtcmErrors ?? this.rtcmErrors,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastNmeaSentence: lastNmeaSentence ?? this.lastNmeaSentence,
      lastAsciiPreview: lastAsciiPreview ?? this.lastAsciiPreview,
      lastRawHex: lastRawHex ?? this.lastRawHex,
      reconnectCount: reconnectCount ?? this.reconnectCount,
      writeErrors: writeErrors ?? this.writeErrors,
      isLogging: isLogging ?? this.isLogging,
      logFilePath: logFilePath ?? this.logFilePath,
      logFileSize: logFileSize ?? this.logFileSize,
      logDuration: logDuration ?? this.logDuration,
    );
  }
}
