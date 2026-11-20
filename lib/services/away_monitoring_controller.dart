import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../models/pager_models.dart';
import 'pager_ssh_service.dart';

class AwayMonitoringController extends ChangeNotifier {
  AwayMonitoringController(this.pager, {FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final PagerSshService pager;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth = LocalAuthentication();
  static const _auditKey = 'pager_audit_json_v1';
  static const fixedScope = 'Authorized personal lab device 172.16.52.1';
  MonitorState state = MonitorState.idle;
  DateTime? deadline;
  Timer? _timer;
  bool _polling = false;
  String? lastError;
  List<AuditRecord> records = [];
  int durationMinutes = 30;
  String labContext = '';

  Future<void> loadAudit() async {
    final raw = await _storage.read(key: _auditKey);
    if (raw != null) {
      try { records = (jsonDecode(raw) as List).whereType<Map>().map((e) => AuditRecord.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) { records = []; }
    }
    notifyListeners();
  }

  Future<bool> arm() async {
    if (labContext.trim().isEmpty || durationMinutes < 30 || durationMinutes > 480) return false;
    state = MonitorState.armed; notifyListeners();
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) { state = MonitorState.stopped; lastError = 'Device authentication is not supported; monitoring not started.'; notifyListeners(); return false; }
      final passed = await _auth.authenticate(localizedReason: 'Confirm starting read-only monitoring of your authorized lab Pager.', options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true));
      if (!passed) { state = MonitorState.stopped; lastError = 'Authentication cancelled or failed.'; notifyListeners(); return false; }
      final initial = await pager.snapshot();
      if (initial.connection != DeviceConnection.online) { state = MonitorState.stopped; lastError = 'Pager is not ONLINE; fail-closed start refused.'; await _log('monitor', lastError!, 'WARN'); notifyListeners(); return false; }
      deadline = DateTime.now().add(Duration(minutes: durationMinutes));
      state = MonitorState.monitoring; lastError = null;
      await _log('monitor', 'Read-only away monitoring started. Scope: $fixedScope. Context: ${labContext.trim()}.', 'INFO');
      _timer?.cancel(); _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      notifyListeners(); return true;
    } catch (e) { await stop('Arming failed closed: $e'); return false; }
  }

  Future<void> _tick() async {
    if (state != MonitorState.monitoring || _polling) return;
    if (deadline == null || !DateTime.now().isBefore(deadline!)) { await stop('Monitoring duration expired.'); return; }
    _polling = true;
    try {
      final snapshot = await pager.snapshot();
      if (snapshot.connection != DeviceConnection.online) { await stop('Connection/authentication/host-key uncertain; auto-stopped.'); return; }
      for (final entry in snapshot.probes.entries) {
        if (!entry.value.available) continue;
        if (entry.key == 'Root storage') {
          final match = RegExp(r'(\d+)%').allMatches(entry.value.value ?? '').lastOrNull;
          final percent = int.tryParse(match?.group(1) ?? '');
          if (percent != null && percent >= 90) await _log('alert', 'Storage pressure: root filesystem reports $percent% used.', 'HIGH');
        }
        if (entry.key == 'Recent logs' && RegExp(r'\b(critical|emergency|panic)\b', caseSensitive: false).hasMatch(entry.value.value ?? '')) {
          await _log('alert', 'Critical keyword observed in bounded recent device logs.', 'HIGH');
        }
      }
    } catch (e) { await stop('Monitoring poll failed closed: $e'); }
    finally { _polling = false; notifyListeners(); }
  }

  Future<void> stop(String reason) async {
    _timer?.cancel(); _timer = null; deadline = null;
    final wasActive = state == MonitorState.monitoring || state == MonitorState.armed;
    state = MonitorState.stopped; lastError = reason;
    await pager.disconnect();
    if (wasActive) await _log('monitor', reason, 'WARN');
    notifyListeners();
  }

  Future<void> stopForBackground() async {
    if (state == MonitorState.monitoring || state == MonitorState.armed) await stop('App left foreground; foreground-only monitor stopped.');
  }

  Duration get remaining => deadline == null ? Duration.zero : deadline!.difference(DateTime.now()).isNegative ? Duration.zero : deadline!.difference(DateTime.now());
  Future<void> _log(String kind, String message, String severity) async {
    records.add(AuditRecord(DateTime.now(), kind, message, severity: severity));
    if (records.length > 1000) records = records.sublist(records.length - 1000);
    await _storage.write(key: _auditKey, value: jsonEncode(records.map((r) => r.toJson()).toList()));
  }
  Future<void> appendAudit(String kind, String message, {String severity = 'INFO'}) => _log(kind, message, severity);
  Future<void> deleteAudit() async { records.clear(); await _storage.delete(key: _auditKey); notifyListeners(); }
  String exportAuditJson() => const JsonEncoder.withIndent('  ').convert(records.map((r) => r.toJson()).toList());
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

extension _LastOrNull<T> on Iterable<T> { T? get lastOrNull => isEmpty ? null : last; }
