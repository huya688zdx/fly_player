class ParallelBrowseSnapshot {
  final String surface;
  final String itemGuid;
  final String parentItemGuid;
  final int originTab;
  final bool canPopToParent;

  const ParallelBrowseSnapshot({
    required this.surface,
    this.itemGuid = '',
    this.parentItemGuid = '',
    this.originTab = 0,
    this.canPopToParent = false,
  });

  const ParallelBrowseSnapshot.home({
    this.itemGuid = '',
    this.parentItemGuid = '',
    this.originTab = 0,
    this.canPopToParent = false,
  }) : surface = 'home';

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'surface': surface,
      'itemGuid': itemGuid.trim(),
      'parentItemGuid': parentItemGuid.trim(),
      'originTab': originTab,
      'canPopToParent': canPopToParent,
    };
  }
}
