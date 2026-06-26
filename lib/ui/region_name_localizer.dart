import '../l10n/generated/app_localizations.dart';

/// 把后端给的地区原始值（英文国名如 `Japan`，或 ISO3166 code 如 `JP`/`JPN`）本地化成
/// 显示名。中文文案一律走 l10n（[AppLocalizations] getter），代码里只保留语言无关的
/// 名称 / code 规整，绝不写死中文。
///
/// 飞牛详情的地区已由服务端 ISO3166 字典翻好（直接是中文），这些值不在本表内 → 原样返回；
/// 因此对两后端的 [List]<地区> 调用都安全。表外未知值同样原样返回（不臆造）。
class RegionNameLocalizer {
  const RegionNameLocalizer._();

  static List<String> localizeAll(AppLocalizations l10n, List<String> raws) {
    return raws.map((r) => localize(l10n, r)).toList(growable: false);
  }

  static String localize(AppLocalizations l10n, String raw) {
    final key = raw.trim();
    switch (key.toUpperCase()) {
      case 'JAPAN':
      case 'JP':
      case 'JPN':
        return l10n.regionJapan;
      case 'CHINA':
      case 'CN':
      case 'CHN':
        return l10n.regionChina;
      case 'HONG KONG':
      case 'HK':
      case 'HKG':
        return l10n.regionHongKong;
      case 'TAIWAN':
      case 'TW':
      case 'TWN':
        return l10n.regionTaiwan;
      case 'MACAU':
      case 'MACAO':
      case 'MO':
      case 'MAC':
        return l10n.regionMacau;
      case 'SOUTH KOREA':
      case 'KOREA':
      case 'KOREA, REPUBLIC OF':
      case 'REPUBLIC OF KOREA':
      case 'KR':
      case 'KOR':
        return l10n.regionSouthKorea;
      case 'NORTH KOREA':
      case 'KP':
      case 'PRK':
        return l10n.regionNorthKorea;
      case 'UNITED STATES':
      case 'UNITED STATES OF AMERICA':
      case 'USA':
      case 'US':
        return l10n.regionUnitedStates;
      case 'UNITED KINGDOM':
      case 'UK':
      case 'GB':
      case 'GBR':
        return l10n.regionUnitedKingdom;
      case 'FRANCE':
      case 'FR':
      case 'FRA':
        return l10n.regionFrance;
      case 'GERMANY':
      case 'DE':
      case 'DEU':
        return l10n.regionGermany;
      case 'ITALY':
      case 'IT':
      case 'ITA':
        return l10n.regionItaly;
      case 'SPAIN':
      case 'ES':
      case 'ESP':
        return l10n.regionSpain;
      case 'PORTUGAL':
      case 'PT':
      case 'PRT':
        return l10n.regionPortugal;
      case 'CANADA':
      case 'CA':
      case 'CAN':
        return l10n.regionCanada;
      case 'AUSTRALIA':
      case 'AU':
      case 'AUS':
        return l10n.regionAustralia;
      case 'NEW ZEALAND':
      case 'NZ':
      case 'NZL':
        return l10n.regionNewZealand;
      case 'INDIA':
      case 'IN':
      case 'IND':
        return l10n.regionIndia;
      case 'RUSSIA':
      case 'RUSSIAN FEDERATION':
      case 'RU':
      case 'RUS':
        return l10n.regionRussia;
      case 'THAILAND':
      case 'TH':
      case 'THA':
        return l10n.regionThailand;
      case 'INDONESIA':
      case 'ID':
      case 'IDN':
        return l10n.regionIndonesia;
      case 'MALAYSIA':
      case 'MY':
      case 'MYS':
        return l10n.regionMalaysia;
      case 'SINGAPORE':
      case 'SG':
      case 'SGP':
        return l10n.regionSingapore;
      case 'PHILIPPINES':
      case 'PH':
      case 'PHL':
        return l10n.regionPhilippines;
      case 'VIETNAM':
      case 'VIET NAM':
      case 'VN':
      case 'VNM':
        return l10n.regionVietnam;
      case 'BRAZIL':
      case 'BR':
      case 'BRA':
        return l10n.regionBrazil;
      case 'MEXICO':
      case 'MX':
      case 'MEX':
        return l10n.regionMexico;
      case 'ARGENTINA':
      case 'AR':
      case 'ARG':
        return l10n.regionArgentina;
      case 'NETHERLANDS':
      case 'NL':
      case 'NLD':
        return l10n.regionNetherlands;
      case 'BELGIUM':
      case 'BE':
      case 'BEL':
        return l10n.regionBelgium;
      case 'SWEDEN':
      case 'SE':
      case 'SWE':
        return l10n.regionSweden;
      case 'NORWAY':
      case 'NO':
      case 'NOR':
        return l10n.regionNorway;
      case 'DENMARK':
      case 'DK':
      case 'DNK':
        return l10n.regionDenmark;
      case 'FINLAND':
      case 'FI':
      case 'FIN':
        return l10n.regionFinland;
      case 'ICELAND':
      case 'IS':
      case 'ISL':
        return l10n.regionIceland;
      case 'IRELAND':
      case 'IE':
      case 'IRL':
        return l10n.regionIreland;
      case 'SWITZERLAND':
      case 'CH':
      case 'CHE':
        return l10n.regionSwitzerland;
      case 'AUSTRIA':
      case 'AT':
      case 'AUT':
        return l10n.regionAustria;
      case 'POLAND':
      case 'PL':
      case 'POL':
        return l10n.regionPoland;
      case 'CZECH REPUBLIC':
      case 'CZECHIA':
      case 'CZ':
      case 'CZE':
        return l10n.regionCzechRepublic;
      case 'HUNGARY':
      case 'HU':
      case 'HUN':
        return l10n.regionHungary;
      case 'GREECE':
      case 'GR':
      case 'GRC':
        return l10n.regionGreece;
      case 'TURKEY':
      case 'TÜRKIYE':
      case 'TR':
      case 'TUR':
        return l10n.regionTurkey;
      case 'IRAN':
      case 'IR':
      case 'IRN':
        return l10n.regionIran;
      case 'ISRAEL':
      case 'IL':
      case 'ISR':
        return l10n.regionIsrael;
      case 'SOUTH AFRICA':
      case 'ZA':
      case 'ZAF':
        return l10n.regionSouthAfrica;
      case 'EGYPT':
      case 'EG':
      case 'EGY':
        return l10n.regionEgypt;
      case 'UKRAINE':
      case 'UA':
      case 'UKR':
        return l10n.regionUkraine;
      default:
        return key;
    }
  }
}
