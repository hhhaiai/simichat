# Android production Release parity 验收记录

日期：2026-08-18（当前工作树复验）

## 验收目标

证明当前工作树的 production Release 构建链路为：

```text
当前工作树
  -> build/app/outputs/flutter-apk/app-production-release.apk
  -> adb install -r
  -> 设备已安装包的 /base.apk
```

正式包固定为 `top.simitalk.aichat`。验收脚本不允许通过环境变量改写正式包、启动组件或 APK 路径；正式包只允许使用 `install -r` 覆盖安装，不执行 `uninstall`、`pm clear` 或正式包 `force-stop`。

## 契约加固

- `android/app/build.gradle.kts`
  - 保留 `production`、`modelswitch`、`realtimepcm` 三个 flavor。
  - `productionRelease` 强制保持 `applicationId=top.simitalk.aichat`；`simichatApplicationId` 仍可供隔离 debug smoke 使用，但不能污染 production Release。
  - 显式设置 `release.isDebuggable=false`。
- `scripts/smoke_android_release_install_launch.sh`
  - 固定 `FLAVOR=production` 和当前工作树下的 `app-production-release.apk`。
  - 使用 `aapt` 检查 APK applicationId，并拒绝 `application-debuggable` / `testOnly`。
  - 使用 `apksigner verify --verbose --print-certs` 检查签名方案和证书 SHA-256；覆盖安装前比较旧包与新 APK 的证书，安装后再次比较设备 `base.apk` 的证书。
  - 使用 `pm path` 要求首个包路径为 `base.apk`，对工作树 APK 与设备 `base.apk` 做 SHA-256 精确比较。
  - 安装前后检查正式包 identity、`firstInstallTime`、`dataDir` 和 release flags。
  - 安装前后扫描 `top.simitalk.aichat.` 子命名空间；发现任意隔离 smoke 包残留时直接拒绝，不尝试清理或覆盖正式包。
- `test/android_variant_contract_test.dart`
  - 锁定上述 flavor、identity、签名、flags、hash、`base.apk`、数据目录保留和正式包操作边界。

## 已执行验证

### 静态测试

```text
flutter --no-version-check test --no-pub --no-test-assets test/android_variant_contract_test.dart -r expanded
```

- 修复前基线：6 项通过。
- 修复后最终结果：6 项通过。
- `bash -n scripts/smoke_android_release_install_launch.sh`：通过。
- 该测试未连接或操作 Android 真机。

### Gradle variant / identity 约束

```text
./gradlew :app:preProductionReleaseBuild :app:validateSigningProductionRelease
```

- 默认 production Release 配置：通过。
- `-PsimichatApplicationId=top.simitalk.aichat.dreamingsmoke`：按契约失败，并报告 `productionRelease must keep applicationId=top.simitalk.aichat`。

### 当前本地 APK 静态取证

文件：

```text
/Users/sanbo/code/simichat/build/app/outputs/flutter-apk/app-production-release.apk
```

- `aapt dump badging`：`package name='top.simitalk.aichat'`。
- APK 未出现 `application-debuggable` 或 `testOnly`。
- `apksigner`：`Verifies`；APK Signature Scheme v2 为 `true`。
- signer certificate SHA-256：
  `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`。
- APK SHA-256：以最后一次真实设备复验输出为准，见下方“Pixel 8 真机复验”。

### 无真机 fake-ADB 闭环

使用临时 fake `adb` 返回固定的 production `Package`、`base.apk`、release flags、`firstInstallTime` 和 `dataDir`，并让 `exec-out cat` 返回上述本地 APK；脚本完整跑通并输出：

