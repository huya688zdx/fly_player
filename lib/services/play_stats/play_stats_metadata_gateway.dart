import 'play_stats_models.dart';

/// 元数据回填链路所需的最小媒体查询能力（后端中立）。
///
/// 只暴露回填真正用到的两项能力，实现方由调用侧注入，统计模块自身不依赖任何
/// 具体后端 API 客户端。
abstract class PlayStatsBackfillGateway {
  /// 拉取条目详情原始字段。
  ///
  /// 返回值是一份扁平的原始详情 Map，字段口径沿用飞牛后端的历史约定；新增后端
  /// 实现必须把自家字段**映射**到下列键，回填服务只认这份契约：
  ///
  /// | 键 | 类型 | 用途与值域约定 |
  /// | --- | --- | --- |
  /// | `type` | String | 条目类型。**当且仅当**小写去空白后等于 `'movie'` 判为电影；电影不查季度详情、题材与地区直接取条目自身 |
  /// | `parent_guid` | String | 季度（父级）标识。非电影时用它二次拉取季度详情；季度详情的 `parent_guid` 再作为剧集（番剧）标识候选 |
  /// | `ancestor_guid` | String | 顶层库/根节点标识。**只用于排除**：等于它的候选一律不认作剧集标识，避免把媒体库当成番剧 |
  /// | `ancestor_name` | String | 顶层库名称，同样只用于识别"标题被写成库名"的脏数据并触发修复 |
  /// | `tv_title` | String | 剧集（番剧）名。为空时回落到 `title`；与库中已存名称不一致会触发身份修复 |
  /// | `title` | String | 条目自身标题（单集名 / 电影名） |
  /// | `parent_title` | String | 季度标题，优先于季度详情里的 `title` |
  /// | `trim_id` | String | 稳定的系列归并键，喂给 `PlayStatsIdentityResolver.resolveAnimeIdentity` 生成派生 animeId；无真实剧集 GUID 时靠它把同系列条目并到一起 |
  /// | `genres` | List&lt;int&gt; | 题材 id 列表。**id 空间必须与 [PlayStatsTaxonomyGateway.fetchGenreNames] 的 key 完全一致**，否则统计页只能显示裸 id。也接受 JSON 字符串形式；非正整数会被丢弃，顺序保留并去重 |
  /// | `production_countries` | List&lt;String&gt; | 地区码列表，统一按**大写**存取，需能在 [PlayStatsTaxonomyGateway.fetchCountryNames] 的 key 中查到（ISO-3166 二字码）。也接受 JSON 字符串形式；列表首项作为主地区 |
  /// | `release_date` | String | 首播/上映日期，**只抠其中第一个四位数字**当年份，格式不限（`2024-01-01` 与 `2024` 等价） |
  /// | `air_date` | String | 同上，`release_date` 为空时的回落来源 |
  ///
  /// 所有键均可缺省：缺失、null 或空串一律按"该字段未知"处理并回落到库中既有值，
  /// 实现方不必为补齐字段而伪造数据。
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
///
/// 合并两个子接口不只是为了少传一个对象：回填与展示之间存在**跨接口的 id 空间
/// 一致性约束**，只有由同一个后端实现同时提供两侧数据才能保证：
///
/// - [PlayStatsBackfillGateway.fetchItemDetail] 写进统计库的 `genres` 元素，必须
///   能在 [PlayStatsTaxonomyGateway.fetchGenreNames] 返回的 map 中命中同一个 key；
/// - 同理 `production_countries` 的大写地区码必须能在 [fetchCountryNames] 中命中。
///
/// 两侧 id 空间一旦错配（例如题材来自 A 服务器而字典来自 B 服务器，或一侧用
/// TMDB id 另一侧用自家 id），统计页的题材/地区分布会退化成一堆裸 id，而且是
/// 静默退化、无报错。所以实现方不得把两个子接口拆给不同数据源，调用方也不得
/// 把不同后端的两个网关拼在一起用。
abstract class PlayStatsMetadataGateway
    implements PlayStatsBackfillGateway, PlayStatsTaxonomyGateway {}
