import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/storage/local_storage.dart';

class InMemoryStorage implements ILocalStorage {
  PairedDeviceRecord? _record;
  Map<String, dynamic>? _recent;

  @override
  Future<void> savePairedDevice(PairedDeviceRecord record) async {
    _record = record;
  }

  @override
  Future<PairedDeviceRecord?> getPairedDevice() async => _record;

  @override
  Future<void> clearPairedDevice() async {
    _record = null;
  }

  @override
  Future<void> saveRecentConnection(String host, int port) async {
    _recent = {'host': host, 'port': port};
  }

  @override
  Future<Map<String, dynamic>?> getRecentConnection() async => _recent;

  String? _installationId;

  @override
  Future<String> getOrCreateInstallationDeviceId() async {
    _installationId ??= 'dev_test_stable_123';
    return _installationId!;
  }

  bool _showHiddenFiles = false;

  @override
  Future<void> saveShowHiddenFiles(bool show) async {
    _showHiddenFiles = show;
  }

  @override
  Future<bool> getShowHiddenFiles() async => _showHiddenFiles;
}

void main() {
  group('LocalStorage & PairedDeviceRecord', () {
    test('PairedDeviceRecord serialization and deserialization', () {
      const record = PairedDeviceRecord(
        deviceId: 'dev_test_123',
        pcAddress: '192.168.1.50',
        pcPort: 4371,
        pcDisplayName: 'Workstation',
        mobileDisplayName: 'My Phone',
        pairedAt: 1788470000,
      );

      final json = record.toJson();
      expect(json['deviceId'], 'dev_test_123');
      expect(json['pcAddress'], '192.168.1.50');
      expect(json['pcPort'], 4371);

      final fromJson = PairedDeviceRecord.fromJson(json);
      expect(fromJson.deviceId, record.deviceId);
      expect(fromJson.pcAddress, record.pcAddress);
      expect(fromJson.pcPort, record.pcPort);
      expect(fromJson.pcDisplayName, record.pcDisplayName);
    });

    test('InMemoryStorage saves, retrieves, and clears paired device', () async {
      final storage = InMemoryStorage();
      expect(await storage.getPairedDevice(), isNull);

      const record = PairedDeviceRecord(
        deviceId: 'dev_999',
        pcAddress: '127.0.0.1',
        pcPort: 4371,
        pcDisplayName: 'PC',
        mobileDisplayName: 'Phone',
        pairedAt: 123456,
      );

      await storage.savePairedDevice(record);
      final retrieved = await storage.getPairedDevice();
      expect(retrieved, isNotNull);
      expect(retrieved!.deviceId, 'dev_999');

      await storage.clearPairedDevice();
      expect(await storage.getPairedDevice(), isNull);
    });
  });
}
