import '../l10n/generated/app_localizations.dart';
import '../media_backend/detail/media_detail.dart';

/// 把中立 [MediaDetailPerson] 渲染成详情页"演职员"卡片所需的展示文案。
///
/// 演职员的**显示逻辑**（名字空回退、角色/职务文案）是飞牛口味，不应进中立模型
/// （[MediaDetailPerson] 只持 name/role/department 等中立字段）。本 presenter 把这层显示
/// 逻辑留在 UI 层（类比 Phase 4.5 的 `CatalogFilterLocalizer`），逐字复刻飞牛
/// `PersonCredit.displayName` / `displaySubTitle` 语义，保证迁移零行为差异。
///
/// Emby 复用：Emby `People[].Name/Role/Type` 映射进 [MediaDetailPerson] 后，同一 presenter
/// 直接适用，UI 不写 `if (isEmby)`。
class CreditPersonPresenter {
  const CreditPersonPresenter._();

  /// 主名：去空白后为空回退「未知」。
  ///
  /// 复刻 `PersonCredit.displayName`——mapper 已把 `name` 为空时回退 `originalName`，故此处
  /// 只需对合并后的 `name` 做「trim 后空则未知」，与原「name→originalName→未知」三级等价。
  static String displayName(MediaDetailPerson person, AppLocalizations l10n) {
    final name = person.name.trim();
    return name.isEmpty ? l10n.creditPersonUnknown : name;
  }

  /// 副标题：角色优先（`饰 <role>`，跳过 `(voice)`），否则按职务映射中文，未知职务原样返回。
  ///
  /// 复刻 `PersonCredit.displaySubTitle`（`role`←飞牛 role，`department`←飞牛 job）。
  static String displaySubTitle(
    MediaDetailPerson person,
    AppLocalizations l10n,
  ) {
    final role = person.role.trim();
    if (role.isNotEmpty && role != '(voice)')
      return l10n.creditPersonRole(role);
    final job = person.department.trim();
    if (job.isEmpty) return '';
    switch (job.toLowerCase()) {
      case 'director':
        return l10n.creditPersonDirector;
      case 'actor':
        return l10n.creditPersonActor;
      case 'screenplay':
        return l10n.creditPersonScreenplay;
      default:
        return job;
    }
  }
}
