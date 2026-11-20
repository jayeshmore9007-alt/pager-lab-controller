import '../models/pager_models.dart';

/// Deterministic local assistant modules. No network model, shell, or tools.
class TelemetryHealthAnalyst {
  String answer(PagerSnapshot? snapshot) {
    if (snapshot == null) return 'No live snapshot is available. Connect to the lab Pager and refresh.';
    if (snapshot.connection != DeviceConnection.online) return 'Connection is ${snapshot.connection.name.toUpperCase()}; values may be unavailable. No stale or simulated readings are shown.';
    final unavailable = snapshot.probes.entries.where((e) => !e.value.available).map((e) => e.key).toList();
    return unavailable.isEmpty ? 'Latest read-only snapshot received at ${snapshot.observedAt.toLocal()}. All configured probes returned parseable output; review raw values on the Status screen.' : 'Snapshot received at ${snapshot.observedAt.toLocal()}. Unavailable probes: ${unavailable.join(', ')}. Unsupported readings are not estimated.';
  }
}

class PayloadCatalogExplainer {
  String answer(CatalogEntry? entry, {required bool verified, required String? unavailableReason}) {
    if (entry == null || !verified) return 'Unclassified — review required. ${unavailableReason ?? 'Catalog entry is missing, outdated, mismatched, or could not be verified.'} This is not a safety assessment; no file is executed.';
    return '${entry.name ?? entry.path}: ${entry.purpose ?? 'No purpose description.'} Category: ${entry.category ?? 'unspecified'}. Risk label: ${entry.risk ?? 'unspecified'}. Cleanup notes: ${entry.cleanup ?? 'not provided'}. Human-authored metadata only; not a safety certification. Nothing is executed.';
  }
}

class AuditMonitoringSummarizer {
  String answer(List<AuditRecord> records, {required String status, required String countdown}) {
    if (records.isEmpty) return 'Monitoring: $status. Remaining time: $countdown. No audit events recorded.';
    final recent = records.reversed.take(5).map((e) => '${e.severity} ${e.kind}: ${e.message}').join('\n');
    return 'Monitoring: $status. Remaining time: $countdown. Recent audit events:\n$recent';
  }
}