```text
ANDROID_RELEASE_ISOLATED_PACKAGE_CHECK stage=pre_install status=clean
ANDROID_RELEASE_ISOLATED_PACKAGE_CHECK stage=post_install status=clean
ANDROID_RELEASE_APK_IDENTITY ... package=top.simitalk.aichat flags=none
ANDROID_RELEASE_POST_INSTALL ... baseApk=/data/app/fake/top.simitalk.aichat/base.apk apkHash=6641041d728a906ed24947c958b90df376f6f2273fbf125d689c984a55423519 builtApkHash=6641041d728a906ed24947c958b90df376f6f2273fbf125d689c984a55423519
ANDROID_RELEASE_PARITY status=verified
ANDROID_RELEASE_FINAL_STATE ... firstInstallTime=2026-08-18 07:00:00 dataDir=/data/user/0/top.simitalk.aichat
```

该 fake-ADB 运行只验证脚本控制流和校验逻辑，不等同于 Android 真机验收。

## Pixel 8 真机复验（2026-08-18 09:33）

命令：

```text
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：

- 当前工作树重新构建 `app-production-release.apk` 成功，大小约 81.9 MB。
- `adb install -r` 返回 `Success`；正式包未执行 `uninstall`、`pm clear` 或正式包 `force-stop`。
- `ANDROID_RELEASE_PARITY status=verified`。
- 构建 APK 与设备 `/base.apk` SHA-256 均为：
  `7fc496f509e80fd2c4a5598a7e59717a889a14d4a47406534508e5fd3511e9fc`。
- 设备中的 `base.apk`：
  `/data/app/~~rDn432BVM43B7q3aD0PLrA==/top.simitalk.aichat-R3NgdvMPtFa2dnGojOGaJw==/base.apk`。
- signer certificate SHA-256：
  `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`。
- `firstInstallTime=2026-08-18 07:11:12`、
  `dataDir=/data/user/0/top.simitalk.aichat` 保持不变。
- `lastUpdateTime=2026-08-18 09:33:06`，PID `22676` 可见。
- 当前前台 Activity 为 `top.simitalk.aichat/.MainActivity`。
- `top.simitalk.aichat.` 子命名空间没有隔离 smoke 包残留。

当前 `release` 仍使用 `signingConfigs.getByName("debug")`。本契约验证的是 APK 可验证、覆盖安装前后证书一致以及设备 `base.apk` 与构建 APK 完全一致；它不把 debug certificate 误判为正式发布证书。正式分发前仍需接入正式 release keystore。

## Pixel 8 真机复验（2026-08-18 12:09）

命令：

```text
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：

- 当前工作树重新构建 `app-production-release.apk` 成功，随后只执行 `adb install -r` 覆盖安装并返回 `Success`；`ANDROID_RELEASE_PARITY status=verified`。
- 构建 APK 与设备 `/base.apk` SHA-256 均为：
  `cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d`。
- signer certificate SHA-256：
  `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`。
- 安装后正式包 `top.simitalk.aichat` 的 `versionName=1.0.0`、`versionCode=1`、`firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 保持有效；`lastUpdateTime=2026-08-18 12:09:37`，PID `32261` 可见，前台 Activity 为 `top.simitalk.aichat/.MainActivity`。
- 隔离模型切换 smoke 随后通过，输出 `SIMICHAT_MODEL_SWITCH_BASELINE`、`SIMICHAT_MODEL_SWITCH_UI_ACTION`、`SIMICHAT_MODEL_SWITCH_DB_EVIDENCE`、`SIMICHAT_MODEL_SWITCH_SMOKE_PASS`、`SMOKE_TEST_EXIT status=0`；隔离包 `top.simitalk.aichat.modelswitch` 已清理，正式包 hash、`firstInstallTime` 和 `dataDir` 未变化。
- 正式包未执行 `uninstall`、`pm clear` 或 `am force-stop`；`git diff --check` 无输出。全量 Flutter 测试 1030 项和 analyze 结果属于当前工作树本地门禁，不等同于真实第三方云端媒体 / 语音 E2E。

## Pixel 8 当前 Android release/model-switch 切片（2026-08-18 12:21–12:25）

执行设备：Pixel 8，serial `37101FDJH0077P`；正式包固定为 `top.simitalk.aichat`。

### 正式包 `install -r` 覆盖安装

命令：

```text
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

关键真实输出：

