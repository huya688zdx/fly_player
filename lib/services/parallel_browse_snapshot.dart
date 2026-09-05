/// 表示并行浏览宿主当前需要同步的浏览快照。
class ParallelBrowseSnapshot {
  final String surface;
  final String itemGuid;
  final String parentItemGuid;
  final int originTab;
  final bool canPopToParent;

  /// 根据当前浏览位置构造快照对象。
  const ParallelBrowseSnapshot({
    required this.surface,
    this.itemGuid = '',
    this.parentItemGuid = '',
    this.originTab = 0,
    this.canPopToParent = false,
  });

  /// 构造指向首页表面的浏览快照。
  const ParallelBrowseSnapshot.home({
    this.itemGuid = '',
    this.parentItemGuid = '',
    this.originTab = 0,
    this.canPopToParent = false,
  }) : surface = 'home';

  /// 将浏览快照转换为平台桥接所需的映射结构。
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
