import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:uuid/uuid.dart';

void main() {
  const validBaseUrl = "https://example.com/configurations/user1/filename.yaml";
  const validExtendedUrl = "https://example.com/configurations/user1/filename.yaml?test#b";
  const validSupportUrl = "https://example.com/support";

  group("parse", () {
    test("Should use filename in url with no headers and fragment", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validBaseUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("filename"));
            expect(rp.url, equals(validBaseUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use fragment in url with no headers", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validExtendedUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("b"));
            expect(rp.url, equals(validExtendedUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use base64 title in headers", () {
      final headers = <String, List<String>>{
        "profile-title": ["base64:ZXhhbXBsZVRpdGxl"],
        "profile-update-interval": ["1"],
        "connection-test-url": [validBaseUrl],
        "remote-dns-address": [validBaseUrl],
        "subscription-userinfo": ["upload=0;download=1024;total=10240.5;expire=1704054600.55"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: ProfileEntity.remote(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validExtendedUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.name, equals("exampleTitle"));
              expect(rp.url, equals(validExtendedUrl));
              expect(rp.options, equals(const ProfileOptions(updateInterval: Duration(hours: 1))));
              expect(
                rp.subInfo,
                equals(
                  SubscriptionInfo(
                    upload: 0,
                    download: 1024,
                    total: 10240,
                    expire: DateTime.fromMillisecondsSinceEpoch(1704054600 * 1000),
                    webPageUrl: validBaseUrl,
                    supportUrl: validSupportUrl,
                  ),
                ),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    test("Should use infinite when given 0 for subscription properties", () {
      final headers = <String, List<String>>{
        "profile-title": ["title"],
        "profile-update-interval": ["1"],
        "subscription-userinfo": ["upload=0;download=1024;total=0;expire=0"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: RemoteProfileEntity(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validBaseUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.subInfo, isNotNull);
              expect(rp.subInfo!.total, equals(ProfileParser.infiniteTrafficThreshold + 1));
              expect(
                rp.subInfo!.expire,
                equals(DateTime.fromMillisecondsSinceEpoch(ProfileParser.infiniteTimeThreshold * 1000)),
              );
            },
            local: (lp) {},
          );
        });
      });
    });
  });

  group("rescue-links (запасной XHTTP из PasarGuard)", () {
    test("адрес /links только для https://host/sub/<токен>", () {
      expect(
        ProfileParser.pasarGuardLinksUrl("https://vpn.example.com/sub/abc123"),
        "https://vpn.example.com/sub/abc123/links",
      );
      expect(
        ProfileParser.pasarGuardLinksUrl(" https://vpn.example.com/sub/abc123/ "),
        "https://vpn.example.com/sub/abc123/links",
      );
      expect(
        ProfileParser.pasarGuardLinksUrl("https://vpn.example.com:8443/sub/abc123#NL"),
        "https://vpn.example.com:8443/sub/abc123/links",
      );
      expect(ProfileParser.pasarGuardLinksUrl("https://vpn.example.com/sub/abc123/links"), isNull);
      expect(ProfileParser.pasarGuardLinksUrl("http://vpn.example.com/sub/abc123"), isNull);
      expect(ProfileParser.pasarGuardLinksUrl(validBaseUrl), isNull);
    });

    test("ссылки дописываются в JSON-подписку, мусорные строки отбрасываются", () {
      const sub = '{"outbounds":[{"type":"vless","tag":"NL"}],"route":{"final":"proxy"}}';
      const links = "vless://a@1.2.3.4:443?type=raw#NL\r\n\r\nне ссылка\nvless://a@1.2.3.4:443?type=xhttp#NL2\n";
      final merged = jsonDecode(ProfileParser.withRescueLinks(sub, links)!) as Map<String, dynamic>;
      expect(merged["rescue-links"], "vless://a@1.2.3.4:443?type=raw#NL\nvless://a@1.2.3.4:443?type=xhttp#NL2");
      expect(merged["route"], {"final": "proxy"});
      expect((merged["outbounds"] as List).length, 1);
    });

    test("не JSON-подписка или пустые ссылки — без изменений", () {
      expect(ProfileParser.withRescueLinks("vless://a@1.2.3.4:443#NL", "vless://b@1.2.3.4:443#X"), isNull);
      expect(ProfileParser.withRescueLinks('{"log":{}}', "vless://b@1.2.3.4:443#X"), isNull);
      expect(ProfileParser.withRescueLinks('{"outbounds":[]}', '{"detail":"Not Found"}'), isNull);
    });
  });

  group("смена портов Hysteria2 (/rescue с сервера)", () {
    const sub =
        '{"outbounds":[{"type":"vless","tag":"NL"},{"type":"hysteria2","tag":"NL игры","server_port":443}, '
        '{"type":"hysteria2","tag":"свой","server_ports":["1000:2000"]}],"route":{"final":"proxy"}}';

    List<Map<String, dynamic>> outbounds(String? merged) =>
        ((jsonDecode(merged!) as Map<String, dynamic>)["outbounds"] as List).cast<Map<String, dynamic>>();

    test("адрес /rescue строится как /links", () {
      expect(
        ProfileParser.pasarGuardSubUrl("https://vpn.example.com/sub/abc123", "rescue"),
        "https://vpn.example.com/sub/abc123/rescue",
      );
      expect(ProfileParser.pasarGuardSubUrl("https://vpn.example.com/sub/abc123/links", "rescue"), isNull);
    });

    test("диапазон и интервал вписываются только в hysteria2 без своих портов", () {
      const rescue = '{"hysteria2":{"ports":"20000-20999","hop_interval":"30"}}';
      final list = outbounds(ProfileParser.withHysteriaHop(sub, rescue));
      expect(list[0], {"type": "vless", "tag": "NL"});
      expect(list[1]["server_ports"], ["20000:20999"]);
      expect(list[1]["hop_interval"], "30s");
      expect(list[1]["server_port"], 443);
      expect(list[2]["server_ports"], ["1000:2000"]);
      expect(list[2].containsKey("hop_interval"), isFalse);
      expect((jsonDecode(ProfileParser.withHysteriaHop(sub, rescue)!) as Map)["route"], {"final": "proxy"});
    });

    test("форматы: двоеточие, несколько диапазонов, один порт, интервал числом и с s", () {
      final list = outbounds(
        ProfileParser.withHysteriaHop(
          sub,
          '{"hysteria2":{"ports":"20000:20099, 30000 ,40000-40001","hop_interval":45}}',
        ),
      );
      expect(list[1]["server_ports"], ["20000:20099", "30000:30000", "40000:40001"]);
      expect(list[1]["hop_interval"], "45s");
      expect(
        outbounds(
          ProfileParser.withHysteriaHop(sub, '{"hysteria2":{"ports":"20000-20999","hop_interval":"60s"}}'),
        )[1]["hop_interval"],
        "60s",
      );
    });

    test("кривой интервал — порты есть, интервал по умолчанию sing-box", () {
      for (final bad in ['"2"', '"полминуты"', '""', 'null', '"30m"']) {
        final list = outbounds(
          ProfileParser.withHysteriaHop(sub, '{"hysteria2":{"ports":"20000-20999","hop_interval":$bad}}'),
        );
        expect(list[1]["server_ports"], ["20000:20999"], reason: bad);
        expect(list[1].containsKey("hop_interval"), isFalse, reason: bad);
      }
    });

    test("кривой ответ или диапазон — подписка без изменений (иначе sing-box не запустится)", () {
      for (final bad in [
        '',
        '<html>404</html>',
        '{"detail":"Not Found"}',
        '{"hysteria2":"20000-20999"}',
        '{"hysteria2":{"ports":20000}}',
        '{"hysteria2":{"ports":""}}',
        '{"hysteria2":{"ports":"20000-"}}',
        '{"hysteria2":{"ports":"0-100"}}',
        '{"hysteria2":{"ports":"20999-20000"}}',
        '{"hysteria2":{"ports":"60000-70000"}}',
        '{"hysteria2":{"ports":"20000-20999,abc"}}',
      ]) {
        expect(ProfileParser.withHysteriaHop(sub, bad), isNull, reason: bad);
      }
    });

    test("нет hysteria2 без портов или подписка не JSON — без изменений", () {
      const rescue = '{"hysteria2":{"ports":"20000-20999"}}';
      expect(ProfileParser.withHysteriaHop('{"outbounds":[{"type":"vless"}]}', rescue), isNull);
      expect(ProfileParser.withHysteriaHop("hysteria2://p@1.2.3.4:443#NL", rescue), isNull);
    });
  });
}
