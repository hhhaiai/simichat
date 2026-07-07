# 移动端网络稳定性 v1：离线发送保护、联网恢复提示与流式断线取消（2026-07-06）

## 背景

当前移动端已经能显示网络不可用提示，但对话发送链路在离线状态下仍会继续尝试发送。对话智能助理的移动端主体验里，离线时最重要的是不要丢用户正在输入的内容，也不要把无法发送的内容写成一条已发送消息。

## 本轮目标

- 离线时点击发送不进入模型请求链路。
- 离线时保留输入框草稿，方便联网后重试。
- 离线时不向当前会话写入 user message，避免出现“看起来已发送但实际失败”的状态。
- 给用户明确反馈：当前网络不可用，输入已保留。
- 网络从离线恢复到在线后，如果仍有被离线阻断的草稿，提示用户可以发送保留输入。
- 联网恢复提示必须绑定到触发离线阻断的会话，避免用户切换到其他会话时误弹旧会话的重试提示。
- 已经开始生成的流式请求遇到网络断开时，必须停止所有已加载会话的流式状态，保留可重试错误条，不继续显示“生成中”。
- 网络恢复后，对被断网中断的流式请求只提示用户手动重试 / 重试全部，不做自动重发。
- 应用启动 / 恢复订阅网络流前先读取一次当前平台网络状态，避免离线启动时因等待网络变化事件而短暂误判在线。
- 网络结果列表为空时按离线处理；列表中只要存在一个非 `none` 传输就按在线处理，降低切换瞬间混合状态误判风险。
- 提供 Android 真机断网 → 恢复 smoke 入口，并验证离线草稿不丢、恢复提示可见、不写入失败消息。

## 实现

- `lib/features/chat/chat_page.dart`
  - 在 `_handleSend()` 中保留原有“流式中点击发送=停止”的优先级。
  - 在空内容判断之后、进入提交状态之前读取 `isOnlineProvider`。
  - 当 `isOnlineProvider == false` 时记录 `_blockedSendWhileOffline=true`，展示 SnackBar：`当前网络不可用，已保留输入，联网后可重试`，并返回 `false`。
  - 返回 `false` 后，`ChatInputBar` 不会清空待发送文本或附件。
  - 使用 `_blockedSendWhileOfflineSessionId` 记录触发离线阻断的会话 ID。
  - 监听 `isOnlineProvider` 从 `false` 恢复为 `true`；只有当前会话仍是触发阻断的会话且输入框仍有草稿，才展示 SnackBar：`网络已恢复，可发送保留的输入`。
  - 离线 / 恢复两类网络提示显式使用 `SnackBarBehavior.fixed`，避免 390×844 真机视口 + 软键盘 + 全局 floating SnackBar 时触发 Flutter `Floating SnackBar presented off screen` 断言。
  - 真正发送成功后清除 `_blockedSendWhileOfflineSessionId` 和草稿缓存，避免后续误提示。
- `lib/shared/providers/connectivity_provider.dart`
  - 新增可注入 `ConnectivityMonitor`，生产实现仍使用 `connectivity_plus`。
  - `connectivityProvider` 订阅实时网络变化前先 `checkConnectivity()` 并发出初始状态。
  - 如果初始 `checkConnectivity()` 抛错，不让 Provider 永久停在错误态，而是保持保守默认并继续监听后续网络变化事件。
  - `isOnlineConnectivityResults()` 统一归一化网络结果：空列表和仅 `none` 为离线，存在任意有效传输为在线。
- `lib/main.dart`
  - `ResponsiveShell` 监听 `isOnlineProvider` 的 `true -> false` 变化。
  - 断网时复用后台切出同一套“已加载会话流式状态枚举”逻辑，取消当前 active 会话和会话列表中所有 `isStreaming=true` 的请求。
  - 断网取消后设置 `networkStreamingInterruptedMessage`，展示 `网络连接断开，已停止生成，联网后可重试`。
  - 网络恢复时只对仍处于断网错误态的会话弹一次提示：单会话为 `网络已恢复，可点“重试”继续`，多会话为 `网络已恢复，N 个会话可点“重试全部”继续`。
