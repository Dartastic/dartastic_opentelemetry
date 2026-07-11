// Licensed under the Apache License, Version 2.0
// Copyright 2026, Michael Bushe, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    show TraceState;

/// First-class support for the W3C Trace Context MULTI-TENANT tracestate key
/// form — `{tenant-id}@{system-id}` ("in the case of multi-tenant vendors,
/// the key SHOULD be in this format").
///
/// OpenTelemetry surfaces no API for this form anywhere (upstream gap —
/// tracked for a spec proposal). The Dartastic API package has validated and
/// accepted these keys since 1.0.0-beta.7, so this extension is pure
/// ergonomics over the released API: build/validate keys, typed get/put, and
/// per-system tenant enumeration.
///
/// Dartastic-maintained-release addition (pub.dartastic.io); the same surface
/// is queued for the canonical API post-donation.
///
/// NOTE ON PROPAGATION: `tracestate` flows to EVERY downstream hop, including
/// third-party services the instrumented app calls. Stamping tenant identity
/// is therefore an explicit, per-call decision — nothing in the SDK writes a
/// multi-tenant entry automatically.
extension TraceStateMultiTenant on TraceState {
  // W3C tracestate grammars for the multi-tenant key parts.
  static final RegExp _tenantIdFormat =
      RegExp(r'^[a-z0-9][a-z0-9_\-*/]{0,240}$');
  static final RegExp _systemIdFormat = RegExp(r'^[a-z][a-z0-9_\-*/]{0,13}$');

  /// The W3C multi-tenant tracestate key for ([tenantId], [systemId]) —
  /// `tenant-id@system-id`. Throws [ArgumentError] when either part violates
  /// the spec grammar (tenant-id: `lcalpha / DIGIT` then up to 240 of
  /// `lcalpha / DIGIT / "_" / "-" / "*" / "/"`; system-id: `lcalpha` then up
  /// to 13 of the same set). Fail fast — no silent mangling.
  static String multiTenantKey(String tenantId, String systemId) {
    if (!_tenantIdFormat.hasMatch(tenantId)) {
      throw ArgumentError.value(
          tenantId, 'tenantId', 'Invalid W3C tracestate tenant-id');
    }
    if (!_systemIdFormat.hasMatch(systemId)) {
      throw ArgumentError.value(
          systemId, 'systemId', 'Invalid W3C tracestate system-id');
    }
    return '$tenantId@$systemId';
  }

  /// A new [TraceState] with the multi-tenant entry
  /// `tenantId@systemId=value` added (or updated). Same freshness/limit
  /// semantics as [TraceState.put].
  TraceState putMultiTenant(String tenantId, String systemId, String value) =>
      put(multiTenantKey(tenantId, systemId), value);

  /// The value of the multi-tenant entry for ([tenantId], [systemId]), or
  /// null when absent.
  String? getMultiTenant(String tenantId, String systemId) =>
      get('$tenantId@$systemId');

  /// Every multi-tenant entry belonging to [systemId], as tenant-id → value.
  /// Empty when the system has no entries (never null).
  Map<String, String> tenantsForSystem(String systemId) {
    final suffix = '@$systemId';
    return Map.unmodifiable({
      for (final e in entries.entries)
        if (e.key.endsWith(suffix) &&
            e.key.indexOf('@') == e.key.length - suffix.length)
          e.key.substring(0, e.key.length - suffix.length): e.value,
    });
  }
}
