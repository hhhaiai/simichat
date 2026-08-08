# iOS release 发送链路 smoke（2026-07-06）

## 背景

用户明确要求：iOS 必须使用 release 版本运行，debug / Flutter integration debug runner 不作为 iOS 有效运行证明。

因此本轮新增 release-only 自动取证入口：

```bash
./scripts/smoke_ios_release_send.sh <device-id>
```

脚本只在构建参数显式打开时启用 smoke harness：

```bash
--dart-define=SIMICHAT_RELEASE_SEND_SMOKE=true
--dart-define=SIMICHAT_RELEASE_SMOKE_RUN_ID=<run-id>
```

普通 release 构建不启用该 harness。脚本默认在取证完成后重新构建并覆盖安装普通 release 包，避免设备长期停留在 smoke 专用包。

## 覆盖范围

本轮验证的是 release app 内的真实发送核心链路：

1. release 包启动后创建内存 SQLite smoke 数据库。
2. 注入 OpenAI Chat 兼容 mock 渠道和模型。
3. 调用正式 `sendMessage` 主路径发送用户消息。
4. 设备内 `dart:io` mock 服务接收 `/v1/chat/completions` SSE 请求。
5. assistant 回复落库。
6. 写出脱敏 JSON 结果到应用私有目录。
7. 通过 `devicectl device copy from` 拉回结果文件。
8. 校验 runId、状态、reply、请求 path / model / lastUser。
9. 自动恢复普通 release 包并启动。

为避免污染真实聊天档案：

- smoke 数据库使用内存 SQLite，不写入真实 `db.sqlite`。
- `chat_provider` 在 `SIMICHAT_RELEASE_SEND_SMOKE=true` 且 session 为 `ios-release-smoke-session` 时跳过 Markdown 原始档案追加。
- harness 启动和结束时会清理旧的 `conversations/ios-release-smoke-session.md`。

## 设备

```text
people
CoreDevice UUID: BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D
iPhone 14 Pro Max (iPhone15,3)
```

## 验证命令

```bash
./scripts/smoke_ios_release_send.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D
```

## 关键输出

### 2026-07-06 people 通过记录

```text
Building iOS release send smoke runId=ios-release-send-20260706121606
Building top.simitalk.aichat for device (ios-release)...
✓ Built build/ios/iphoneos/Runner.app (33.2MB)
Installed release app:
- bundleID: top.simitalk.aichat
- databaseSequenceNumber: 6160
Launched release app:
- pid: 64152
iOS release send smoke passed:
- runId: ios-release-send-20260706121606
- reply: IOS release smoke reply 20260706
- request.path: /v1/chat/completions
- request.model: ios-release-smoke-model
- request.lastUser: ios release send smoke
Restoring normal iOS release build without smoke dart-defines...
✓ Built build/ios/iphoneos/Runner.app (33.1MB)
Installed release app:
- bundleID: top.simitalk.aichat
- databaseSequenceNumber: 6168
Launched release app:
- pid: 64165
```

补充取证：

```text
64165 /private/var/containers/Bundle/Application/C0090A47-C003-4B1E-80AF-6CA57DA0AFD0/Runner.app/Runner
SMOKE_ARCHIVE_ABSENT
result.status=passed
result.runId=ios-release-send-20260706121606
result.reply=IOS release smoke reply 20260706
```

### 2026-07-07 iPhone13 复查记录

本轮在 iPhone13 `00008110-0016349A3A20A01E`（CoreDevice `CAFC7AFA-4565-5C8D-B724-090061D144D0`）复跑当前 release send harness。前半段发送 / 重试 / 模型切换已经进入真实 release harness，但停止慢流先红灯：

```text
runId=ios-release-send-20260707100852
runId=ios-release-send-20260707101242
error=stop smoke did not cancel the slow upstream request
lastUser=ios release stop smoke
completed=true
brokenPipe=false
```

根因与修复：

- `cancelStreaming()` 过去只移除 `_streamSubscriptions`，没有显式调用 `StreamSubscription.cancel()`；已修复为移除后 `unawaited(subscription.cancel())`。
- `openSseStream()` 返回的 SSE 字节流已改为 cancellation-aware wrapper：下游订阅被取消且流未正常结束时，会触发 `CancelToken.cancel('SSE stream subscription cancelled')`。
- release send harness 的内置 `dart:io` OpenAI SSE mock 增加 `request.response.bufferOutput = false`，避免 iOS loopback 小 chunk 被服务端缓冲，导致停止验证误判。
- 新增 `OpenAiChatProtocol` 取消传播测试：本地长连接 SSE 收到首个 chunk 后取消订阅，断言 `CancelToken.isCancelled == true`。

随后第三次复跑时设备变为 Locked。旧脚本在 smoke 包安装后才因 launch Locked 失败，本轮立即加固：

- `scripts/smoke_ios_release_send.sh` 安装 smoke 包前新增 launch preflight。
- Locked、timeout 或任何不能证明设备已解锁的预检失败都会退出 2，拒绝安装 smoke 包。
- 如果 smoke 包已经安装后任意步骤失败，trap 会恢复普通 release 包；本轮已恢复普通 release，安装 `databaseSequenceNumber=4376`，但设备 Locked，无法启动。

加固后复验：

```text
./scripts/smoke_ios_release_send.sh 00008110-0016349A3A20A01E
Refusing to install iOS release send smoke build because launch preflight did not prove the device is unlocked
SMOKE_SEND_EXIT_CODE=2
```

