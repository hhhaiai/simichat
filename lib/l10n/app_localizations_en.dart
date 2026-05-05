// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AI Chat';

  @override
  String get newSession => 'New Session';

  @override
  String get settings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get send => 'Send';

  @override
  String get stop => 'Stop';

  @override
  String get thinking => 'Thinking...';

  @override
  String get thinkingProcess => 'Thinking Process';

  @override
  String get inputMessage => 'Input message...';

  @override
  String get addAttachment => 'Add Attachment';

  @override
  String get cameraPhoto => 'Camera';

  @override
  String get galleryPick => 'Gallery';

  @override
  String get pickFile => 'Pick File';

  @override
  String get networkDisconnected => 'Network disconnected';

  @override
  String loadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String get selectOrNewSession => 'Select or create a new session';

  @override
  String get startChat => 'Start chatting';

  @override
  String get modelSelector => 'Model Selector';

  @override
  String get systemPrompt => 'System Prompt';

  @override
  String get systemPromptHint =>
      'Enter system prompt (leave empty for default)...';

  @override
  String get clearPrompt => 'Clear';

  @override
  String get selectFromPromptLibrary => 'Select from Prompt Library';

  @override
  String get promptLibraryEmpty =>
      'Prompt library is empty, add prompts in Settings first';

  @override
  String get channels => 'Model Channels';

  @override
  String get addChannel => 'Add Channel';

  @override
  String get editChannel => 'Edit Channel';

  @override
  String get deleteChannel => 'Delete Channel';

  @override
  String get channelName => 'Channel Name';

  @override
  String get channelNameHint => 'e.g. OpenAI';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get apiKey => 'API Key';

  @override
  String get protocolType => 'Protocol Type';

  @override
  String get models => 'Models';

  @override
  String get addModel => 'Add Model';

  @override
  String get modelName => 'Model Name';

  @override
  String get modelNameHint => 'e.g. gpt-4o';

  @override
  String get autoFetchModels => 'Auto Fetch Models';

  @override
  String get fetchingModels => 'Fetching model list...';

  @override
  String get noModelsFound =>
      'No chat models found (may only have embedding models)';

  @override
  String allModelsExist(Object count) {
    return 'All $count chat models already exist';
  }

  @override
  String modelsAdded(Object count) {
    return 'Added $count models';
  }

  @override
  String fetchedModels(Object count) {
    return 'Fetched $count models';
  }

  @override
  String deleteChannelConfirm(Object name) {
    return 'Delete \"$name\" and all its models?';
  }

  @override
  String get deleteModel => 'Delete Model';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get contextSettings => 'Context';

  @override
  String get compressThreshold => 'Compress Threshold';

  @override
  String compressThresholdDesc(Object tokens) {
    return 'Current: $tokens tokens - Auto-compress history when exceeded';
  }

  @override
  String get promptLibrary => 'Prompt Library';

  @override
  String get addPrompt => 'Add Prompt';

  @override
  String get editPrompt => 'Edit Prompt';

  @override
  String get deletePrompt => 'Delete Prompt';

  @override
  String get promptName => 'Name';

  @override
  String get promptNameHint => 'e.g. Translation Assistant';

  @override
  String get promptCategory => 'Category';

  @override
  String get promptContent => 'Prompt Content';

  @override
  String get promptContentHint => 'You are a translation assistant...';

  @override
  String deletePromptConfirm(Object name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get selectPrompt => 'Select Prompt';

  @override
  String get selectModel => 'Select Model';

  @override
  String get selectThemeMode => 'Select Theme Mode';

  @override
  String tokens(Object count) {
    return '~$count tokens';
  }

  @override
  String get retryLastMessage => 'Retry last message';

  @override
  String get forkSession => 'Fork Session';

  @override
  String get searchPlaceholder => 'Search...';
}
