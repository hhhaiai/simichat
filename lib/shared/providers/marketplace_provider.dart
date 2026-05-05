import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/marketplace/marketplace_models.dart';

/// 市场搜索/筛选状态
class MarketplaceState {
  const MarketplaceState({
    this.keyword = '',
    this.category = '全部',
    this.items = builtinMcpServers,
  });

  final String keyword;
  final String category;
  final List<MarketplaceItem> items;

  MarketplaceState copyWith({
    String? keyword,
    String? category,
    List<MarketplaceItem>? items,
  }) {
    return MarketplaceState(
      keyword: keyword ?? this.keyword,
      category: category ?? this.category,
      items: items ?? this.items,
    );
  }
}

class MarketplaceNotifier extends StateNotifier<MarketplaceState> {
  MarketplaceNotifier() : super(const MarketplaceState());

  void setKeyword(String keyword) {
    state = state.copyWith(keyword: keyword);
    _filter();
  }

  void setCategory(String category) {
    state = state.copyWith(category: category);
    _filter();
  }

  void _filter() {
    final keyword = state.keyword.toLowerCase();
    final category = state.category;

    var filtered = builtinMcpServers.where((item) {
      final matchesCategory = category == '全部' || item.category == category;
      final matchesKeyword = keyword.isEmpty ||
          item.name.toLowerCase().contains(keyword) ||
          item.description.toLowerCase().contains(keyword) ||
          item.tags.any((t) => t.toLowerCase().contains(keyword));
      return matchesCategory && matchesKeyword;
    }).toList();

    // 按安装量排序
    filtered.sort((a, b) => b.installCount.compareTo(a.installCount));

    state = state.copyWith(items: filtered);
  }
}

final marketplaceProvider =
    StateNotifierProvider<MarketplaceNotifier, MarketplaceState>((ref) {
  return MarketplaceNotifier();
});