```text
ANDROID_RELEASE_ISOLATED_PACKAGE_CHECK stage=pre_install status=clean prefix=top.simitalk.aichat.
ANDROID_RELEASE_PRE_INSTALL package=top.simitalk.aichat firstInstallTime=2026-08-18 07:11:12 dataDir=/data/user/0/top.simitalk.aichat apk=/data/app/~~ldVetp459SOwa3bMl6bW6w==/top.simitalk.aichat-hBgZxZi8F8hBNOXFUROe2Q==/base.apk apkHash=cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d
ANDROID_RELEASE_APK_IDENTITY source=/Users/sanbo/code/simichat/build/app/outputs/flutter-apk/app-production-release.apk package=top.simitalk.aichat flags=none
ANDROID_RELEASE_APK_SIGNATURE stage=built certSha256=30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42 schemes=Verified using v2 scheme (APK Signature Scheme v2): true
Performing Streamed Install
Success
ANDROID_RELEASE_ISOLATED_PACKAGE_CHECK stage=post_install status=clean prefix=top.simitalk.aichat.
ANDROID_RELEASE_POST_INSTALL package=top.simitalk.aichat installedPackage=top.simitalk.aichat firstInstallTime=2026-08-18 07:11:12 dataDir=/data/user/0/top.simitalk.aichat baseApk=/data/app/~~buHKlXxQm5LlKN_oGjqqFg==/top.simitalk.aichat-hkT1vVqB6BuRTOTG_FOdKA==/base.apk apkHash=cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d builtApkHash=cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d
ANDROID_RELEASE_PARITY status=verified source=/Users/sanbo/code/simichat/build/app/outputs/flutter-apk/app-production-release.apk baseApk=/data/app/~~buHKlXxQm5LlKN_oGjqqFg==/top.simitalk.aichat-hkT1vVqB6BuRTOTG_FOdKA==/base.apk package=top.simitalk.aichat apkHash=cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d certSha256=30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42 firstInstallTime=2026-08-18 07:11:12 dataDir=/data/user/0/top.simitalk.aichat lastUpdateTime=2026-08-18 12:21:56
SIMICHAT_ANDROID_RELEASE_LAUNCH_RESULT status=success mode=monkey component=top.simitalk.aichat/.MainActivity package=top.simitalk.aichat pid=1642
ANDROID_RELEASE_FINAL_STATE package=top.simitalk.aichat firstInstallTime=2026-08-18 07:11:12 dataDir=/data/user/0/top.simitalk.aichat
```

- 构建 APK：`/Users/sanbo/code/simichat/build/app/outputs/flutter-apk/app-production-release.apk`，SHA-256 为 `cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d`；设备 `base.apk` 与构建 APK 完全一致。
- signer certificate SHA-256 为 `30e29ac7421f4b6f4cbc0dc086be0d0b9b16260c58747290edccf4391b33eb42`，v2 签名验证通过。
- `firstInstallTime=2026-08-18 07:11:12`、`dataDir=/data/user/0/top.simitalk.aichat` 在覆盖安装前后保持不变；`lastUpdateTime=2026-08-18 12:21:56`。
- release 脚本使用 `monkey` 启动并观察到 PID `1642`。随后用不停止正式包的 `adb shell monkey -p top.simitalk.aichat -c android.intent.category.LAUNCHER 1` 复核，`topResumedActivity` / `mFocusedApp` 均为 `top.simitalk.aichat/.MainActivity`，PID 仍为 `1642`。
- 脚本没有对正式包执行 `uninstall`、`pm clear` 或 `am force-stop`。

### 隔离 `modelswitch` smoke

命令：

```text
scripts/smoke_device_integration_model_switch.sh 37101FDJH0077P
```

关键真实输出：

