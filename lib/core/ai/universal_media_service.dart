import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../media/media_job.dart';
import 'api_endpoint_resolver.dart';
import 'http_helper.dart';
import 'sse_helper.dart';

export '../media/media_job.dart';

/// OpenAI 兼容 / 自定义媒体接口的默认路径。
const kDefaultImageGenerationEndpoint = '/v1/images/generations';
const kDefaultImageEditEndpoint = '/v1/images/edits';
/// OpenAI Videos 风格默认提交端点。实测 OpenAI 兼容中转站
///（如 SimiRouter）只在 `/v1/videos` 注册路由，`/v1/videos/generations`
/// 会返回 "Invalid URL"；xAI 风格仍是可选 profile 的显式端点。
const kDefaultVideoGenerationEndpoint = '/v1/videos';
const kDefaultMusicGenerationEndpoint = '/v1/audio/music';

const kDefaultImageGenerationModel = 'dall-e-3';
const kDefaultVideoGenerationModel = 'sora-2';
const kDefaultMusicGenerationModel = 'music-1';

/// 本地保存生成结果前的安全上限。
const kMaxGeneratedImageBytes = 10 * 1024 * 1024;
const kMaxGeneratedVideoBytes = 100 * 1024 * 1024;
const kMaxGeneratedMusicBytes = 25 * 1024 * 1024;

class UniversalMediaException implements Exception {
  final String message;

  const UniversalMediaException(this.message);

  @override
  String toString() => message;
}

/// 取消是可区分的失败，不会被转换成“接口未返回媒体”或半成功结果。
class UniversalMediaCancelledException extends UniversalMediaException {
  const UniversalMediaCancelledException([super.message = '请求已取消']);
}

/// OpenAI 兼容 / 自定义中转站媒体客户端。
///
/// 旧的 `generateVideo` / `generateMusic` 仍然返回最终
/// `UniversalMediaAsset`。当服务端返回异步任务时，这两个兼容入口会按
/// `pollingOptions` 等待完成；需要立即拿到结构化状态时使用
/// `submitVideo` / `submitMusic` / `submit`，再显式调用 `pollJob` 或
/// `waitForJob`。
class UniversalMediaService {
  const UniversalMediaService({
    required this.baseUrl,
    required this.apiKey,
    this.adapter,
    this.pollingOptions = const UniversalMediaPollingOptions(),
    this.onJobUpdate,
  });

  final String baseUrl;
  final String apiKey;
  final UniversalMediaAdapter? adapter;
  final UniversalMediaPollingOptions pollingOptions;

  /// 进程内状态观察钩子。它不负责持久化，异常也不会改变媒体请求结果。
  final void Function(UniversalMediaJob job)? onJobUpdate;

  /// 兼容原有同步调用签名；新增可选参数不会影响已有调用方。
  Future<UniversalMediaAsset> generateVideo({
    required String model,
    required String prompt,
    String endpoint = kDefaultVideoGenerationEndpoint,
    String? referenceImagePath,
    CancelToken? cancelToken,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    UniversalMediaPollingOptions? pollingOptions,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
  }) async {
    final submitted = await submitVideo(
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      referenceImagePath: referenceImagePath,
      cancelToken: cancelToken,
      extra: extra,
      taskOptions: taskOptions,
      endpointStyle: endpointStyle,
    );
    final completed = await waitForJob(
      submitted.job,
      cancelToken: cancelToken,
      pollingOptions: pollingOptions,
    );
    return _assetOrThrow(completed, kind: UniversalMediaKind.video);
  }

  /// 兼容原有同步调用签名；异步音乐任务同样会自动有限轮询。
  Future<UniversalMediaAsset> generateMusic({
    required String model,
    required String prompt,
    String endpoint = kDefaultMusicGenerationEndpoint,
    CancelToken? cancelToken,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    UniversalMediaPollingOptions? pollingOptions,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
  }) async {
    final submitted = await submitMusic(
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      cancelToken: cancelToken,
      extra: extra,
      taskOptions: taskOptions,
      endpointStyle: endpointStyle,
    );
    final completed = await waitForJob(
      submitted.job,
      cancelToken: cancelToken,
      pollingOptions: pollingOptions,
    );
    return _assetOrThrow(completed, kind: UniversalMediaKind.music);
  }

  /// 通用图片入口，供媒体任务层覆盖图片异步响应形状；不会改动现有
  /// `ImageGenerationService` 的调用路径。
  Future<UniversalMediaAsset> generateImage({
    String model = kDefaultImageGenerationModel,
    required String prompt,
    String endpoint = kDefaultImageGenerationEndpoint,
    CancelToken? cancelToken,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    UniversalMediaPollingOptions? pollingOptions,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
  }) async {
    final submitted = await submit(
      kind: UniversalMediaKind.image,
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      cancelToken: cancelToken,
      extra: extra,
      taskOptions: taskOptions,
      endpointStyle: endpointStyle,
    );
    final completed = await waitForJob(
      submitted.job,
      cancelToken: cancelToken,
      pollingOptions: pollingOptions,
    );
    return _assetOrThrow(completed, kind: UniversalMediaKind.image);
  }

  /// OpenAI / xAI 图片编辑的统一入口。
  ///
  /// 图片编辑与普通图片生成共享同一套 submit / poll / cancel 状态机，
  /// 但默认 endpoint 必须是 `/v1/images/edits`，否则带参考图的请求会被
  /// 一些兼容服务当成非法的 `images/generations` 请求。
  Future<UniversalMediaAsset> generateImageEdit({
    required String model,
    required String prompt,
    required String referenceImagePath,
    String endpoint = kDefaultImageEditEndpoint,
    CancelToken? cancelToken,
    UniversalMediaPollingOptions? pollingOptions,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
  }) async {
    final submitted = await submitImageEdit(
      model: model,
      prompt: prompt,
      referenceImagePath: referenceImagePath,
      endpoint: endpoint,
      cancelToken: cancelToken,
      endpointStyle: endpointStyle,
      extra: extra,
      taskOptions: taskOptions,
    );
    final completed = await waitForJob(
      submitted.job,
      cancelToken: cancelToken,
      pollingOptions: pollingOptions,
    );
    return _assetOrThrow(completed, kind: UniversalMediaKind.image);
  }

  Future<UniversalMediaJobResult> submitImage({
    String model = kDefaultImageGenerationModel,
    required String prompt,
    String endpoint = kDefaultImageGenerationEndpoint,
    CancelToken? cancelToken,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
  }) {
    return submit(
      kind: UniversalMediaKind.image,
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      cancelToken: cancelToken,
      endpointStyle: endpointStyle,
      extra: extra,
      taskOptions: taskOptions,
    );
  }

