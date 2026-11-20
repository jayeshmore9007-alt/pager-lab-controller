import 'package:flutter/foundation.dart';

enum DeviceConnection { online, degraded, offline }
enum MonitorState { idle, armed, monitoring, stopped, auditReady }

class ProbeValue {
  const ProbeValue.live(this.value) : available = true, reason = null;
  const ProbeValue.unavailable(this.reason) : available = false, value = null;
  final bool available;
  final String? value;
  final String? reason;
}

class PagerSnapshot {
  const PagerSnapshot({required this.connection, required this.observedAt, required this.probes});
  final DeviceConnection connection;
  final DateTime observedAt;
  final Map<String, ProbeValue> probes;
}

@immutable
class CatalogEntry {
  const CatalogEntry({required this.path, this.name, this.purpose, this.category, this.risk, this.scope, this.impact, this.artifacts, this.cleanup, this.reviewed, this.sha256, this.prerequisites = const []});
  final String path;
  final String? name, purpose, category, risk, scope, impact, artifacts, cleanup, sha256;
  final DateTime? reviewed;
  final List<String> prerequisites;
  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
    path: j['path'] as String,
    name: j['name'] as String?, purpose: j['purpose'] as String?, category: j['category'] as String?, risk: j['risk'] as String?,
    scope: j['scope'] as String?, impact: j['impact'] as String?, artifacts: j['artifacts'] as String?, cleanup: j['cleanup'] as String?,
    sha256: j['sha256'] as String?, reviewed: DateTime.tryParse(j['reviewed'] as String? ?? ''),
    prerequisites: j['prerequisites'] is List ? (j['prerequisites'] as List).map((e) => '$e').toList() : const [],
  );
}

class AuditRecord {
  const AuditRecord(this.at, this.kind, this.message, {this.severity = 'INFO'});
  final DateTime at;
  final String kind, message, severity;
  Map<String, Object?> toJson() => {'at': at.toUtc().toIso8601String(), 'kind': kind, 'severity': severity, 'message': message};
  factory AuditRecord.fromJson(Map<String, dynamic> j) => AuditRecord(DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(), '${j['kind'] ?? 'event'}', '${j['message'] ?? ''}', severity: '${j['severity'] ?? 'INFO'}');
}
