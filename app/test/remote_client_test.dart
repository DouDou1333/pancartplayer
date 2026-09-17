import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/remote_client.dart';

void main() {
  group('SseDecoder', () {
    test('payloads data: simples sur un chunk unique', () {
      final d = SseDecoder();
      final evs = d.add(utf8.encode('data: {"a":1}\n\ndata: {"a":2}\n'));
      expect(evs, ['{"a":1}', '{"a":2}']);
      expect(d.isComplete, isFalse);
    });

    test('ligne scindée entre deux chunks réseau', () {
      final d = SseDecoder();
      // "data: {c" + "afé}\n" coupé au milieu de l'événement
      final part1 = utf8.encode('data: {"tok":"c');
      final part2 = utf8.encode('afé"}\n');
      expect(d.add(part1), isEmpty); // ligne incomplète -> rien pour l'instant
      final evs = d.add(part2);
      expect(evs, ['{"tok":"café"}']);
    });

    test('caractère UTF-8 multi-octets coupé ne fait pas crasher', () {
      final d = SseDecoder();
      final bytes = utf8.encode('data: {"tok":"café"}\n');
      final start = bytes.indexOf(0xc3); // premier octet du « é »
      expect(start, greaterThan(0));
      final chunk1 = bytes.sublist(0, start + 1); // se termine au milieu du é
      final chunk2 = bytes.sublist(start + 1); // commence par 0xa9
      final evs1 = d.add(chunk1); // aucune exception
      expect(evs1, isEmpty); // ligne pas encore terminée
      final evs2 = d.add(chunk2);
      expect(evs2, isNotEmpty);
      expect(evs2.join(), contains('caf'));
    });

    test('événement [DONE] termine le flux', () {
      final d = SseDecoder();
      d.add(utf8.encode('data: {"a":1}\n\n'));
      expect(d.isComplete, isFalse);
      d.add(utf8.encode('data: [DONE]\n'));
      expect(d.isComplete, isTrue);
      expect(d.add(utf8.encode('data: extra\n')), isEmpty);
    });

    test('lignes non-data et vides ignorées', () {
      final d = SseDecoder();
      final evs = d.add(utf8.encode(': ping\n\nid: 42\ndata: {"ok":true}\n\nevent: foo\n'));
      expect(evs, ['{"ok":true}']);
    });
  });
}