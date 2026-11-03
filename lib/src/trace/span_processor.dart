// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'span.dart';

/// Interface for span processors that handle span lifecycle events.
///
/// Span processors are invoked at key moments in a span's lifecycle, such as
/// when it is started, ended, or when its name is updated. They are responsible
/// for performing additional processing on spans, such as filtering, batching,
/// or exporting them.
///
/// More information:
/// https://opentelemetry.io/docs/specs/otel/trace/sdk/#span-processor
abstract class SpanProcessor {
  /// Called when a span is started.
  ///
  /// This method is called synchronously when a span is started, allowing
  /// for immediate processing of the span. Implementations should be lightweight
  /// and avoid blocking operations or excessive processing.
  ///
  /// @param span The span that was started
  /// @param parentContext The parent context, if any
  Future<void> onStart(Span span, Context? parentContext);

  /// Called when a span is ended.
  ///
  /// This method is called synchronously when a span is ended, allowing
  /// for processing of the completed span. This is typically where spans
  /// are exported or otherwise processed for storage or analysis.
  ///
  /// @param span The span that was ended
  Future<void> onEnd(Span span);

  /// Called when a span's name is updated.
  ///
  /// This method is called synchronously when a span's name is updated,
  /// allowing for processing of the updated span metadata.
  ///
  /// @param span The span whose name was updated
  /// @param newName The new name of the span
  Future<void> onNameUpdate(Span span, String newName);

  /// Shuts down the span processor.
  ///
  /// This method is called when the tracer provider is shut down.
  /// Implementations should release any resources they hold and perform
  /// any final processing of spans.
  Future<void> shutdown();

  /// Forces the span processor to flush any queued spans.
  ///
  /// This method is called when the tracer provider's forceFlush method
  /// is called. Implementations should ensure that any spans that have
  /// been processed but not yet exported are exported immediately.
  Future<void> forceFlush();
}

/// A [SpanProcessor] that is also called as a span ends, while the span can
/// still be changed: the Trace SDK spec's `OnEnding`, in Development status.
///
/// It is an interface of its own, as Java's `ExtendedSpanProcessor` is, so
/// that every class implementing [SpanProcessor] stays valid.
///
/// More information:
/// https://opentelemetry.io/docs/specs/otel/trace/sdk/#onending
abstract class ExtendedSpanProcessor implements SpanProcessor {
  /// Called during [Span.end], after the end timestamp is computed and
  /// before any processor's [onEnd].
  ///
  /// The span can still be changed here: what this sets is part of the span
  /// every [onEnd] receives. [Span.endTime] is already the end timestamp,
  /// and [Span.isEnded] is still false. A call to [Span.end] from here is
  /// ignored: the span is already ending.
  ///
  /// This method is called synchronously, in the order the processors were
  /// registered, so it must not block. An exception it throws is logged, and
  /// the span still ends.
  ///
  /// @param span The span that is ending
  void onEnding(Span span);
}
