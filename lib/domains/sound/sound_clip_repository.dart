import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'sound_clip.dart';
import 'sound_settings.dart';

class SoundClipRepository {
  static const _libraryKey = 'sound_clips_library';
  static const _settingsKey = 'sound_settings';
  static const _uuid = Uuid();

  Future<Directory> _getClipsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final clipsDir = Directory('${dir.path}/sound_clips');
    if (!await clipsDir.exists()) await clipsDir.create(recursive: true);
    return clipsDir;
  }

  Future<String> pathForClip(SoundClip clip) async {
    final dir = await _getClipsDir();
    return '${dir.path}/${clip.filename}';
  }

  Future<List<SoundClip>> getClips() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_libraryKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => SoundClip.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _saveClips(List<SoundClip> clips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_libraryKey, jsonEncode(clips.map((c) => c.toJson()).toList()));
  }

  Future<SoundClip?> findByName(String name) async {
    final clips = await getClips();
    return clips.firstWhereOrNull((c) => c.name.toLowerCase() == name.toLowerCase());
  }

  Future<SoundClip?> findById(String id) async {
    final clips = await getClips();
    return clips.firstWhereOrNull((c) => c.id == id);
  }

  Future<SoundClip> importClip(String sourcePath, String name) async {
    final ext = sourcePath.contains('.')
        ? sourcePath.split('.').last.toLowerCase()
        : 'audio';
    final id = _uuid.v4();
    final clip = SoundClip(id: id, name: name, extension: ext);
    final destPath = await pathForClip(clip);
    await File(sourcePath).copy(destPath);
    final clips = await getClips();
    clips.add(clip);
    await _saveClips(clips);
    return clip;
  }

  Future<void> renameClip(String id, String newName) async {
    final clips = await getClips();
    final idx = clips.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    clips[idx] = SoundClip(id: clips[idx].id, name: newName, extension: clips[idx].extension);
    await _saveClips(clips);
  }

  Future<void> deleteClip(String id) async {
    final clips = await getClips();
    final clip = clips.firstWhereOrNull((c) => c.id == id);
    if (clip == null) return;
    final path = await pathForClip(clip);
    final file = File(path);
    if (await file.exists()) await file.delete();
    clips.removeWhere((c) => c.id == id);
    await _saveClips(clips);
  }

  Future<SoundSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return SoundSettings();
    return SoundSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(SoundSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}

extension _ListFirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