  Future<UniversalMediaJobResult> submitImageEdit({
    required String model,
    required String prompt,
    required String referenceImagePath,
    String endpoint = kDefaultImageEditEndpoint,
    CancelToken? cancelToken,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
  }) {
    return submit(
      kind: UniversalMediaKind.image,
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      referenceImagePath: referenceImagePath,
      cancelToken: cancelToken,
      endpointStyle: endpointStyle,
      extra: extra,
      taskOptions: taskOptions,
    );
  }

  Future<UniversalMediaJobResult> submitVideo({
    required String model,
    required String prompt,
    String endpoint = kDefaultVideoGenerationEndpoint,
    String? referenceImagePath,
    CancelToken? cancelToken,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
  }) {
    return submit(
      kind: UniversalMediaKind.video,
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      referenceImagePath: referenceImagePath,
      cancelToken: cancelToken,
      extra: extra,
      taskOptions: taskOptions,
      endpointStyle: endpointStyle,
    );
  }

  Future<UniversalMediaJobResult> submitMusic({
    required String model,
    required String prompt,
    String endpoint = kDefaultMusicGenerationEndpoint,
    CancelToken? cancelToken,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
  }) {
    return submit(
      kind: UniversalMediaKind.music,
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      cancelToken: cancelToken,
      extra: extra,
      taskOptions: taskOptions,
      endpointStyle: endpointStyle,
    );
  }

  /// 立即提交一次任务，并返回 completed / pending / failed 等结构化状态。
  Future<UniversalMediaJobResult> submit({
    required UniversalMediaKind kind,
    required String model,
    required String prompt,
    String? endpoint,
    String? referenceImagePath,
    CancelToken? cancelToken,
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
  }) async {
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    final token = _validateCommon(
      kind: kind,
      model: model,
      prompt: prompt,
      apiKey: apiKey,
    );
    final normalizedEndpoint = _endpointForKind(kind, endpoint);
    final submitUrl = _resolveEndpoint(normalizedBaseUrl, normalizedEndpoint);
    _throwIfCancelled(cancelToken);

    final request = UniversalMediaSubmitRequest(
      baseUri: Uri.parse(normalizedBaseUrl),
      apiKey: token,
      kind: kind,
      model: model.trim(),
      prompt: prompt.trim(),
      endpoint: normalizedEndpoint,
      endpointStyle: endpointStyle,
      taskOptions: taskOptions,
      referenceImagePath: referenceImagePath,
      extra: extra,
      cancelToken: cancelToken,
    );

    try {
      final response = await _adapter.submit(request);
      _throwIfCancelled(cancelToken);
      final parsed = UniversalMediaResponseParser.parse(
        kind: kind,
        statusCode: response.statusCode,
        headers: response.headers,
        body: response.bytes,
        submitUri: Uri.parse(submitUrl),
        endpointStyle: endpointStyle,
        taskOptions: taskOptions,
        mimeHint: _mediaMimeHintFromExtra(kind, extra),
      );
      final result = await _materializeParsedResponse(
        parsed,
        kind: kind,
        submitUri: Uri.parse(submitUrl),
        endpointStyle: endpointStyle,
        taskOptions: taskOptions,
        requestMimeHint: _mediaMimeHintFromExtra(kind, extra),
        apiKey: token,
        cancelToken: cancelToken,
      );
      _emit(result.job);
      return result;
    } on UniversalMediaException {
      rethrow;
    } on DioException catch (error) {
      throw _exceptionFromDio(error, kind: kind);
    } catch (error) {
      if (cancelToken?.isCancelled == true) {
        throw const UniversalMediaCancelledException();
      }
      if (error is FormatException || error is ArgumentError) {
        throw UniversalMediaException(error.toString());
      }
      throw UniversalMediaException('${_kindLabel(kind)}生成失败，请稍后重试');
    }
  }

  /// 兼容更明确的命名。
  Future<UniversalMediaJobResult> submitVideoJob({
    required String model,
    required String prompt,
    String endpoint = kDefaultVideoGenerationEndpoint,
    String? referenceImagePath,
    CancelToken? cancelToken,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
  }) {
    return submitVideo(
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      referenceImagePath: referenceImagePath,
      cancelToken: cancelToken,
      extra: extra,
      taskOptions: taskOptions,
      endpointStyle: endpointStyle,
    );
  }

  Future<UniversalMediaJobResult> submitMusicJob({
    required String model,
    required String prompt,
    String endpoint = kDefaultMusicGenerationEndpoint,
    CancelToken? cancelToken,
    Map<String, dynamic> extra = const <String, dynamic>{},
    UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
    UniversalMediaEndpointStyle endpointStyle =
        UniversalMediaEndpointStyle.auto,
  }) {
    return submitMusic(
      model: model,
      prompt: prompt,
      endpoint: endpoint,
      cancelToken: cancelToken,
      extra: extra,
      taskOptions: taskOptions,
      endpointStyle: endpointStyle,
    );
  }

