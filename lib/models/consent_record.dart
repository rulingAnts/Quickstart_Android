/// Represents the consent information logged for ethical data collection
class ConsentRecord {
  /// Database row id; null until inserted so SQLite can auto-assign one.
  final int? id;
  final DateTime timestamp;
  final String deviceId;
  final ConsentType type;
  final ConsentResponse response;
  final String? verbalConsentFilename; // If verbal consent was recorded

  ConsentRecord({
    this.id,
    required this.timestamp,
    required this.deviceId,
    required this.type,
    required this.response,
    this.verbalConsentFilename,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'device_id': deviceId,
      'type': type.toString().split('.').last,
      'response': response.toString().split('.').last,
      'verbal_consent_filename': verbalConsentFilename,
    };
  }

  factory ConsentRecord.fromMap(Map<String, dynamic> map) {
    return ConsentRecord(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      deviceId: map['device_id'] as String,
      type: ConsentType.values.firstWhere(
        (e) => e.toString().split('.').last == map['type'],
      ),
      response: ConsentResponse.values.firstWhere(
        (e) => e.toString().split('.').last == map['response'],
      ),
      verbalConsentFilename: map['verbal_consent_filename'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'device_id': deviceId,
      'consent_type': type.toString().split('.').last,
      'consent_response': response.toString().split('.').last,
      'verbal_consent_file': verbalConsentFilename,
    };
  }
}

enum ConsentType {
  verbal,
  written,
}

enum ConsentResponse {
  assent,
  decline,
}
