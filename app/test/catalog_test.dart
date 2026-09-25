import 'package:flutter_test/flutter_test.dart';

import 'package:pancartplayer/core/catalog.dart';
import 'package:pancartplayer/core/models.dart';

void main() {
  group('kCatalog', () {
    test('IDs uniques', () {
      final ids = kCatalog.map((m) => m.id).toSet();
      expect(ids.length, kCatalog.length);
    });

    test('tailles cohérentes avec la recommandation', () {
      for (final m in kCatalog) {
        if (m.recommendedFor == 'phone') {
          expect(m.sizeMb, lessThanOrEqualTo(1200),
              reason: '${m.id} trop gros pour "phone"');
        }
        if (m.recommendedFor == 'all') {
          expect(m.sizeMb, lessThanOrEqualTo(kLocalRamLimitMb),
              reason: '${m.id} dépasse la limite RAM locale');
        }
        expect(m.sizeMb, greaterThan(0));
      }
    });

    test('gemma3-4b est exécutable en local', () {
      expect(catalogById('gemma3-4b')!.sizeMb, lessThanOrEqualTo(kLocalRamLimitMb));
    });

    test('zenith-v1 est exécutable en local', () {
      expect(catalogById('zenith-v1-coding-uncensored')!.sizeMb,
          lessThanOrEqualTo(kLocalRamLimitMb));
    });
  });

  group('catalogByIdOrCustom', () {
    test('retrouve dans le base puis dans les customs', () {
      expect(catalogByIdOrCustom('qwen3-4b', const []), isNotNull);
      final custom = CatalogModel.fromHfUrl(
        url:
            'https://huggingface.co/x/legacy/resolve/main/maestro-dens-8b-Q4_K_M.gguf',
      );
      expect(catalogByIdOrCustom('dans-le-vide', const []), isNull);
      expect(
        catalogByIdOrCustom(custom.id, [custom])?.name,
        contains('maestro-dens-8b'),
      );
    });
  });
}