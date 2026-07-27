import '../../api/feiniu_api.dart';
import '../../api/person_list_request.dart';
import '../../models/person_credit.dart';
import '../../services/play_stats/play_stats_metadata_gateway.dart';
import '../../services/play_stats/play_stats_models.dart';

/// 播放统计元数据网关的飞牛实现。
///
/// 统计模块只认 [PlayStatsMetadataGateway] 抽象，飞牛的 API 细节（分页参数、
/// 人员模型、字典语言）全部收在这里。
class FeiniuPlayStatsGateway implements PlayStatsMetadataGateway {
  static const PersonListRequest _creditsRequest = PersonListRequest(
    page: 1,
    pageSize: 200,
  );

  final FeiniuApi _api;

  const FeiniuPlayStatsGateway(this._api);

  @override
  Future<Map<String, dynamic>> fetchItemDetail(String itemId) {
    return _api.getItemDetail(itemId);
  }

  @override
  Future<List<PlayStatsCredit>> fetchCredits(String itemId) async {
    final credits = await _api.getPersonList(itemId, request: _creditsRequest);
    return _mapCredits(credits);
  }

  @override
  Future<Map<int, String>> fetchGenreNames() {
    return _api.getTagGenresMap(lan: 'zh-CN');
  }

  @override
  Future<Map<String, String>> fetchCountryNames() {
    return _api.getTagIso3166Map(lan: 'zh-CN');
  }

  List<PlayStatsCredit> _mapCredits(List<PersonCredit> credits) {
    return credits
        .where((credit) => credit.personGuid.trim().isNotEmpty)
        .map(
          (credit) => PlayStatsCredit(
            personId: credit.personGuid.trim(),
            name: credit.displayName,
            role: credit.role.trim(),
            job: credit.job.trim().toLowerCase(),
            order: credit.order,
          ),
        )
        .toList(growable: false);
  }
}
