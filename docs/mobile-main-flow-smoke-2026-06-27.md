# 移动端主链路冒烟记录 — 2026-06-27

> 目的：为移动端优先的聊天主流程建立可重复回归门禁。当前为 Flutter Widget 移动视口自动化冒烟；真机 / 模拟器手工冒烟仍需后续补充。

## 1. 自动化脚本

脚本：`scripts/smoke_mobile_main_flow.sh`

执行内容：

```bash
flutter test test/mobile_main_flow_smoke_test.dart
flutter analyze
```

覆盖场景：

1. 390 × 844 移动端视口启动 `AiChatApp`。
2. 首次启动自动创建 1 个本地会话。
3. 点击“新建会话”，确认本地会话数量增加。
4. 进入设置页，确认“数据与档案”等关键设置入口可打开。
5. 返回聊天页，在无模型状态下输入并点击发送。
6. 确认出现“还没有可用模型”保护弹窗，避免无模型时写入半残缺消息。
7. 使用已有会话数据打开移动端抽屉。
8. 在“搜索会话...”输入关键词，确认历史会话搜索结果出现并可点击选择。
9. 预置两个本地模型，点击 AppBar 模型菜单切换模型，确认会话默认模型更新并写入 `model_switch` 时间线记录。

## 2. 本轮发现并修复的问题

自动化冒烟首次运行失败，原因是 `ResponsiveShell` 首次启动时在 `sessionsProvider` 仍处于 loading 状态就读取会话列表，导致没有自动创建默认会话。

修复方式：

- `_autoSelectOrCreateSession` 改为等待 `sessionsProvider.future`。
- 增加 `_autoSelectingSession` 防重入标记。
- 创建 / 选择会话前再次检查 `activeSessionId`，避免重复创建。

## 3. 当前验证结果

- `./scripts/smoke_mobile_main_flow.sh`：通过。
- `flutter test test/mobile_main_flow_smoke_test.dart`：`00:03 +3: All tests passed!`。
- `flutter analyze`：通过，`No issues found!`。

## 4. 未覆盖风险

- 尚未在真实 Android / iOS 设备或模拟器上执行。
- 尚未覆盖真实模型发送到首 token。
- 尚未覆盖停止生成、重试生成和全局搜索弹层的完整人工链路；抽屉内会话标题搜索与 AppBar 模型切换已有自动化覆盖。
- 尚未覆盖键盘弹出、权限弹窗、相机 / 相册权限。

## 5. 后续真机冒烟清单

- [ ] Android 真机：首次启动 → 新建会话 → 添加模型 → 发送消息 → 停止生成 → 重试。
- [ ] iOS 真机：首次启动 → 新建会话 → 添加模型 → 发送消息 → 停止生成 → 重试。
- [x] 自动化：单对话内切换模型并确认 AppBar 路径写入 `model_switch` 记录。
- [ ] 真机：单对话内切换模型并确认 AppBar 展示更新。
- [ ] 历史搜索：搜索会话标题 / 消息内容并跳转。
- [ ] 设置：字体大小、主题、Markdown 档案入口可用。
- [ ] 附件：图片 / PDF / 普通文件选择、发送、消息气泡展示。