  /// 只执行一次 poll；状态仍然是结构化的，不会把 pending 当成错误。
  Future<UniversalMediaJobResult> pollJob(
    UniversalMediaJob job, {
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    if (job.status.isTerminal) {
      return UniversalMediaJobResult(job: job, asset: job.asset);
    }
    if (job.pollUrl == null) {
      final expired = _terminalJob(
        job,
        status: UniversalMediaJobStatus.expired,
        error: '媒体任务没有可用的轮询 URL',
      );
      _emit(expired);
      return UniversalMediaJobResult(job: expired);
    }

    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    final token = _validateCommon(
      kind: job.kind,
      model: 'poll',
      prompt: 'poll',
      apiKey: apiKey,
      validatePrompt: false,
    );
    final request = UniversalMediaPollRequest(
      baseUri: Uri.parse(normalizedBaseUrl),
      apiKey: token,
      job: job,
      cancelToken: cancelToken,
    );
    try {
      final response = await _adapter.poll(request);
      _throwIfCancelled(cancelToken);
      final submitUri = _submitUriForJob(job) ?? job.pollUrl!;
      final taskOptions = _taskOptionsFromJob(job);
      final requestMimeHint = _mimeHintFromJob(job);
      final parsed = UniversalMediaResponseParser.parse(
        kind: job.kind,
        statusCode: response.statusCode,
        headers: response.headers,
        body: response.bytes,
        submitUri: submitUri,
        endpointStyle: job.endpointStyle,
        taskOptions: taskOptions,
        mimeHint: requestMimeHint,
      );
      final result = await _materializeParsedResponse(
        parsed,
        kind: job.kind,
        submitUri: submitUri,
        endpointStyle: job.endpointStyle,
        taskOptions: taskOptions,
        previousJob: job,
        requestMimeHint: requestMimeHint,
        apiKey: token,
        cancelToken: cancelToken,
      );
      _emit(result.job);
      return result;
    } on UniversalMediaException {
      rethrow;
    } on DioException catch (error) {
      throw _exceptionFromDio(error, kind: job.kind);
    } catch (error) {
      if (cancelToken?.isCancelled == true) {
        throw const UniversalMediaCancelledException();
      }
      if (error is FormatException || error is ArgumentError) {
        throw UniversalMediaException(error.toString());
      }
      throw UniversalMediaException('${_kindLabel(job.kind)}任务轮询失败');
    }
  }

  Future<UniversalMediaJobResult> poll(
    UniversalMediaJob job, {
    CancelToken? cancelToken,
  }) => pollJob(job, cancelToken: cancelToken);

  /// 按有限 attempts / deadline / backoff 等待任务完成。
  Future<UniversalMediaJobResult> waitForJob(
    UniversalMediaJob job, {
    CancelToken? cancelToken,
    UniversalMediaPollingOptions? pollingOptions,
  }) async {
    final options = pollingOptions ?? this.pollingOptions;
    options.validate();
    _throwIfCancelled(cancelToken);
    if (job.status.isTerminal) {
      return UniversalMediaJobResult(job: job, asset: job.asset);
    }

    final deadline = DateTime.now().add(options.deadline);
    var current = UniversalMediaJobResult(job: job, asset: job.asset);
    try {
      while (true) {
        _throwIfCancelled(cancelToken);
        if (DateTime.now().isAfter(deadline)) {
          return _expire(current.job, '媒体任务轮询超时');
        }
        if (current.job.attempts >= options.maxAttempts) {
          return _expire(current.job, '媒体任务轮询次数已达上限');
        }
        if (current.job.pollUrl == null) {
          return _expire(current.job, '媒体任务没有可用的轮询 URL');
        }

        final delay = current.job.attempts == 0
            ? Duration.zero
            : options.delayAfterAttempt(current.job.attempts);
        if (delay > Duration.zero) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) {
            return _expire(current.job, '媒体任务轮询超时');
          }
          await _delayWithCancellation(
            delay > remaining ? remaining : delay,
            cancelToken,
          );
          if (DateTime.now().isAfter(deadline)) {
            return _expire(current.job, '媒体任务轮询超时');
          }
        }
        current = await _pollWithDeadline(
          current.job,
          deadline: deadline,
          cancelToken: cancelToken,
        );
        // _pollWithDeadline already emitted a terminal timeout. Avoid a
        // duplicate update for that same result, while still rejecting a
        // completed response that actually arrived after the deadline.
        if (current.job.status == UniversalMediaJobStatus.expired) {
          return current;
        }
        if (DateTime.now().isAfter(deadline)) {
          return _expire(current.job, '媒体任务轮询超时');
        }
        if (current.job.status.isTerminal) {
          return current;
        }
      }
    } on UniversalMediaCancelledException {
      final cancelled = _terminalJob(
        current.job,
        status: UniversalMediaJobStatus.cancelled,
        error: '请求已取消',
      );
      _emit(cancelled);
      rethrow;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel ||
          cancelToken?.isCancelled == true) {
        final cancelled = _terminalJob(
          current.job,
          status: UniversalMediaJobStatus.cancelled,
          error: '请求已取消',
        );
        _emit(cancelled);
        throw const UniversalMediaCancelledException();
      }
      rethrow;
    }
  }

  Future<UniversalMediaJobResult> pollUntilComplete(
    UniversalMediaJob job, {
    CancelToken? cancelToken,
    UniversalMediaPollingOptions? pollingOptions,
  }) =>
      waitForJob(job, cancelToken: cancelToken, pollingOptions: pollingOptions);

  /// 请求服务端取消；没有 cancel URL 的自定义任务仍会被本地标为
  /// cancelled，但不会伪造 completed 结果。
  Future<UniversalMediaJobResult> cancelJob(
    UniversalMediaJob job, {
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    if (job.status.isTerminal) {
      return UniversalMediaJobResult(job: job, asset: job.asset);
    }
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    final token = _validateCommon(
      kind: job.kind,
      model: 'cancel',
      prompt: 'cancel',
      apiKey: apiKey,
      validatePrompt: false,
    );
    try {
      final response = await _adapter.cancel(
        UniversalMediaCancelRequest(
          baseUri: Uri.parse(normalizedBaseUrl),
          apiKey: token,
          job: job,
          cancelToken: cancelToken,
        ),
      );
      _throwIfCancelled(cancelToken);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _cancelFailure(job, response);
      }
      final cancelled = _terminalJob(
        job,
        status: UniversalMediaJobStatus.cancelled,
        error: '请求已取消',
      );
      _emit(cancelled);
      return UniversalMediaJobResult(job: cancelled);
    } on UniversalMediaException {
      rethrow;
    } on DioException catch (error) {
      throw _exceptionFromDio(error, kind: job.kind);
    } catch (error) {
      if (cancelToken?.isCancelled == true) {
        throw const UniversalMediaCancelledException();
      }
      if (error is FormatException || error is ArgumentError) {
        throw UniversalMediaException(error.toString());
      }
      throw UniversalMediaException('${_kindLabel(job.kind)}任务取消失败');
    }
  }

  Future<UniversalMediaJobResult> cancel(
    UniversalMediaJob job, {
    CancelToken? cancelToken,
  }) => cancelJob(job, cancelToken: cancelToken);

  Future<UniversalMediaJobResult> _materializeParsedResponse(
    UniversalMediaParsedResponse parsed, {
    required UniversalMediaKind kind,
    required Uri submitUri,
    required UniversalMediaEndpointStyle endpointStyle,
    required UniversalMediaTaskOptions taskOptions,
    UniversalMediaJob? previousJob,
    String? requestMimeHint,
    required String apiKey,
    required CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    UniversalMediaAsset? asset;
    final payload =
        parsed.media ??
        (parsed.status == UniversalMediaJobStatus.completed &&
                (parsed.contentUrl ?? previousJob?.contentUrl) != null
            ? UniversalMediaPayload(
                value: (parsed.contentUrl ?? previousJob?.contentUrl)
                    .toString(),
                requiresAuth: true,
              )
            : null);
    if (payload != null &&
        parsed.status != UniversalMediaJobStatus.failed &&
        parsed.status != UniversalMediaJobStatus.expired &&
        parsed.status != UniversalMediaJobStatus.cancelled) {
      asset = await _assetFromPayload(
        payload,
        kind: kind,
        submitUri: submitUri,
        apiKey: apiKey,
        cancelToken: cancelToken,
      );
      _throwIfCancelled(cancelToken);
    }

    var status = parsed.status;
    String? error = parsed.error;
    if (status == UniversalMediaJobStatus.completed && asset == null) {
      status = UniversalMediaJobStatus.failed;
      error ??= '${_kindLabel(kind)}接口未返回可用媒体';
    }
    final identifier = parsed.identifier ?? previousJob?.providerId;
    final id = previousJob?.id ?? identifier ?? _localJobId();
    final style =
        previousJob?.endpointStyle ??
        (parsed.endpointStyle != UniversalMediaEndpointStyle.auto
            ? parsed.endpointStyle
            : endpointStyle);
    final pollUrl = parsed.pollUrl ?? previousJob?.pollUrl;
    final cancelUrl = parsed.cancelUrl ?? previousJob?.cancelUrl;
    final contentUrl = parsed.contentUrl ?? previousJob?.contentUrl;
    final requestMimeMetadata = requestMimeHint == null
        ? const <String, dynamic>{}
        : <String, dynamic>{'request_mime_hint': requestMimeHint};
    final metadata = <String, dynamic>{
      ...?previousJob?.metadata,
      'submit_url': submitUri.toString(),
      ...requestMimeMetadata,
      ...taskOptions.toJson().map((key, value) => MapEntry('task_$key', value)),
      if (parsed.providerStatus != null)
        'provider_status': parsed.providerStatus,
    };
    final job = UniversalMediaJob(
      id: id,
      kind: kind,
      status: status,
      jobId: parsed.jobId ?? previousJob?.jobId ?? identifier,
      requestId: parsed.requestId ?? previousJob?.requestId,
      pollUrl: pollUrl,
      cancelUrl: cancelUrl,
      contentUrl: contentUrl,
      createdAt: previousJob?.createdAt,
      updatedAt: DateTime.now(),
      attempts: previousJob == null ? 0 : previousJob.attempts + 1,
      error: error,
      asset: asset,
      endpointStyle: style,
      metadata: metadata,
    );
    return UniversalMediaJobResult(job: job, asset: asset);
  }

  Future<UniversalMediaAsset> _assetFromPayload(
    UniversalMediaPayload payload, {
    required UniversalMediaKind kind,
    required Uri submitUri,
    required String apiKey,
    required CancelToken? cancelToken,
  }) async {
    if (payload.bytes != null) {
      return _assetFromBytes(
        payload.bytes!,
        mimeType: payload.mimeType ?? '',
        kind: kind,
      );
    }
    final value = payload.value?.trim();
    if (value == null || value.isEmpty) {
      throw UniversalMediaException('${_kindLabel(kind)}内容为空');
    }
    if (_isDataUri(value)) {
      return _assetFromDataUri(value, kind: kind);
    }
    if (payload.isBase64) {
      return _assetFromBase64(value, kind: kind, mimeType: payload.mimeType);
    }
    final uri = _resolveMediaUri(value, submitUri);
    if (uri == null) {
      throw UniversalMediaException('${_kindLabel(kind)}返回的媒体 URL 无效');
    }
    _throwIfCancelled(cancelToken);
    final downloadDio = getDio(uri.origin);
    try {
      final downloaded = await downloadDio.get<List<int>>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          // A generated content URL can be an external signed URL. Never
          // forward the chat/media provider credential to another origin;
          // same-origin content remains authenticated even when the parser
          // did not explicitly mark it as requiring auth.
          headers:
              _shouldSendMediaAuthorization(
                payload: payload,
                contentUri: uri,
                submitUri: submitUri,
              )
              ? {'Authorization': 'Bearer $apiKey'}
              : null,
        ),
        cancelToken: cancelToken,
      );
      _throwIfCancelled(cancelToken);
      final declaredLength = int.tryParse(
        downloaded.headers.value('content-length') ?? '',
      );
      final maxBytes = _maxBytesFor(kind);
      if (declaredLength != null && declaredLength > maxBytes) {
        throw UniversalMediaException(
          '${_kindLabel(kind)}过大，已拒绝保存（上限 ${maxBytes ~/ (1024 * 1024)} MB）',
        );
      }
      final bytes = downloaded.data ?? const <int>[];
      if (bytes.isEmpty) {
        throw UniversalMediaException('下载${_kindLabel(kind)}失败');
      }
      final headerMime = downloaded.headers.value('content-type');
      return _assetFromBytes(
        bytes,
        mimeType:
            _firstUsableMime(<String?>[
              headerMime,
              payload.mimeType,
              _mimeFromPath(uri.path, kind),
            ], kind) ??
            headerMime ??
            payload.mimeType ??
            '',
        kind: kind,
      );
    } on DioException catch (error) {
      throw _exceptionFromDio(error, kind: kind);
    }
  }

  bool _shouldSendMediaAuthorization({
    required UniversalMediaPayload payload,
    required Uri contentUri,
    required Uri submitUri,
  }) {
    if (!_sameOrigin(contentUri, submitUri)) return false;
    return payload.requiresAuth || _sameOrigin(contentUri, submitUri);
  }

  UniversalMediaAsset _assetFromDataUri(
    String value, {
    required UniversalMediaKind kind,
  }) {
    final normalized = value.trim();
    if (!_isDataUri(normalized)) {
      throw UniversalMediaException('${_kindLabel(kind)} data URI 无效');
    }
    final comma = normalized.indexOf(',');
    if (comma <= 'data:'.length) {
      throw UniversalMediaException('${_kindLabel(kind)} data URI 无效');
    }
    final header = normalized.substring('data:'.length, comma);
    final headerParts = header.split(';');
    final declaredMime = headerParts.first.trim();
    final isBase64 = headerParts
        .skip(1)
        .any((part) => part.trim().toLowerCase() == 'base64');
    final data = normalized.substring(comma + 1);
    try {
      final bytes = isBase64
          ? _decodeBase64(data)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(data)));
      return _assetFromBytes(bytes, mimeType: declaredMime, kind: kind);
    } catch (error) {
      if (error is UniversalMediaException) rethrow;
      throw UniversalMediaException('${_kindLabel(kind)} base64 数据损坏');
    }
  }

  UniversalMediaAsset _assetFromBase64(
    String value, {
    required UniversalMediaKind kind,
    String? mimeType,
  }) {
    try {
      return _assetFromBytes(
        _decodeBase64(value),
        mimeType: mimeType ?? '',
        kind: kind,
      );
    } catch (error) {
      if (error is UniversalMediaException) rethrow;
      throw UniversalMediaException('${_kindLabel(kind)} base64 数据损坏');
    }
  }

  UniversalMediaAsset _assetFromBytes(
    List<int> bytes, {
    required String mimeType,
    required UniversalMediaKind kind,
  }) {
    if (bytes.isEmpty) {
      throw UniversalMediaException('${_kindLabel(kind)}内容为空');
    }
    final maxBytes = _maxBytesFor(kind);
    if (bytes.length > maxBytes) {
      throw UniversalMediaException(
        '${_kindLabel(kind)}过大，已拒绝保存（上限 ${maxBytes ~/ (1024 * 1024)} MB）',
      );
    }
    final normalizedMime = _mimeFromContentType(mimeType, kind, bytes: bytes);
    return UniversalMediaAsset(
      bytes: Uint8List.fromList(bytes),
      mimeType: normalizedMime,
      extension: _extensionFor(normalizedMime, kind),
    );
  }

  UniversalMediaJob _terminalJob(
    UniversalMediaJob source, {
    required UniversalMediaJobStatus status,
    required String error,
  }) {
    return UniversalMediaJob(
      id: source.id,
      kind: source.kind,
      status: status,
      jobId: source.jobId,
      requestId: source.requestId,
      pollUrl: source.pollUrl,
      cancelUrl: source.cancelUrl,
      contentUrl: source.contentUrl,
      createdAt: source.createdAt,
      updatedAt: DateTime.now(),
      attempts: source.attempts,
      error: error,
      endpointStyle: source.endpointStyle,
      metadata: source.metadata,
    );
  }

  UniversalMediaJobResult _expire(UniversalMediaJob source, String message) {
    final expired = _terminalJob(
      source,
      status: UniversalMediaJobStatus.expired,
      error: message,
    );
    _emit(expired);
    return UniversalMediaJobResult(job: expired);
  }

  UniversalMediaAsset _assetOrThrow(
    UniversalMediaJobResult result, {
    required UniversalMediaKind kind,
  }) {
    if (result.job.status == UniversalMediaJobStatus.cancelled) {
      throw const UniversalMediaCancelledException();
    }
    final asset = result.asset ?? result.job.asset;
    if (result.job.status == UniversalMediaJobStatus.expired) {
      throw UniversalMediaException(result.job.error ?? '媒体任务轮询超时');
    }
    if (result.job.status == UniversalMediaJobStatus.failed || asset == null) {
      throw UniversalMediaException(
        result.job.error ?? '${_kindLabel(kind)}接口未返回可用媒体',
      );
    }
    return asset;
  }

  UniversalMediaAdapter get _adapter =>
      adapter ?? const DioUniversalMediaAdapter();

  String _validateCommon({
    required UniversalMediaKind kind,
    required String model,
    required String prompt,
    required String apiKey,
    bool validatePrompt = true,
  }) {
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const UniversalMediaException('媒体生成 API Key 未配置');
    }
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw const UniversalMediaException('媒体生成模型未配置');
    }
    if (validatePrompt) {
      final normalizedPrompt = prompt.trim();
      if (normalizedPrompt.isEmpty) {
        throw const UniversalMediaException('媒体生成描述不能为空');
      }
      if (normalizedPrompt.length > 4000) {
        throw const UniversalMediaException('媒体生成描述过长，请精简后重试');
      }
    }
    return token;
  }

  String _endpointForKind(UniversalMediaKind kind, String? endpoint) {
    final value = endpoint?.trim();
    if (value != null && value.isNotEmpty) return value;
    return switch (kind) {
      UniversalMediaKind.image => kDefaultImageGenerationEndpoint,
      UniversalMediaKind.video => kDefaultVideoGenerationEndpoint,
      UniversalMediaKind.music => kDefaultMusicGenerationEndpoint,
    };
  }

  String _normalizeBaseUrl(String value) {
    try {
      // Media endpoints use the configured prefix as-is. In particular,
      // `/v2` and `/api/v3` must not be silently reduced to an origin because
      // custom relative endpoints are resolved below against that prefix.
      final normalized = normalizeUrl(value);
      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.host.isEmpty) throw const FormatException();
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') {
        throw const FormatException();
      }
      return normalized;
    } catch (_) {
      throw const UniversalMediaException('媒体接口 Base URL 仅支持 HTTP(S)');
    }
  }

  String _resolveEndpoint(String normalizedBaseUrl, String endpoint) {
    try {
      return _resolveUniversalMediaEndpoint(normalizedBaseUrl, endpoint);
    } on FormatException catch (error) {
      throw UniversalMediaException(error.message);
    }
  }

  Uri? _submitUriForJob(UniversalMediaJob job) {
    final value = job.metadata['submit_url'];
    final uri = Uri.tryParse(value?.toString() ?? '');
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri;
    }
    return null;
  }

  UniversalMediaTaskOptions _taskOptionsFromJob(UniversalMediaJob job) {
    final encoded = <String, dynamic>{};
    for (final entry in job.metadata.entries) {
      if (entry.key.startsWith('task_')) {
        encoded[entry.key.substring('task_'.length)] = entry.value;
      }
    }
    if (encoded.isEmpty) return const UniversalMediaTaskOptions();
    try {
      return UniversalMediaTaskOptions.fromJson(encoded);
    } catch (_) {
      return const UniversalMediaTaskOptions();
    }
  }

  String? _mimeHintFromJob(UniversalMediaJob job) {
    final value = job.metadata['request_mime_hint'];
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void _emit(UniversalMediaJob job) {
    try {
      onJobUpdate?.call(job);
    } catch (_) {
      // 状态观察者不能改变网络任务的语义。
    }
  }

  void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const UniversalMediaCancelledException();
    }
  }

  UniversalMediaException _exceptionFromDio(
    DioException error, {
    required UniversalMediaKind kind,
  }) {
    if (error.type == DioExceptionType.cancel) {
      return const UniversalMediaCancelledException();
    }
    return UniversalMediaException(_formatError(error, kind: kind));
  }

  Future<void> _delayWithCancellation(
    Duration duration,
    CancelToken? cancelToken,
  ) async {
    if (duration <= Duration.zero) return;
    if (cancelToken == null) {
      await Future<void>.delayed(duration);
      return;
    }
    _throwIfCancelled(cancelToken);
    await Future.any<dynamic>(<Future<dynamic>>[
      Future<void>.delayed(duration),
      cancelToken.whenCancel,
    ]);
    _throwIfCancelled(cancelToken);
  }

  Future<UniversalMediaJobResult> _pollWithDeadline(
    UniversalMediaJob job, {
    required DateTime deadline,
    required CancelToken? cancelToken,
  }) async {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return _expire(job, '媒体任务轮询超时');
    }

    // Use a per-request token so an adapter that honors cancellation stops at
    // the deadline, while the caller's token remains reusable. pollJob checks
    // this token after the adapter returns, so a late response cannot be
    // parsed or emitted as a successful result.
    final requestToken = CancelToken();
    var deadlineReached = false;
    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancel.then((error) {
          if (!requestToken.isCancelled) {
            requestToken.cancel(error.message);
          }
        }),
      );
    }

    final pollFuture = pollJob(job, cancelToken: requestToken);
    final timeoutFuture =
        Future<void>.delayed(remaining, () {
          deadlineReached = true;
          if (!requestToken.isCancelled) {
            requestToken.cancel('媒体任务轮询超时');
          }
        }).then<UniversalMediaJobResult>((_) {
          throw const _UniversalMediaPollDeadlineReached();
        });
    // An adapter is allowed to be implemented outside this package. Do not
    // assume every implementation observes CancelToken: race the caller's
    // cancellation future as well, otherwise a non-cooperative adapter can
    // hold waitForJob until the full deadline despite a user pressing Stop.
    final callerCancellationFuture = cancelToken?.whenCancel
        .then<UniversalMediaJobResult>((_) {
          throw const UniversalMediaCancelledException();
        });
    final futures = <Future<UniversalMediaJobResult>>[
      pollFuture,
      timeoutFuture,
    ];
    if (callerCancellationFuture != null) {
      futures.add(callerCancellationFuture);
    }
    try {
      return await Future.any<UniversalMediaJobResult>(futures);
    } on _UniversalMediaPollDeadlineReached {
      return _expire(job, '媒体任务轮询超时');
    } on UniversalMediaCancelledException {
      if (deadlineReached) return _expire(job, '媒体任务轮询超时');
      rethrow;
    } finally {
      if (!requestToken.isCancelled) requestToken.cancel();
    }
  }

  UniversalMediaException _cancelFailure(
    UniversalMediaJob job,
    UniversalMediaHttpResponse response,
  ) {
    final parsed = UniversalMediaResponseParser.parse(
      kind: job.kind,
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.bytes,
      submitUri: _submitUriForJob(job) ?? job.cancelUrl,
      endpointStyle: job.endpointStyle,
    );
    final detail = parsed.error;
    if (detail == null || detail.isEmpty) {
      return UniversalMediaException(
        '${_kindLabel(job.kind)}任务取消失败（HTTP ${response.statusCode}）',
      );
    }
    return UniversalMediaException('${_kindLabel(job.kind)}任务取消失败：$detail');
  }

  Uri? _resolveMediaUri(String value, Uri submitUri) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null) return null;
    final resolved = parsed.hasScheme ? parsed : submitUri.resolveUri(parsed);
    final scheme = resolved.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || resolved.host.isEmpty) {
      return null;
    }
    return resolved;
  }

  String _localJobId() =>
      'local-media-${DateTime.now().microsecondsSinceEpoch}';
}

