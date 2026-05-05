// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AI 对话';

  @override
  String get newSession => '新建会话';

  @override
  String get settings => '设置';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get confirm => '确定';

  @override
  String get close => '关闭';

  @override
  String get retry => '重试';

  @override
  String get send => '发送';

  @override
  String get stop => '停止';

  @override
  String get thinking => '思考中...';

  @override
  String get thinkingProcess => '思考过程';

  @override
  String get inputMessage => '输入消息...';

  @override
  String get addAttachment => '添加附件';

  @override
  String get cameraPhoto => '相机拍照';

  @override
  String get galleryPick => '从相册选择';

  @override
  String get pickFile => '选择文件';

  @override
  String get networkDisconnected => '网络已断开';

  @override
  String loadFailed(Object error) {
    return '加载失败: $error';
  }

  @override
  String get selectOrNewSession => '选择或新建一个会话';

  @override
  String get startChat => '开始对话吧';

  @override
  String get modelSelector => '模型选择器';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get systemPromptHint => '输入系统提示词（留空则使用默认）...';

  @override
  String get clearPrompt => '清除';

  @override
  String get selectFromPromptLibrary => '从提示词库选择';

  @override
  String get promptLibraryEmpty => '提示词库为空，请先在设置中添加';

  @override
  String get channels => '模型渠道';

  @override
  String get addChannel => '添加渠道';

  @override
  String get editChannel => '编辑渠道';

  @override
  String get deleteChannel => '删除渠道';

  @override
  String get channelName => '渠道名称';

  @override
  String get channelNameHint => '如 OpenAI';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get apiKey => 'API Key';

  @override
  String get protocolType => '协议类型';

  @override
  String get models => '模型';

  @override
  String get addModel => '添加模型';

  @override
  String get modelName => '模型名称';

  @override
  String get modelNameHint => '如 gpt-4o';

  @override
  String get autoFetchModels => '自动获取模型';

  @override
  String get fetchingModels => '正在获取模型列表...';

  @override
  String get noModelsFound => '未获取到可用的对话模型（可能只有 embedding 模型）';

  @override
  String allModelsExist(Object count) {
    return '所有 $count 个对话模型已存在，无需添加';
  }

  @override
  String modelsAdded(Object count) {
    return '已添加 $count 个模型';
  }

  @override
  String fetchedModels(Object count) {
    return '获取到 $count 个模型';
  }

  @override
  String deleteChannelConfirm(Object name) {
    return '确定删除「$name」及其所有模型？';
  }

  @override
  String get deleteModel => '删除模型';

  @override
  String get appearance => '外观';

  @override
  String get themeMode => '主题模式';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色模式';

  @override
  String get themeDark => '深色模式';

  @override
  String get contextSettings => '上下文';

  @override
  String get compressThreshold => '压缩阈值';

  @override
  String compressThresholdDesc(Object tokens) {
    return '当前: $tokens tokens · 超过此值自动压缩历史';
  }

  @override
  String get promptLibrary => '提示词库';

  @override
  String get addPrompt => '添加提示词';

  @override
  String get editPrompt => '编辑提示词';

  @override
  String get deletePrompt => '删除提示词';

  @override
  String get promptName => '名称';

  @override
  String get promptNameHint => '如 翻译助手';

  @override
  String get promptCategory => '分类';

  @override
  String get promptContent => '提示词内容';

  @override
  String get promptContentHint => '你是一个翻译助手...';

  @override
  String deletePromptConfirm(Object name) {
    return '确定删除「$name」？';
  }

  @override
  String get about => '关于';

  @override
  String get version => '版本';

  @override
  String get selectPrompt => '选择提示词';

  @override
  String get selectModel => '选择模型';

  @override
  String get selectThemeMode => '选择主题模式';

  @override
  String tokens(Object count) {
    return '~$count tokens';
  }

  @override
  String get retryLastMessage => '重试最后一条消息';

  @override
  String get forkSession => '复制会话';

  @override
  String get searchPlaceholder => '搜索...';
}
