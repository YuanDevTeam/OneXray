import 'package:onexray/core/errors/failure.dart';

import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/shared/ping/state.dart';

class PingBatchSource {
  final String xrayJson;
  final String? outboundTag;

  const PingBatchSource(this.xrayJson, {this.outboundTag});
}

class PingBatchResult {
  final bool success;
  final int delay;
  final String error;

  const PingBatchResult(this.success, this.delay, this.error);

  factory PingBatchResult.failed([String error = ""]) =>
      PingBatchResult(false, PingDelayConstants.error, error);

  factory PingBatchResult.fromResponse(PingBatchItemResponse response) {
    if (response.delay == null) {
      return PingBatchResult.failed(response.error ?? "");
    }

    return PingBatchResult(
      response.success ?? false,
      response.delay!,
      response.error ?? "",
    );
  }
}

class PingBatchRunner {
  static const maxBatchSize = 5;

  static Future<List<PingBatchResult>> run(
    List<PingBatchSource> sources,
    PingState pingState,
  ) async {
    if (sources.isEmpty) {
      return const [];
    }
    if (sources.length > maxBatchSize) {
      throw ArgumentError.value(
        sources.length,
        "sources.length",
        "Ping batch supports at most $maxBatchSize configs",
      );
    }

    final request = PingBatchRequest(
      sources
          .map(
            (source) => PingBatchItemRequest(
              source.xrayJson,
              outboundTag: source.outboundTag,
            ),
          )
          .toList(growable: false),
      pingState.timeout.toInt(),
      pingState.realUrl,
    );
    final PingBatchResponse? response;
    try {
      response = await AppHostApi().pingBatch(request);
    } catch (error) {
      return [
        for (final _ in sources) PingBatchResult.failed(failureDetails(error)),
      ];
    }
    final responseResults = response?.results;
    if (responseResults == null || responseResults.length != sources.length) {
      return List.generate(
        sources.length,
        (_) => PingBatchResult.failed(
          'Invalid pingBatch response: result count does not match the request',
        ),
        growable: false,
      );
    }

    return responseResults
        .map(PingBatchResult.fromResponse)
        .toList(growable: false);
  }
}