class _UniversalMediaPollDeadlineReached implements Exception {
  const _UniversalMediaPollDeadlineReached();
}

/// 默认 Dio adapter。它只负责 submit / poll / cancel HTTP 动作，所有
/// cancelToken 都沿着请求边界传入；解析和轮询策略在 service 层完成。
class DioUniversalMediaAdapter implements UniversalMediaAdapter {
  const DioUniversalMediaAdapter();

  @override
  Future<UniversalMediaHttpResponse> submit(
    UniversalMediaSubmitRequest request,
  ) async {
    final url = _resolveAdapterUrl(request.baseUri, request.endpoint);
    final taskOptions = request.taskOptions;
    taskOptions.validate();
    final explicitlyConfigured =
        taskOptions.protocol != UniversalMediaProtocol.auto;
    final openAiVideoCreate =
        taskOptions.protocol == UniversalMediaProtocol.openAiVideo ||
        (!explicitlyConfigured && _isOpenAiVideoCreateEndpoint(url));
    final referencePath = request.referenceImagePath?.trim();
    final xAiVideoGeneration =
        taskOptions.protocol == UniversalMediaProtocol.xAiVideo ||
        (!explicitlyConfigured &&
            _isXAiVideoGenerationEndpoint(url) &&
            (request.endpointStyle ==
                    UniversalMediaEndpointStyle.xAiRequestId ||
                referencePath == null ||
                referencePath.isEmpty));
    final imageEndpoint = request.kind == UniversalMediaKind.image;
    final modelLooksLikeGptImage = request.model
        .trim()
        .toLowerCase()
        .startsWith('gpt-image');
    final imageResponseFormatRequested =
        imageEndpoint &&
        !openAiVideoCreate &&
        !xAiVideoGeneration &&
        !modelLooksLikeGptImage &&
        !request.extra.containsKey('response_format') &&
        !request.extra.containsKey('output_format');
    final fields = <String, dynamic>{
      'model': request.model,
      'prompt': request.prompt,
      if (imageResponseFormatRequested) 'response_format': 'b64_json',
      ...request.extra,
    };
    final hasReference = referencePath != null && referencePath.isNotEmpty;
    final referenceField =
        taskOptions.referenceField ??
        (openAiVideoCreate ? 'input_reference' : 'image');
    final requestFormat = taskOptions.requestFormat;
    final useMultipart =
        !xAiVideoGeneration &&
        (requestFormat == UniversalMediaRequestFormat.multipart ||
            (requestFormat == UniversalMediaRequestFormat.auto &&
                hasReference));
    final Object data;
    if (xAiVideoGeneration) {
      data = <String, dynamic>{
        ...fields,
        if (hasReference)
          'image': <String, String>{
            'url': await _localImageDataUri(referencePath),
          },
      };
    } else if (useMultipart) {
      final path = referencePath;
      data = FormData.fromMap({
        ...fields,
        if (path != null && path.isNotEmpty)
          referenceField: await MultipartFile.fromFile(
            path,
            filename: _fileNameFromPath(path),
          ),
      });
    } else if (hasReference) {
      // JSON-only compatible endpoints must receive bytes as a data URL; a
      // local path is never serialized into a request body.
      data = <String, dynamic>{
        ...fields,
        referenceField: await _localImageDataUri(referencePath),
      };
    } else {
      data = fields;
    }
    return _request(
      method: 'POST',
      url: url,
      kind: request.kind,
      apiKey: request.apiKey,
      data: data,
      cancelToken: request.cancelToken,
    );
  }

