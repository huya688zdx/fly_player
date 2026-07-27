import 'play_stats_models.dart';

/// 元数据回填链路所需的最小媒体查询能力（后端中立）。
///
/// 只暴露回填真正用到的两项能力，实现方由调用侧注入，统计模块自身不依赖任何
/// 具体后端 API 客户端。
///
/// 注意：[fetchItemDetail] 返回的原始详情 Map 沿用现有字段口径（`type`、
/// `parent_guid`、`ancestor_guid`、`tv_title`、`genres`、`production_countries`、
/// `release_date` 等）；新增后端实现需自行把自家字段映射到该口径。
abstract class PlayStatsBackfillGateway {
  /// 拉取条目详情原始字段。
  Future<Map<String, dynamic>> fetchItemDetail(String itemId);

  /// 拉取条目演职员列表，已映射为统计模块的信用模型。
  Future<List<PlayStatsCredit>> fetchCredits(String itemId);
}

/// 统计页展示题材 / 地区名称所需的字典能力（后端中立）。
abstract class PlayStatsTaxonomyGateway {
  /// 题材 id 到显示名的映射。
  Future<Map<int, String>> fetchGenreNames();

  /// ISO-3166 地区码到显示名的映射。
  Future<Map<String, String>> fetchCountryNames();
}

/// 播放统计模块所需的全部元数据能力，供后端实现一并提供。
abstract class PlayStatsMetadataGateway
    implements PlayStatsBackfillGateway, PlayStatsTaxonomyGateway {}
