class SoundSettings {
  bool hardMute;
  bool rollingEnabled;
  bool rolledEnabled;
  int queueDepth;
  String? rollingClipId;
  String? rolledClipId;

  SoundSettings({
    this.hardMute = false,
    this.rollingEnabled = true,
    this.rolledEnabled = true,
    this.queueDepth = 3,
    this.rollingClipId,
    this.rolledClipId,
  });

  Map<String, dynamic> toJson() => {
    'hardMute': hardMute,
    'rollingEnabled': rollingEnabled,
    'rolledEnabled': rolledEnabled,
    'queueDepth': queueDepth,
    if (rollingClipId != null) 'rollingClipId': rollingClipId,
    if (rolledClipId != null) 'rolledClipId': rolledClipId,
  };

  factory SoundSettings.fromJson(Map<String, dynamic> json) => SoundSettings(
    hardMute: json['hardMute'] as bool? ?? false,
    rollingEnabled: json['rollingEnabled'] as bool? ?? true,
    rolledEnabled: json['rolledEnabled'] as bool? ?? true,
    queueDepth: json['queueDepth'] as int? ?? 3,
    rollingClipId: json['rollingClipId'] as String?,
    rolledClipId: json['rolledClipId'] as String?,
  );
}