```text
SMOKE_TARGET formalPackage=top.simitalk.aichat smokePackage=top.simitalk.aichat.modelswitch flavor=modelswitch device=37101FDJH0077P test=integration_test/mobile_model_switch_smoke_test.dart
SMOKE_DEBUG_RUNNER_INSTALLED package=top.simitalk.aichat.modelswitch flavor=modelswitch apk=.../app-modelswitch-debug.apk dataDir=/data/user/0/top.simitalk.aichat.modelswitch installMode=覆盖安装(-r -d)
SMOKE_FORMAL_PACKAGE_STATE stage=smoke-install package=top.simitalk.aichat ... apkHash=cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d firstInstallTime=2026-08-18 07:11:12 dataDir=/data/user/0/top.simitalk.aichat
SIMICHAT_MODEL_SWITCH_BASELINE session=model-switch-session defaultChannelModelId=model-switch-first selectedModelId=model-switch-first
SIMICHAT_MODEL_SWITCH_UI_ACTION selector=top_app_bar option=switch-model-b
SIMICHAT_MODEL_SWITCH_DB_EVIDENCE session=model-switch-session defaultChannelModelId=model-switch-second selectedModelId=model-switch-second messageType=model_switch messageChannelModelId=model-switch-second
SIMICHAT_MODEL_SWITCH_SMOKE_PASS session=model-switch-session from=model-switch-first to=model-switch-second systemMessageCount=1
SMOKE_TEST_EXIT status=0 flavor=modelswitch package=top.simitalk.aichat.modelswitch
SMOKE_DEBUG_RUNNER_CLEANED package=top.simitalk.aichat.modelswitch flavor=modelswitch cleanup=already-removed
SMOKE_FORMAL_PACKAGE_STATE stage=cleanup package=top.simitalk.aichat ... apkHash=cb27e060e282857ac51b530bf0f29390a6f8c9b3024bd0f3f3c7fd40272a8c7d firstInstallTime=2026-08-18 07:11:12 dataDir=/data/user/0/top.simitalk.aichat
SMOKE_FORMAL_PACKAGE_PRESERVED package=top.simitalk.aichat ...
```

- 四个 marker 在 `/tmp/simichat-model-switch-20260818122208-53048.log` 中均恰好出现 1 次，顺序为 `BASELINE -> UI_ACTION -> DB_EVIDENCE -> SMOKE_PASS`。
- 集成测试 `All tests passed!`，`SMOKE_TEST_EXIT status=0`；切换前后 session 默认模型、Provider 当前模型和 `model_switch` system message 的 `channelModelId` 均有 DB 证据。
- `top.simitalk.aichat.modelswitch` 的独立 `dataDir` 为 `/data/user/0/top.simitalk.aichat.modelswitch`，未复用正式包数据目录。Flutter runner 已先清理隔离包，脚本报告 `cleanup=already-removed`；复核 `pm list packages` 未发现 `top.simitalk.aichat.` 子命名空间残留。
- smoke 前、安装后、cleanup 后正式包的 `base.apk` 路径、SHA-256、`firstInstallTime`、`dataDir` 均保持不变；未执行正式包卸载、清库或停止。

### 本轮门禁

```text
bash -n scripts/smoke_android_release_install_launch.sh scripts/smoke_device_integration_model_switch.sh
flutter --no-version-check test --no-pub --no-test-assets test/android_variant_contract_test.dart test/model_switch_smoke_manifest_test.dart -r expanded
flutter --no-version-check analyze --no-pub
git diff --check
```

- `bash -n` 通过；契约 / manifest 聚焦测试共 10 项通过；`analyze` 无问题；`git diff --check` 无输出。
- 本轮审计未发现确定性缺口，因此未修改 release/model-switch 脚本、集成测试或契约测试；仅补充本验收记录。

## 后续真机命令

在确认设备处于可用状态、且正式包仍已安装后执行：

```text
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

预期看到 `ANDROID_RELEASE_PARITY status=verified`，且 `ANDROID_RELEASE_FINAL_STATE` 中的 `firstInstallTime`、`dataDir` 与安装前一致；若存在任意隔离 smoke 包残留、identity / flags / 签名 / hash 不匹配，脚本应在启动前或覆盖安装后失败，而不是清理正式包。
