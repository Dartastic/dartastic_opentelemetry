// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// A processor or reader added while a provider is flushing or shutting
// down must not break the loop. Each provider walks a copy of its list
// across the awaits, so a late add (an SDK built on this one installs
// processors when a license verifies) lands in the list and is reached
// on the next pass, never mid-iteration.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:test/test.dart';

/// A log processor that runs [onFlush] or [onShutdown] once, from inside
/// the provider's loop, then behaves as a no-op.
class _LogProcessorThatAdds extends LogRecordProcessor {
  _LogProcessorThatAdds({this.onFlush, this.onShutdown});
  void Function()? onFlush;
  void Function()? onShutdown;
  int flushes = 0;

  @override
  Future<void> onEmit(ReadWriteLogRecord logRecord, Context? context) async {}

  @override
  Future<void> forceFlush() async {
    flushes++;
    await Future<void>.delayed(Duration.zero);
    final f = onFlush;
    onFlush = null;
    f?.call();
  }

  @override
  Future<void> shutdown() async {
    await Future<void>.delayed(Duration.zero);
    final f = onShutdown;
    onShutdown = null;
    f?.call();
  }
}

class _SpanProcessorThatAdds implements SpanProcessor {
  _SpanProcessorThatAdds({this.onFlush, this.onShutdown});
  void Function()? onFlush;
  void Function()? onShutdown;
  int flushes = 0;

  @override
  Future<void> onStart(Span span, Context? parentContext) async {}

  @override
  Future<void> onEnd(Span span) async {}

  @override
  Future<void> onNameUpdate(Span span, String newName) async {}

  @override
  Future<void> forceFlush() async {
    flushes++;
    await Future<void>.delayed(Duration.zero);
    final f = onFlush;
    onFlush = null;
    f?.call();
  }

  @override
  Future<void> shutdown() async {
    await Future<void>.delayed(Duration.zero);
    final f = onShutdown;
    onShutdown = null;
    f?.call();
  }
}

class _ReaderThatAdds extends MetricReader {
  _ReaderThatAdds({this.onFlush, this.onShutdown});
  void Function()? onFlush;
  void Function()? onShutdown;
  int flushes = 0;

  @override
  Future<MetricData> collect() async => MetricData.empty();

  @override
  Future<bool> forceFlush() async {
    flushes++;
    await Future<void>.delayed(Duration.zero);
    final f = onFlush;
    onFlush = null;
    f?.call();
    return true;
  }

  @override
  Future<bool> shutdown() async {
    await Future<void>.delayed(Duration.zero);
    final f = onShutdown;
    onShutdown = null;
    f?.call();
    return true;
  }
}

void main() {
  setUp(() async {
    await OTel.reset();
    await OTel.initialize(
      serviceName: 'provider-loop-copies-test',
      detectPlatformResources: false,
    );
  });

  tearDown(() async {
    await OTel.shutdown();
    await OTel.reset();
  });

  group('LoggerProvider', () {
    test('forceFlush survives a processor added mid-flush', () async {
      final provider = OTel.loggerProvider();
      final late = _LogProcessorThatAdds();
      provider.addLogRecordProcessor(_LogProcessorThatAdds(
          onFlush: () => provider.addLogRecordProcessor(late)));

      await expectLater(provider.forceFlush(), completes);
      expect(late.flushes, 0, reason: 'added after the pass began');
      await provider.forceFlush();
      expect(late.flushes, 1, reason: 'reached on the next pass');
    });

    test('shutdown survives a processor added mid-shutdown', () async {
      final provider = OTel.loggerProvider();
      provider.addLogRecordProcessor(_LogProcessorThatAdds(
          onShutdown: () =>
              provider.addLogRecordProcessor(_LogProcessorThatAdds())));

      await expectLater(provider.shutdown(), completes);
    });
  });

  group('TracerProvider', () {
    test('forceFlush survives a processor added mid-flush', () async {
      final provider = OTel.tracerProvider();
      final late = _SpanProcessorThatAdds();
      provider.addSpanProcessor(_SpanProcessorThatAdds(
          onFlush: () => provider.addSpanProcessor(late)));

      await expectLater(provider.forceFlush(), completes);
      expect(late.flushes, 0, reason: 'added after the pass began');
      await provider.forceFlush();
      expect(late.flushes, 1, reason: 'reached on the next pass');
    });

    test('shutdown survives a processor added mid-shutdown', () async {
      final provider = OTel.tracerProvider();
      provider.addSpanProcessor(_SpanProcessorThatAdds(
          onShutdown: () =>
              provider.addSpanProcessor(_SpanProcessorThatAdds())));

      await expectLater(provider.shutdown(), completes);
    });
  });

  group('MeterProvider', () {
    test('forceFlush survives a reader added mid-flush', () async {
      final provider = OTel.meterProvider();
      final late = _ReaderThatAdds();
      provider.addMetricReader(
          _ReaderThatAdds(onFlush: () => provider.addMetricReader(late)));

      await expectLater(provider.forceFlush(), completes);
      expect(late.flushes, 0, reason: 'added after the pass began');
      await provider.forceFlush();
      expect(late.flushes, 1, reason: 'reached on the next pass');
    });

    test('shutdown survives a reader added mid-shutdown', () async {
      final provider = OTel.meterProvider();
      provider.addMetricReader(_ReaderThatAdds(
          onShutdown: () => provider.addMetricReader(_ReaderThatAdds())));

      await expectLater(provider.shutdown(), completes);
    });
  });
}
