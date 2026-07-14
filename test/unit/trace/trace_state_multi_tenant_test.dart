// W3C Trace Context multi-tenant tracestate keys ({tenant-id}@{system-id})
// — extension surface over the released API's existing validation.
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:test/test.dart';

void main() {
  setUp(() async {
    await OTel.reset();
    await OTel.initialize(
      serviceName: 'test-service',
      serviceVersion: '1.0.0',
      endpoint: 'http://localhost:4317',
    );
  });

  group('multiTenantKey', () {
    test('builds the spec form; digit-leading tenants legal', () {
      expect(TraceStateMultiTenant.multiTenantKey('acme', 'dartastic'),
          'acme@dartastic');
      expect(TraceStateMultiTenant.multiTenantKey('0mg', 'dt'), '0mg@dt');
    });

    test('throws on grammar violations (fail fast)', () {
      expect(() => TraceStateMultiTenant.multiTenantKey('BAD', 'dartastic'),
          throwsArgumentError);
      expect(() => TraceStateMultiTenant.multiTenantKey('acme', '1sys'),
          throwsArgumentError);
      expect(() => TraceStateMultiTenant.multiTenantKey('acme', 'a' * 15),
          throwsArgumentError);
      expect(() => TraceStateMultiTenant.multiTenantKey('a' * 242, 'dt'),
          throwsArgumentError);
    });
  });

  test('put/get round-trip + W3C header serialization', () {
    final ts = OTel.traceState({})
        .putMultiTenant('acme', 'dartastic', 'affinity')
        .put('simple', 'x');
    expect(ts.getMultiTenant('acme', 'dartastic'), 'affinity');
    expect(ts.toString(), contains('acme@dartastic=affinity'));
    final parsed = TraceState.fromString(ts.toString());
    expect(parsed.getMultiTenant('acme', 'dartastic'), 'affinity');
  });

  test('tenantsForSystem separates systems; unmodifiable', () {
    final ts = OTel.traceState({})
        .putMultiTenant('acme', 'dartastic', 'a')
        .putMultiTenant('globex', 'dartastic', 'b')
        .putMultiTenant('acme', 'dt', 'c')
        .put('plain', 'd');
    expect(ts.tenantsForSystem('dartastic'), {'acme': 'a', 'globex': 'b'});
    expect(ts.tenantsForSystem('dt'), {'acme': 'c'});
    expect(ts.tenantsForSystem('none'), isEmpty);
    expect(() => ts.tenantsForSystem('dt')['x'] = 'y', throwsUnsupportedError);
  });
}
