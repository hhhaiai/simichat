import 'package:ai_chat_app/core/ai/model_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelCapabilities', () {
    test('unknown file capability never guesses a transport', () {
      const capabilities = ModelCapabilities(
        fileInputSupport: CapabilityState.unknown,
        supportedFileTransports: [FileTransport.multipart],
        supportedInputMimeTypes: ['text/plain'],
      );
      expect(
        capabilities.canUseFileInput(
          mimeType: 'text/plain',
          fileCount: 1,
          fileBytes: 12,
        ),
        isFalse,
      );
      expect(capabilities.preferredFileTransport(), isNull);
    });

    test(
      'declared file capability also requires MIME, count, and byte limits',
      () {
        const capabilities = ModelCapabilities(
          fileInputSupport: CapabilityState.supported,
          supportedFileTransports: [FileTransport.multipart],
          supportedInputMimeTypes: ['text/plain', 'text/markdown'],
          maxInputFiles: 2,
          maxInputFileBytes: 100,
        );
        expect(
          capabilities.canUseFileInput(
            mimeType: 'text/plain',
            fileCount: 2,
            fileBytes: 100,
          ),
          isTrue,
        );
        expect(
          capabilities.canUseFileInput(
            mimeType: 'application/pdf',
            fileCount: 1,
            fileBytes: 10,
          ),
          isFalse,
        );
        expect(
          capabilities.canUseFileInput(
            mimeType: 'text/plain',
            fileCount: 3,
            fileBytes: 10,
          ),
          isFalse,
        );
      },
    );

    test(
      'registry combines sources by declared priority without erasing data',
      () {
        const registry = ModelCapabilitiesRegistry();
        final result = registry.resolve(
          conservativeDefault: const ModelCapabilities(
            modelId: 'fallback',
            fileInputSupport: CapabilityState.unknown,
            contextWindowTokens: 8192,
          ),
          userOverride: const ModelCapabilities(
            fileInputSupport: CapabilityState.unsupported,
          ),
          builtInProfile: const ModelCapabilities(
            fileInputSupport: CapabilityState.supported,
            supportedFileTransports: [FileTransport.multipart],
            supportedInputMimeTypes: ['text/plain'],
            supportedImageSizes: ['1024x1024'],
          ),
          provider: const ModelCapabilities(
            fileInputSupport: CapabilityState.unknown,
            maxRequestBytes: 2048,
            supportedImageSizes: ['1536x1024'],
          ),
        );

        expect(result.modelId, 'fallback');
        expect(result.fileInputSupport, CapabilityState.supported);
        expect(result.supportedFileTransports, [FileTransport.multipart]);
        expect(result.maxRequestBytes, 2048);
        expect(result.contextWindowTokens, 8192);
        expect(result.supportedImageSizes, ['1536x1024']);
      },
    );
  });
}