  @override
  Future<UniversalMediaHttpResponse> poll(
    UniversalMediaPollRequest request,
  ) async {
    final url = request.job.pollUrl;
    if (url == null) {
      throw const UniversalMediaException('媒体任务没有可用的轮询 URL');
    }
    return _request(
      method: 'GET',
      url: url,
      kind: request.job.kind,
      apiKey: request.apiKey,
      cancelToken: request.cancelToken,
    );
  }

  @override
  Future<UniversalMediaHttpResponse> cancel(
    UniversalMediaCancelRequest request,
  ) async {
    final url = request.job.cancelUrl;
    if (url == null) {
      return UniversalMediaHttpResponse(
        statusCode: 204,
        requestUri: request.job.pollUrl ?? request.baseUri,
        bytes: const <int>[],
      );
    }
    return _request(
      method: 'DELETE',
      url: url,
      kind: request.job.kind,
      apiKey: request.apiKey,
      cancelToken: request.cancelToken,
    );
  }

  Future<UniversalMediaHttpResponse> _request({
    required String method,
    required Uri url,
    required UniversalMediaKind kind,
    required String apiKey,
    Object? data,
    CancelToken? cancelToken,
  }) async {
    final dio = getDio(url.origin);
    final response = await dio.request<List<int>>(
      url.toString(),
      data: data,
      options: Options(
        method: method,
        responseType: ResponseType.bytes,
        // 4xx / 5xx JSON 也交给统一 parser，便于返回 failed / expired 状态。
        validateStatus: (status) => status != null,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': _acceptFor(kind),
        },
      ),
      cancelToken: cancelToken,
    );
    final headers = <String, String>{};
    response.headers.forEach((key, values) {
      headers[key] = values.join(', ');
    });
    return UniversalMediaHttpResponse(
      statusCode: response.statusCode ?? 0,
      requestUri: response.requestOptions.uri,
      bytes: response.data ?? const <int>[],
      headers: headers,
    );
  }
}

