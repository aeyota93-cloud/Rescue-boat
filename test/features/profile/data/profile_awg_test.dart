import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/servers/model/servers_format.dart';

const _fresh = [
  {'type': 'awg', 'tag': 'fresh'},
];

void main() {
  test('saved profile: AmneziaWG from endpoints is named by protocol', () {
    // Ядро переносит rescue-endpoints в endpoints; без этого серверы назывались «Запасной N».
    expect(protocolsOfConfig({'outbounds': const [], 'endpoints': _fresh}), {'fresh': 'AmneziaWG'});
  });
}
