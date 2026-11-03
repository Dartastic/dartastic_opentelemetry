// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// Tests for ExtendedSpanProcessor.onEnding, per the OpenTelemetry Trace SDK
// spec (Span processor, OnEnding):
// - the end timestamp is computed before the calls, so they are not part
//   of the span's duration
// - the span is still mutable while they run
// - they run in registration order, before any processor's onEnd
// - only a recording span gets them

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:test/test.dart';

import '../../testing_utils/in_memory_span_exporter.dart';

/// A clock one second further on at every read.
class _SteppingTimeProvider implements TimeProvider {
  int reads = 0;

  @override
  DateTime nowDateTime() => DateTime.utc(2026, 11, 3).add(
        Duration(seconds: reads++),
      );
}

/// Records its calls in [log], under [label].
class _LoggingProcessor implements SpanProcessor {
  _LoggingProcessor(this.label, this.log);

  final String label;
  final List<String> log;

  @override
  Future<void> onStart(Span span, Context? parentContext) async {}

  @override
  Future<void> onEnd(Span span) async => log.add('onEnd:$label');

  @override
  Future<void> onNameUpdate(Span span, String newName) async {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

/// Records its calls in [log], under [label], and runs [onEndingDo] in
/// onEnding.
class _EndingProcessor extends _LoggingProcessor
    implements ExtendedSpanProcessor {
  _EndingProcessor(super.label, super.log, {this.onEndingDo});

  final void Function(Span span)? onEndingDo;

  @override
  void onEnding(Span span) {
    log.add('onEnding:$label');
    onEndingDo?.call(span);
  }
}

/// A sampler that drops every span.
class _DropSampler implements Sampler {
  @override
  String get description => 'DropSampler';

  @override
  SamplingResult shouldSample({
    required Context parentContext,
    required String traceId,
    required String name,
    required SpanKind spanKind,
    required Attributes? attributes,
    required List<SpanLink>? links,
  }) =>
      const SamplingResult(
        decision: SamplingDecision.drop,
        source: SamplingDecisionSource.tracerConfig,
      );
}

void main() {
  late InMemorySpanExporter exporter;
  late _SteppingTimeProvider clock;
  final log = <String>[];

  Future<void> initWith(
    List<SpanProcessor> processors, {
    Sampler? sampler,
  }) async {
    await OTel.reset();
    log.clear();
    exporter = InMemorySpanExporter();
    clock = _SteppingTimeProvider();
    await OTel.initialize(
      serviceName: 'span-on-ending-test',
      spanProcessor: SimpleSpanProcessor(exporter),
      sampler: sampler,
      timeProvider: clock,
      detectPlatformResources: false,
      enableMetrics: false,
      enableLogs: false,
    );
    processors.forEach(OTel.tracerProvider().addSpanProcessor);
  }

  tearDown(() async {
    await OTel.shutdown();
    await OTel.reset();
  });

  test('every onEnding runs, in registration order, before any onEnd',
      () async {
    await initWith([
      _LoggingProcessor('plain', log),
      _EndingProcessor('a', log),
      _EndingProcessor('b', log),
    ]);
    OTel.tracer().startSpan('ordered').end();
    expect(log, [
      'onEnding:a',
      'onEnding:b',
      'onEnd:plain',
      'onEnd:a',
      'onEnd:b',
    ]);
  });

  test('what onEnding sets is part of the exported span', () async {
    await initWith([
      _EndingProcessor(
        'tagger',
        log,
        onEndingDo: (span) => span
          ..setStringAttribute<String>('tagged.by', 'onEnding')
          ..addEventNow('ending')
          ..setStatus(SpanStatusCode.Error, 'tagged'),
      ),
    ]);
    OTel.tracer().startSpan('tagged').end();
    await OTel.tracerProvider().forceFlush();

    final exported = exporter.spans.single;
    expect(
      exported.attributes.getString('tagged.by'),
      'onEnding',
    );
    expect(exported.spanEvents?.map((e) => e.name), ['ending']);
    expect(exported.status, SpanStatusCode.Error);
  });

  test('onEnding sees the end timestamp on a span not yet ended', () async {
    DateTime? seenEnd;
    bool? seenEnded;
    bool? seenRecording;
    await initWith([
      _EndingProcessor(
        'reader',
        log,
        onEndingDo: (span) {
          seenEnd = span.endTime;
          seenEnded = span.isEnded;
          seenRecording = span.isRecording;
          // Time spent here reads the clock again: it must not move the end.
          clock.nowDateTime();
        },
      ),
    ]);
    final span = OTel.tracer().startSpan('timed');
    final readsBeforeEnd = clock.reads;
    span.end();

    expect(seenEnded, isFalse);
    expect(seenRecording, isTrue);
    expect(
      seenEnd,
      DateTime.utc(2026, 11, 3).add(Duration(seconds: readsBeforeEnd)),
    );
    expect(span.endTime, seenEnd,
        reason: 'the span ends at the timestamp computed before onEnding');
    expect(span.isEnded, isTrue);
  });

  test('onEnding sees an end timestamp the caller gives', () async {
    DateTime? seenEnd;
    await initWith([
      _EndingProcessor('reader', log, onEndingDo: (s) => seenEnd = s.endTime),
    ]);
    final given = DateTime.utc(2030);
    final span = OTel.tracer().startSpan('given')..end(endTime: given);
    expect(seenEnd, given);
    expect(span.endTime, given);
  });

  test('a status given to end() is set before onEnding', () async {
    SpanStatusCode? seenStatus;
    await initWith([
      _EndingProcessor('reader', log, onEndingDo: (s) => seenStatus = s.status),
    ]);
    OTel.tracer().startSpan('status').end(spanStatus: SpanStatusCode.Ok);
    expect(seenStatus, SpanStatusCode.Ok);
  });

  test('an onEnding that throws is logged, and the span still ends', () async {
    final errors = <String>[];
    OTelLog.logFunction = errors.add;
    OTelLog.currentLevel = LogLevel.error;
    addTearDown(() {
      OTelLog.logFunction = null;
      OTelLog.currentLevel = LogLevel.info;
    });
    await initWith([
      _EndingProcessor('thrower', log,
          onEndingDo: (_) => throw StateError('x')),
      _EndingProcessor('after', log),
    ]);
    final span = OTel.tracer().startSpan('throws')..end();
    await OTel.tracerProvider().forceFlush();

    expect(span.isEnded, isTrue);
    expect(exporter.spans.single.name, 'throws');
    expect(log, [
      'onEnding:thrower',
      'onEnding:after',
      'onEnd:thrower',
      'onEnd:after',
    ]);
    expect(errors.join('\n'), contains('onEnding'));
  });

  test('an end() from onEnding is ignored', () async {
    late Span ending;
    await initWith([
      _EndingProcessor('ender', log, onEndingDo: (span) {
        span.end(endTime: DateTime.utc(2040));
        // Still mutable after the ignored end().
        span.setBoolAttribute('after.end', true);
      }),
      _EndingProcessor('next', log, onEndingDo: (span) => ending = span),
    ]);
    final span = OTel.tracer().startSpan('reentrant')..end();
    await OTel.tracerProvider().forceFlush();

    expect(identical(ending, span), isTrue);
    expect(span.endTime, isNot(DateTime.utc(2040)));
    expect(span.attributes.getBool('after.end'), isTrue);
    expect(log, [
      'onEnding:ender',
      'onEnding:next',
      'onEnd:ender',
      'onEnd:next',
    ]);
    expect(exporter.spans, hasLength(1));
  });

  test('a span that has ended gets no second onEnding', () async {
    await initWith([_EndingProcessor('a', log)]);
    final span = OTel.tracer().startSpan('twice')..end();
    log.clear();
    span.end();
    expect(log.where((l) => l.startsWith('onEnding')), isEmpty);
  });

  test('a span that is not recording gets no onEnding', () async {
    await initWith([_EndingProcessor('a', log)], sampler: _DropSampler());
    final span = OTel.tracer().startSpan('dropped')..end();
    expect(span.isRecording, isFalse);
    expect(log, isEmpty);
  });

  test('with no ExtendedSpanProcessor, end() reads the clock as before',
      () async {
    await initWith([_LoggingProcessor('plain', log)]);
    final span = OTel.tracer().startSpan('plain');
    final readsBeforeEnd = clock.reads;
    span.end();
    expect(
      span.endTime,
      DateTime.utc(2026, 11, 3).add(Duration(seconds: readsBeforeEnd)),
    );
    expect(log, ['onEnd:plain']);
  });
}
