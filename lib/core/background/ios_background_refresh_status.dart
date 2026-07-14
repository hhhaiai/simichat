import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kIosBackgroundRefreshStatusChannelName =
    'simichat/background_refresh_status';

enum IosBackgroundRefreshStatus {
  restricted,
  denied,
  available,
  unsupported,
  unknown;

  String? get settingsSummary => switch (this) {
    IosBackgroundRefreshStatus.restricted => 'iOS 后台 App 刷新受系统限制',
    IosBackgroundRefreshStatus.denied => 'iOS 后台 App 刷新已关闭',
    IosBackgroundRefreshStatus.available => 'iOS 后台 App 刷新可用',
    IosBackgroundRefreshStatus.unknown => 'iOS 后台 App 刷新状态未知',
    IosBackgroundRefreshStatus.unsupported => null,
  };
}

class IosBackgroundRefreshUnavailableException implements Exception {
  const IosBackgroundRefreshUnavailableException(this.status);

  final IosBackgroundRefreshStatus status;

  String get userMessage => switch (status) {
    IosBackgroundRefreshStatus.denied =>
      'iOS 后台 App 刷新已关闭；自动 Dreaming 将使用前台到期兜底，请到系统设置中开启。',
    IosBackgroundRefreshStatus.restricted =>
      'iOS 后台 App 刷新受系统限制；自动 Dreaming 将使用前台到期兜底。',
    _ => 'iOS 系统后台暂不可用；自动 Dreaming 将使用前台到期兜底。',
  };

  @override
  String toString() => userMessage;
}

const _iosBackgroundRefreshStatusChannel = MethodChannel(
  kIosBackgroundRefreshStatusChannelName,
);

Future<IosBackgroundRefreshStatus> readIosBackgroundRefreshStatus() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return IosBackgroundRefreshStatus.unsupported;
  }
  try {
    final raw = await _iosBackgroundRefreshStatusChannel.invokeMethod<int>(
      'getBackgroundRefreshStatus',
    );
    return switch (raw) {
      0 => IosBackgroundRefreshStatus.restricted,
      1 => IosBackgroundRefreshStatus.denied,
      2 => IosBackgroundRefreshStatus.available,
      _ => IosBackgroundRefreshStatus.unknown,
    };
  } on PlatformException {
    return IosBackgroundRefreshStatus.unknown;
  } on MissingPluginException {
    return IosBackgroundRefreshStatus.unknown;
  }
}

Future<bool> openIosAppSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    return await _iosBackgroundRefreshStatusChannel.invokeMethod<bool>(
          'openAppSettings',
        ) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

Future<void> ensureIosBackgroundRefreshAvailable({
  Future<IosBackgroundRefreshStatus> Function()? statusReader,
}) async {
  final status = await (statusReader ?? readIosBackgroundRefreshStatus)();
  if (status == IosBackgroundRefreshStatus.denied ||
      status == IosBackgroundRefreshStatus.restricted) {
    throw IosBackgroundRefreshUnavailableException(status);
  }
}

final iosBackgroundRefreshStatusProvider =
    FutureProvider<IosBackgroundRefreshStatus>((ref) {
      return readIosBackgroundRefreshStatus();
    });
