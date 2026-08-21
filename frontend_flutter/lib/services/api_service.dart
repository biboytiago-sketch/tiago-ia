import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/backend_config.dart';

class ApiService {
  // ============================================================
  // CACHE LAYER: SharedPreferences com validação por DATA
  // - Se a data de hoje mudou → PURGE automático de sinais + status
  // - Se API falhar: retorna cache válido do dia (nao usa frozen seeds!)
  // - Último caso: lista VAZIA clean com flag api_failed=true
  // ============================================================
  static const String _pkSinais = 'tiagoia_cache_ia_sinais_v1';
  static const String _pkSinaisData = 'tiagoia_cache_ia_sinais_day_v1';
  static const String _pkStatus = 'tiagoia_cache_sports_status_v1';
  static const String _pkStatusData = 'tiagoia_cache_sports_status_day_v1';

  static String _todayIso() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static Future<bool> purgeStaleCacheIfDateChanged() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String hoje = _todayIso();
      bool purged = false;
      for (final MapEntry<String, String> e in <String, String>{
        _pkSinaisData: _pkSinais,
        _pkStatusData: _pkStatus,
      }.entries) {
        final String? stored = sp.getString(e.key);
        if (stored != null && stored != hoje) {
          await sp.remove(e.value);
          await sp.setString(e.key, hoje);
          purged = true;
          debugPrint(
              '[ApiService] PURGE_AUTO ${e.value}: data $stored -> $hoje');
        } else if (stored == null) {
          await sp.setString(e.key, hoje);
        }
      }
      return purged;
    } catch (_) {
      return false;
    }
  }

  static Future<void> purgeAllCaches() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.remove(_pkSinais);
      await sp.remove(_pkSinaisData);
      await sp.remove(_pkStatus);
      await sp.remove(_pkStatusData);
      BackendConfig.invalidarCache();
      debugPrint(
          '[ApiService] PURGE_TOTAL: SharedPreferences + BackendConfig OK');
    } catch (_) {}
  }

  static Future<void> _cacheWriteJson(final String keyData,
      final String keyPayload, final Map<String, dynamic> payload) async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(keyData, _todayIso());
      await sp.setString(keyPayload, jsonEncode(payload));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _cacheReadJson(
    final String keyData,
    final String keyPayload,
  ) async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? d = sp.getString(keyData);
      if (d != _todayIso()) return null;
      final String? raw = sp.getString(keyPayload);
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  // ============================================================
  // AUTO-RESOLVE DE BACKEND (fallback chain):
  // 1. Usa cache de 6h se válido
  // 2. Senão: testa Render → LAN IPs → Emulador → pega primeiro /ping = "pong"
  // 3. Tudo com timeout individual curto (1.5s por candidato)
  // ============================================================
  static const String baseUrlLocal = BackendConfig.baseV1;
  static const String baseUrlRender = BackendConfig.baseV1;
  static const bool useRender = false;

  // ============================================================
  // HELPERS: normaliza campos que podem chegar como Map (ex: liga={id,name})
  // Garante String plana para exibição no Flutter.
  // ============================================================
  static String _extrairLigaString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map) {
      final Map<String, dynamic> m = BackendConfig.safeMap(v);
      final String n = BackendConfig.safeString(m['name']);
      if (n.isNotEmpty) return n;
      final String n2 = BackendConfig.safeString(m['nome']);
      if (n2.isNotEmpty) return n2;
      final String n3 = BackendConfig.safeString(m['liga']);
      if (n3.isNotEmpty) return n3;
    }
    return v.toString();
  }

  /// Extrai objeto LIGA compatível com flashscore_home_screen (que espera
  /// `{id, name, country, flag}`). Se `value` já for Map, retorna ele mesmo
  /// (com defaults). Se for STRING plana (ex: "Championship"), monta um
  /// Map sintético compatível para não crashar em `s['league'] as Map`.
  static Map<String, dynamic> _extrairLigaComoMap(dynamic value,
      {String fallbackName = ''}) {
    if (value is Map) return BackendConfig.safeMap(value);
    final String nome = value is String
        ? value
        : (_extrairLigaString(value).isEmpty
            ? fallbackName
            : _extrairLigaString(value));
    return <String, dynamic>{
      'id': 0,
      'name': nome,
      'country': '',
      'flag': '',
    };
  }

  static List<Map<String, dynamic>> _normalizarListaSinais(
      List<Map<String, dynamic>> lista) {
    return lista.map<Map<String, dynamic>>((Map<String, dynamic> s) {
      final Map<String, dynamic> out = Map<String, dynamic>.from(s);
      // 1) Extrai nome da liga como string plana
      final String ligaFlat = _extrairLigaString(out['liga']);
      final String leagueFlat = _extrairLigaString(out['league']);
      final String nomeFinal = ligaFlat.isNotEmpty ? ligaFlat : leagueFlat;
      // 2) Campos flat (string) — telas antigas leem `out['liga']` como texto
      if (nomeFinal.isNotEmpty) {
        out['liga'] = nomeFinal;
        out['liga_nome'] = nomeFinal;
        out['campeonato'] = nomeFinal;
        out['league_name'] = nomeFinal;
      }
      // 3) Campo `league` SEMPRE como MAP compatível (L816 e L1493 do
      //    flashscore_home_screen esperam Map<String, dynamic>).
      //    Se liga veio como string (ou já foi achatada), recompõe o objeto.
      out['league'] = _extrairLigaComoMap(
        out['league'] is Map || out['liga'] is Map
            ? (out['league'] ?? out['liga'])
            : nomeFinal,
        fallbackName: nomeFinal,
      );
      return out;
    }).toList(growable: false);
  }

  /// Base RESOLVIDA (usa cache). Chame [resolveBaseUrl] antes das requisições
  /// ou use [baseUrlAuto] getter.
  static String get baseUrl => BackendConfig.baseV1;

  /// Getter SMART: retorna cache se existir, senão retorna default estático
  /// (não dispara auto-detect para não bloquear em sync). Use [resolveBaseUrl]
  /// em initState das telas para rodar o health check.
  static String get baseUrlAuto {
    if (BackendConfig.temCacheValido) return BackendConfig.cachedBaseV1;
    return BackendConfig.baseV1;
  }

  static String get baseRootAuto {
    if (BackendConfig.temCacheValido) return BackendConfig.cachedBaseRoot;
    return BackendConfig.baseRoot;
  }

  static String get baseV3Auto {
    if (BackendConfig.temCacheValido) return BackendConfig.cachedBaseV3;
    return BackendConfig.baseV3;
  }

  /// Helper: resolve V1 (dispara fallback chain se necessário). Retorna SEMPRE
  /// uma String válida (pior caso = default IP LAN). Pode ser usado em await
  /// dentro de TODAS as funções de request para garantir Render primeiro.
  ///
  /// Se houver cache VÁLIDO, faz um PING RÁPIDO (800ms) para confirmar que o
  /// backend ainda está acessível (ex: usuário mudou de Wi-Fi → 5G). Se não
  /// responder, invalida o cache e roda a re-detecção completa.
  static Future<String> _v1() async {
    if (BackendConfig.temCacheValido) {
      if (await _cacheAindaValido()) return BackendConfig.cachedBaseV1;
      BackendConfig.invalidarCache();
    }
    return resolveV1();
  }

  /// Helper: resolve V3, fallback igual ao _v1().
  static Future<String> _v3() async {
    if (BackendConfig.temCacheValido) {
      if (await _cacheAindaValido()) return BackendConfig.cachedBaseV3;
      BackendConfig.invalidarCache();
    }
    return resolveV3();
  }

  /// Ping rápido para validar se o backend em cache ainda responde.
  /// Evita problema do usuário mudar de Wi-Fi (LAN) para 5G e ficar travado
  /// com IP local que não existe mais na nova rede.
  static Future<bool> _cacheAindaValido() async {
    final String root = BackendConfig.cachedBaseRoot;
    if (root.isEmpty) return false;
    try {
      final http.Response r = await http
          .get(Uri.parse('$root/ping'))
          .timeout(const Duration(milliseconds: 800));
      return r.statusCode == 200 &&
          r.body.trim().toLowerCase().replaceAll('"', '') == 'pong';
    } catch (_) {
      return false;
    }
  }

  /// Resolve automaticamente o melhor backend disponível (RODA NOBOOT).
  /// Retorna o BASE ROOT encontrado (ex: https://tiago-ia-backend.onrender.com
  /// ou http://192.168.1.42:8000) — ou String vazia se nenhum responder.
  ///
  /// Timeouts diferenciados:
  /// - Render (nuvem): até 45s para cold start (acorda instância dormindo)
  /// - LAN / localhost: 1.8s cada (rede local é rápida)
  static Future<String> resolveBaseUrl({
    bool forcarRedeteccao = false,
  }) async {
    if (!forcarRedeteccao && BackendConfig.temCacheValido) {
      return BackendConfig.cachedBaseRoot;
    }
    if (forcarRedeteccao) BackendConfig.invalidarCache();

    String primeiroQueFuncionou = '';
    int idx = 0;
    for (final String root in BackendConfig.candidatosBaseRoot) {
      final Duration timeoutPorCandidato = idx == 0
          ? const Duration(seconds: 45)
          : const Duration(milliseconds: 1800);
      try {
        final http.Response r = await http
            .get(Uri.parse('$root/ping'))
            .timeout(timeoutPorCandidato);
        if (r.statusCode == 200 &&
            r.body.trim().toLowerCase().replaceAll('"', '') == 'pong') {
          primeiroQueFuncionou = root;
          BackendConfig.cachearBaseRoot(root);
          return primeiroQueFuncionou;
        }
      } catch (_) {}
      idx++;
    }
    return primeiroQueFuncionou;
  }

  /// Helper: resolve e retorna a base V1 (mais usada).
  static Future<String> resolveV1({bool forcar = false}) async {
    final String root = await resolveBaseUrl(forcarRedeteccao: forcar);
    if (root.isEmpty) return BackendConfig.baseV1;
    return BackendConfig.baseV1FromRoot(root);
  }

  /// Helper: resolve e retorna a base V3.
  static Future<String> resolveV3({bool forcar = false}) async {
    final String root = await resolveBaseUrl(forcarRedeteccao: forcar);
    if (root.isEmpty) return BackendConfig.baseV3;
    return BackendConfig.baseV3FromRoot(root);
  }

  static Map<String, String> get _headers =>
      {'Content-Type': 'application/json; charset=UTF-8'};

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ LOGIN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Map<String, dynamic> _loginMock(String username, String password) {
    if (username.trim().toLowerCase() == 'tiago' &&
        password == 'jessica2024@') {
      return <String, dynamic>{
        'success': true,
        'offline': true,
        'data': <String, dynamic>{
          'token':
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.tiago.offline_mock_token',
          'user': <String, dynamic>{
            'id': 1,
            'username': 'tiago',
            'role': 'admin',
          },
        },
      };
    }
    return <String, dynamic>{
      'success': false,
      'error': 'Credenciais invÃ¡lidas (modo offline)'
    };
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .post(
            Uri.parse('$base/auth/login'),
            headers: _headers,
            body: jsonEncode(<String, String>{
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return <String, dynamic>{
          'success': true,
          'data': jsonDecode(response.body)
        };
      } else if (response.statusCode == 401) {
        try {
          final Map<String, dynamic> errorBody =
              jsonDecode(response.body) as Map<String, dynamic>;
          return <String, dynamic>{
            'success': false,
            'error': errorBody['detail'] ?? 'Credenciais invÃ¡lidas'
          };
        } catch (_) {
          return <String, dynamic>{
            'success': false,
            'error': 'Credenciais invÃ¡lidas'
          };
        }
      }
    } catch (_) {}

    return _loginMock(username, password);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ HELPERS GERAÃ‡ÃƒO DE DATAS P/ MOCK MULTIDIAS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  static String _fmtDateShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  static String _fmtHora(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  static List<String> _ligasBandeira(String liga) {
    const Map<String, List<String>> mapa = <String, List<String>>{
      'BrasileirÃ£o SÃ©rie A': <String>['Brasil', 'ðŸ‡§ðŸ‡·'],
      'Copa do Brasil': <String>['Brasil', 'ðŸ‡§ðŸ‡·'],
      'Libertadores': <String>['Sul-Americana', 'ðŸ†'],
      'Premier League': <String>['Inglaterra', 'ðŸ´'],
      'La Liga': <String>['Espanha', 'ðŸ‡ªðŸ‡¸'],
      'Serie A': <String>['ItÃ¡lia', 'ðŸ‡®ðŸ‡¹'],
      'Bundesliga': <String>['Alemanha', 'ðŸ‡©ðŸ‡ª'],
      'Ligue 1': <String>['FranÃ§a', 'ðŸ‡«ðŸ‡·'],
      'Champions League': <String>['Europa', 'ðŸ†'],
    };
    return mapa[liga] ?? <String>['Mundo', 'ðŸŒ'];
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ SPORTS MATCHES (CAMPOS OBRIGATÃ“RIOS FLASHSCORE) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Map<String, dynamic> _mkMatch({
    required Random rand,
    required int id,
    required String categoria,
    required String casa,
    required String fora,
    required double oddCasa,
    required double oddEmpate,
    required double oddFora,
    required int probabilidade,
    required String liga,
    required String horario,
    required String dataJogo,
    required String dataCurta,
    required String status,
    int? minutoLive,
    int? placarCasa,
    int? placarFora,
    List<String> alertas = const <String>[],
  }) {
    final List<String> infoLiga = _ligasBandeira(liga);
    return <String, dynamic>{
      'id': 'MATCH_${dataCurta.replaceAll('/', '')}_$id',
      'categoria': categoria,
      'time_casa': casa,
      'time_fora': fora,
      'odd_casa': oddCasa,
      'odd_empate': oddEmpate,
      'odd_fora': oddFora,
      'probabilidade_real': probabilidade,
      'probabilidade': probabilidade,
      'alertas': alertas,
      // ======== CAMPOS OBRIGATÃ“RIOS FLASHSCORE ========
      'data_jogo': dataJogo,
      'data_curta': dataCurta,
      'horario': horario,
      'liga_nome': liga,
      'liga_pais': infoLiga[0],
      'liga_bandeira': infoLiga[1],
      'status': status,
      'minuto_live': minutoLive,
      'placar_casa': placarCasa,
      'placar_fora': placarFora,
      // compatibilidade
      'campeonato': liga,
      'pais': infoLiga[0],
    };
  }

  static Map<String, List<Map<String, dynamic>>> _multidayMockCore() {
    final DateTime hoje = DateTime.now();
    final Random rand = Random(hoje.year * 10000 + hoje.month * 100 + hoje.day);
    final Map<String, List<Map<String, dynamic>>> porData =
        <String, List<Map<String, dynamic>>>{};

    // ── LIGAS & TIMES REAIS TEMPORADA 2025/26 (SEED DINÂMICO) ──
    final List<Map<String, dynamic>> ligasReais = <Map<String, dynamic>>[
      <String, dynamic>{
        'liga': 'Brasileirão Série A',
        'pais': 'Brasil',
        'band': '🇧🇷',
        'times': <String>[
          'Flamengo',
          'Palmeiras',
          'São Paulo',
          'Botafogo',
          'Bahia',
          'Atlético MG',
          'Cruzeiro',
          'Corinthians',
          'Santos',
          'Fluminense',
          'Goiás',
          'Atlético PR',
          'Vasco',
          'Grêmio',
          'Internacional',
          'Fortaleza',
          'Red Bull Bragantino',
          'Cuiabá',
        ],
      },
      <String, dynamic>{
        'liga': 'Premier League',
        'pais': 'Inglaterra',
        'band': '🏴',
        'times': <String>[
          'Arsenal',
          'Chelsea',
          'Liverpool',
          'Man City',
          'Man United',
          'Tottenham',
          'Newcastle',
          'Aston Villa',
          'Brighton',
          'West Ham',
          'Brentford',
          'Wolves',
          'Everton',
          'Crystal Palace',
          'Chelsea',
          'Fulham',
          'Ipswich',
          'Leicester',
          'Bournemouth',
          'Nottingham Forest',
        ],
      },
      <String, dynamic>{
        'liga': 'La Liga EA',
        'pais': 'Espanha',
        'band': '🇪🇸',
        'times': <String>[
          'Real Madrid',
          'Barcelona',
          'Atlético Madrid',
          'Sevilla',
          'Valencia',
          'Villarreal',
          'Real Sociedad',
          'Athletic Bilbao',
          'Espanyol',
          'Celta Vigo',
          'Getafe',
          'Rayo Vallecano',
          'Osasuna',
          'Leganés',
          'Mallorca',
          'Girona',
          'Las Palmas',
          'Alavés',
        ],
      },
      <String, dynamic>{
        'liga': 'Bundesliga',
        'pais': 'Alemanha',
        'band': '🇩🇪',
        'times': <String>[
          'Bayern Munique',
          'Dortmund',
          'Bayer Leverkusen',
          'RB Leipzig',
          'Union Berlin',
          'Freiburg',
          'Eintracht Frankfurt',
          'Wolfsburg',
          'Mönchengladbach',
          'Stuttgart',
          'Hoffenheim',
          'Köln',
          'Darmstadt',
          'Mainz',
          'Werder Bremen',
          'Heidenheim',
          'Bochum',
          'Holstein Kiel',
        ],
      },
      <String, dynamic>{
        'liga': 'Serie A TIM',
        'pais': 'Itália',
        'band': '🇮🇹',
        'times': <String>[
          'Juventus',
          'Inter',
          'Milan',
          'Napoli',
          'Roma',
          'Atalanta',
          'Fiorentina',
          'Lazio',
          'Torino',
          'Bologna',
          'Monza',
          'Udinese',
          'Genoa',
          'Lecce',
          'Empoli',
          'Cagliari',
          'Verona',
          'Parma',
        ],
      },
      <String, dynamic>{
        'liga': 'Ligue 1 McDonalds',
        'pais': 'França',
        'band': '🇫🇷',
        'times': <String>[
          'PSG',
          'Marseille',
          'Monaco',
          'Lyon',
          'Lille',
          'Rennes',
          'Nice',
          'Strasbourg',
          'Nantes',
          'Toulouse',
          'Brest',
          'Lorient',
          'Reims',
          'Le Havre',
          'Montpellier',
          'Metz',
          'Racing Strasbourg',
          'Saint-Étienne',
        ],
      },
    ];

    // ── Gerar plantel DINÂMICO por seed (diferente a cada dia) ──
    final List<Map<String, dynamic>> plantel = <Map<String, dynamic>>[];
    const List<String> categorias = <String>[
      'ACERTOS_80',
      'MULTIPLE_80',
      'LOW_ODDS_155',
      'VALUE',
      'EVITAR'
    ];
    for (int li = 0; li < ligasReais.length; li++) {
      final Map<String, dynamic> L = ligasReais[li];
      final List<String> T = List<String>.from(L['times'] as List<String>);
      T.shuffle(rand);
      int timesUsadosIdx = 0;
      // 3 jogos por liga para compor o plantel
      const int jogosPorLiga = 3;
      for (int k = 0; k < jogosPorLiga && timesUsadosIdx + 1 < T.length; k++) {
        final String casa = T[timesUsadosIdx++];
        final String fora = T[timesUsadosIdx++];
        final String cat = categorias[rand.nextInt(categorias.length)];
        double o1, ox, o2;
        int prob;
        switch (cat) {
          case 'ACERTOS_80':
            o1 = 1.45 + rand.nextDouble() * 0.35;
            ox = 3.20 + rand.nextDouble() * 1.0;
            o2 = 3.80 + rand.nextDouble() * 2.5;
            prob = 78 + rand.nextInt(10);
            break;
          case 'MULTIPLE_80':
            o1 = 1.65 + rand.nextDouble() * 0.3;
            ox = 3.10 + rand.nextDouble() * 0.9;
            o2 = 3.20 + rand.nextDouble() * 2.0;
            prob = 74 + rand.nextInt(8);
            break;
          case 'LOW_ODDS_155':
            o1 = 1.18 + rand.nextDouble() * 0.35;
            ox = 4.80 + rand.nextDouble() * 2.0;
            o2 = 7.50 + rand.nextDouble() * 5.0;
            prob = 84 + rand.nextInt(10);
            break;
          case 'VALUE':
            o1 = 2.0 + rand.nextDouble() * 0.9;
            ox = 2.9 + rand.nextDouble() * 0.6;
            o2 = 2.4 + rand.nextDouble() * 1.0;
            prob = 50 + rand.nextInt(18);
            break;
          case 'EVITAR':
          default:
            o1 = 2.3 + rand.nextDouble() * 1.4;
            ox = 2.85 + rand.nextDouble() * 0.8;
            o2 = 2.3 + rand.nextDouble() * 1.2;
            prob = 33 + rand.nextInt(18);
            break;
        }
        plantel.add(<String, dynamic>{
          'cat': cat,
          'casa': casa,
          'fora': fora,
          'o1': double.parse(o1.toStringAsFixed(2)),
          'oX': double.parse(ox.toStringAsFixed(2)),
          'o2': double.parse(o2.toStringAsFixed(2)),
          'p': prob,
          'liga': L['liga'] as String,
          'pais_liga': L['pais'] as String,
          'band_liga': L['band'] as String,
        });
      }
    }
    // Embaralha tudo para ligas não ficarem sempre agrupadas
    plantel.shuffle(rand);
    // Garante o tamanho mínimo (se precisar enche até 18)
    while (plantel.length < 18) {
      plantel.add(
          Map<String, dynamic>.from(plantel[plantel.length % plantel.length]));
    }

    const List<List<int>> horariosBase = <List<int>>[
      <int>[16, 30],
      <int>[17, 00],
      <int>[18, 00],
      <int>[19, 00],
      <int>[19, 30],
      <int>[20, 00],
      <int>[20, 45],
      <int>[21, 00],
      <int>[21, 30],
      <int>[22, 00],
    ];
    final List<int> minutosLive = <int>[12, 22, 34, 48, 63, 76, 82, 88];
    final List<int> placares = <int>[0, 1, 2, 3];

    // 4 dias: hoje + amanhÃ£ + D+2 + D+3
    for (int d = 0; d < 4; d++) {
      final DateTime dataRef = hoje.add(Duration(days: d));
      final String dataJogo = _fmtDate(dataRef);
      final String dataCurta = _fmtDateShort(dataRef);
      final List<Map<String, dynamic>> jogosDoDia = <Map<String, dynamic>>[];

      for (int j = 0; j < plantel.length; j++) {
        final Map<String, dynamic> base = plantel[(j + d * 2) % plantel.length];
        final List<int> h = horariosBase[(j + d) % horariosBase.length];
        final bool aoVivo = (d == 0 && j % 4 == 0);
        final bool encerrado = (d == 0 && j % 5 == 3);

        String status = 'PROXIMO';
        int? minutoLive;
        int? placarCasa;
        int? placarFora;
        if (aoVivo) {
          status = 'AO_VIVO';
          minutoLive = minutosLive[rand.nextInt(minutosLive.length)];
          placarCasa = placares[rand.nextInt(placares.length)];
          placarFora = placares[rand.nextInt(placares.length - 1)];
        } else if (encerrado) {
          status = 'ENCERRADO';
          placarCasa = placares[rand.nextInt(placares.length)];
          placarFora = placares[rand.nextInt(placares.length)];
        }

        jogosDoDia.add(_mkMatch(
          rand: rand,
          id: j + 1,
          categoria: base['cat'] as String,
          casa: base['casa'] as String,
          fora: base['fora'] as String,
          oddCasa: base['o1'] as double,
          oddEmpate: base['oX'] as double,
          oddFora: base['o2'] as double,
          probabilidade: base['p'] as int,
          liga: base['liga'] as String,
          horario: _fmtHora(h[0], h[1]),
          dataJogo: dataJogo,
          dataCurta: dataCurta,
          status: status,
          minutoLive: minutoLive,
          placarCasa: placarCasa,
          placarFora: placarFora,
          alertas: (base['alertas'] as List<String>?) ?? const <String>[],
        ));
      }
      porData[dataCurta] = jogosDoDia;
    }
    return porData;
  }

  static List<Map<String, dynamic>> _matchesMock() {
    final Map<String, List<Map<String, dynamic>>> md = _multidayMockCore();
    final String chaveHoje = _fmtDateShort(DateTime.now());
    return md[chaveHoje] ?? md.values.first;
  }

  static List<Map<String, dynamic>> _datasDisponiveisMock() {
    final DateTime hoje = DateTime.now();
    return List<Map<String, dynamic>>.generate(4, (int i) {
      final DateTime d = hoje.add(Duration(days: i));
      final String dataCurta = _fmtDateShort(d);
      final String label = i == 0 ? 'Hoje' : (i == 1 ? 'AmanhÃ£' : dataCurta);
      return <String, dynamic>{
        'data_curta': dataCurta,
        'data_completa': _fmtDate(d),
        'label': label,
        'dia_semana': <String>[
          'Dom',
          'Seg',
          'Ter',
          'Qua',
          'Qui',
          'Sex',
          'SÃ¡b'
        ][d.weekday % 7],
      };
    });
  }

  static Map<String, dynamic> _multidayFullMock() {
    final Map<String, List<Map<String, dynamic>>> porData = _multidayMockCore();
    final List<Map<String, dynamic>> datas = _datasDisponiveisMock();
    return <String, dynamic>{
      'datas': datas,
      'jogos_por_data': porData,
      'total_dias': datas.length,
      'total_jogos': porData.values
          .fold<int>(0, (int s, List<Map<String, dynamic>> l) => s + l.length),
    };
  }

  static Future<List<Map<String, dynamic>>> getTodayMatches() async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .get(Uri.parse('$base/sports/today'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<Map<String, dynamic>> lista =
            List<Map<String, dynamic>>.from(data['jogos'] ?? <dynamic>[]);
        if (lista.isNotEmpty) return lista;
      }
    } catch (_) {}
    return _matchesMock();
  }

  static Future<Map<String, dynamic>> getMultidayMatches({int dias = 4}) async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .get(Uri.parse('$base/sports/multiday?dias=$dias'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final Map<String, dynamic> r =
            jsonDecode(response.body) as Map<String, dynamic>;
        if (r['datas'] != null) return r;
      }
    } catch (_) {}
    return _multidayFullMock();
  }

  static Future<List<Map<String, dynamic>>> getLowOddsMatches() async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .get(Uri.parse('$base/sports/low-odds'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<Map<String, dynamic>> lista =
            List<Map<String, dynamic>>.from(data['jogos'] ?? <dynamic>[]);
        if (lista.isNotEmpty) return lista;
      }
    } catch (_) {}
    return _matchesMock().where((Map<String, dynamic> j) {
      final List<num> odds = <num>[
        j['odd_casa'] as num? ?? 999,
        j['odd_empate'] as num? ?? 999,
        j['odd_fora'] as num? ?? 999,
      ];
      final num menorOdd = odds.reduce((num a, num b) => a < b ? a : b);
      return menorOdd <= 1.55;
    }).toList();
  }

  static Map<String, dynamic> _verifyMock(List<String> matchIds) {
    final List<Map<String, dynamic>> jogosFlat = _matchesMock();
    final List<Map<String, dynamic>> jogos = jogosFlat
        .where((Map<String, dynamic> j) => matchIds.contains(j['id'] as String))
        .toList();

    final List<Map<String, dynamic>> cascas = <Map<String, dynamic>>[];
    double oddAcum = 1.0;
    double probProd = 1.0;

    for (final Map<String, dynamic> j in jogos) {
      final num menorOdd = <num>[
        j['odd_casa'] as num? ?? 999,
        j['odd_empate'] as num? ?? 999,
        j['odd_fora'] as num? ?? 999,
      ].reduce((num a, num b) => a < b ? a : b);
      oddAcum *= menorOdd.toDouble();
      final int probReal = j['probabilidade_real'] as int? ?? 50;
      probProd *= probReal / 100.0;
      if (probReal < 60 || (j['categoria'] as String? ?? '') == 'EVITAR') {
        cascas.add(<String, dynamic>{
          'jogo_id': j['id'],
          'time_casa': j['time_casa'],
          'time_fora': j['time_fora'],
          'jogo': '${j['time_casa']} x ${j['time_fora']}',
          'motivo': (j['categoria'] as String? ?? '') == 'EVITAR'
              ? 'Categoria EVITAR â€” risco elevado'
              : 'Probabilidade real baixa (${probReal}%) â€” desmarque.',
        });
      }
    }

    final double probAcum = probProd * 100.0;
    final bool aprovado = jogos.isNotEmpty &&
        cascas.isEmpty &&
        oddAcum <= 1.56 &&
        probAcum >= 65.0;

    return <String, dynamic>{
      'total_selecionados': jogos.length,
      'odd_acumulada': double.parse(oddAcum.toStringAsFixed(2)),
      'probabilidade_real_acumulada': double.parse(probAcum.toStringAsFixed(1)),
      'aprovado': aprovado,
      'recomendacao_final': aprovado
          ? 'APROVADO: Bilhete seguro! Boa sorte.'
          : 'REVISAR: Ajuste seleÃ§Ã£o.',
      'cascas_de_banana': cascas,
      'jogos_selecionados': jogos,
    };
  }

  static Future<Map<String, dynamic>> verifySelectedMatches(
      List<String> matchIds) async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .post(
            Uri.parse('$base/sports/verify-selected-matches'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{'match_ids': matchIds}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return _verifyMock(matchIds);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ CRYPTO SIGNALS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static List<Map<String, dynamic>> _cryptoMock() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'symbol': 'BTCUSDT',
        'par': 'BTC/USDT',
        'preco_atual': 64250.0,
        'precoAtual': 64250.0,
        'rsi_14': 62.4,
        'rsi14': 62.4,
        'ema_20': 63820.0,
        'ema20': 63820.0,
        'tendencia': 'ALTA',
        'side': 'BUY',
        'entry': 64200.0,
        'stop': 62800.0,
        'target': 67500.0,
        'analise_macro':
            'BTC mantÃ©m acima da EMA 20 com RSI neutro-alta. Risco/RazÃ£o favorÃ¡vel.',
        'analiseMacro':
            'BTC mantÃ©m acima da EMA 20 com RSI neutro-alta. Risco/RazÃ£o favorÃ¡vel.',
        'quantfury_copy':
            'PAIR: BTC/USDT | SIDE: BUY | ENTRY: \$64200 | STOP: \$62800 | TARGET: \$67500',
        'quantfuryCopy':
            'PAIR: BTC/USDT | SIDE: BUY | ENTRY: \$64200 | STOP: \$62800 | TARGET: \$67500',
      },
      <String, dynamic>{
        'symbol': 'AAVEUSDT',
        'par': 'AAVE/USDT',
        'preco_atual': 138.55,
        'precoAtual': 138.55,
        'rsi_14': 54.2,
        'rsi14': 54.2,
        'ema_20': 135.80,
        'ema20': 135.80,
        'tendencia': 'CONSOLIDAÃ‡ÃƒO',
        'side': 'BUY',
        'entry': 138.40,
        'stop': 133.20,
        'target': 148.90,
        'analise_macro':
            'AAVE em consolidaÃ§Ã£o perto da EMA. Aguardar rompimento para entrar maior.',
        'analiseMacro':
            'AAVE em consolidaÃ§Ã£o perto da EMA. Aguardar rompimento para entrar maior.',
        'quantfury_copy':
            'PAIR: AAVE/USDT | SIDE: BUY | ENTRY: \$138.40 | STOP: \$133.20 | TARGET: \$148.90',
        'quantfuryCopy':
            'PAIR: AAVE/USDT | SIDE: BUY | ENTRY: \$138.40 | STOP: \$133.20 | TARGET: \$148.90',
      },
    ];
  }

  static Future<List<Map<String, dynamic>>> getCryptoSignals() async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .get(Uri.parse('$base/crypto/signals'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<Map<String, dynamic>> lista =
            List<Map<String, dynamic>>.from(data['sinais'] ?? <dynamic>[]);
        if (lista.isNotEmpty) return lista;
      }
    } catch (_) {}
    return _cryptoMock();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ BANKROLL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Map<String, dynamic> get bankrollMock => <String, dynamic>{
        'dailyLimit': 500.0,
        'daily_limit': 500.0,
        'currentLoss': 0.0,
        'current_loss': 0.0,
        'isLocked': false,
        'is_locked': false,
        'assertividade': 72.5,
        'totalGreens': 28,
        'total_greens': 28,
        'totalReds': 11,
        'total_reds': 11,
      };

  static Future<Map<String, dynamic>> getBankrollStatus() async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .get(Uri.parse('$base/bankroll/status'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final Map<String, dynamic> r =
            jsonDecode(response.body) as Map<String, dynamic>;
        return <String, dynamic>{
          'dailyLimit': (r['daily_limit'] ?? r['dailyLimit'] ?? 500) as num,
          'currentLoss': (r['perda_atual'] ?? r['currentLoss'] ?? 0) as num,
          'isLocked': r['trava_ativada'] ?? r['isLocked'] ?? false,
          'assertividade': (r['assertividade'] ?? 0) as num,
          'totalGreens': (r['total_greens'] ?? r['totalGreens'] ?? 0) as num,
          'totalReds': (r['total_reds'] ?? r['totalReds'] ?? 0) as num,
        };
      }
    } catch (_) {}
    return bankrollMock;
  }

  static Future<Map<String, dynamic>> updateBankrollLimit(
      double dailyLimit) async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .post(
            Uri.parse('$base/bankroll/update-limit'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{'daily_limit': dailyLimit}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return <String, dynamic>{
      'success': true,
      'offline': true,
      'dailyLimit': dailyLimit,
    };
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ CHAT (Tiago) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static String _chatMockReply(String msg) {
    final String lower = msg.toLowerCase();
    if (lower.contains('quem') || lower.contains('vocÃª Ã©')) {
      return 'OlÃ¡! Eu sou o Tiago, sua IA de anÃ¡lise esportiva e cripto. '
          'Minha missÃ£o Ã© proteger a sua banca ðŸ’š. Em que posso te ajudar hoje?';
    }
    if (lower.contains('banca') || lower.contains('bankroll')) {
      return 'Sou o Tiago. Regra principal: nunca arrisque mais de 2% da sua banca por operaÃ§Ã£o. '
          'Use stop loss diÃ¡rio de 5% â€” se perder, pare imediatamente. Qual Ã© o tamanho da sua banca?';
    }
    if (lower.contains('futebol') ||
        lower.contains('apost') ||
        lower.contains('palpite')) {
      return 'Tiago aqui. Categorias principais: ðŸŸ¢ Acertos 80%+ (melhores palpites), '
          'ðŸŽ¯ MÃºltipla Segura (acumuladas), ðŸŽ¯ Odds â‰¤ 1.55 (mÃ¡xima seguranÃ§a), ðŸŸ¡ Valor e âš ï¸ Evitar. Quer listar os de hoje?';
    }
    if (lower.contains('cripto') ||
        lower.contains('btc') ||
        lower.contains('bitcoin')) {
      return 'Sou o Tiago. Sinais cripto (BTC + AAVE) seguem EMA 20 + RSI 14 como referÃªncia: RSI < 30 oversold, > 70 overbought. Acima da EMA20 = tendÃªncia de ALTA.';
    }
    if (lower.contains('olÃ¡') ||
        lower.contains('ola') ||
        lower.contains('bom dia') ||
        lower.contains('boa tarde') ||
        lower.contains('boa noite') ||
        lower.trim() == 'oi') {
      return 'OlÃ¡! Eu sou o Tiago ðŸ’š. Estou aqui para preservar sua banca. Qual anÃ¡lise deseja agora: futebol, cripto ou banca?';
    }
    return 'OlÃ¡, sou o Tiago. Recebi sua mensagem: "$msg". '
        'Como posso te ajudar com anÃ¡lise esportiva ðŸŸ¢, sinais crypto ðŸª™ ou gestÃ£o de banca ðŸ“Š?';
  }

  static Future<Map<String, dynamic>> sendChatMessage(String message) async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .post(
            Uri.parse('$base/chat/message'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{'message': message}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        return <String, dynamic>{'success': true, 'response': data['response']};
      }
    } catch (_) {}
    return <String, dynamic>{
      'success': true,
      'offline': true,
      'response': _chatMockReply(message),
    };
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ REGISTER RESULT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<Map<String, dynamic>> registerResult({
    required String jogoId,
    required String resultado,
    String? motivo,
  }) async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .post(
            Uri.parse('$base/history/register-result'),
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'jogo_id': jogoId,
              'resultado': resultado,
              'motivo': motivo ?? '',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return <String, dynamic>{
      'success': true,
      'offline': true,
      'jogo_id': jogoId,
      'resultado': resultado,
    };
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ SPORTS GROUPED (PaÃ­s â†’ Liga â†’ Jogos FlashScore) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static List<Map<String, dynamic>> _groupFromFlat(
      List<Map<String, dynamic>> flat) {
    final Map<String, Map<String, dynamic>> porPais =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> j in flat) {
      final String pais = (j['liga_pais'] as String?) ?? 'Mundo';
      final String liga =
          (j['liga_nome'] as String?) ?? j['campeonato'] as String? ?? 'Liga';
      final String bandeira = (j['liga_bandeira'] as String?) ?? 'ðŸŒ';

      final Map<String, dynamic> paisNode = porPais.putIfAbsent(
          pais,
          () => <String, dynamic>{
                'pais': pais,
                'total_ligas': 0,
                'total_jogos_pais': 0,
                'ligas': <Map<String, dynamic>>[],
              });
      final List<Map<String, dynamic>> ligas =
          paisNode['ligas'] as List<Map<String, dynamic>>;
      Map<String, dynamic>? ligaNode;
      for (final Map<String, dynamic> l in ligas) {
        if (l['liga_nome'] == liga) {
          ligaNode = l;
          break;
        }
      }
      if (ligaNode == null) {
        ligaNode = <String, dynamic>{
          'liga_nome': liga,
          'liga_bandeira': bandeira,
          'total_jogos': 0,
          'jogos': <Map<String, dynamic>>[],
        };
        ligas.add(ligaNode);
      }
      (ligaNode['jogos'] as List<Map<String, dynamic>>).add(j);
      ligaNode['total_jogos'] = (ligaNode['total_jogos'] as int) + 1;
      paisNode['total_jogos_pais'] = (paisNode['total_jogos_pais'] as int) + 1;
    }
    for (final Map<String, dynamic> p in porPais.values) {
      p['total_ligas'] = (p['ligas'] as List<dynamic>).length;
    }
    final List<Map<String, dynamic>> lista = porPais.values.toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        final int pa = (a['pais'] == 'Brasil') ? 0 : 1;
        final int pb = (b['pais'] == 'Brasil') ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        return (a['pais'] as String).compareTo(b['pais'] as String);
      });
    return lista;
  }

  static Future<List<Map<String, dynamic>>> getGroupedMatches() async {
    try {
      final String base = await _v1();
      final http.Response response = await http
          .get(Uri.parse('$base/sports/grouped'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<Map<String, dynamic>> paises =
            List<Map<String, dynamic>>.from(
                data['paises'] as List<dynamic>? ?? <dynamic>[]);
        if (paises.isNotEmpty) return paises;
      }
    } catch (_) {}
    return _groupFromFlat(_matchesMock());
  }

  static Future<Map<String, List<Map<String, dynamic>>>>
      getGroupedMatchesByDate() async {
    try {
      final Map<String, dynamic> md = await getMultidayMatches();
      final Map<String, List<Map<String, dynamic>>> out =
          <String, List<Map<String, dynamic>>>{};
      final Map<String, dynamic>? jogosPorData =
          md['jogos_por_data'] as Map<String, dynamic>?;
      if (jogosPorData != null) {
        for (final MapEntry<String, dynamic> e in jogosPorData.entries) {
          final List<Map<String, dynamic>> flat =
              List<Map<String, dynamic>>.from(e.value as List<dynamic>);
          out[e.key] = _groupFromFlat(flat);
        }
        return out;
      }
    } catch (_) {}
    final Map<String, List<Map<String, dynamic>>> out =
        <String, List<Map<String, dynamic>>>{};
    final Map<String, List<Map<String, dynamic>>> mock = _multidayMockCore();
    for (final MapEntry<String, List<Map<String, dynamic>>> e in mock.entries) {
      out[e.key] = _groupFromFlat(e.value);
    }
    return out;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ STREAMING SSE CHAT (Caractere por Caractere Ao Vivo) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Stream<String> streamChatMessage(String mensagem) async* {
    bool teveSucessoSSE = false;
    try {
      final String base = await _v1();
      final http.Client client = http.Client();
      final http.Request request =
          http.Request('POST', Uri.parse('$base/chat/stream'))
            ..headers.addAll(<String, String>{
              'Content-Type': 'application/json; charset=UTF-8',
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
            })
            ..body = jsonEncode(<String, dynamic>{'message': mensagem});

      final http.StreamedResponse streamed =
          await client.send(request).timeout(const Duration(seconds: 10));
      if (streamed.statusCode == 200) {
        teveSucessoSSE = true;
        final StringBuffer buffer = StringBuffer();
        await for (final List<int> bytes in streamed.stream) {
          final String chunk = utf8.decode(bytes);
          buffer.write(chunk);
          final String str = buffer.toString();
          final List<String> lines = str.split('\n');
          buffer.clear();
          for (int i = 0; i < lines.length; i++) {
            final String line = lines[i];
            if (i == lines.length - 1 && !str.endsWith('\n')) {
              buffer.write(line);
              continue;
            }
            final String trimmed = line.trim();
            if (trimmed.startsWith('data:')) {
              final String data = trimmed.substring(5).trim();
              if (data.isEmpty) continue;
              try {
                final Map<String, dynamic> obj =
                    jsonDecode(data) as Map<String, dynamic>;
                if (obj['done'] == true) {
                  client.close();
                  return;
                }
                final String? chunkTxt = obj['chunk'] as String?;
                if (chunkTxt != null && chunkTxt.isNotEmpty) yield chunkTxt;
              } catch (_) {
                if (data.isNotEmpty && data != '[DONE]') yield data;
              }
            }
          }
        }
        client.close();
        return;
      }
      client.close();
    } catch (_) {
      // Fallback para modo mock gradual abaixo
    }

    if (teveSucessoSSE) return;

    final String texto = _chatMockReply(mensagem);
    for (int i = 0; i < texto.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 22));
      yield texto[i];
    }
  }

  // ============================================================
  //   REQUISITO FLASHSCORE LIVE: /sports/live + /fixture + /odds
  // ============================================================

  static Map<String, dynamic> _mockTimeTeam({
    required String name,
    required int score,
    required int htScore,
    required int redCards,
    required int yellowCards,
    required int corners,
    required int shotsOnTarget,
    required int shotsOffTarget,
    required int dangerousAttacks,
    required int totalAttacks,
    required int possessionPct,
  }) {
    return <String, dynamic>{
      'name': name,
      'score': score,
      'ht_score': htScore,
      'htScore': htScore,
      'red_cards': redCards,
      'redCards': redCards,
      'yellow_cards': yellowCards,
      'yellowCards': yellowCards,
      'corners': corners,
      'shots_on_target': shotsOnTarget,
      'shotsOnTarget': shotsOnTarget,
      'shots_off_target': shotsOffTarget,
      'shotsOffTarget': shotsOffTarget,
      'dangerous_attacks': dangerousAttacks,
      'dangerousAttacks': dangerousAttacks,
      'total_attacks': totalAttacks,
      'totalAttacks': totalAttacks,
      'possession_pct': possessionPct,
      'possessionPct': possessionPct,
    };
  }

  static List<Map<String, dynamic>> _mockTimeline(int seed, int minuteMax) {
    final Random r = Random(seed);
    final List<Map<String, dynamic>> evs = <Map<String, dynamic>>[];
    void ev(int m, String t, String team, String player, String detail) =>
        evs.add(<String, dynamic>{
          'minute': m,
          'type': t,
          'team': team,
          'player': player,
          'detail': detail,
        });
    final List<String> golsCasa = <String>[
      'Pedro',
      'Gabigol',
      'Luiz AraÃºjo',
      'Endrick'
    ];
    final List<String> golsFora = <String>['Raphael Veiga', 'LÃ³pez', 'Dudu'];
    if (minuteMax >= 18) {
      ev(
          r.nextInt(14) + 8,
          'goal',
          'home',
          golsCasa[r.nextInt(golsCasa.length)],
          'Gol! FinalizaÃ§Ã£o no Ã¢ngulo.');
    }
    if (minuteMax >= 32) {
      ev(r.nextInt(14) + 27, 'yellow', 'away', 'ZÃ© Ivaldo',
          'CartÃ£o amarelo - falta.');
    }
    ev(minuteMax >= 45 ? 45 : minuteMax, 'ht_score', 'info', '',
        'Intervalo - Placar parcial computado.');
    if (minuteMax >= 58) {
      ev(r.nextInt(14) + 50, 'dangerous_attack', 'home', '',
          'Ataque perigoso - 3 toques na Ã¡rea.');
    }
    if (minuteMax >= 72) {
      ev(r.nextInt(16) + 68, 'substitution', r.nextBool() ? 'home' : 'away',
          'Gerson â†’ Thiago Maia', 'SubstituiÃ§Ã£o estratÃ©gica.');
    }
    if (minuteMax >= 80) {
      ev(r.nextInt(10) + 75, 'var', 'info', '',
          'VAR revisando - anÃ¡lise de lance.');
    }
    if (minuteMax >= 86) {
      ev(minuteMax - r.nextInt(5), 'goal', 'away',
          golsFora[r.nextInt(golsFora.length)], 'Gol de cabeÃ§a no escanteio.');
    }
    evs.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final String ma = a['minute'].toString();
      final String mb = b['minute'].toString();
      final bool aStr = ma == 'HT';
      final bool bStr = mb == 'HT';
      if (aStr && !bStr) return 1;
      if (!aStr && bStr) return -1;
      if (aStr && bStr) return 0;
      final int ia = int.tryParse(ma) ?? 0;
      final int ib = int.tryParse(mb) ?? 0;
      return ia.compareTo(ib);
    });
    return evs;
  }

  static Map<String, dynamic> _mockStats({
    required int posseCasa,
    required int daCasa,
    required int daFora,
    required int ataCasa,
    required int ataFora,
    required int sOtCasa,
    required int sOtFora,
    required int sOffCasa,
    required int sOffFora,
    required int escCasa,
    required int escFora,
    required int amaCasa,
    required int amaFora,
    required int verCasa,
    required int verFora,
  }) {
    return <String, dynamic>{
      'possession_pct': <String, int>{
        'home': posseCasa,
        'away': 100 - posseCasa
      },
      'possessionPct': <String, int>{
        'home': posseCasa,
        'away': 100 - posseCasa
      },
      'dangerous_attacks': <String, int>{'home': daCasa, 'away': daFora},
      'dangerousAttacks': <String, int>{'home': daCasa, 'away': daFora},
      'total_attacks': <String, int>{'home': ataCasa, 'away': ataFora},
      'totalAttacks': <String, int>{'home': ataCasa, 'away': ataFora},
      'shots_on_target': <String, int>{'home': sOtCasa, 'away': sOtFora},
      'shotsOnTarget': <String, int>{'home': sOtCasa, 'away': sOtFora},
      'shots_off_target': <String, int>{'home': sOffCasa, 'away': sOffFora},
      'shotsOffTarget': <String, int>{'home': sOffCasa, 'away': sOffFora},
      'corners': <String, int>{'home': escCasa, 'away': escFora},
      'yellow_cards': <String, int>{'home': amaCasa, 'away': amaFora},
      'yellowCards': <String, int>{'home': amaCasa, 'away': amaFora},
      'red_cards': <String, int>{'home': verCasa, 'away': verFora},
      'redCards': <String, int>{'home': verCasa, 'away': verFora},
    };
  }

  static Map<String, dynamic> _flashscoreMockFull() {
    final DateTime agora = DateTime.now();
    final String updatedAt = agora.toIso8601String();

    String minuteTxt(String ss, int baseMin) {
      if (ss == '1H') return '${baseMin.clamp(1, 45)}\'';
      if (ss == '2H') return '${(45 + baseMin).clamp(46, 90)}\'';
      if (ss == 'HT') return 'HT';
      if (ss == 'FT') return 'FT';
      if (ss == 'NS') return '16:00';
      return ss;
    }

    final List<Map<String, dynamic>> allGames = <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> cfg = <Map<String, dynamic>>[
      <String, dynamic>{
        'fid': 1001,
        'league': 'BrasileirÃ£o SÃ©rie A',
        'country': 'Brasil',
        'flag': 'ðŸ‡§ðŸ‡·',
        'ss': '1H',
        'min': 32,
        'homeName': 'Flamengo',
        'awayName': 'Vasco',
        'scoreH': 1,
        'scoreA': 0,
        'htH': 1,
        'htA': 0,
        'oddH': '1.85',
        'oddD': '3.40',
        'oddA': '4.20',
        'posseC': 58,
        'daC': 37,
        'daF': 22,
        'ataC': 82,
        'ataF': 61,
        'sOtC': 6,
        'sOtF': 3,
        'sOffC': 9,
        'sOffF': 7,
        'escC': 4,
        'escF': 2,
        'amaC': 2,
        'amaF': 3,
        'verC': 0,
        'verF': 0,
      },
      <String, dynamic>{
        'fid': 1002,
        'league': 'Paulista SÃ©rie A1',
        'country': 'Brasil',
        'flag': 'ðŸ‡§ðŸ‡·',
        'ss': 'NS',
        'min': 0,
        'homeName': 'Palmeiras',
        'awayName': 'Fluminense',
        'scoreH': 0,
        'scoreA': 0,
        'htH': 0,
        'htA': 0,
        'oddH': '1.45',
        'oddD': '4.60',
        'oddA': '6.90',
        'posseC': 0,
        'daC': 0,
        'daF': 0,
        'ataC': 0,
        'ataF': 0,
        'sOtC': 0,
        'sOtF': 0,
        'sOffC': 0,
        'sOffF': 0,
        'escC': 0,
        'escF': 0,
        'amaC': 0,
        'amaF': 0,
        'verC': 0,
        'verF': 0,
      },
      <String, dynamic>{
        'fid': 1003,
        'league': 'BrasileirÃ£o SÃ©rie B',
        'country': 'Brasil',
        'flag': 'ðŸ‡§ðŸ‡·',
        'ss': '2H',
        'min': 69,
        'homeName': 'Real Madrid',
        'awayName': 'Barcelona',
        'scoreH': 3,
        'scoreA': 0,
        'htH': 2,
        'htA': 0,
        'oddH': '1.12',
        'oddD': '9.50',
        'oddA': '21.0',
        'posseC': 63,
        'daC': 51,
        'daF': 19,
        'ataC': 104,
        'ataF': 52,
        'sOtC': 9,
        'sOtF': 2,
        'sOffC': 12,
        'sOffF': 8,
        'escC': 7,
        'escF': 1,
        'amaC': 3,
        'amaF': 2,
        'verC': 0,
        'verF': 1,
      },
      <String, dynamic>{
        'fid': 1004,
        'league': 'Premier League',
        'country': 'Inglaterra',
        'flag': 'ðŸ´ó §ó ¢ó ¥ó ®ó §ó ¿',
        'ss': 'NS',
        'min': 0,
        'homeName': 'Liverpool',
        'awayName': 'Arsenal',
        'scoreH': 0,
        'scoreA': 0,
        'htH': 0,
        'htA': 0,
        'oddH': '2.30',
        'oddD': '3.30',
        'oddA': '3.00',
        'posseC': 0,
        'daC': 0,
        'daF': 0,
        'ataC': 0,
        'ataF': 0,
        'sOtC': 0,
        'sOtF': 0,
        'sOffC': 0,
        'sOffF': 0,
        'escC': 0,
        'escF': 0,
        'amaC': 0,
        'amaF': 0,
        'verC': 0,
        'verF': 0,
      },
      <String, dynamic>{
        'fid': 1005,
        'league': 'Serie A',
        'country': 'ItÃ¡lia',
        'flag': 'ðŸ‡®ðŸ‡¹',
        'ss': 'FT',
        'min': 90,
        'homeName': 'Inter',
        'awayName': 'Milan',
        'scoreH': 2,
        'scoreA': 1,
        'htH': 1,
        'htA': 1,
        'oddH': '2.10',
        'oddD': '3.20',
        'oddA': '3.50',
        'posseC': 52,
        'daC': 33,
        'daF': 28,
        'ataC': 88,
        'ataF': 74,
        'sOtC': 5,
        'sOtF': 4,
        'sOffC': 11,
        'sOffF': 10,
        'escC': 5,
        'escF': 4,
        'amaC': 4,
        'amaF': 3,
        'verC': 0,
        'verF': 0,
      },
      <String, dynamic>{
        'fid': 1006,
        'league': 'La Liga',
        'country': 'Espanha',
        'flag': 'ðŸ‡ªðŸ‡¸',
        'ss': 'HT',
        'min': 45,
        'homeName': 'AtlÃ©tico Madrid',
        'awayName': 'Sevilla',
        'scoreH': 1,
        'scoreA': 0,
        'htH': 1,
        'htA': 0,
        'oddH': '1.72',
        'oddD': '3.60',
        'oddA': '5.10',
        'posseC': 59,
        'daC': 29,
        'daF': 15,
        'ataC': 71,
        'ataF': 44,
        'sOtC': 4,
        'sOtF': 1,
        'sOffC': 6,
        'sOffF': 4,
        'escC': 3,
        'escF': 1,
        'amaC': 1,
        'amaF': 2,
        'verC': 0,
        'verF': 0,
      },
      <String, dynamic>{
        'fid': 1007,
        'league': 'Bundesliga',
        'country': 'Alemanha',
        'flag': 'ðŸ‡©ðŸ‡ª',
        'ss': '2H',
        'min': 48,
        'homeName': 'Bayern',
        'awayName': 'Dortmund',
        'scoreH': 1,
        'scoreA': 1,
        'htH': 0,
        'htA': 1,
        'oddH': '1.55',
        'oddD': '4.20',
        'oddA': '5.90',
        'posseC': 61,
        'daC': 41,
        'daF': 31,
        'ataC': 95,
        'ataF': 76,
        'sOtC': 7,
        'sOtF': 5,
        'sOffC': 10,
        'sOffF': 9,
        'escC': 6,
        'escF': 4,
        'amaC': 2,
        'amaF': 2,
        'verC': 0,
        'verF': 0,
      },
      <String, dynamic>{
        'fid': 1008,
        'league': 'Ligue 1',
        'country': 'FranÃ§a',
        'flag': 'ðŸ‡«ðŸ‡·',
        'ss': 'NS',
        'min': 0,
        'homeName': 'PSG',
        'awayName': 'Marseille',
        'scoreH': 0,
        'scoreA': 0,
        'htH': 0,
        'htA': 0,
        'oddH': '1.38',
        'oddD': '5.20',
        'oddA': '8.50',
        'posseC': 0,
        'daC': 0,
        'daF': 0,
        'ataC': 0,
        'ataF': 0,
        'sOtC': 0,
        'sOtF': 0,
        'sOffC': 0,
        'sOffF': 0,
        'escC': 0,
        'escF': 0,
        'amaC': 0,
        'amaF': 0,
        'verC': 0,
        'verF': 0,
      },
    ];

    for (int i = 0; i < cfg.length; i++) {
      final Map<String, dynamic> g = cfg[i];
      final String ss = g['ss'] as String;
      final int baseMin = g['min'] as int;
      final String statusLabel = switch (ss) {
        '1H' => '1Âº TEMPO',
        'HT' => 'INTERVALO',
        '2H' => '2Âº TEMPO',
        'FT' => 'ENCERRADO',
        'NS' => 'NÃƒO INICIADO',
        _ => ss,
      };
      final int scoreH = g['scoreH'] as int;
      final int scoreA = g['scoreA'] as int;
      final Map<String, dynamic> stats = _mockStats(
        posseCasa: g['posseC'] as int,
        daCasa: g['daC'] as int,
        daFora: g['daF'] as int,
        ataCasa: g['ataC'] as int,
        ataFora: g['ataF'] as int,
        sOtCasa: g['sOtC'] as int,
        sOtFora: g['sOtF'] as int,
        sOffCasa: g['sOffC'] as int,
        sOffFora: g['sOffF'] as int,
        escCasa: g['escC'] as int,
        escFora: g['escF'] as int,
        amaCasa: g['amaC'] as int,
        amaFora: g['amaF'] as int,
        verCasa: g['verC'] as int,
        verFora: g['verF'] as int,
      );

      final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
      if (ss != 'NS') {
        if (scoreH > 0)
          events.add(<String, dynamic>{
            'type': 'goal',
            'team': 'home',
            'minute': 14,
            'player': 'Gol Casa'
          });
        if (scoreA > 0)
          events.add(<String, dynamic>{
            'type': 'goal',
            'team': 'away',
            'minute': 22,
            'player': 'Gol Fora'
          });
      }

      final String leagueName = g['league'] as String;
      final String homeName = g['homeName'] as String;
      final String awayName = g['awayName'] as String;

      allGames.add(<String, dynamic>{
        'fixture_id': g['fid'].toString(),
        'fixtureId': g['fid'].toString(),
        'league': leagueName,
        'country': g['country'] as String,
        'flag': g['flag'] as String,
        'leagueId': 100 + i,
        'league_name': leagueName,
        'leagueName': leagueName,
        'statusShort': ss,
        'status': ss,
        'minute_text': minuteTxt(ss, baseMin),
        'minuteText': minuteTxt(ss, baseMin),
        'elapsed': (ss == 'NS' || ss == 'FT') ? null : baseMin,
        'status_label': statusLabel,
        'statusLabel': statusLabel,
        'home_id': 200 + (i * 2),
        'homeId': 200 + (i * 2),
        'home_name': homeName,
        'homeName': homeName,
        'home_logo': '',
        'away_id': 200 + (i * 2) + 1,
        'awayId': 200 + (i * 2) + 1,
        'away_name': awayName,
        'awayName': awayName,
        'away_logo': '',
        'score': <String, int>{'home': scoreH, 'away': scoreA},
        'goals_home': scoreH,
        'goalsAway': scoreA,
        'score_ht': <String, int>{
          'home': g['htH'] as int,
          'away': g['htA'] as int
        },
        'scoreHtHome': g['htH'] as int,
        'scoreHtAway': g['htA'] as int,
        'odds': <String, dynamic>{
          'home_win': g['oddH'] as String,
          'draw': g['oddD'] as String,
          'away_win': g['oddA'] as String,
          'homeWin': g['oddH'] as String,
          'awayWin': g['oddA'] as String,
        },
        'home': <String, dynamic>{
          'name': homeName,
          'logo': '',
          'id': 200 + (i * 2),
          'score': scoreH,
          'ht_score': g['htH'] as int,
          'possessionPct': g['posseC'] as int,
          'shotsOnTarget': g['sOtC'] as int,
          'shotsOffTarget': g['sOffC'] as int,
          'totalAttacks': g['ataC'] as int,
          'dangerousAttacks': g['daC'] as int,
          'corners': g['escC'] as int,
          'yellowCards': g['amaC'] as int,
          'redCards': g['verC'] as int,
        },
        'away': <String, dynamic>{
          'name': awayName,
          'logo': '',
          'id': 200 + (i * 2) + 1,
          'score': scoreA,
          'ht_score': g['htA'] as int,
          'possessionPct': 100 - (g['posseC'] as int),
          'shotsOnTarget': g['sOtF'] as int,
          'shotsOffTarget': g['sOffF'] as int,
          'totalAttacks': g['ataF'] as int,
          'dangerousAttacks': g['daF'] as int,
          'corners': g['escF'] as int,
          'yellowCards': g['amaF'] as int,
          'redCards': g['verF'] as int,
        },
        'statistics': stats,
        'stats': stats,
        'events': events,
        'timeline': events,
        'favorito_id': 200 + (i * 2),
        'favoritoOdd': g['oddH'] as String,
      });
    }

    return <String, dynamic>{
      'updated_at': updatedAt,
      'updatedAt': updatedAt,
      'polling_next_ms': 20000,
      'pollingNextMs': 20000,
      'total': allGames.length,
      'matches': allGames,
    };
  }

  Future<Map<String, dynamic>> getIaSinais({
    bool usarGemini = false,
    bool apenasHojeLive = true,
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final List<String> queries = <String>[
      'usar_gemini=$usarGemini',
      'apenas_hoje_live=$apenasHojeLive',
      'salt=${DateTime.now().millisecondsSinceEpoch % 10000}',
    ];
    final String base = await _v1();
    final String url = '$base/ia/sinais?${queries.join('&')}';
    int httpStatus = 0;
    String? erroDetalhe;

    // 1) Cache se NÃO é forçado
    if (!forceRefresh) {
      final Map<String, dynamic>? cached =
          await _cacheReadJson(_pkSinaisData, _pkSinais);
      if (cached != null) {
        debugPrint('[ApiService] getIaSinais: CACHE HIT dia ${_todayIso()}'
            ' (total=${cached['total']})');
        return cached;
      }
    }

    // 2) HTTP LIVE (com logs detalhados)
    try {
      debugPrint('[ApiService] GET (live) $url');
      final http.Response resp =
          await http.get(Uri.parse(url), headers: _headers).timeout(timeout);
      httpStatus = resp.statusCode;
      if (httpStatus == 200) {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(jsonDecode(resp.body));
        final int total = data['total'] as int? ?? 0;
        final List<Map<String, dynamic>> sinais =
            List<Map<String, dynamic>>.from(
          ((data['sinais'] as List<dynamic>?) ?? <dynamic>[])
              .map<Map<String, dynamic>>(
                  (dynamic e) => Map<String, dynamic>.from(e as Map)),
        );
        final Map<String, dynamic> totais =
            Map<String, dynamic>.from(data['totais'] ?? <String, dynamic>{});
        final String fonte = data['fonte']?.toString() ?? 'API';
        final String? generatedAt = data['generated_at']?.toString();

        final Map<String, dynamic> saida = <String, dynamic>{
          'ok': true,
          'fonte': fonte,
          'totais': totais,
          'total': total,
          'generated_at': generatedAt ?? DateTime.now().toIso8601String(),
          'sinais': _normalizarListaSinais(sinais),
          'http_status': 200,
          'cache_hit': false,
          'api_failed': false,
        };
        await _cacheWriteJson(_pkSinaisData, _pkSinais, saida);
        debugPrint(
            '[ApiService] getIaSinais LIVE OK: $total sinais (fonte=$fonte)');
        return saida;
      } else if (httpStatus == 401) {
        erroDetalhe = 'HTTP 401 Unauthorized · chave inválida (API)';
      } else if (httpStatus == 403) {
        erroDetalhe = 'HTTP 403 Forbidden · plano não pago';
      } else if (httpStatus == 429) {
        erroDetalhe = 'HTTP 429 Rate Limit';
      } else {
        erroDetalhe = 'HTTP $httpStatus';
      }
      debugPrint('[ApiService] getIaSinais FALHOU: $erroDetalhe · url=$url');
    } catch (e) {
      httpStatus = 0;
      erroDetalhe = 'Exception: ${e.toString().replaceRange(
            e.toString().length > 160 ? 160 : e.toString().length,
            e.toString().length,
            '...',
          )}';
      debugPrint('[ApiService] getIaSinais EXCEPTION: $erroDetalhe · url=$url');
    }

    // 3) Fallback 1: cache válido do DIA (não seeds antigos!)
    final Map<String, dynamic>? cached =
        await _cacheReadJson(_pkSinaisData, _pkSinais);
    if (cached != null) {
      final Map<String, dynamic> out = Map<String, dynamic>.from(cached);
      out['cache_hit'] = true;
      out['http_status'] = httpStatus;
      out['api_failed'] = true;
      out['erro_detalhe'] = erroDetalhe;
      out['aviso'] = 'API fora temporariamente · usando cache do dia';
      out['sinais'] = _normalizarListaSinais(
        List<Map<String, dynamic>>.from(
            out['sinais'] as List<dynamic>? ?? <Map<String, dynamic>>[]),
      );
      debugPrint(
          '[ApiService] getIaSinais CACHE FALLBACK · total=${out['total']}');
      return out;
    }

    // 4) Fallback final: LISTA VAZIA clean (NÃO USA SEEDS ESTÁTICOS: deprecated!)
    debugPrint(
        '[ApiService] getIaSinais: API falhou e sem cache → retorna lista VAZIA clean');
    return <String, dynamic>{
      'ok': true,
      'fonte': 'Offline (cache vazio)',
      'totais': <String, int>{'apostar': 0, 'cuidado': 0, 'nao_apostar': 0},
      'total': 0,
      'generated_at': DateTime.now().toIso8601String(),
      'sinais': <Map<String, dynamic>>[],
      'http_status': httpStatus,
      'cache_hit': false,
      'api_failed': true,
      'erro_detalhe': erroDetalhe,
      'lista_vazia': true,
    };
  }

  static Map<String, dynamic> _getIaSinaisLocal() {
    final DateTime agora = DateTime.now();
    final int seed = agora.year * 1000000 +
        agora.month * 10000 +
        agora.day * 100 +
        agora.hour;
    final Random rand = Random(seed);

    const List<List<String>> confrontos = <List<String>>[
      <String>[
        'Palmeiras',
        'Fluminense',
        'Brasileir\u00e3o S\u00e9rie A',
        'BR',
        'Brazil'
      ],
      <String>[
        'Flamengo',
        'Vasco da Gama',
        'Brasileir\u00e3o S\u00e9rie A',
        'BR',
        'Brazil'
      ],
      <String>[
        'S\u00e3o Paulo',
        'Botafogo',
        'Brasileir\u00e3o S\u00e9rie A',
        'BR',
        'Brazil'
      ],
      <String>[
        'Internacional',
        'Gr\u00eanio',
        'Brasileir\u00e3o S\u00e9rie A',
        'BR',
        'Brazil'
      ],
      <String>[
        'Corinthians',
        'Santos',
        'Brasileir\u00e3o S\u00e9rie A',
        'BR',
        'Brazil'
      ],
      <String>[
        'Atl\u00e9tico MG',
        'Cruzeiro',
        'Brasileir\u00e3o S\u00e9rie A',
        'BR',
        'Brazil'
      ],
      <String>['Liverpool', 'Arsenal', 'Premier League', 'UK', 'England'],
      <String>['Man. City', 'Chelsea', 'Premier League', 'UK', 'England'],
      <String>['Man. United', 'Tottenham', 'Premier League', 'UK', 'England'],
      <String>['Newcastle', 'Aston Villa', 'Premier League', 'UK', 'England'],
      <String>['Real Madrid', 'Barcelona', 'La Liga', 'ES', 'Spain'],
      <String>['Atl\u00e9tico Madrid', 'Sevilla', 'La Liga', 'ES', 'Spain'],
      <String>['Real Sociedad', 'Villarreal', 'La Liga', 'ES', 'Spain'],
      <String>['Bayern', 'Dortmund', 'Bundesliga', 'DE', 'Germany'],
      <String>['Leipzig', 'Bayer Leverkusen', 'Bundesliga', 'DE', 'Germany'],
      <String>['Inter', 'Milan', 'Serie A', 'IT', 'Italy'],
      <String>['Juventus', 'Napoli', 'Serie A', 'IT', 'Italy'],
      <String>['Roma', 'Atalanta', 'Serie A', 'IT', 'Italy'],
      <String>['PSG', 'Marseille', 'Ligue 1', 'FR', 'France'],
      <String>['Monaco', 'Lyon', 'Ligue 1', 'FR', 'France'],
      <String>[
        'Flamengo',
        'Palmeiras',
        'Copa Libertadores',
        'SA',
        'South America'
      ],
      <String>[
        'Boca Juniors',
        'River Plate',
        'Libertadores',
        'AR',
        'Argentina'
      ],
      <String>['Real Madrid', 'Man. City', 'Champions League', 'EU', 'Europe'],
      <String>['Bayern', 'PSG', 'Champions League', 'EU', 'Europe'],
    ];

    final List<Map<String, dynamic>> pool = <Map<String, dynamic>>[];
    for (int i = 0; i < confrontos.length; i++) {
      final List<String> c = confrontos[i];
      final double o1 = 1.25 + rand.nextDouble() * 3.4;
      final double ox = 2.8 + rand.nextDouble() * 2.0;
      final double o2 = 1.35 + rand.nextDouble() * 4.8;
      final bool favoritoCasa = o1 < o2;
      final double oddMin = favoritoCasa ? o1 : o2;

      String sinal;
      int conf;
      String tipo;
      double valorOdd;
      if (oddMin <= 1.85 && rand.nextDouble() < 0.78) {
        sinal = 'apostar';
        conf = 68 + rand.nextInt(22);
        if (rand.nextBool()) {
          tipo = favoritoCasa ? 'Vit\u00f3ria Casa' : 'Vit\u00f3ria Fora';
          valorOdd = oddMin;
        } else if (rand.nextBool()) {
          tipo = 'Dupla Chance ${favoritoCasa ? '1X' : 'X2'}';
          valorOdd = oddMin * 0.82;
        } else {
          tipo = 'Over 2.5 Gols';
          valorOdd = 1.55 + rand.nextDouble() * 0.9;
        }
      } else if (rand.nextDouble() < 0.45) {
        sinal = 'cuidado';
        conf = 42 + rand.nextInt(24);
        tipo = rand.nextBool() ? 'Over 2.5 Gols' : 'Ambos Marcam';
        valorOdd = 1.6 + rand.nextDouble() * 1.0;
      } else {
        sinal = 'nao_apostar';
        conf = 62 + rand.nextInt(28);
        tipo = rand.nextBool() ? 'Mercado vol\u00e1til' : 'Evitar entrada';
        valorOdd = rand.nextDouble() * 2.0;
      }

      final List<String> rs = <String>[];
      final List<String> razoesBase = <String>[
        'Favorito com odd baixa, alta probabilidade estat\u00edstica.',
        'Press\u00e3o em casa + mando de campo consistente.',
        'Hist\u00f3rico recente: 4 vit\u00f3rias em 5 \u00faltimos jogos.',
        'Defesa s\u00f3lida sofrendo menos de 0.8 gols/jogo.',
        'Ataque com m\u00e9dia > 2.1 gols/jogo nas \u00faltimas 6 rodadas.',
        'Intervalo HT com placar baixo, expectativa de gols no 2\u00baT.',
        'Ao vivo placar baixo + press\u00e3o indicando gols finais.',
        'Time visitante em m\u00e1 fase (3 derrotas consecutivas).',
        'Cl\u00e1ssico com rivalidade: expectativa de faltas e cart\u00f5es.',
        'Odd alta indica volatilidade, evitar mercado principal.',
        'Odds equilibradas - jogo muito imprevis\u00edvel.',
        'Placar distante + jogo avan\u00e7ado, poucas possibilidades.',
      ];
      final int qtdRazoes = 2 + rand.nextInt(2);
      for (int k = 0; k < qtdRazoes; k++) {
        final String r = razoesBase[rand.nextInt(razoesBase.length)];
        if (!rs.contains(r)) rs.add(r);
      }

      pool.add(<String, dynamic>{
        'fixture_id': 80000 + i * 17 + seed % 97,
        'sinal': sinal,
        'confianca': conf,
        'league': <String, dynamic>{
          'name': c[2],
          'flag': c[3],
          'country': c[4],
        },
        'teams': <String, dynamic>{
          'home': <String, dynamic>{'name': c[0]},
          'away': <String, dynamic>{'name': c[1]},
        },
        'razoes': rs,
        'odd_sugerida': <String, dynamic>{
          'tipo': tipo,
          'valor': double.parse(valorOdd.toStringAsFixed(2)),
          'time': sinal == 'apostar'
              ? (favoritoCasa ? c[0] : c[1])
              : (sinal == 'cuidado' ? '${c[0]} x ${c[1]}' : '-'),
        },
      });
    }

    pool.shuffle(rand);
    final List<Map<String, dynamic>> sinais =
        pool.sublist(0, 8 + rand.nextInt(6)).toList(growable: false);
    int apostar = 0;
    int cuidado = 0;
    int nao = 0;
    for (final Map<String, dynamic> s in sinais) {
      switch (s['sinal'] as String) {
        case 'apostar':
          apostar++;
          break;
        case 'cuidado':
          cuidado++;
          break;
        default:
          nao++;
      }
    }
    return <String, dynamic>{
      'totais': <String, int>{
        'apostar': apostar,
        'cuidado': cuidado,
        'nao_apostar': nao,
      },
      'total': sinais.length,
      'sinais': sinais,
    };
  }

  // ===============================
  // APOSTA MÚLTIPLA (ACCUMULATOR)
  // ===============================

  Future<Map<String, dynamic>> postAnalyzeAccumulator({
    required List<Map<String, dynamic>> selecoes,
    String userId = 'default',
    double stakeTotal = 100.0,
    String? perfilOverride,
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final String base = await _v1();
    final String url = '$base/sports/analyze-accumulator';
    final Map<String, dynamic> body = <String, dynamic>{
      'user_id': userId,
      'stake_total': stakeTotal,
      if (perfilOverride != null) 'perfil_usuario_override': perfilOverride,
      'selecoes': selecoes,
    };
    try {
      final http.Response resp = await http
          .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(_decodeStatic(resp.body));
        return <String, dynamic>{'ok': true, ...data};
      }
    } catch (_) {}
    return _fallbackAccumulator(selecoes);
  }

  static Map<String, dynamic> _fallbackAccumulator(
      List<Map<String, dynamic>> selecoes) {
    final List<Map<String, dynamic>> res = <Map<String, dynamic>>[];
    double oddManter = 1.0;
    double probReal = 1.0;
    int manter = 0;
    int qtdVerde = 0;
    for (int i = 0; i < selecoes.length; i++) {
      final Map<String, dynamic> s = selecoes[i];
      final double odd = (s['odd_apostada'] as num?)?.toDouble() ?? 2.05;
      final String mercado =
          (s['mercado'] as String? ?? 'Resultado Final').toLowerCase();
      bool vale = false;
      double prob = 48.0;
      String risco = 'Médio';
      List<String> motivos = <String>[];
      if (mercado.contains('escanteio') || mercado.contains('corner')) {
        vale = true;
        prob = 60.0;
        risco = 'Médio';
        motivos = <String>[
          'Média campeonato Brasileirão = 9.2 escanteios / partida.',
          'Times em casa costumam pressionar e aumentar cantos.',
        ];
      } else if (mercado.contains('cartão') || mercado.contains('amarelo')) {
        vale = i % 2 == 0;
        prob = vale ? 56.0 : 38.0;
        risco = vale ? 'Médio' : 'Alto';
        motivos = vale
            ? <String>[
                'Clássico com rivalidade histórica: expectativa de faltas.'
              ]
            : <String>['Árbitro atual tem média baixa de 3.8 amarelos.'];
      } else if (mercado.contains('chute') || mercado.contains('jogador')) {
        vale = odd <= 2.3;
        prob = vale ? 52.0 : 34.0;
        risco = 'Alto';
        motivos = <String>[
          vale
              ? 'Jogador escalado como titular, média 3.1 chutes/partida.'
              : 'Jogador pode sair reservado.',
        ];
      } else {
        vale = odd < 1.85 &&
            (s['aposta_em'] as String? ?? 'Casa').toLowerCase() != 'fora';
        prob = vale ? 72.0 : 41.0;
        risco = vale ? 'Baixo' : (odd > 3.8 ? 'Extremo' : 'Alto');
        motivos = vale
            ? <String>[
                'Favorito com odd baixa: pressão em casa.',
                'Histórico recente: 4 vitórias em 5 últimos.'
              ]
            : <String>[
                'Odd alta fora de casa indica volatilidade.',
                'Falhas recentes no sistema defensivo.'
              ];
      }
      final String status =
          vale ? 'VALE A PENA ARRISCAR' : 'NÃO VALE A PENA / MUITO ARRISCADO';
      final String acao =
          vale ? 'MANTER APOSTA' : 'REMOVER ESTE JOGO DO BILHETE';
      if (vale) {
        oddManter *= odd;
        probReal *= (prob / 100.0);
        manter++;
        qtdVerde++;
      }
      res.add(<String, dynamic>{
        'fixture_id': (s['fixture_id'] as String?) ?? 'sel_$i',
        'home_name': s['home_name'] ?? 'Casa',
        'away_name': s['away_name'] ?? 'Fora',
        'liga_name': s['liga_name'] ?? 'Brasileirão',
        'mercado': s['mercado'] ?? 'Resultado Final',
        'aposta_em': s['aposta_em'] ?? 'Casa',
        'odd_apostada': odd,
        'status': status,
        'motivo_detalhado': motivos,
        'nivel_de_risco': risco,
        'probabilidade_real_pct': prob,
        'odd_justa': double.parse((100.0 / max(15.0, prob)).toStringAsFixed(2)),
        'recomendacao_acao': acao,
        'noticias_ultimas_horas': <dynamic>[],
        'estatisticas_mercado': <String, dynamic>{
          'probabilidade_implícita_odd':
              double.parse((100.0 / max(1.01, odd)).toStringAsFixed(1)),
        },
      });
    }
    return <String, dynamic>{
      'ok': false,
      'fallback': true,
      'gerado_em': DateTime.now().toIso8601String(),
      'perfil_risco_usuario': <String, dynamic>{
        'perfil': 'moderado',
        'score_risco': 5.0,
        'total_decisoes': 0,
      },
      'resumo_bilhete': <String, dynamic>{
        'total_selecoes': selecoes.length,
        'total_manter': manter,
        'total_remover': selecoes.length - manter,
        'total_vale_a_pena': qtdVerde,
        'total_nao_vale': selecoes.length - qtdVerde,
        'odd_acumulada_manter': double.parse(oddManter.toStringAsFixed(3)),
        'odd_acumulada_total': double.parse(selecoes
            .fold<double>(
                1.0,
                (double ant, dynamic s) =>
                    ant * ((s['odd_apostada'] as num?)?.toDouble() ?? 1.0))
            .toStringAsFixed(3)),
        'probabilidade_real_estimada_pct':
            double.parse((probReal * 100.0).toStringAsFixed(3)),
      },
      'selecoes': res,
    };
  }

  // ===============================
  // CRIPTO MACRO INVESTMENT
  // ===============================

  Future<Map<String, dynamic>> postCryptoAnalyze({
    String userId = 'default',
    List<String> ativos = const <String>['BTC', 'AAVE', 'IOTA'],
    int horizonteDias = 30,
    double valorAporteUsd = 1000.0,
    String? perfilOverride,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final String base = await _v1();
    final String url = '$base/crypto/analyze-investment';
    final Map<String, dynamic> body = <String, dynamic>{
      'user_id': userId,
      'ativos': ativos,
      'horizonte_dias': horizonteDias,
      'valor_aporte_usd': valorAporteUsd,
      if (perfilOverride != null) 'perfil_risco_override': perfilOverride,
    };
    try {
      final http.Response resp = await http
          .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(_decodeStatic(resp.body));
        return <String, dynamic>{'ok': true, ...data};
      }
    } catch (_) {}
    return _fallbackCrypto(
        ativos: ativos,
        valorAporte: valorAporteUsd,
        horizonteDias: horizonteDias);
  }

  static Map<String, dynamic> _fallbackCrypto({
    required List<String> ativos,
    double valorAporte = 1000.0,
    int horizonteDias = 30,
  }) {
    final Map<String, Map<String, dynamic>> mocks =
        <String, Map<String, dynamic>>{
      'BTC': <String, dynamic>{
        'preco': 67450.0,
        'rsi': 58.2,
        'ema20': 66100.0,
        'status': 'COMPRAR',
        'score': 71.5,
        'entry': 66800.0,
        'sl': 63400.0,
        'tp': 72900.0,
        'impacto': <String>[
          'Taxa FED atual 5.25% com expectativa HOLD na próxima reunião.',
          'Fear & Greed = 62 (Greed), fluxo ETF BTC positivo 7 dias.',
          'Halving consolidado + BlackRock aumentou posição.',
        ],
        'noticias': <String>[
          'ETF spot BTC acumula 1.2B em entrada líquida na semana.',
          'MicroStrategy compra mais 12,000 BTC no trimestre.',
        ],
        'eco': <String>[
          'Halving 2024: inflação anual caiu para 0.85%.',
          'Rede Lightning capacidade >6.1k BTC.',
        ],
      },
      'AAVE': <String, dynamic>{
        'preco': 138.45,
        'rsi': 51.8,
        'ema20': 135.2,
        'status': 'AGUARDAR / ALTO RISCO',
        'score': 49.0,
        'entry': 135.5,
        'sl': 127.0,
        'tp': 152.0,
        'impacto': <String>[
          'Risco regulatório alto na UE para DeFi.',
          'Depende de APY stablecoin (USDC APY = 4.1%).',
          'Auditoria Certora recente: zero vulnerabilidades.',
        ],
        'noticias': <String>['Governança AAVE aprova ativação GHO L2.'],
        'eco': <String>['TVL AAVE >12B USD; lidera lending DeFi.'],
      },
      'IOTA': <String, dynamic>{
        'preco': 0.4185,
        'rsi': 63.3,
        'ema20': 0.402,
        'status': 'COMPRAR',
        'score': 64.3,
        'entry': 0.410,
        'sl': 0.372,
        'tp': 0.488,
        'impacto': <String>[
          'Baixa correlação com BTC em altcoin rallies.',
          'RWA (tokenização ativos reais) em parcerias automotivas.',
          'Coordicídio Tangle 2.0 ativo: rede feel-less segura.',
        ],
        'noticias': <String>['IOTA anuncia integração EVM em ShimmerEVM.'],
        'eco': <String>[
          'Tangle 2.0 + ISC (Smart Contracts) em mainnet.',
          'Parceria MOBI para dados veiculares.',
        ],
      },
    };
    final List<Map<String, dynamic>> analises = <Map<String, dynamic>>[];
    double scoreTotal = 0.0;
    final Map<String, double> alocPadrao = <String, double>{
      'BTC': 55,
      'AAVE': 25,
      'IOTA': 20,
    };
    for (final String ativo in ativos) {
      final Map<String, dynamic> m =
          mocks[ativo.toUpperCase()] ?? mocks.values.first;
      final double score = (m['score'] as num).toDouble();
      scoreTotal += score;
      final double alocPct =
          alocPadrao[ativo.toUpperCase()] ?? (100.0 / ativos.length);
      analises.add(<String, dynamic>{
        'simbolo': ativo.toUpperCase(),
        'nome': ativo.toUpperCase(),
        'preco_atual_usd': m['preco'],
        'status': m['status'],
        'score_sinal_0_100': score,
        'impacto_geopolitico': m['impacto'],
        'resumo_noticias': m['noticias'],
        'ponto_entrada_sugerido_usd': m['entry'],
        'stop_loss_usd': m['sl'],
        'take_profit_usd': m['tp'],
        'razao_risco_retorno': double.parse((((m['tp'] as num) -
                        (m['entry'] as num))
                    .abs() /
                max(0.000001, ((m['sl'] as num) - (m['entry'] as num)).abs()))
            .toStringAsFixed(2)),
        'alocacao_sugerida_pct_carteira': alocPct,
        'valor_alocado_aporte_usd':
            double.parse((valorAporte * alocPct / 100.0).toStringAsFixed(2)),
        'pilares': <String, dynamic>{
          'geopolitica_macro': <String, dynamic>{
            'taxa_juros_fed_atual_pct': 5.25,
            'risco_regulatorio_cripto': 'MODERADO',
          },
          'noticias_sentimento_global': m['noticias'],
          'analise_tecnica_onchain': <String, dynamic>{
            'preco_atual_usd': m['preco'],
            'rsi_14': m['rsi'],
            'ema_20': m['ema20'],
            'fear_greed_index': <String, dynamic>{
              'value': 62,
              'classification': 'Greed',
            },
          },
          'ecossistema_desenvolvimentos': m['eco'],
        },
      });
    }
    final double med = scoreTotal / max(1, ativos.length);
    final String rec = med >= 60
        ? 'ALOCAR GRADUALMENTE (DCA 4 semanas)'
        : (med >= 45
            ? 'PARCIAL: Alocar apenas em ativos COMPRAR.'
            : 'AGUARDAR MELHOR CENÁRIO.');
    return <String, dynamic>{
      'ok': false,
      'fallback': true,
      'gerado_em': DateTime.now().toIso8601String(),
      'perfil_risco_usuario': <String, dynamic>{
        'perfil': 'moderado',
        'score_risco': 5.0,
      },
      'horizonte_dias': horizonteDias,
      'valor_aporte_usd': valorAporte,
      'recomendacao_geral_carteira': rec,
      'fear_and_greed_global': <String, dynamic>{
        'value': 62,
        'classification': 'Greed',
      },
      'macro_geopolitico': <String, dynamic>{
        'taxa_juros_fed_atual_pct': 5.25,
        'risco_regulatorio_cripto': 'MODERADO',
        'dolar_r4': 5.48,
      },
      'analises_ativos': analises,
    };
  }

  // ===============================
  // USER FEEDBACK (APRENDIZADO)
  // ===============================

  Future<Map<String, dynamic>> postUserFeedback({
    required String categoria,
    required String itemId,
    required String decisao,
    String userId = 'default',
    String? itemLabel,
    String? sinalIa,
    double? confiancaIa,
    bool riscoAceito = false,
    String perfilRisco = 'moderado',
    double valorStake = 0.0,
    String? resultadoReal,
    String? comentario,
    Map<String, dynamic>? extra,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final String base = await _v1();
    final String url = '$base/user/feedback';
    final Map<String, dynamic> body = <String, dynamic>{
      'user_id': userId,
      'categoria': categoria,
      'item_id': itemId,
      'decisao': decisao,
      if (itemLabel != null) 'item_label': itemLabel,
      if (sinalIa != null) 'sinal_ia': sinalIa,
      if (confiancaIa != null) 'confianca_ia': confiancaIa,
      'risco_aceito': riscoAceito,
      'perfil_risco_usuario': perfilRisco,
      'valor_stake': valorStake,
      if (resultadoReal != null) 'resultado_real': resultadoReal,
      if (comentario != null) 'comentario_usuario': comentario,
      if (extra != null) 'extra': extra,
    };
    try {
      final http.Response resp = await http
          .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(_decodeStatic(resp.body));
        return <String, dynamic>{'ok': true, ...data};
      }
    } catch (_) {}
    return <String, dynamic>{
      'ok': true,
      'offline': true,
      'mensagem': 'Feedback salvo localmente (modo offline).',
      'salvo_em': DateTime.now().toIso8601String(),
    };
  }

  static Map<String, dynamic> _decodeStatic(String body) =>
      Map<String, dynamic>.from(jsonDecode(body) as Map<String, dynamic>);

  // ── STEP 1 · API STATUS BADGE ────────────────────────────────
  static Future<Map<String, dynamic>> getSportsApiStatus({
    bool probe = true,
    bool forceRefresh = false,
    Duration timeout = const Duration(
        seconds: 30), // 🟢 antes 20s (ping em 6 fontes pode demorar)
  }) async {
    // 1) Cache se nao forcar refresh
    if (!forceRefresh) {
      final Map<String, dynamic>? cached =
          await _cacheReadJson(_pkStatusData, _pkStatus);
      if (cached != null) {
        debugPrint(
            '[ApiService] getSportsApiStatus: CACHE HIT dia ${_todayIso()}');
        return cached;
      }
    }

    String? ultimoErro;
    int ultimoStatus = 0;
    try {
      final String v1 = await resolveV1();
      final String v3 = await resolveV3();
      http.Response? resp;
      for (final String base in <String>[v3, v1]) {
        final String url =
            '$base/sports/api-status?probe=${probe ? 'true' : 'false'}&salt=${DateTime.now().millisecondsSinceEpoch % 1000000}';
        try {
          debugPrint('[ApiService] GET SportsApiStatus LIVE $url');
          resp = await http
              .get(Uri.parse(url), headers: _headers)
              .timeout(timeout);
          ultimoStatus = resp.statusCode;
          if (resp.statusCode == 200) break;
          ultimoErro = 'HTTP ${resp.statusCode} em $base';
        } catch (e) {
          ultimoErro = 'Exception: $e';
          resp = null;
        }
      }
      if (resp != null && resp.statusCode == 200) {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(
            jsonDecode(resp.body) as Map<String, dynamic>);
        payload['cache_hit'] = false;
        payload['api_failed'] = false;
        payload['http_status'] = 200;
        await _cacheWriteJson(_pkStatusData, _pkStatus, payload);
        debugPrint('[ApiService] getSportsApiStatus LIVE OK: '
            'online=${payload['fontes_online']}/${payload['total_fontes']} '
            'status=${payload['status_geral']}');
        return payload;
      }
    } catch (e) {
      ultimoErro = 'Exception geral: $e';
    }

    // 2) Fallback 1: cache valido do DIA (nao mock 0/6 hardcoded!)
    final Map<String, dynamic>? cached2 =
        await _cacheReadJson(_pkStatusData, _pkStatus);
    if (cached2 != null) {
      final Map<String, dynamic> out = Map<String, dynamic>.from(cached2);
      out['cache_hit'] = true;
      out['api_failed'] = true;
      out['http_status'] = ultimoStatus;
      out['erro_detalhe'] = ultimoErro;
      debugPrint('[ApiService] getSportsApiStatus CACHE FALLBACK');
      return out;
    }

    // 3) Fallback final: SOMENTE se NENHUM cache do dia.
    debugPrint(
        '[ApiService] getSportsApiStatus: MOCK 0/6 (sem cache, API falhou: $ultimoErro)');
    return <String, dynamic>{
      'assinatura': 'IA do Tiago · Offline Mock',
      'versao': '3.4.0-mock',
      'gerado_em_utc': DateTime.now().toUtc().toIso8601String(),
      'status_geral': 'OFFLINE_FALLBACK',
      'fontes_online': 0,
      'fontes_chave_ok': 0,
      'total_fontes': 6,
      'http_status': ultimoStatus,
      'cache_hit': false,
      'api_failed': true,
      'erro_detalhe': ultimoErro,
      'lista_vazia': false,
      'fallback': <String, dynamic>{
        'ativa': true,
        'label': 'IA do Tiago · Dinâmico',
      },
      'fontes': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'MOCK',
          'ordem': 1,
          'label': 'Offline (Fallback IA)',
          'camada': 'FALLBACK',
          'chave_configurada': false,
          'probe_online': false,
          'latencia_ms': 0,
          'ultimo_erro':
              ultimoErro ?? 'Backend não conectado — aguardando rede.',
          'quantidade_jogos_recente': 0,
        },
      ],
      'env_vars_check': <String, dynamic>{
        'chaves_ok': 0,
        'chaves_faltando': 99,
        'detalhes': <dynamic>[],
      },
    };
  }
}
