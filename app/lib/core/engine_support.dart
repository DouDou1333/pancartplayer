/// Disponibilité du moteur LOCAL (llama.cpp/llamadart) sur la plateforme.
///
/// Le binaire macOS téléchargé par llamadart exige macOS 13.3+ ; sur macOS 12
/// (et antérieur) le chat local est indisponible mais le Cloud fonctionne.
/// Web-safe : sur web, l'implémentation stub (aucune API native) est utilisée.
library;

export 'engine_support_stub.dart'
    if (dart.library.io) 'engine_support_io.dart';