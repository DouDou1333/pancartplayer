/// Détection automatique d'un serveur Ollama sur le réseau local.
///
/// Philosophie « setting friendly » : sur un téléphone, un fournisseur qui
/// pointe sur `localhost:11434` ne peut pas joindre le PC — l'app se
/// configure toute seule en scannant le Wi-Fi. Web-safe : retourne null.
library;

import 'dart:convert';
import 'dart:io'
    show InternetAddressType, NetworkInterface, Socket;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

const int kOllamaPort = 11434;

/// Délais courts pour que le scan /24 reste rapide.
const Duration _probeTimeout = Duration(milliseconds: 350);
const Duration _httpTimeout = Duration(milliseconds: 1200);

/// Nombre de connexions testées en parallèle.
const int _batchSize = 34;

/// Vrai si le corps de réponse /api/version correspond à Ollama.
bool isOllamaVersionJson(String body) {
  if (body.trim().isEmpty) return false;
  try {
    final j = jsonDecode(body);
    return j is Map && j['version'] is String && (j['version'] as String).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Renvoie la base URL `http://<ip>:11434` du premier serveur Ollama
/// joignable (localhost, hôte d'émulateur, puis scan du sous-réseau local),
/// ou null si aucun n'est trouvé avant `timeout`.
Future<String?> detectOllamaUrl({
  Duration timeout = const Duration(seconds: 6),
}) async {
  if (kIsWeb) return null;

  final deadline = DateTime.now().add(timeout);
  final hosts = await _candidateHosts();
  final found = <String>[];

  for (var i = 0; i < hosts.length; i += _batchSize) {
    if (found.isNotEmpty || DateTime.now().isAfter(deadline)) break;
    final chunk = hosts.sublist(
      i,
      i + _batchSize > hosts.length ? hosts.length : i + _batchSize,
    );
    await Future.wait(chunk.map((host) async {
      if (found.isNotEmpty || DateTime.now().isAfter(deadline)) return;
      if (!await _reachable(host)) return;
      if (await _isOllama(host)) found.add('http://$host:$kOllamaPort');
    }));
  }

  return found.isEmpty ? null : found.first;
}

/// Hôtes à tester, par ordre de probabilité (le premier trouvé gagne).
Future<List<String>> _candidateHosts() async {
  final out = <String>{};
  // Ollama lancé sur la même machine (desktop, usage du bouton manuel).
  out.add('127.0.0.1');
  // Émulateur Android : localhost de l'hôte.
  if (defaultTargetPlatform == TargetPlatform.android) out.add('10.0.2.2');
  // Scan du sous-réseau local (Wi-Fi avec le PC).
  final local = await _localIps();
  for (final ip in local) {
    final parts = ip.split('.');
    if (parts.length != 4) continue;
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';
    for (var i = 1; i <= 254; i++) {
      out.add('$prefix$i');
    }
  }
  return <String>[...out];
}

/// IP IPv4 locales attribuées (hors loopback).
Future<List<String>> _localIps() async {
  try {
    final list = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final ips = <String>[];
    for (final i in list) {
      for (final a in i.addresses) {
        final h = a.address;
        if (!h.startsWith('127.') && !h.startsWith('0.')) ips.add(h);
      }
    }
    return ips;
  } catch (_) {
    return const [];
  }
}

Future<bool> _reachable(String host) async {
  try {
    final sock = await Socket.connect(host, kOllamaPort, timeout: _probeTimeout);
    sock.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _isOllama(String host) async {
  try {
    final res = await Dio().get<String>(
      'http://$host:$kOllamaPort/api/version',
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: _httpTimeout,
        receiveTimeout: _httpTimeout,
      ),
    );
    return isOllamaVersionJson(res.data ?? '');
  } catch (_) {
    return false;
  }
}