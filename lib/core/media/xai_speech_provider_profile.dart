/// xAI Voice REST profile.
///
/// The batch REST endpoints are deliberately separate from the OpenAI
/// compatibility endpoints:
///
/// * STT: `/v1/stt`
/// * TTS: `/v1/tts`
///
/// The profile does not define a model name.  xAI's REST voice endpoints use
/// the uploaded audio (STT) or `voice_id` (TTS), so neither adapter invents or
/// serializes a `model` field.
const kXaiSpeechProviderId = 'xai';
const kXaiSpeechProviderBaseUrl = 'https://api.x.ai';
const kXaiSpeechToTextEndpoint = 'stt';
const kXaiTextToSpeechEndpoint = 'tts';
const kXaiCustomVoiceEndpoint = 'custom-voices';
const kXaiDefaultTextToSpeechVoice = 'eve';
const kXaiDefaultSpeechLanguage = 'auto';

/// xAI's documented playback-safe codecs. Raw telephony codecs are a valid
/// xAI wire option, but the app's native playback path does not advertise
/// support for them yet.
const kXaiTextToSpeechPlaybackFormats = ['mp3', 'wav'];
const kXaiTextToSpeechWireFormats = ['mp3', 'wav', 'pcm', 'mulaw', 'alaw'];
const kXaiTextToSpeechMinSpeed = 0.7;
const kXaiTextToSpeechMaxSpeed = 1.5;

/// REST STT request body variants supported by the adapter.
///
/// The current xAI documentation shows the REST operation with no JSON
/// parameters while the voice guide demonstrates a multipart `file` upload.
/// `multipart` is the default because it is the documented file-upload form;
/// `rawAudio` is available for deployments that expose the same endpoint as a
/// binary request body.  Neither mode adds a model field.
enum XaiSpeechToTextRequestBodyMode { multipart, rawAudio }

class XaiSpeechProviderProfile {
  const XaiSpeechProviderProfile({
    this.id = kXaiSpeechProviderId,
    this.baseUrl = kXaiSpeechProviderBaseUrl,
    this.sttEndpoint = kXaiSpeechToTextEndpoint,
    this.ttsEndpoint = kXaiTextToSpeechEndpoint,
    this.customVoiceEndpoint = kXaiCustomVoiceEndpoint,
    this.sttRequestBodyMode = XaiSpeechToTextRequestBodyMode.multipart,
    this.includeSttLanguageField = false,
    this.defaultTtsVoice = kXaiDefaultTextToSpeechVoice,
    this.defaultLanguage = kXaiDefaultSpeechLanguage,
    this.maxSttAudioBytes = 25 * 1024 * 1024,
    this.maxSttResponseBytes = 2 * 1024 * 1024,
    this.maxTtsAudioBytes = 10 * 1024 * 1024,
    this.maxCustomVoiceAudioBytes = 25 * 1024 * 1024,
  });

  final String id;
  final String baseUrl;

  /// Endpoint paths are relative to the configured API prefix.  An origin
  /// Base URL therefore resolves them to `/v1/stt` and `/v1/tts`.
  final String sttEndpoint;
  final String ttsEndpoint;
  final String customVoiceEndpoint;

  final XaiSpeechToTextRequestBodyMode sttRequestBodyMode;

  /// The public xAI batch STT request currently documents no language form
  /// field. This opt-in exists only for explicitly configured compatible
  /// gateways that require one.
  final bool includeSttLanguageField;
  final String defaultTtsVoice;
  final String defaultLanguage;
  final int maxSttAudioBytes;
  final int maxSttResponseBytes;
  final int maxTtsAudioBytes;
  final int maxCustomVoiceAudioBytes;
}

const kXaiSpeechProviderProfile = XaiSpeechProviderProfile();

bool isXaiSpeechProvider(String provider) =>
    provider.trim().toLowerCase() == kXaiSpeechProviderId;