- `lib/shared/providers/chat_provider.dart`
  - `cancelStreaming(..., error)` 的中断错误保留机制从后台专用扩展为通用中断错误 map，避免断网取消后异步 `_runAssistantResponse()` 醒来又把半截内容落库为 assistant 消息。
  - 新增 `networkStreamingInterruptedMessage`：`网络连接断开，已停止本次生成，联网后可重试。`

## 回归测试

- `test/shared/chat_page_offline_test.dart`
  - 构造内存 SQLite、一个可用模型和一个会话。
  - 覆盖 `isOnlineProvider=false`。
  - 输入 `offline draft 20260706` 后点击发送。
  - 断言：输入仍可见、离线提示出现、会话消息表仍为空、无 Flutter 异常。
  - 新增联网恢复用例：用 `connectivityProvider` 流模拟 `none -> wifi`，断言恢复提示出现、草稿仍保留、数据库仍未写入失败消息。
  - 新增会话隔离用例：A 会话离线发送被阻断后切到 B 会话并输入 B 草稿，模拟网络恢复，断言不会在 B 会话误弹 A 会话的恢复提示，两个会话数据库都不写入失败消息。
- `test/shared/connectivity_provider_test.dart`
  - 覆盖空列表、仅 `none`、单一 Wi-Fi、`none + mobile` 混合状态的在线判断。
  - 用 fake `ConnectivityMonitor` 验证 Provider 会先发出 `checkConnectivity()` 初始结果，再响应后续变化流。
  - 用 fake `ConnectivityMonitor` 验证初始探测抛错后仍会继续监听变化流，并在后续 `none` 事件到来后更新为离线。
- `test/smoke/mobile_main_flow_smoke_test.dart`
  - 新增 `mobile network loss cancels active streaming response`：模拟当前会话处于流式输出中，`connectivityProvider` 发出 `none` 后必须清空流式状态、展示断网错误条和断网停止提示，且不写入后台中断持久化 marker；恢复 Wi-Fi 后展示手动重试提示。
  - 新增 `mobile network loss cancels all streaming sessions`：当前会话和非当前会话都处于 streaming 时，断网会同时取消两条；联网恢复后显示 `重试全部`，仍不自动重发。
- `integration_test/mobile_network_restore_smoke_test.dart`
  - 使用真实 `connectivity_plus` 状态，不覆盖网络 Provider。
  - 在脚本断开 Wi-Fi / 移动数据后启动应用，等待 `网络已断开`，输入草稿并点击发送。
  - 断言离线提示、草稿保留、SQLite 不写入 user message。
  - 打印 `SIMICHAT_NETWORK_RESTORE_READY` 后由脚本恢复 Wi-Fi / 移动数据，再断言恢复提示出现、草稿仍保留、数据库仍为空。
- `scripts/smoke_android_network_restore.sh`
  - 默认安全拒绝真实断网；必须显式 `REAL_NETWORK_TOGGLE=1` 才会执行。
  - 只支持 Android adb 设备；会临时断开 Wi-Fi / data，看到测试 READY 标记后恢复，退出时也会兜底恢复网络和 pubspec。

## 验证记录

```bash
flutter --no-version-check test --no-pub -r expanded test/shared/chat_page_offline_test.dart
flutter --no-version-check test --no-pub -r expanded test/shared/connectivity_provider_test.dart
flutter --no-version-check analyze
flutter --no-version-check test --no-pub -r expanded \
  test/shared/connectivity_provider_test.dart \
  test/shared/chat_page_offline_test.dart \
  test/shared/chat_page_tts_playback_event_test.dart \
  test/smoke/mobile_main_flow_smoke_test.dart
flutter --no-version-check test --no-pub -r expanded \
  test/smoke/mobile_main_flow_smoke_test.dart \
  --name "mobile network loss"
bash -n scripts/smoke_android_network_restore.sh
REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_restore.sh 37101FDJH0077P
REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_restore.sh 37101FDJH0077P
scripts/smoke_android_release_install_launch.sh 37101FDJH0077P
```

结果：新增离线发送、联网恢复提示与跨会话隔离回归通过；新增网络 Provider 启动探测 / 结果归一化 / 初始探测失败降级 3 项回归通过；静态分析无问题；受影响脚本清单 / 网络 Provider / 聊天页 / TTS / 移动主流程共 21 项测试通过；`flutter --no-version-check analyze` 无问题；`git diff --check` 无输出；此前同轮全量稳定性 gate 351 项测试通过。