bool _isOpenAiVideoCreateEndpoint(Uri url) {
  final segments = url.pathSegments;
  return segments.isNotEmpty && segments.last.toLowerCase() == 'videos';
}

bool _isXAiVideoGenerationEndpoint(Uri url) {
  final segments = url.pathSegments.map((segment) => segment.toLowerCase());
  return segments.contains('videos') && segments.contains('generations');
}

Future<String> _localImageDataUri(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const UniversalMediaException('参考图片文件不存在');
  }
  final length = await file.length();
  if (length <= 0) {
    throw const UniversalMediaException('参考图片文件为空');
  }
  if (length > kMaxGeneratedImageBytes) {
    throw const UniversalMediaException('参考图片过大，无法提交');
  }
  final bytes = await file.readAsBytes();
  return 'data:${_mimeForImagePath(path)};base64,${base64Encode(bytes)}';
}

String _mimeForImagePath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (normalized.endsWith('.webp')) return 'image/webp';
  if (normalized.endsWith('.gif')) return 'image/gif';
  if (normalized.endsWith('.avif')) return 'image/avif';
  return 'image/png';
}

Uri _resolveAdapterUrl(Uri baseUri, String endpoint) {
  return Uri.parse(
    _resolveUniversalMediaEndpoint(baseUri.toString(), endpoint),
  );
}

