import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ProviderAccess {
  T read<T>(ProviderListenable<T> provider);

  void invalidate(ProviderOrFamily provider);
}

class WidgetRefProviderAccess implements ProviderAccess {
  const WidgetRefProviderAccess(this.ref);

  final WidgetRef ref;

  @override
  T read<T>(ProviderListenable<T> provider) => ref.read(provider);

  @override
  void invalidate(ProviderOrFamily provider) => ref.invalidate(provider);
}

class ContainerProviderAccess implements ProviderAccess {
  const ContainerProviderAccess(this.container);

  final ProviderContainer container;

  @override
  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  @override
  void invalidate(ProviderOrFamily provider) => container.invalidate(provider);
}