2026-07-07 补充断网中断流式请求代码级回归：

- iOS release send 修复复跑前，`./scripts/smoke_ios_release_send.sh 00008110-0016349A3A20A01E` 被安装前解锁预检安全拒绝：`launch preflight did not prove the device is unlocked`，未覆盖安装 smoke 包。
- 转向本地可验证的网络断开流式保护后，新增两条移动主流程测试。
- 首轮目标测试先红灯于断言过窄：同屏同时存在错误条和 SnackBar action 两个 `重试`；业务状态已经正确，修正为 `findsWidgets` 后复跑通过。
- 验证命令：`flutter --no-version-check test --no-pub -r expanded test/smoke/mobile_main_flow_smoke_test.dart --name "mobile network loss"`，2 项通过。
- 配套回归：`flutter --no-version-check test --no-pub -r expanded test/shared/connectivity_provider_test.dart test/shared/chat_page_offline_test.dart test/core/release_send_smoke_manifest_test.dart`，16 项通过。
- 静态检查：`flutter --no-version-check analyze` 无问题。
- 全量理论门禁：`./scripts/smoke_full_stability_gate.sh -r expanded`，379 项通过。
- 卫生检查：`git diff --check` 无输出；正式 `pubspec.yaml` / `pubspec.lock` 不保留临时 `sqlite3.source=system` hook。

真实 Android 网络切换补证：

- 先确认 `scripts/smoke_android_network_restore.sh` 默认拒绝真实断网，退出码 2 且提示 `Refusing to toggle device network`。
- 初版固定延迟恢复网络曾在 Pixel 8 上失败：恢复可能早于测试确认离线状态，导致等待 `网络已断开` 超时；脚本改为监听 `SIMICHAT_NETWORK_RESTORE_READY` 后再恢复网络。
- 真机复跑暴露 Flutter UI 问题：全局 floating SnackBar 在 390×844 + 软键盘场景下触发 `Floating SnackBar presented off screen`；修复为网络离线 / 恢复提示显式 fixed SnackBar 后复跑通过。
- 最终 `REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_restore.sh 37101FDJH0077P` 通过：脚本断开 Wi-Fi / data，测试输出 `SIMICHAT_NETWORK_RESTORE_READY` 后恢复网络，`mobile network restore smoke keeps offline draft` 通过。随后 `REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_restore.sh 37101FDJH0077P` 通过：脚本启用 Android airplane mode，测试输出 READY 标记后关闭飞行模式并恢复 Wi-Fi / data；补充 `adb shell cmd connectivity airplane-mode` 返回 `disabled`。
- 因 integration runner 会安装 debug 包，随后运行 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，构建 `app-release.apk` 31.5MB，`adb install -r` 成功并启动；Wi-Fi/data smoke 后 release pid `31267` 可见，airplane smoke 后 release pid `32254` 可见；本轮未触碰 people 主力机。

补充真机稳定性：同日通过 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 在 Pixel 8 构建 31.5MB release APK、`adb install -r` 覆盖安装并启动，`firstInstallTime=2026-07-06 15:07:44` 保持不变，`lastUpdateTime=2026-07-06 15:33:20` 更新，`dataDir=/data/user/0/top.simitalk.aichat`，release 进程 pid `5312` 可见；本轮未触碰 people 主力机。

2026-07-07 补充 Android 真机物理断网流式取消 smoke：

