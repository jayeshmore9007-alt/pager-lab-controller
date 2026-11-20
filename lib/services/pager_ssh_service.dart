import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/pager_models.dart';

class PagerSshService {
  PagerSshService({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  static const target = '172.16.52.1';
  static const defaultRemoteRoot = '/root/payloads/user';
  static const _userKey = 'pager_ssh_user';
  static const _passwordKey = 'pager_ssh_password';
  static const _pinKey = 'pager_ssh_fingerprint';
  final FlutterSecureStorage _storage;
  SSHClient? _client;
  String remoteRoot = defaultRemoteRoot;

  static const probes = <String, String>{
    'Kernel': 'uname -srm',
    'Uptime': 'cat /proc/uptime',
    'Load average': 'cat /proc/loadavg',
    'Memory': 'cat /proc/meminfo',
    'Root storage': 'df -P /',
    'Interfaces': 'ip -brief address',
    'Recent logs': 'logread -l 50',
  };

  Future<void> saveCredentials(String username, String password, String fingerprint) async {
    if (username.trim().isEmpty || password.isEmpty || !fingerprint.trim().startsWith('SHA256:')) {
      throw ArgumentError('Provide username, password, and independently verified SHA256 fingerprint.');
    }
    await _storage.write(key: _userKey, value: username.trim());
    await _storage.write(key: _passwordKey, value: password);
    await _storage.write(key: _pinKey, value: fingerprint.trim());
    await disconnect();
  }

  Future<void> forgetCredentials() async {
    await disconnect();
    for (final key in [_userKey, _passwordKey, _pinKey]) { await _storage.delete(key: key); }
  }

  void setRemoteRoot(String value) {
    final path = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (!path.startsWith('/') || path == '/' || path.contains('\\') ||
        path.split('/').any((p) => p == '..') || !path.endsWith('/payloads/user')) {
      throw ArgumentError('Use an absolute directory whose final path is /payloads/user.');
    }
    remoteRoot = path;
  }

  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    client?.close();
  }

  Future<SSHClient> _getClient() async {
    if (_client != null) return _client!;
    final user = await _storage.read(key: _userKey);
    final password = await _storage.read(key: _passwordKey);
    final pin = await _storage.read(key: _pinKey);
    if (user == null || password == null || pin == null) throw StateError('SSH credentials or verified host pin not configured.');
    final socket = await SSHSocket.connect(target, 22).timeout(const Duration(seconds: 8));
    try {
      final client = SSHClient(socket, username: user, onPasswordRequest: () => password,
        onVerifyHostKey: (type, encoded, fingerprint) => fingerprint == pin);
      await client.authenticated.timeout(const Duration(seconds: 10));
      _client = client;
      return client;
    } catch (_) {
      socket.close();
      rethrow;
    }
  }

  Future<PagerSnapshot> snapshot() async {
    final values = <String, ProbeValue>{};
    var connection = DeviceConnection.offline;
    try {
      final client = await _getClient();
      for (final entry in probes.entries) {
        try {
          final bytes = await client.run(entry.value).timeout(const Duration(seconds: 6));
          final output = utf8.decode(bytes, allowMalformed: true).trim();
          values[entry.key] = _validate(entry.key, output);
        } on Object catch (e) {
          values[entry.key] = ProbeValue.unavailable(e is TimeoutException ? 'Probe timed out.' : 'Probe unavailable: $e');
        }
      }
      connection = values.values.any((v) => v.available) ? DeviceConnection.online : DeviceConnection.degraded;
    } on Object catch (e) {
      for (final name in probes.keys) { values[name] = ProbeValue.unavailable('Connection/authentication/host-key failure: $e'); }
      connection = DeviceConnection.offline;
    }
    return PagerSnapshot(connection: connection, observedAt: DateTime.now(), probes: values);
  }

  ProbeValue _validate(String name, String text) {
    if (text.isEmpty || text.toLowerCase().contains('not found') || text.toLowerCase().contains('permission denied') || text.toLowerCase().contains('no such file')) {
      return ProbeValue.unavailable('Unsupported, empty, or inaccessible response.');
    }
    if (name == 'Uptime' && double.tryParse(text.split(RegExp(r'\s+')).first) == null) return ProbeValue.unavailable('Unparseable uptime response.');
    if (name == 'Load average' && text.split(RegExp(r'\s+')).length < 3) return ProbeValue.unavailable('Unparseable load response.');
    if (name == 'Memory' && !text.contains('MemTotal:')) return ProbeValue.unavailable('Unparseable memory response.');
    if (name == 'Root storage' && text.split('\n').length < 2) return ProbeValue.unavailable('Unparseable df response.');
    return ProbeValue.live(text);
  }

  String _safePath(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    if (normalized.isEmpty || normalized.startsWith('/') || normalized.split('/').any((p) => p == '..') || normalized.contains('//')) {
      throw ArgumentError('Invalid relative payload path.');
    }
    return '$remoteRoot/$normalized';
  }

  Future<List<String>> listPayloads() async {
    final client = await _getClient();
    final sftp = await client.sftp().timeout(const Duration(seconds: 8));
    final entries = await sftp.listdir(remoteRoot).timeout(const Duration(seconds: 8));
    return entries.map((e) => e.filename).where((n) => n != '.' && n != '..').toList()..sort();
  }

  Future<List<int>> readFile(String path, {int limit = 2 * 1024 * 1024}) async {
    final client = await _getClient();
    final sftp = await client.sftp().timeout(const Duration(seconds: 8));
    final bytes = await sftp.readFile(_safePath(path)).timeout(const Duration(seconds: 15));
    if (bytes.length > limit) throw StateError('File exceeds the $limit byte read limit.');
    return bytes;
  }

  Future<String?> readText(String name) async {
    if (name != 'catalog.json' && name != 'README.md') throw ArgumentError('Only catalog.json and README.md are allowed.');
    try { return utf8.decode(await readFile(name), allowMalformed: false); } catch (_) { return null; }
  }

  Future<bool> catalogMatches(String path, String expectedHash) async {
    final bytes = await readFile(path);
    return sha256.convert(bytes).toString() == expectedHash.toLowerCase().replaceFirst(RegExp(r'^sha256:'), '');
  }
}
