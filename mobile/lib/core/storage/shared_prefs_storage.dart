import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_storage.dart';

class SharedPrefsStorage implements ILocalStorage {
  static const _keyPairedDevice = 'orbit_paired_device';
  static const _keyRecentHost = 'orbit_recent_host';
  static const _keyRecentPort = 'orbit_recent_port';
  static const _keyInstallationDeviceId = 'orbit_installation_device_id';

  final SharedPreferences _prefs;

  SharedPrefsStorage(this._prefs);

  static Future<SharedPrefsStorage> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsStorage(prefs);
  }

  @override
  Future<void> savePairedDevice(PairedDeviceRecord record) async {
    final jsonStr = jsonEncode(record.toJson());
    await _prefs.setString(_keyPairedDevice, jsonStr);
    await saveRecentConnection(record.pcAddress, record.pcPort);
  }

  @override
  Future<PairedDeviceRecord?> getPairedDevice() async {
    final jsonStr = _prefs.getString(_keyPairedDevice);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return PairedDeviceRecord.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearPairedDevice() async {
    await _prefs.remove(_keyPairedDevice);
  }

  @override
  Future<void> saveRecentConnection(String host, int port) async {
    await _prefs.setString(_keyRecentHost, host);
    await _prefs.setInt(_keyRecentPort, port);
  }

  @override
  Future<Map<String, dynamic>?> getRecentConnection() async {
    final host = _prefs.getString(_keyRecentHost);
    final port = _prefs.getInt(_keyRecentPort);
    if (host == null) return null;
    return {'host': host, 'port': port ?? 4371};
  }

  @override
  Future<String> getOrCreateInstallationDeviceId() async {
    final existing = _prefs.getString(_keyInstallationDeviceId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    // Generate stable client installation ID
    final randomPart = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final newId = 'dev_mob_$randomPart';
    await _prefs.setString(_keyInstallationDeviceId, newId);
    return newId;
  }

  static const _keyShowHiddenFiles = 'orbit_files_show_hidden';

  @override
  Future<void> saveShowHiddenFiles(bool show) async {
    await _prefs.setBool(_keyShowHiddenFiles, show);
  }

  @override
  Future<bool> getShowHiddenFiles() async {
    return _prefs.getBool(_keyShowHiddenFiles) ?? false;
  }
}
