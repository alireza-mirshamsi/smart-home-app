class DeviceKey {
  final String status;
  final String relayNumber;
  final String deviceType;
  final String sourceId;
  final String destinationId;
  final String packetNumber;
  final String powerStatus;

  DeviceKey({
    required this.status,
    required this.relayNumber,
    required this.deviceType,
    required this.sourceId,
    required this.destinationId,
    required this.packetNumber,
    required this.powerStatus,
  });

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'relayNumber': relayNumber,
      'deviceType': deviceType,
      'sourceId': sourceId,
      'destinationId': destinationId,
      'packetNumber': packetNumber,
      'powerStatus': powerStatus,
    };
  }

  factory DeviceKey.fromMap(Map<String, dynamic> map) {
    return DeviceKey(
      status: map['status']?.toString() ?? '',
      relayNumber: map['relayNumber']?.toString() ?? '',
      deviceType: map['deviceType']?.toString() ?? '',
      sourceId: map['sourceId']?.toString() ?? '',
      destinationId: map['destinationId']?.toString() ?? '',
      packetNumber: map['packetNumber']?.toString() ?? '',
      powerStatus: map['powerStatus']?.toString() ?? '',
    );
  }
}
