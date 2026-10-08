import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// Шлюпка: правило из экрана «Правила маршрутов» в том виде, как его читает ядро
/// (Go encoding/json по полям HiddifyOptions.Rules в Rescue-boat-core: ключи во
/// множественном числе, перечисления числами). Правила применяет rescue_rules.go.
Map<String, dynamic> ruleToCoreJson(Rule rule) => {
  'list_order': rule.listOrder,
  'enabled': rule.enabled,
  'name': rule.name,
  'outbound': rule.outbound.value,
  'rule_sets': rule.ruleSets,
  'package_names': rule.packageNames,
  'process_names': rule.processNames,
  'process_paths': rule.processPaths,
  'network': rule.network.value,
  'port_ranges': rule.portRanges,
  'source_port_ranges': rule.sourcePortRanges,
  'protocols': rule.protocols.map((p) => p.value).toList(),
  'ip_cidrs': rule.ipCidrs,
  'source_ip_cidrs': rule.sourceIpCidrs,
  'domains': rule.domains,
  'domain_suffixes': rule.domainSuffixes,
  'domain_keywords': rule.domainKeywords,
  'domain_regexes': rule.domainRegexes,
};