/// Resolve media endpoints without conflating a caller's explicit root path
/// with a path relative to the configured Base URL.
///
/// The built-in defaults intentionally start with `/v1/...` and therefore
/// target the origin root. Custom endpoints without a leading slash are
/// resolved against the configured Base URL prefix (`/v2`, `/api/v3`, etc.).
/// Absolute HTTP(S) URLs are preserved for custom relays.
String _resolveUniversalMediaEndpoint(String baseUrl, String endpoint) {
  final trimmed = endpoint.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('媒体接口路径不能为空');
  }
  final parsed = Uri.tryParse(trimmed);
  final parsedScheme = parsed?.scheme.toLowerCase();
  if (parsed != null && (parsedScheme == 'http' || parsedScheme == 'https')) {
    return trimmed;
  }
  if (parsed != null && parsed.hasScheme) {
    throw const FormatException('媒体接口路径仅支持 HTTP(S)');
  }

  final normalizedBase = normalizeUrl(baseUrl);
  final base = Uri.tryParse(normalizedBase);
  if (base == null || base.host.isEmpty) {
    throw const FormatException('媒体接口 Base URL 格式无效');
  }

  if (trimmed.startsWith('/')) {
    final path = parsed?.path.isNotEmpty == true
        ? parsed!.path
        : '/${trimmed.replaceFirst(RegExp(r'^/+'), '')}';
    final query = parsed?.query ?? '';
    final fragment = parsed?.fragment ?? '';
    return Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.port,
      path: path.startsWith('/') ? path : '/$path',
      query: query.isEmpty ? null : query,
      fragment: fragment.isEmpty ? null : fragment,
    ).toString();
  }

  return resolveApiEndpoint(normalizedBase, trimmed);
}

String _acceptFor(UniversalMediaKind kind) => switch (kind) {
  UniversalMediaKind.image => 'image/*, application/json',
  UniversalMediaKind.video => 'video/*, application/json',
  UniversalMediaKind.music => 'audio/*, application/json',
};

int _maxBytesForKind(UniversalMediaKind kind) => switch (kind) {
  UniversalMediaKind.image => kMaxGeneratedImageBytes,
  UniversalMediaKind.video => kMaxGeneratedVideoBytes,
  UniversalMediaKind.music => kMaxGeneratedMusicBytes,
};

int _maxBytesFor(UniversalMediaKind kind) => _maxBytesForKind(kind);

String _kindLabel(UniversalMediaKind kind) => switch (kind) {
  UniversalMediaKind.image => '图片',
  UniversalMediaKind.video => '视频',
  UniversalMediaKind.music => '音乐',
};

String? _mediaMimeHintFromExtra(
  UniversalMediaKind kind,
  Map<String, dynamic> extra,
) {
  final raw =
      extra['output_format'] ?? extra['outputFormat'] ?? extra['format'];
  if (raw is! String) return null;
  final value = raw.trim().toLowerCase().replaceFirst('.', '');
  if (value.isEmpty) return null;
  if (value.contains('/')) {
    return _mimeMatchesKind(value, kind) ? value : null;
  }
  return switch ((kind, value)) {
    (UniversalMediaKind.image, 'png') => 'image/png',
    (UniversalMediaKind.image, 'jpg' || 'jpeg') => 'image/jpeg',
    (UniversalMediaKind.image, 'webp') => 'image/webp',
    (UniversalMediaKind.image, 'gif') => 'image/gif',
    (UniversalMediaKind.image, 'avif') => 'image/avif',
    (UniversalMediaKind.video, 'mp4') => 'video/mp4',
    (UniversalMediaKind.video, 'webm') => 'video/webm',
    (UniversalMediaKind.video, 'mov' || 'qt') => 'video/quicktime',
    (UniversalMediaKind.music, 'mp3' || 'mpeg') => 'audio/mpeg',
    (UniversalMediaKind.music, 'wav') => 'audio/wav',
    (UniversalMediaKind.music, 'webm') => 'audio/webm',
    (UniversalMediaKind.music, 'ogg' || 'oga') => 'audio/ogg',
    (UniversalMediaKind.music, 'opus') => 'audio/opus',
    (UniversalMediaKind.music, 'm4a' || 'mp4a' || 'mp4') => 'audio/mp4',
    (UniversalMediaKind.music, 'aac') => 'audio/aac',
    (UniversalMediaKind.music, 'flac') => 'audio/flac',
    _ => null,
  };
}