- 新增 `integration_test/mobile_network_stream_cancel_smoke_test.dart` 与 `scripts/smoke_android_network_stream_cancel.sh`。
- 脚本默认拒绝真实断网，必须 `REAL_NETWORK_TOGGLE=1`；收到 `SIMICHAT_NETWORK_STREAM_CANCEL_READY` 后才断开 Wi-Fi / data，收到 `SIMICHAT_NETWORK_STREAM_CANCEL_INTERRUPTED` 后恢复网络。
- 首轮红灯来自过强的 loopback socket 断开断言：应用已经进入断网取消态，但设备内 mock 8 秒内未观察到 socket 关闭；取消传播已有独立 SSE / 后台慢流 smoke 覆盖，本 smoke 改为聚焦物理网络事件触发的 UI / 状态 / 数据库结果。
- `REAL_NETWORK_TOGGLE=1 scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P` 通过：输出 READY 后断网，输出 INTERRUPTED 后恢复网络，测试验证 `networkStreamingInterruptedMessage`、恢复提示、仅 1 条 user 消息且无 assistant 半截回复。
- 随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，31.5MB APK 覆盖安装并启动 pid `7197`；复核 Pixel 8 飞行模式关闭、Wi-Fi enabled、Active default network 为 `WIFI CONNECTED / IS_VALIDATED`。
- 配套门禁：`test/core/release_send_smoke_manifest_test.dart` 10 项通过；`flutter --no-version-check analyze` 无问题；`./scripts/smoke_full_stability_gate.sh -r expanded` 380 项通过；`git diff --check` 无输出。

2026-07-07 补充 airplane streaming cancel 复跑：

- `REAL_NETWORK_TOGGLE=1 NETWORK_TOGGLE_MODE=airplane scripts/smoke_android_network_stream_cancel.sh 37101FDJH0077P` 通过：READY 后启用 airplane mode，INTERRUPTED 后恢复网络，测试 1 项通过。
- 随后 `scripts/smoke_android_release_install_launch.sh 37101FDJH0077P` 恢复普通 release，31.5MB APK 覆盖安装并启动 pid `8774`，`lastUpdateTime=2026-07-07 11:19:07`。
- 复核 Pixel 8 飞行模式关闭、Wi-Fi enabled、Active default network 为 `WIFI CONNECTED / IS_VALIDATED`。


2026-07-07 补充 iOS release 网络恢复 smoke 入口：

- 新增 `lib/core/smoke/release_network_smoke_harness.dart`。
- release 包通过 `SIMICHAT_RELEASE_NETWORK_SMOKE=true` 进入专用 harness，覆盖内存 SQLite 与 fake `ConnectivityMonitor`，在真实 release app 进程内模拟 `wifi -> none -> wifi`。
- harness 等待 `isOnlineProvider` 从在线变为离线，再恢复在线；结果写入应用 Documents：`ai_chat/release_network_smoke/ios-release-network-smoke.json`，包含 `SIMICHAT_RELEASE_NETWORK_READY`、离线提示 `当前网络不可用，已保留输入，联网后可重试` 和恢复提示 `网络已恢复，可发送保留的输入`。
- 新增 `scripts/smoke_ios_release_network_restore.sh`，采用 iOS release-only 路径：安装 smoke 包前先执行 `assert_device_unlocked_for_launch`；Locked / timeout / 未证明解锁都在 build / install 前退出 2；构建时临时启用 `sqlite3.source=system`，退出时恢复 `pubspec.yaml` / `pubspec.lock`；安装 smoke 包后失败或成功都会默认恢复普通 release。
- 本入口不物理切换 iPhone 网络，只做 release 包内 fake connectivity 门禁；真实 iOS Wi-Fi / 蜂窝 / 飞行模式切换仍待设备可用后补。
- 验证：先红灯于缺少 `release_network_smoke_harness.dart` / `smoke_ios_release_network_restore.sh`；修复后 `bash -n scripts/smoke_ios_release_network_restore.sh` 通过，`flutter --no-version-check test --no-pub -r expanded test/core/release_send_smoke_manifest_test.dart --name "iOS release network restore smoke"` 通过，完整 `test/core/release_send_smoke_manifest_test.dart` 14 项通过，`flutter --no-version-check analyze` 无问题。本轮未触碰 people。

## 边界

本轮覆盖离线发送保护与前台断网中断流式请求，不等同于完整网络恢复队列。仍待补：

- 网络恢复后自动重试队列；当前对离线草稿提示用户可发送保留输入，对断网中断的流式请求提示用户显式点击“重试 / 重试全部”。
- Android 已有 Pixel 8 Wi-Fi / data 断开 → 恢复 smoke、airplane mode 断开 → 恢复 smoke，以及 Wi-Fi / data 与 airplane mode 两种物理断网触发前台 streaming 取消 smoke；iOS 已补 release fake connectivity harness / 脚本入口；真机物理网络切换和更细蜂窝场景仍待补。
- 后台恢复后未完成请求的状态复原。
