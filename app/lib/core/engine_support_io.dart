/// Implémentation native (dart:io disponible) : détecte les systèmes où le
/// moteur local ne peut pas charger les binaires llama.cpp.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Version minimale exigée par les binaires macOS de llamadart-native.
const int kLocalMinMacosMajor = 13;
const int kLocalMinMacosMinor = 3;

/// Renvoie une explication si le moteur LOCAL est indisponible sur ce
/// système, sinon null.
String? localEngineUnsupportedReason() {
  if (kIsWeb) {
    return 'le moteur local (llama.cpp) n\'est pas disponible sur le web — '
        'utilise un fournisseur Cloud.';
  }
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    final raw = Platform.operatingSystemVersion;
    final parts = raw.split('.');
    final major = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 99;
    final minor = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 99;
    if (major < kLocalMinMacosMajor ||
        (major == kLocalMinMacosMajor && minor < kLocalMinMacosMinor)) {
      return 'llama.cpp exige macOS $kLocalMinMacosMajor.$kLocalMinMacosMinor+ '
          '(ici $raw). Le chat local est désactivé : passe en Cloud.';
    }
  }
  return null;
}