String _fileNameFromPath(String value) {
  final normalized = value.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}

Uint8List _decodeBase64(String value) {
  var normalized = value.replaceAll(RegExp(r'\s+'), '');
  normalized = normalized.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = normalized.length % 4;
  if (remainder != 0) normalized = '$normalized${'=' * (4 - remainder)}';
  return Uint8List.fromList(base64Decode(normalized));
}

bool _isDataUri(String value) => value.trim().toLowerCase().startsWith('data:');

bool _sameOrigin(Uri left, Uri right) {
  final leftScheme = left.scheme.toLowerCase();
  final rightScheme = right.scheme.toLowerCase();
  if (leftScheme != rightScheme ||
      left.host.toLowerCase() != right.host.toLowerCase()) {
    return false;
  }
  int effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  return effectivePort(left) == effectivePort(right);
}

String _mimeFromContentType(
  String value,
  UniversalMediaKind kind, {
  List<int> bytes = const <int>[],
}) {
  final declared = _normalizeMime(value);
  final detected = _detectMimeFromBytes(bytes, kind);
  if (detected != null &&
      (declared == null ||
          declared == 'application/octet-stream' ||
          declared == 'application/json' ||
          !_mimeMatchesKind(declared, kind))) {
    return detected;
  }
  if (declared != null &&
      declared != 'application/octet-stream' &&
      declared != 'application/json' &&
      _mimeMatchesKind(declared, kind)) {
    return declared;
  }
  return detected ??
      switch (kind) {
        UniversalMediaKind.image => 'image/png',
        UniversalMediaKind.video => 'video/mp4',
        UniversalMediaKind.music => 'audio/mpeg',
      };
}

String? _normalizeMime(String value) {
  final normalized = value.split(';').first.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  return switch (normalized) {
    'image/jpg' => 'image/jpeg',
    'audio/x-wav' => 'audio/wav',
    'audio/x-m4a' => 'audio/mp4',
    'application/ogg' || 'application/x-ogg' => 'audio/ogg',
    'application/mp4' => 'video/mp4',
    _ => normalized,
  };
}

String? _firstUsableMime(Iterable<String?> values, UniversalMediaKind kind) {
  for (final value in values) {
    final normalized = _normalizeMime(value ?? '');
    if (normalized != null &&
        normalized != 'application/octet-stream' &&
        normalized != 'application/json' &&
        _mimeMatchesKind(normalized, kind)) {
      return normalized;
    }
  }
  return null;
}

bool _mimeMatchesKind(String mimeType, UniversalMediaKind kind) {
  return switch (kind) {
    UniversalMediaKind.image => mimeType.startsWith('image/'),
    UniversalMediaKind.video => mimeType.startsWith('video/'),
    UniversalMediaKind.music => mimeType.startsWith('audio/'),
  };
}

String? _detectMimeFromBytes(List<int> bytes, UniversalMediaKind kind) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    return 'image/gif';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x66 &&
      bytes[1] == 0x4c &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43) {
    return 'audio/flac';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45) {
    return 'audio/wav';
  }
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return kind == UniversalMediaKind.music ? 'audio/mp4' : 'video/mp4';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x4f &&
      bytes[1] == 0x67 &&
      bytes[2] == 0x67 &&
      bytes[3] == 0x53) {
    return kind == UniversalMediaKind.video ? 'video/ogg' : 'audio/ogg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x1a &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xdf &&
      bytes[3] == 0xa3) {
    return kind == UniversalMediaKind.video ? 'video/webm' : 'audio/webm';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    return 'audio/mpeg';
  }
  return null;
}

String? _mimeFromPath(String path, UniversalMediaKind kind) {
  final normalized = path.split('?').first.split('#').first.toLowerCase();
  final extension = normalized.contains('.')
      ? normalized.substring(normalized.lastIndexOf('.') + 1)
      : '';
  final mime = switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'avif' => 'image/avif',
    'svg' => 'image/svg+xml',
    'mp4' ||
    'm4v' => kind == UniversalMediaKind.music ? 'audio/mp4' : 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => kind == UniversalMediaKind.video ? 'video/webm' : 'audio/webm',
    'ogv' => 'video/ogg',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'ogg' || 'oga' => 'audio/ogg',
    'opus' => 'audio/opus',
    'aac' => 'audio/aac',
    'flac' => 'audio/flac',
    'm4a' => 'audio/mp4',
    _ => null,
  };
  return mime == null || !_mimeMatchesKind(mime, kind) ? null : mime;
}

String _extensionFor(String mimeType, UniversalMediaKind kind) {
  final normalized = _normalizeMime(mimeType) ?? mimeType.toLowerCase();
  return switch (normalized) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/avif' => 'avif',
    'image/bmp' => 'bmp',
    'image/svg+xml' => 'svg',
    'video/webm' => 'webm',
    'video/ogg' => 'ogv',
    'video/quicktime' => 'mov',
    'video/x-msvideo' => 'avi',
    'video/mpeg' => 'mpeg',
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/ogg' => 'ogg',
    'audio/opus' => 'opus',
    'audio/webm' => 'webm',
    'audio/aac' => 'aac',
    'audio/flac' => 'flac',
    'audio/mp4' || 'audio/x-m4a' => 'm4a',
    _ => switch (kind) {
      UniversalMediaKind.image => 'png',
      UniversalMediaKind.video => 'mp4',
      UniversalMediaKind.music => 'mp3',
    },
  };
}

String _formatError(DioException error, {required UniversalMediaKind kind}) {
  if (error.type == DioExceptionType.cancel) return '请求已取消';
  final status = error.response?.statusCode;
  if (status == 404 || status == 405 || status == 501) {
    return '当前渠道不支持${_kindLabel(kind)}生成接口，请检查通用接口路径';
  }
  return formatDioError(error);
}
