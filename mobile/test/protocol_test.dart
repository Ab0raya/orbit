import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/protocol/messages/orbit_request.dart';
import 'package:orbit_mobile/protocol/messages/orbit_response.dart';
import 'package:orbit_mobile/protocol/messages/orbit_event.dart';
import 'package:orbit_mobile/protocol/messages/orbit_error.dart';
import 'package:orbit_mobile/protocol/models/agent_status.dart';
import 'package:orbit_mobile/protocol/models/system_info.dart';
import 'package:orbit_mobile/protocol/models/server_info.dart';
import 'package:orbit_mobile/protocol/models/pairing_models.dart';
import 'package:orbit_mobile/protocol/models/terminal_models.dart';

void main() {
  group('Protocol Envelopes', () {
    test('OrbitRequest serializes correctly according to v1.0 spec', () {
      const req = OrbitRequest(
        id: 'req_123',
        action: 'system.info',
        payload: {'filter': 'network'},
      );

      final json = req.toJson();
      expect(json['id'], 'req_123');
      expect(json['type'], 'request');
      expect(json['action'], 'system.info');
      expect(json['payload'], {'filter': 'network'});
    });

    test('OrbitResponse deserializes success envelope', () {
      final json = {
        'id': 'req_456',
        'type': 'response',
        'action': 'ping',
        'success': true,
        'payload': {'timestamp': 1788472015},
      };

      final res = OrbitResponse.fromJson(json);
      expect(res.id, 'req_456');
      expect(res.action, 'ping');
      expect(res.success, true);
      expect(res.payload?['timestamp'], 1788472015);
      expect(res.error, isNull);
    });

    test('OrbitResponse deserializes error envelope with OrbitError', () {
      final json = {
        'id': 'req_789',
        'type': 'response',
        'action': 'system.info',
        'success': false,
        'error': {
          'code': 'UNAUTHORIZED',
          'message': 'Device must be paired to access this resource.',
        },
      };

      final res = OrbitResponse.fromJson(json);
      expect(res.id, 'req_789');
      expect(res.success, false);
      expect(res.error, isNotNull);
      expect(res.error!.code, 'UNAUTHORIZED');
      expect(res.error!.message, contains('Device must be paired'));
    });

    test('OrbitError model roundtrips', () {
      const err = OrbitError(code: 'RATE_LIMITED', message: 'Too many attempts');
      expect(err.code, 'RATE_LIMITED');
      expect(err.toJson()['code'], 'RATE_LIMITED');
      final fromJson = OrbitError.fromJson(err.toJson());
      expect(fromJson.message, 'Too many attempts');
    });

    test('ServerInfo parses correctly', () {
      final json = {
        'port': 4371,
        'isListening': true,
        'bindAddress': '0.0.0.0',
        'connectedClients': 1,
      };
      final srv = ServerInfo.fromJson(json);
      expect(srv.port, 4371);
      expect(srv.isListening, true);
      expect(srv.bindAddress, '0.0.0.0');
      expect(srv.connectedClients, 1);
    });

    test('OrbitEvent deserializes welcome, device.paired, and terminal.output', () {
      final welcomeJson = {
        'type': 'event',
        'event': 'welcome',
        'payload': {'server': 'Orbit Desktop Agent', 'version': '0.1.0', 'protocol': '1.0'},
      };
      final welcomeEv = OrbitEvent.fromJson(welcomeJson);
      expect(welcomeEv.event, 'welcome');
      expect(welcomeEv.payload['server'], 'Orbit Desktop Agent');

      final outputJson = {
        'type': 'event',
        'event': 'terminal.output',
        'payload': {'sessionId': 'term_01', 'data': 'Hello Orbit\n'},
      };
      final outputEv = OrbitEvent.fromJson(outputJson);
      expect(outputEv.event, 'terminal.output');
      expect(outputEv.payload['sessionId'], 'term_01');
      expect(outputEv.payload['data'], 'Hello Orbit\n');
    });
  });

  group('Protocol Models', () {
    test('AgentStatus parses and formats uptime correctly', () {
      final json = {
        'status': 'online',
        'uptimeSeconds': 3665,
        'version': '0.1.0',
        'connectedDevices': 2,
      };
      final status = AgentStatus.fromJson(json);
      expect(status.status, 'online');
      expect(status.uptimeSeconds, 3665);
      expect(status.formattedUptime, '01:01:05');
      expect(status.connectedDevices, 2);
    });

    test('SystemInfo parses host and network adapters', () {
      final json = {
        'hostname': 'Dev-Station',
        'os': 'Linux',
        'osVersion': '6.8.0',
        'architecture': 'x86_64',
        'primaryIp': '192.168.1.100',
        'network': [
          {
            'interface_name': 'wlan0',
            'ip': '192.168.1.100',
            'is_ipv4': true,
            'is_loopback': false,
          }
        ],
      };
      final info = SystemInfo.fromJson(json);
      expect(info.hostname, 'Dev-Station');
      expect(info.os, 'Linux');
      expect(info.network.length, 1);
      expect(info.network.first.interfaceName, 'wlan0');
      expect(info.network.first.ip, '192.168.1.100');
    });

    test('PairingPayload and PairingResult roundtrip', () {
      const payload = PairingPayload(
        code: '842917',
        name: 'Pixel 8',
        platform: 'android',
      );
      final json = payload.toJson();
      expect(json['code'], '842917');
      expect(json['name'], 'Pixel 8');
      expect(json['platform'], 'android');

      final resJson = {'paired': true, 'deviceId': 'dev_abc123'};
      final res = PairingResult.fromJson(resJson);
      expect(res.paired, true);
      expect(res.deviceId, 'dev_abc123');
    });

    test('Terminal models parse properly', () {
      final summaryJson = {
        'sessionId': 'term_abc',
        'status': 'running',
        'cwd': '/home/dev',
        'shell': '/bin/bash',
        'rows': 30,
        'cols': 120,
        'createdAt': 100,
        'lastActivityAt': 200,
        'ownerDeviceId': 'dev_01',
      };
      final summary = TerminalSessionSummary.fromJson(summaryJson);
      expect(summary.sessionId, 'term_abc');
      expect(summary.isRunning, true);
      expect(summary.isExited, false);
      expect(summary.rows, 30);
      expect(summary.cols, 120);

      const input = TerminalInputPayload(sessionId: 'term_abc', data: 'ls\n');
      expect(input.toJson()['data'], 'ls\n');

      const resize = TerminalResizePayload(sessionId: 'term_abc', cols: 100, rows: 40);
      expect(resize.toJson()['cols'], 100);
      expect(resize.toJson()['rows'], 40);
    });
  });
}
