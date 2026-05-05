import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Chat'**
  String get appTitle;

  /// No description provided for @newSession.
  ///
  /// In en, this message translates to:
  /// **'New Session'**
  String get newSession;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thinking;

  /// No description provided for @thinkingProcess.
  ///
  /// In en, this message translates to:
  /// **'Thinking Process'**
  String get thinkingProcess;

  /// No description provided for @inputMessage.
  ///
  /// In en, this message translates to:
  /// **'Input message...'**
  String get inputMessage;

  /// No description provided for @addAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add Attachment'**
  String get addAttachment;

  /// No description provided for @cameraPhoto.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraPhoto;

  /// No description provided for @galleryPick.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryPick;

  /// No description provided for @pickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick File'**
  String get pickFile;

  /// No description provided for @networkDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Network disconnected'**
  String get networkDisconnected;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String loadFailed(Object error);

  /// No description provided for @selectOrNewSession.
  ///
  /// In en, this message translates to:
  /// **'Select or create a new session'**
  String get selectOrNewSession;

  /// No description provided for @startChat.
  ///
  /// In en, this message translates to:
  /// **'Start chatting'**
  String get startChat;

  /// No description provided for @modelSelector.
  ///
  /// In en, this message translates to:
  /// **'Model Selector'**
  String get modelSelector;

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get systemPrompt;

  /// No description provided for @systemPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Enter system prompt (leave empty for default)...'**
  String get systemPromptHint;

  /// No description provided for @clearPrompt.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearPrompt;

  /// No description provided for @selectFromPromptLibrary.
  ///
  /// In en, this message translates to:
  /// **'Select from Prompt Library'**
  String get selectFromPromptLibrary;

  /// No description provided for @promptLibraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Prompt library is empty, add prompts in Settings first'**
  String get promptLibraryEmpty;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Model Channels'**
  String get channels;

  /// No description provided for @addChannel.
  ///
  /// In en, this message translates to:
  /// **'Add Channel'**
  String get addChannel;

  /// No description provided for @editChannel.
  ///
  /// In en, this message translates to:
  /// **'Edit Channel'**
  String get editChannel;

  /// No description provided for @deleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Delete Channel'**
  String get deleteChannel;

  /// No description provided for @channelName.
  ///
  /// In en, this message translates to:
  /// **'Channel Name'**
  String get channelName;

  /// No description provided for @channelNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. OpenAI'**
  String get channelNameHint;

  /// No description provided for @baseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @protocolType.
  ///
  /// In en, this message translates to:
  /// **'Protocol Type'**
  String get protocolType;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @addModel.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get addModel;

  /// No description provided for @modelName.
  ///
  /// In en, this message translates to:
  /// **'Model Name'**
  String get modelName;

  /// No description provided for @modelNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. gpt-4o'**
  String get modelNameHint;

  /// No description provided for @autoFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Auto Fetch Models'**
  String get autoFetchModels;

  /// No description provided for @fetchingModels.
  ///
  /// In en, this message translates to:
  /// **'Fetching model list...'**
  String get fetchingModels;

  /// No description provided for @noModelsFound.
  ///
  /// In en, this message translates to:
  /// **'No chat models found (may only have embedding models)'**
  String get noModelsFound;

  /// No description provided for @allModelsExist.
  ///
  /// In en, this message translates to:
  /// **'All {count} chat models already exist'**
  String allModelsExist(Object count);

  /// No description provided for @modelsAdded.
  ///
  /// In en, this message translates to:
  /// **'Added {count} models'**
  String modelsAdded(Object count);

  /// No description provided for @fetchedModels.
  ///
  /// In en, this message translates to:
  /// **'Fetched {count} models'**
  String fetchedModels(Object count);

  /// No description provided for @deleteChannelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\" and all its models?'**
  String deleteChannelConfirm(Object name);

  /// No description provided for @deleteModel.
  ///
  /// In en, this message translates to:
  /// **'Delete Model'**
  String get deleteModel;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @contextSettings.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get contextSettings;

  /// No description provided for @compressThreshold.
  ///
  /// In en, this message translates to:
  /// **'Compress Threshold'**
  String get compressThreshold;

  /// No description provided for @compressThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Current: {tokens} tokens - Auto-compress history when exceeded'**
  String compressThresholdDesc(Object tokens);

  /// No description provided for @promptLibrary.
  ///
  /// In en, this message translates to:
  /// **'Prompt Library'**
  String get promptLibrary;

  /// No description provided for @addPrompt.
  ///
  /// In en, this message translates to:
  /// **'Add Prompt'**
  String get addPrompt;

  /// No description provided for @editPrompt.
  ///
  /// In en, this message translates to:
  /// **'Edit Prompt'**
  String get editPrompt;

  /// No description provided for @deletePrompt.
  ///
  /// In en, this message translates to:
  /// **'Delete Prompt'**
  String get deletePrompt;

  /// No description provided for @promptName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get promptName;

  /// No description provided for @promptNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Translation Assistant'**
  String get promptNameHint;

  /// No description provided for @promptCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get promptCategory;

  /// No description provided for @promptContent.
  ///
  /// In en, this message translates to:
  /// **'Prompt Content'**
  String get promptContent;

  /// No description provided for @promptContentHint.
  ///
  /// In en, this message translates to:
  /// **'You are a translation assistant...'**
  String get promptContentHint;

  /// No description provided for @deletePromptConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deletePromptConfirm(Object name);

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @selectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select Prompt'**
  String get selectPrompt;

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select Model'**
  String get selectModel;

  /// No description provided for @selectThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Select Theme Mode'**
  String get selectThemeMode;

  /// No description provided for @tokens.
  ///
  /// In en, this message translates to:
  /// **'~{count} tokens'**
  String tokens(Object count);

  /// No description provided for @retryLastMessage.
  ///
  /// In en, this message translates to:
  /// **'Retry last message'**
  String get retryLastMessage;

  /// No description provided for @forkSession.
  ///
  /// In en, this message translates to:
  /// **'Fork Session'**
  String get forkSession;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchPlaceholder;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
