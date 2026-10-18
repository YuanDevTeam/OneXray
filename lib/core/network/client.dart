import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/network/model.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

class NetClient {
  static final NetClient _singleton = NetClient._internal();

  factory NetClient() => _singleton;

  NetClient._internal()
    : _downloadClient = Dio(
        BaseOptions(
          connectTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(seconds: 60),
        ),
      );

  @visibleForTesting
  NetClient.forTesting(Dio client)
    : _downloadClient = client,
      _initFuture = Future.value();

  //========================
  final Dio _downloadClient;

  Future<void>? _initFuture;

  String get downloadUserAgent =>
      _downloadClient.options.headers['User-Agent']?.toString() ?? '';

  Future<void> asyncInit() {
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    _downloadClient.options.headers['User-Agent'] = await defaultUserAgent();
  }

  static Future<String> defaultUserAgent() async {
    var version = '0.0.0';
    var userAgent = 'OneXray (${Platform.operatingSystem})';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      version = packageInfo.version;
      userAgent =
          'OneXray/$version '
          '(${packageInfo.packageName}; build:${packageInfo.buildNumber}; '
          '${Platform.operatingSystem})';
    } catch (error) {
      ygLogger('Unable to build the OneXray User-Agent: $error');
    }
    // Providers can select an Xray JSON template by this leading product.
    return 'v2rayN/$version $userAgent';
  }

  static const _maxDownloadRedirects = 8;

  static bool isHttpsDownloadUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.port > 0 &&
      uri.port <= 65535;

  Future<String?> getText(
    String url, {
    DownloadRequestHeaders? requestHeaders,
    bool httpsOnly = false,
  }) async =>
      (await getTextResponse(
        url,
        requestHeaders: requestHeaders,
        httpsOnly: httpsOnly,
      )).data ??
      '';

  Future<Response<String>> getTextResponse(
    String url, {
    DownloadRequestHeaders? requestHeaders,
    bool httpsOnly = false,
  }) async {
    try {
      var uri = Uri.parse(url);
      if (httpsOnly && !isHttpsDownloadUri(uri)) {
        throw const AppFailure(
          FailureCategory.input,
          'downloadUrl',
          cause: 'A valid HTTPS download URL is required',
        );
      }
      await asyncInit();
      final headers = requestHeaders?.toHttpHeaders();
      for (
        var redirectCount = 0;
        redirectCount <= _maxDownloadRedirects;
        redirectCount++
      ) {
        final res = await _downloadClient.getUri<String>(
          uri,
          options: Options(
            responseType: ResponseType.plain,
            headers: headers,
            followRedirects: false,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        );
        final status = res.statusCode ?? 0;
        if (status < 300) {
          return res;
        }
        final location = res.headers.value(HttpHeaders.locationHeader);
        if (location == null ||
            location.isEmpty ||
            redirectCount == _maxDownloadRedirects) {
          throw const AppFailure(
            FailureCategory.network,
            'redirect',
            cause: 'Missing redirect location or too many redirects',
          );
        }
        final next = uri.resolve(location);
        if (next.scheme != uri.scheme ||
            next.host != uri.host ||
            next.port != uri.port) {
          // Consent belongs to the subscription origin, not a redirect target.
          // Do not restore the identifier later in the redirect chain.
          headers?.remove('x-hwid');
        }
        uri = next;
        if (httpsOnly && !isHttpsDownloadUri(uri)) {
          throw const AppFailure(
            FailureCategory.network,
            'redirect',
            cause: 'Download redirected to a non-HTTPS URL',
          );
        }
      }
      throw const AppFailure(
        FailureCategory.network,
        'redirect',
        cause: 'Too many download redirects',
      );
    } catch (e) {
      // Subscription URLs can contain credentials; never log the request URI.
      ygLogger('text download failed: ${failureDetails(e)}');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getJson(String url) async {
    try {
      await asyncInit();
      final res = await _downloadClient.get<Map<String, dynamic>>(url);
      return res.data;
    } catch (e) {
      ygLogger('JSON download failed: ${failureDetails(e)}');
      rethrow;
    }
  }
}
