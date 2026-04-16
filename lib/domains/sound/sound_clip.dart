class SoundClip {
  final String id;
  final String name;
  final String extension;

  SoundClip({required this.id, required this.name, required this.extension});

  String get filename => '$id.$extension';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'extension': extension};

  factory SoundClip.fromJson(Map<String, dynamic> json) => SoundClip(
    id: json['id'] as String,
    name: json['name'] as String,
    extension: json['extension'] as String,
  );
}