结论：停止慢流的代码级修复和脚本安全加固已完成；2026-07-07 13:05 已在 iPhone13 完成修复后的 release send / retry / model switch / stop 全链路复跑。


### 2026-07-07 iPhone13 修复后全链路通过记录

```text
Building iOS release send smoke runId=ios-release-send-20260707130509
✓ Built build/ios/iphoneos/Runner.app (33.2MB)
Installed release app:
- bundleID: top.simitalk.aichat
- databaseSequenceNumber: 4400
Launched release app:
- pid: 80205
iOS release send smoke passed:
- runId: ios-release-send-20260707130509
- reply: IOS release smoke reply 20260706
- request.path: /v1/chat/completions
- request.model: ios-release-smoke-model
- request.lastUser: ios release send smoke
- retry.requestCountForInitialPrompt: 2
- modelSwitch.requestModel: ios-release-smoke-model-b
- modelSwitch.timelineRecordCount: 1
- stop.partialReply: IOS slow chunk 1 IOS slow chunk 2
- stop.requestCompleted: False
Restoring normal iOS release build without smoke dart-defines...
✓ Built build/ios/iphoneos/Runner.app (33.2MB)
Installed release app:
- bundleID: top.simitalk.aichat
- databaseSequenceNumber: 4408
Launched release app:
- pid: 80206
```

本次复跑证明：

- release app 内真实发送主路径仍可完成 OpenAI Chat SSE 请求与 assistant 回复落库。
- `retry.requestCountForInitialPrompt=2`，重试链路命中同一用户问题的第二次请求。
- `modelSwitch.requestModel=ios-release-smoke-model-b` 且 `timelineRecordCount=1`，模型切换和时间线记录正常。
- 停止慢流保留部分回复 `IOS slow chunk 1 IOS slow chunk 2`，且 `stop.requestCompleted=False`，说明取消订阅与 SSE `CancelToken` 传播已阻断上游慢流完成。
- 脚本结束后已恢复普通 release 包，普通 release pid `80206` 可见。

## 本轮代码 / 脚本变更

- 新增 `lib/core/smoke/release_send_smoke_harness.dart`：release-only 发送 smoke harness。
- 更新 `lib/main.dart`：仅当 `SIMICHAT_RELEASE_SEND_SMOKE=true` 时进入 smoke harness；普通 release 仍走原启动路径。
- 更新 `lib/shared/providers/chat_provider.dart`：release smoke session 跳过 Markdown 原始档案追加，避免污染真实会话档案。
- 新增 `scripts/smoke_ios_release_send.sh`：构建 smoke release、覆盖安装、启动、拉取结果、恢复普通 release。
- 新增 `test/release_send_smoke_manifest_test.dart`：静态回归 dart-define 防护、结果目录和恢复普通 release 约束。
- 2026-07-07 更新：
  - `cancelStreaming()` 显式取消 active `StreamSubscription`。
  - `openSseStream()` 的 SSE 字节流支持下游取消时传播 `CancelToken.cancel()`。
  - release send harness 的内置 SSE mock 关闭 `bufferOutput`。
  - `smoke_ios_release_send.sh` 增加 Locked / timeout / 未证明解锁预检拒绝和失败自动恢复普通 release。

## 已通过检查

```bash
dart format lib/core/smoke/release_send_smoke_harness.dart lib/shared/providers/chat_provider.dart test/release_send_smoke_manifest_test.dart
flutter --no-version-check analyze
flutter --no-version-check test --no-pub --no-test-assets -r expanded test/release_send_smoke_manifest_test.dart
bash -n scripts/smoke_ios_release_send.sh
./scripts/smoke_ios_release_send.sh BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D
```

2026-07-07 补充验证：

```bash
flutter --no-version-check test --no-pub -r expanded \
  test/openai_chat_protocol_test.dart \
  test/release_send_smoke_manifest_test.dart \
  test/chat_provider_retry_test.dart
git diff --check
bash -n scripts/smoke_ios_release_send.sh scripts/smoke_ios_release_background_restore.sh
flutter --no-version-check analyze
./scripts/smoke_ios_release_send.sh 00008110-0016349A3A20A01E
```

结果：

- OpenAI Chat / release manifest / retry 聚焦测试 16 项通过。
- `git diff --check` 无输出。
- 两个 iOS release smoke 脚本 `bash -n` 通过。
- `flutter --no-version-check analyze` 无问题。
- 2026-07-07 修复后 iPhone13 全链路复跑通过，runId `ios-release-send-20260707130509`，普通 release 已恢复并启动 pid `80206`。

## 当前边界

已完成：

- `people` iOS 真机 release 构建、覆盖安装、启动和进程可见。
- release app 内发送主路径、OpenAI Chat SSE 请求、assistant 回复落库和结果取证。
- iPhone13 release send / retry / model switch / stop 全链路复跑已通过。
- smoke 结束后自动恢复普通 release 包。
- smoke 临时 Markdown 档案不残留。
- 代码级停止链路已补取消订阅和 SSE CancelToken 传播回归。
- smoke 脚本已补 Locked / timeout 安全预检和失败恢复普通 release。

仍未覆盖：

- iOS release 下的手工 UI 输入、停止、重试、模型切换和历史搜索。
- iOS release 下真实外部模型 API。
- iOS 真机真实音频中断 / 后台恢复 / 网络切换。
