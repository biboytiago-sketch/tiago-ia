import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/backend_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class _Esportes {
  static const String futebol = 'Futebol';
  static const String basquete = 'Basquete';
  static const String tenis = 'Tênis';
  static const String volei = 'Vôlei';
  static const List<String> todos = <String>[
    futebol,
    basquete,
    tenis,
    volei,
    'Futsal',
    'Handebol',
    'MMA',
    'Corridas',
  ];
}

class _LigaFixada {
  final String nome;
  final String pais;
  final String flag;
  final String? idChave;
  const _LigaFixada(
      {required this.nome,
      required this.pais,
      required this.flag,
      this.idChave});
}

const List<_LigaFixada> _kLigasFixadas = <_LigaFixada>[
  _LigaFixada(
      nome: 'Brasileirão Série A',
      pais: 'Brasil',
      flag: '🇧🇷',
      idChave: 'Brasileirão Série A'),
  _LigaFixada(
      nome: 'Brasileirão Série B',
      pais: 'Brasil',
      flag: '🇧🇷',
      idChave: 'Brasileirão Série B'),
  _LigaFixada(
      nome: 'Copa do Brasil',
      pais: 'Brasil',
      flag: '🇧🇷',
      idChave: 'Copa do Brasil'),
  _LigaFixada(
      nome: 'LaLiga', pais: 'Espanha', flag: '🇪🇸', idChave: 'La Liga'),
  _LigaFixada(
      nome: 'Premier League',
      pais: 'Inglaterra',
      flag: '🏴',
      idChave: 'Premier League'),
  _LigaFixada(
      nome: 'UEFA Champions League',
      pais: 'Europa',
      flag: '🇪🇺',
      idChave: 'UEFA Champions League'),
  _LigaFixada(
      nome: 'Copa Libertadores',
      pais: 'América do Sul',
      flag: '🌎',
      idChave: 'Copa Libertadores'),
  _LigaFixada(
      nome: 'Bundesliga',
      pais: 'Alemanha',
      flag: '🇩🇪',
      idChave: 'Bundesliga'),
  _LigaFixada(
      nome: 'Serie A', pais: 'Itália', flag: '🇮🇹', idChave: 'Serie A'),
  _LigaFixada(
      nome: 'Ligue 1', pais: 'França', flag: '🇫🇷', idChave: 'Ligue 1'),
];

enum _FiltroStatus { todos, live, odds, finished, upcoming }

class FlashScoreHomeScreen extends StatefulWidget {
  final String backendBaseUrl;
  const FlashScoreHomeScreen(
      {super.key, this.backendBaseUrl = BackendConfig.baseRoot});

  @override
  State<FlashScoreHomeScreen> createState() => _FlashScoreHomeScreenState();
}

class _FlashScoreHomeScreenState extends State<FlashScoreHomeScreen> {
  static const String _favKey = 'flashscore.favoritos.v1';
  static const Color _bg = Color(0xff0d1821);

  String _esporte = _Esportes.futebol;
  _FiltroStatus _filtro = _FiltroStatus.todos;
  String? _ligaFiltro;
  String _busca = '';
  List<dynamic> _partidas = <dynamic>[];
  bool _carregando = true;
  String? _erro;
  Timer? _pollingLive;
  Set<String> _favoritos = <String>{};
  final Random _rnd = Random();

  // IA sinais
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _sinais = <Map<String, dynamic>>[];
  Map<String, String> _sinalPorFixture = <String, String>{};
  Map<String, int> _confPorFixture = <String, int>{};
  bool _carregandoSinais = true;
  String _fonteSinais = 'Heurística';

  @override
  void initState() {
    super.initState();
    _carregarFavoritos();
    _buscarPartidas();
    _buscarSinais();
    _iniciarPollingGlobal();
  }

  @override
  void dispose() {
    _pollingLive?.cancel();
    _pollingSinais?.cancel();
    super.dispose();
  }

  Timer? _pollingSinais;

  void _iniciarPollingGlobal() {
    _pollingSinais = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) {
        _buscarSinais(usarGemini: false);
        if (_filtro != _FiltroStatus.finished) {
          _buscarPartidas(silent: true);
        }
      }
    });
  }

  Future<void> _buscarSinais({bool usarGemini = false}) async {
    setState(() => _carregandoSinais = true);
    try {
      final Map<String, dynamic> res = await _api.getIaSinais(
        usarGemini: usarGemini,
        apenasHojeLive: true,
      );
      if (!mounted) return;
      final List<Map<String, dynamic>> lista = List<Map<String, dynamic>>.from(
          (res['sinais'] as List<dynamic>?) ?? <dynamic>[]);
      final Map<String, String> porFixture = <String, String>{};
      final Map<String, int> confFixture = <String, int>{};
      for (final Map<String, dynamic> s in lista) {
        final String? fid = s['fixture_id']?.toString();
        if (fid == null || fid.isEmpty) {
          continue;
        }
        porFixture[fid] = (s['sinal'] as String?) ?? 'cuidado';
        final int? c = s['confianca'] as int?;
        if (c != null) confFixture[fid] = c;
      }
      setState(() {
        _sinais = lista;
        _sinalPorFixture = porFixture;
        _confPorFixture = confFixture;
        _carregandoSinais = false;
        _fonteSinais = (res['fonte'] as String?) ?? 'Heurística';
      });
    } catch (_) {
      if (mounted) setState(() => _carregandoSinais = false);
    }
  }

  void _abrirIaBottomSheet() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: const Color(0xff000000).withValues(alpha: 0.65),
      builder: (BuildContext c) => _IaSinaisSheet(
        sinais: _sinais,
        loading: _carregandoSinais,
        fonte: _fonteSinais,
        onRefreshGemini: () {
          Navigator.of(c).pop();
          _buscarSinais(usarGemini: true);
        },
        onRefreshHeur: () {
          Navigator.of(c).pop();
          _buscarSinais(usarGemini: false);
        },
      ),
    );
  }

  Future<void> _carregarFavoritos() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? raw = prefs.getStringList(_favKey);
      if (mounted && raw != null) {
        setState(() => _favoritos = raw.toSet());
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorito(String fixtureId) async {
    final Set<String> copia = Set<String>.from(_favoritos);
    if (copia.contains(fixtureId)) {
      copia.remove(fixtureId);
    } else {
      copia.add(fixtureId);
    }
    if (!mounted) return;
    setState(() => _favoritos = copia);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favKey, copia.toList());
    } catch (_) {}
  }

  String get _statusQuery {
    switch (_filtro) {
      case _FiltroStatus.live:
        return 'live';
      case _FiltroStatus.finished:
        return 'finished';
      case _FiltroStatus.upcoming:
        return 'upcoming';
      case _FiltroStatus.odds:
      case _FiltroStatus.todos:
        return 'all';
    }
  }

  Future<void> _buscarPartidas({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      final Uri url = Uri.parse('${widget.backendBaseUrl}/api/v1/matches')
          .replace(queryParameters: <String, String>{
        'status': _statusQuery,
        'sport': 'football',
      });
      final http.Response resp =
          await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final List<dynamic> list =
          (data['matches'] as List<dynamic>? ?? <dynamic>[]);
      final List<dynamic> filtrados = list.where((dynamic e) {
        if (_ligaFiltro != null && _ligaFiltro!.isNotEmpty) {
          final dynamic lg = (e as Map<String, dynamic>)['league'];
          if (lg is! Map<String, dynamic>) return false;
          final String? ln = lg['name'] as String?;
          if (ln == null) return false;
          if (_ligaFiltro == 'LaLiga' && ln.contains('La Liga')) {
            return true;
          }
          if (!ln.toLowerCase().contains(_ligaFiltro!.toLowerCase())) {
            return false;
          }
        }
        if (_busca.trim().isNotEmpty) {
          final Map<String, dynamic> m = e as Map<String, dynamic>;
          final dynamic t = m['teams'];
          final String hh = t is Map<String, dynamic>
              ? (t['home'] is Map<String, dynamic>
                  ? t['home']['name']?.toString() ?? ''
                  : '')
              : '';
          final String aa = t is Map<String, dynamic>
              ? (t['away'] is Map<String, dynamic>
                  ? t['away']['name']?.toString() ?? ''
                  : '')
              : '';
          final String txt = ('$hh $aa').toLowerCase();
          if (!txt.contains(_busca.trim().toLowerCase())) return false;
        }
        return true;
      }).toList(growable: false);
      if (mounted) {
        setState(() {
          _partidas = filtrados;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = e.toString();
          _partidas = _fallbackMock();
        });
      }
    }
  }

  List<dynamic> _fallbackMock() {
    final DateTime hoje = DateTime.now();
    final String dataIso =
        '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    final List<dynamic> out = <dynamic>[];
    final List<List<String>> confrontos = <List<String>>[
      <String>[
        'Palmeiras',
        'Fluminense',
        'Brasileirão Série A',
        '🇧🇷',
        'Brasil'
      ],
      <String>[
        'Flamengo',
        'Vasco da Gama',
        'Brasileirão Série A',
        '🇧🇷',
        'Brasil'
      ],
      <String>[
        'São Paulo',
        'Botafogo',
        'Brasileirão Série A',
        '🇧🇷',
        'Brasil'
      ],
      <String>[
        'Internacional',
        'Grêmio',
        'Brasileirão Série A',
        '🇧🇷',
        'Brasil'
      ],
      <String>[
        'Corinthians',
        'Santos',
        'Brasileirão Série A',
        '🇧🇷',
        'Brasil'
      ],
      <String>['Liverpool', 'Arsenal', 'Premier League', '🏴', 'England'],
      <String>['Manchester City', 'Chelsea', 'Premier League', '🏴', 'England'],
      <String>['Real Madrid', 'Barcelona', 'La Liga', '🇪🇸', 'Spain'],
      <String>['Atlético Madrid', 'Sevilla', 'La Liga', '🇪🇸', 'Spain'],
      <String>[
        'Bayern de Munique',
        'Dortmund',
        'Bundesliga',
        '🇩🇪',
        'Germany'
      ],
      <String>['Inter', 'Milan', 'Serie A', '🇮🇹', 'Italy'],
      <String>['PSG', 'Marseille', 'Ligue 1', '🇫🇷', 'France'],
      <String>[
        'Flamengo',
        'Palmeiras',
        'Copa Libertadores',
        '🌎',
        'South America'
      ],
      <String>[
        'Real Madrid',
        'Man. City',
        'UEFA Champions League',
        '🇪🇺',
        'Europe'
      ],
    ];
    final List<_FiltroStatus> statusRandom = <_FiltroStatus>[
      _FiltroStatus.live,
      _FiltroStatus.live,
      _FiltroStatus.upcoming,
      _FiltroStatus.upcoming,
      _FiltroStatus.finished,
      _FiltroStatus.upcoming,
      _FiltroStatus.live,
      _FiltroStatus.upcoming,
    ];
    for (int i = 0; i < confrontos.length; i++) {
      final List<String> c = confrontos[i];
      final String casa = c[0],
          fora = c[1],
          liga = c[2],
          flag = c[3],
          pais = c[4];
      final _FiltroStatus st = statusRandom[i % statusRandom.length];
      final Map<String, dynamic> fixture = <String, dynamic>{
        'id': 100000 + i,
        'date': dataIso,
        'time':
            '${(15 + (i * 2) % 9).toString().padLeft(2, '0')}:${(i * 15) % 60 == 0 ? '00' : ((i * 15) % 60).toString().padLeft(2, '0')}',
      };
      if (st == _FiltroStatus.live) {
        final int min = 15 + _rnd.nextInt(75);
        fixture['status_short'] = min <= 45 ? '1H' : '2H';
        fixture['elapsed'] = min;
        fixture['status_long'] = 'Em andamento';
      } else if (st == _FiltroStatus.finished) {
        fixture['status_short'] = 'FT';
        fixture['elapsed'] = 90;
        fixture['status_long'] = 'Encerrado';
      } else {
        fixture['status_short'] = 'NS';
        fixture['elapsed'] = 0;
        fixture['status_long'] = 'Não iniciado';
      }
      final int gc = (st == _FiltroStatus.upcoming)
          ? 0
          : _rnd.nextInt(st == _FiltroStatus.finished ? 5 : 4);
      final int ga = (st == _FiltroStatus.upcoming)
          ? 0
          : _rnd.nextInt(st == _FiltroStatus.finished ? 5 : 3);
      final double o1 = 1.3 + _rnd.nextDouble() * 3.2;
      final double ox = 2.7 + _rnd.nextDouble() * 1.8;
      final double o2 = 1.4 + _rnd.nextDouble() * 4.5;
      out.add(<String, dynamic>{
        'league': <String, dynamic>{
          'id': i + 1,
          'name': liga,
          'country': pais,
          'flag': flag,
          'has_standings': i % 3 != 2,
        },
        'fixture': fixture,
        'teams': <String, dynamic>{
          'home': <String, dynamic>{
            'id': 100 + i,
            'name': casa,
            'logo': 'https://media.api-sports.io/football/teams/${i % 1500}.png'
          },
          'away': <String, dynamic>{
            'id': 200 + i,
            'name': fora,
            'logo':
                'https://media.api-sports.io/football/teams/${(i + 11) % 1500}.png'
          },
        },
        'goals': <String, dynamic>{'home': gc, 'away': ga},
        'odds': <String, dynamic>{
          'home_win': o1.toStringAsFixed(2),
          'draw': ox.toStringAsFixed(2),
          'away_win': o2.toStringAsFixed(2),
        },
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _agruparPorLiga() {
    final Map<String, Map<String, dynamic>> grupos =
        <String, Map<String, dynamic>>{};
    for (final dynamic p in _partidas) {
      final Map<String, dynamic> m = p as Map<String, dynamic>;
      final Map<String, dynamic> lg = BackendConfig.safeLeagueMap(m['league']);
      final String nome = lg['name']?.toString() ?? 'Outros';
      final String chave = '${lg['country']?.toString() ?? ''}_$nome';
      final Map<String, dynamic> slot = grupos.putIfAbsent(
          chave,
          () => <String, dynamic>{
                'league': lg,
                'partidas': <Map<String, dynamic>>[],
              });
      (slot['partidas'] as List<dynamic>).add(m);
    }
    return grupos.values.toList(growable: false);
  }

  void _ligaOnTap(String? nomeChave) {
    if (!mounted) return;
    setState(() => _ligaFiltro = _ligaFiltro == nomeChave ? null : nomeChave);
    _buscarPartidas(silent: true);
  }

  void _mudarFiltro(_FiltroStatus f) {
    if (!mounted) return;
    setState(() => _filtro = f);
    _pollingLive?.cancel();
    _pollingLive = null;
    _buscarPartidas();
    _buscarSinais(usarGemini: false);
    switch (f) {
      case _FiltroStatus.live:
        _pollingLive = Timer.periodic(const Duration(seconds: 15), (_) {
          if (mounted) _buscarPartidas(silent: true);
        });
        break;
      case _FiltroStatus.todos:
      case _FiltroStatus.odds:
        _pollingLive = Timer.periodic(const Duration(seconds: 45), (_) {
          if (mounted) _buscarPartidas(silent: true);
        });
        break;
      case _FiltroStatus.upcoming:
        _pollingLive = Timer.periodic(const Duration(seconds: 60), (_) {
          if (mounted) _buscarPartidas(silent: true);
        });
        break;
      case _FiltroStatus.finished:
        _pollingLive = Timer.periodic(const Duration(seconds: 120), (_) {
          if (mounted) _buscarPartidas(silent: true);
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(
              busca: _busca,
              esporteAtivo: _esporte,
              qtdFavoritos: _favoritos.length,
              onBuscaChange: (String v) {
                if (!mounted) return;
                setState(() => _busca = v);
                Future<void>.microtask(() => _buscarPartidas(silent: true));
              },
              onEsporteTap: (String e) {
                if (!mounted) return;
                setState(() => _esporte = e);
                if (e != _Esportes.futebol) {
                  setState(() {
                    _partidas = <dynamic>[];
                    _carregando = false;
                    _erro = null;
                  });
                } else {
                  _buscarPartidas();
                }
              },
              onRefresh: () => _buscarPartidas(),
              onIaTap: () => _abrirIaBottomSheet(),
              iaQtdVerdes: _sinais
                  .where((Map<String, dynamic> s) => s['sinal'] == 'apostar')
                  .length,
              iaLoading: _carregandoSinais,
              fonteSinais: _fonteSinais,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SidebarLigas(
                      selecionado: _ligaFiltro,
                      onSelecionar: _ligaOnTap,
                      todasLabel: 'Todas as Ligas'),
                  Container(width: 1, color: Colors.white10),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _FiltrosPilula(
                            filtro: _filtro,
                            onMudar: _mudarFiltro,
                            totalAoVivo: _partidas.where((dynamic p) {
                              final Map<String, dynamic> fx =
                                  (p as Map<String, dynamic>)['fixture']
                                          as Map<String, dynamic>? ??
                                      <String, dynamic>{};
                              final String? ss = fx['status_short']?.toString();
                              return ss != null && ss != 'FT' && ss != 'NS';
                            }).length),
                        if (_erro != null && _partidas.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: <Widget>[
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.yellow),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      'Falha na API (${_erro ?? ''}), exibindo dados simulados.',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5))),
                            ]),
                          ),
                        Expanded(
                          child: _carregando
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: AppTheme.flashLiveRed),
                                )
                              : _CorpoLista(
                                  grupos: _agruparPorLiga(),
                                  favoritos: _favoritos,
                                  sinalPorFixture: _sinalPorFixture,
                                  confPorFixture: _confPorFixture,
                                  onFavoritoToggle: _toggleFavorito,
                                  mostrarApenasOdds:
                                      _filtro == _FiltroStatus.odds,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// COMPONENTES: IA Sinais Sheet
// =============================================================================

class _IaSinaisSheet extends StatelessWidget {
  final List<Map<String, dynamic>> sinais;
  final bool loading;
  final String fonte;
  final VoidCallback onRefreshGemini;
  final VoidCallback onRefreshHeur;
  const _IaSinaisSheet({
    required this.sinais,
    required this.loading,
    required this.fonte,
    required this.onRefreshGemini,
    required this.onRefreshHeur,
  });

  static Color sinalCor(String s) {
    switch (s) {
      case 'apostar':
        return const Color(0xff00e676);
      case 'nao_apostar':
        return const Color(0xffef5350);
      case 'cuidado':
      default:
        return const Color(0xffffc107);
    }
  }

  static String sinalNome(String s) {
    switch (s) {
      case 'apostar':
        return '✅ APOSTAR';
      case 'nao_apostar':
        return '❌ NÃO APOSTAR';
      case 'cuidado':
      default:
        return '⚠️ CUIDADO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final int totApostar = sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'apostar')
        .length;
    final int totCuidado = sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'cuidado')
        .length;
    final int totNao = sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'nao_apostar')
        .length;
    final double h = MediaQuery.of(context).size.height;
    return Container(
        height: h * 0.84,
        decoration: const BoxDecoration(
          color: Color(0xff0d1821),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(children: <Widget>[
              Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  )),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                const Icon(Icons.auto_awesome_rounded,
                    color: Color(0xffce93d8), size: 24),
                const SizedBox(width: 8),
                const Text('Sinais da IA Tiago',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const Spacer(),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xff1a2a37),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text('Fonte: $fonte',
                        style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                IconButton(
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white60, size: 20)),
              ]),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                _chipResumo('✅ Apostar', totApostar, const Color(0xff00e676)),
                const SizedBox(width: 8),
                _chipResumo('⚠️ Cuidado', totCuidado, const Color(0xffffc107)),
                const SizedBox(width: 8),
                _chipResumo('❌ Não', totNao, const Color(0xffef5350)),
              ]),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: onRefreshHeur,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Color(0xff00e676), width: 1),
                          foregroundColor: const Color(0xff00e676),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          backgroundColor:
                              const Color(0xff00e676).withValues(alpha: 0.07),
                        ),
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xff00e676))))
                            : const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Recalcular Heurística',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800)))),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton.icon(
                        onPressed: onRefreshGemini,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff9c27b0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon:
                            const Icon(Icons.psychology_alt_rounded, size: 18),
                        label: const Text('Consultar Gemini IA',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800)))),
              ]),
              const SizedBox(height: 12),
              Expanded(
                  child: loading
                      ? const Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                              SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xffce93d8)))),
                              SizedBox(height: 10),
                              Text('IA analisando partidas...',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ]))
                      : sinais.isEmpty
                          ? const Center(
                              child: Text('Sem partidas para análise.',
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)))
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 10),
                              itemCount: sinais.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (BuildContext ctx, int idx) {
                                final Map<String, dynamic> s = sinais[idx];
                                final String ss =
                                    (s['sinal'] as String?) ?? 'cuidado';
                                final Color cor = sinalCor(ss);
                                final int pct = (s['confianca'] as int?) ?? 50;
                                final Map<String, dynamic> liga =
                                    BackendConfig.safeLeagueMap(s['league']);
                                final Map<String, dynamic> teams =
                                    BackendConfig.safeMap(s['teams']);
                                final String home = (((teams['home'] is Map)
                                            ? (teams['home'] as Map)['name']
                                            : null)
                                        ?.toString()) ??
                                    (BackendConfig.safeString(s['home']).isEmpty
                                        ? 'Casa'
                                        : BackendConfig.safeString(s['home']));
                                final String away = (((teams['away'] is Map)
                                            ? (teams['away'] as Map)['name']
                                            : null)
                                        ?.toString()) ??
                                    (BackendConfig.safeString(s['away']).isEmpty
                                        ? 'Fora'
                                        : BackendConfig.safeString(s['away']));
                                final String flag =
                                    liga['flag']?.toString() ?? '';
                                final String ligaNome =
                                    liga['name']?.toString() ??
                                        BackendConfig.safeString(s['liga']);
                                final Map<String, dynamic> odd =
                                    BackendConfig.safeMap(s['odd_sugerida']);
                                final List<String> razoes = List<String>.from(
                                    s['razoes'] as List<dynamic>? ??
                                        <dynamic>[]);
                                final String tipoOdd =
                                    odd['tipo']?.toString() ?? '';
                                final double? valor = double.tryParse(
                                    odd['valor']?.toString() ?? '');
                                final String timeOdd =
                                    odd['time']?.toString() ?? '';

                                return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: const Color(0xff11232f),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: cor.withValues(alpha: 0.35),
                                            width: 1),
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                              color:
                                                  cor.withValues(alpha: 0.10),
                                              blurRadius: 10,
                                              spreadRadius: 0.5)
                                        ]),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Row(children: <Widget>[
                                            Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                    color: cor.withValues(
                                                        alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    border: Border.all(
                                                        color: cor.withValues(
                                                            alpha: 0.5),
                                                        width: 1)),
                                                child: Text(
                                                    '${sinalNome(ss)} · $pct%',
                                                    style: TextStyle(
                                                        color: cor,
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w900))),
                                            const Spacer(),
                                            Text('$flag $ligaNome',
                                                style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ]),
                                          const SizedBox(height: 8),
                                          Row(children: <Widget>[
                                            const Icon(Icons.home_rounded,
                                                color: Colors.white38,
                                                size: 14),
                                            const SizedBox(width: 4),
                                            Expanded(
                                                child: Text(home,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13.5,
                                                        fontWeight:
                                                            FontWeight.w800),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis)),
                                            const SizedBox(width: 10),
                                            const Text('×',
                                                style: TextStyle(
                                                    color: Colors.white30,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 12)),
                                            const SizedBox(width: 10),
                                            const Icon(
                                                Icons.flight_takeoff_rounded,
                                                color: Colors.white38,
                                                size: 14),
                                            const SizedBox(width: 4),
                                            Expanded(
                                                child: Text(away,
                                                    textAlign: TextAlign.right,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13.5,
                                                        fontWeight:
                                                            FontWeight.w800),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis)),
                                          ]),
                                          const SizedBox(height: 9),
                                          Container(
                                              height: 5,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Container(
                                                      width: (MediaQuery.of(ctx)
                                                              .size
                                                              .width *
                                                          0.80 *
                                                          (pct / 100)),
                                                      decoration: BoxDecoration(
                                                          color: cor,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                          boxShadow: <BoxShadow>[
                                                            BoxShadow(
                                                                color: cor
                                                                    .withValues(
                                                                        alpha:
                                                                            0.40),
                                                                blurRadius: 6,
                                                                spreadRadius:
                                                                    0.5)
                                                          ])))),
                                          const SizedBox(height: 9),
                                          Row(children: <Widget>[
                                            Icon(Icons.attach_money_rounded,
                                                color: cor, size: 16),
                                            const SizedBox(width: 4),
                                            Text(tipoOdd,
                                                style: TextStyle(
                                                    color: cor,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                            const SizedBox(width: 6),
                                            Text(
                                                valor != null
                                                    ? '@ ${valor.toStringAsFixed(2)}'
                                                    : '',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w900)),
                                            const Spacer(),
                                            if (timeOdd.isNotEmpty)
                                              Flexible(
                                                  child: Text('· $timeOdd',
                                                      style: const TextStyle(
                                                          color: Colors.white60,
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w700),
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis)),
                                          ]),
                                          const SizedBox(height: 6),
                                          if (razoes.isNotEmpty)
                                            ...razoes
                                                .map((String r) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 3),
                                                      child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: <Widget>[
                                                            Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top: 2),
                                                                child: Icon(
                                                                    Icons
                                                                        .info_outline_rounded,
                                                                    color: cor,
                                                                    size: 13)),
                                                            const SizedBox(
                                                                width: 5),
                                                            Expanded(
                                                                child: Text(r,
                                                                    style: TextStyle(
                                                                        color: Colors.white.withValues(
                                                                            alpha:
                                                                                0.78),
                                                                        fontSize:
                                                                            11.5,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w600,
                                                                        height:
                                                                            1.35)))
                                                          ]),
                                                    ))
                                                .toList(growable: false),
                                        ]));
                              }))
            ])));
  }

  Widget _chipResumo(String label, int qtd, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cor.withValues(alpha: 0.5), width: 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text('$label ',
            style: TextStyle(
                color: cor, fontSize: 11.5, fontWeight: FontWeight.w900)),
        Text('$qtd',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900)),
      ]));
}

// =============================================================================
// COMPONENTES
// =============================================================================

class _TopBar extends StatelessWidget {
  final String busca;
  final String esporteAtivo;
  final int qtdFavoritos;
  final ValueChanged<String> onBuscaChange;
  final ValueChanged<String> onEsporteTap;
  final VoidCallback onRefresh;
  final VoidCallback onIaTap;
  final int iaQtdVerdes;
  final bool iaLoading;
  final String fonteSinais;
  final bool showBackButton;
  const _TopBar({
    required this.busca,
    required this.esporteAtivo,
    required this.qtdFavoritos,
    required this.onBuscaChange,
    required this.onEsporteTap,
    required this.onRefresh,
    required this.onIaTap,
    required this.iaQtdVerdes,
    required this.iaLoading,
    required this.fonteSinais,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
        color: const Color(0xff0a141b),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Column(children: <Widget>[
          Row(children: <Widget>[
            if (showBackButton && Navigator.canPop(context)) ...<Widget>[
              IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white70, size: 22)),
              const SizedBox(width: 2),
            ],
            const Icon(Icons.sports_soccer_rounded,
                color: Color(0xff00e676), size: 26),
            const SizedBox(width: 8),
            const Text('FlashScore',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6)),
            const Spacer(),
            Badge(
                label: Text('$qtdFavoritos',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                isLabelVisible: qtdFavoritos > 0,
                alignment: Alignment.topRight,
                child: IconButton(
                    icon: const Icon(Icons.star_border_rounded,
                        color: Colors.white70, size: 22),
                    onPressed: () {})),
            Badge(
                label: Text('$iaQtdVerdes',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                isLabelVisible: !iaLoading && iaQtdVerdes > 0,
                alignment: Alignment.topRight,
                child: Stack(
                  alignment: Alignment.topRight,
                  children: <Widget>[
                    IconButton(
                        icon: iaLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xff9c27b0))))
                            : const Icon(Icons.auto_awesome_rounded,
                                color: Color(0xffce93d8), size: 22),
                        onPressed: onIaTap,
                        tooltip: 'Sinais da IA Tiago ($fonteSinais)'),
                  ],
                )),
            IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white70, size: 22),
                onPressed: onRefresh),
          ]),
          const SizedBox(height: 10),
          Container(
              height: 40,
              decoration: BoxDecoration(
                  color: const Color(0xff182835),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10, width: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: <Widget>[
                const Icon(Icons.search_rounded,
                    color: Colors.white38, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                      onChanged: onBuscaChange,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13.5),
                      cursorColor: Colors.white54,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Buscar time, liga ou país…',
                        hintStyle: TextStyle(color: Colors.white38),
                        contentPadding: EdgeInsets.symmetric(vertical: 9),
                        isDense: true,
                      )),
                ),
              ])),
          const SizedBox(height: 10),
          SizedBox(
              height: 38,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _Esportes.todos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext c, int i) {
                    final String name = _Esportes.todos[i];
                    final bool ativo = name == esporteAtivo;
                    return GestureDetector(
                      onTap: () => onEsporteTap(name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: ativo
                              ? Border.all(
                                  color: const Color(0xff00e676), width: 1.2)
                              : Border.all(color: Colors.white10, width: 0.6),
                          color: ativo
                              ? const Color(0xff00e676).withValues(alpha: 0.12)
                              : const Color(0xff182835),
                        ),
                        alignment: Alignment.center,
                        child: Text(name,
                            style: TextStyle(
                                color: ativo
                                    ? const Color(0xff00e676)
                                    : Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold)),
                      ),
                    );
                  })),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
        ]));
  }
}

class _SidebarLigas extends StatelessWidget {
  final String? selecionado;
  final ValueChanged<String?> onSelecionar;
  final String todasLabel;
  const _SidebarLigas(
      {required this.selecionado,
      required this.onSelecionar,
      required this.todasLabel});

  @override
  Widget build(BuildContext context) {
    final bool selTodas = selecionado == null;
    return Container(
        width: 240,
        color: const Color(0xff0b151c),
        child: ListView(
          children: <Widget>[
            _ligaTile(
                icon: Icons.tune_rounded,
                flag: '⚽',
                titulo: todasLabel,
                sub: 'Todas as competições',
                selecionado: selTodas,
                onTap: () => onSelecionar(null)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('LIGAS FAVORITAS',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800)),
            ),
            for (final _LigaFixada l in _kLigasFixadas)
              _ligaTile(
                  flag: l.flag,
                  titulo: l.nome,
                  sub: l.pais,
                  selecionado: (l.idChave ?? l.nome) == selecionado,
                  onTap: () => onSelecionar(l.idChave ?? l.nome)),
          ],
        ));
  }

  Widget _ligaTile(
      {required String flag,
      required String titulo,
      required String sub,
      required bool selecionado,
      required VoidCallback onTap,
      IconData? icon}) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            color: selecionado
                ? const Color(0xff00e676).withValues(alpha: 0.10)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                icon != null
                    ? Icon(icon,
                        size: 18,
                        color: selecionado
                            ? const Color(0xff00e676)
                            : Colors.white70)
                    : Text(flag, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(titulo,
                            style: TextStyle(
                                color: selecionado
                                    ? const Color(0xff00e676)
                                    : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(sub,
                            style: TextStyle(
                                color: selecionado
                                    ? const Color(0xff00e676)
                                        .withValues(alpha: 0.85)
                                    : Colors.white38,
                                fontSize: 11.5)),
                      ]),
                ),
              ],
            )));
  }
}

class _FiltrosPilula extends StatelessWidget {
  final _FiltroStatus filtro;
  final ValueChanged<_FiltroStatus> onMudar;
  final int totalAoVivo;
  const _FiltrosPilula(
      {required this.filtro, required this.onMudar, required this.totalAoVivo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _pilula('TODOS', _FiltroStatus.todos),
            const SizedBox(width: 8),
            _pilulaAoVivo('AO VIVO', _FiltroStatus.live, totalAoVivo),
            const SizedBox(width: 8),
            _pilula('ODDS', _FiltroStatus.odds),
            const SizedBox(width: 8),
            _pilula('ENCERRADOS', _FiltroStatus.finished),
            const SizedBox(width: 8),
            _pilula('PRÓXIMOS', _FiltroStatus.upcoming),
          ],
        ),
      ),
    );
  }

  Widget _pilula(String texto, _FiltroStatus st) {
    final bool ativo = filtro == st;
    return GestureDetector(
        onTap: () => onMudar(st),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
          decoration: BoxDecoration(
            color: ativo
                ? const Color(0xff00e676).withValues(alpha: 0.15)
                : const Color(0xff182835),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: ativo ? const Color(0xff00e676) : Colors.white10,
                width: ativo ? 1.2 : 0.6),
          ),
          child: Text(texto,
              style: TextStyle(
                  color: ativo ? const Color(0xff00e676) : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4)),
        ));
  }

  Widget _pilulaAoVivo(String texto, _FiltroStatus st, int qtd) {
    final bool ativo = filtro == st;
    return GestureDetector(
        onTap: () => onMudar(st),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
          decoration: BoxDecoration(
            color: ativo
                ? AppTheme.flashLiveRed.withValues(alpha: 0.18)
                : const Color(0xff182835),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: ativo ? AppTheme.flashLiveRed : Colors.white10,
                width: ativo ? 1.3 : 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.flashLiveRed,
                    shape: BoxShape.circle,
                    boxShadow: ativo
                        ? <BoxShadow>[
                            BoxShadow(
                                color: AppTheme.flashLiveRed
                                    .withValues(alpha: 0.7),
                                blurRadius: 6,
                                spreadRadius: 1),
                          ]
                        : null,
                  )),
              const SizedBox(width: 7),
              Text(texto,
                  style: TextStyle(
                      color: ativo ? AppTheme.flashLiveRed : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4)),
              if (qtd > 0) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: ativo
                        ? AppTheme.flashLiveRed
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$qtd',
                      style: TextStyle(
                          color: ativo ? Colors.white : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
        ));
  }
}

class _CorpoLista extends StatelessWidget {
  final List<Map<String, dynamic>> grupos;
  final Set<String> favoritos;
  final ValueChanged<String> onFavoritoToggle;
  final bool mostrarApenasOdds;
  final Map<String, String> sinalPorFixture;
  final Map<String, int> confPorFixture;
  const _CorpoLista({
    required this.grupos,
    required this.favoritos,
    required this.onFavoritoToggle,
    required this.mostrarApenasOdds,
    required this.sinalPorFixture,
    required this.confPorFixture,
  });

  @override
  Widget build(BuildContext context) {
    if (grupos.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const Icon(Icons.sports_soccer_outlined,
                    size: 52, color: Colors.white24),
                const SizedBox(height: 12),
                const Text('Nenhuma partida encontrada.',
                    style: TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Troque os filtros ou aguarde o início das rodadas.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12)),
              ])));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
      itemCount: grupos.length,
      itemBuilder: (BuildContext c, int i) {
        final Map<String, dynamic> g = grupos[i];
        final Map<String, dynamic> liga =
            BackendConfig.safeLeagueMap(g['league']);
        List<Map<String, dynamic>> partidas =
            (g['partidas'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
                <Map<String, dynamic>>[];
        if (mostrarApenasOdds) {
          partidas = partidas.where((Map<String, dynamic> p) {
            final Map<String, dynamic> odds =
                p['odds'] as Map<String, dynamic>? ?? <String, dynamic>{};
            final double? oh =
                double.tryParse(odds['home_win']?.toString() ?? '');
            final double? oa =
                double.tryParse(odds['away_win']?.toString() ?? '');
            final double? od = double.tryParse(odds['draw']?.toString() ?? '');
            return (oh != null && oh > 0) ||
                (oa != null && oa > 0) ||
                (od != null && od > 0);
          }).toList(growable: false);
        }
        if (partidas.isEmpty) return const SizedBox.shrink();
        return _GrupoLiga(
            liga: liga,
            partidas: partidas,
            favoritos: favoritos,
            sinalPorFixture: sinalPorFixture,
            confPorFixture: confPorFixture,
            onFavoritoToggle: onFavoritoToggle);
      },
    );
  }
}

class _GrupoLiga extends StatelessWidget {
  final Map<String, dynamic> liga;
  final List<Map<String, dynamic>> partidas;
  final Set<String> favoritos;
  final ValueChanged<String> onFavoritoToggle;
  final Map<String, String> sinalPorFixture;
  final Map<String, int> confPorFixture;
  const _GrupoLiga({
    required this.liga,
    required this.partidas,
    required this.favoritos,
    required this.onFavoritoToggle,
    required this.sinalPorFixture,
    required this.confPorFixture,
  });

  @override
  Widget build(BuildContext context) {
    final String nome = liga['name']?.toString() ?? 'Liga';
    final String pais = liga['country']?.toString() ?? '';
    final String flag = liga['flag']?.toString() ?? '🏆';
    final bool temTab = liga['has_standings'] == true;
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: const BoxDecoration(
                  color: Color(0xff10212c),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(10))),
              child: Row(
                children: <Widget>[
                  Text(flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('📍 $pais',
                      style: TextStyle(
                          color: AppTheme.flashLiveRed.withValues(alpha: 0.85),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(nome,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis)),
                  if (temTab)
                    TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const Size(0, 0),
                            foregroundColor: AppTheme.flashSub),
                        onPressed: () {},
                        icon: const Icon(Icons.table_chart_outlined, size: 14),
                        label: const Text('Classificação ao vivo',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: Color(0xff0d1821),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(10)),
                border: Border(
                    left: BorderSide(color: Colors.white10, width: 0.6),
                    right: BorderSide(color: Colors.white10, width: 0.6),
                    bottom: BorderSide(color: Colors.white10, width: 0.6)),
              ),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < partidas.length; i++) ...<Widget>[
                    if (i > 0)
                      const Divider(color: Colors.white10, height: 0.6),
                    _MatchItem(
                        partida: partidas[i],
                        favoritado: favoritos
                            .contains(partidas[i]['fixture']['id'].toString()),
                        sinal: sinalPorFixture[
                                partidas[i]['fixture']['id'].toString()] ??
                            'cuidado',
                        confianca: confPorFixture[
                            partidas[i]['fixture']['id'].toString()],
                        onFavoritoTap: () => onFavoritoToggle(
                            partidas[i]['fixture']['id'].toString())),
                  ],
                ],
              ),
            ),
          ],
        ));
  }
}

class _MatchItem extends StatelessWidget {
  final Map<String, dynamic> partida;
  final bool favoritado;
  final VoidCallback onFavoritoTap;
  final String sinal; // 'apostar' | 'cuidado' | 'nao_apostar'
  final int? confianca;
  const _MatchItem({
    required this.partida,
    required this.favoritado,
    required this.onFavoritoTap,
    this.sinal = 'cuidado',
    this.confianca,
  });

  static Color sinalColor(String s) {
    switch (s) {
      case 'apostar':
        return const Color(0xff00e676);
      case 'nao_apostar':
        return const Color(0xffef5350);
      case 'cuidado':
      default:
        return const Color(0xffffc107);
    }
  }

  static String sinalLabel(String s) {
    switch (s) {
      case 'apostar':
        return 'APOSTAR';
      case 'nao_apostar':
        return 'NÃO APOSTAR';
      case 'cuidado':
      default:
        return 'CUIDADO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> fx =
        partida['fixture'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> teams =
        partida['teams'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> h =
        teams['home'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> a =
        teams['away'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> goals =
        partida['goals'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> odds =
        partida['odds'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String ss = fx['status_short']?.toString() ?? 'NS';
    final int? elapsed = int.tryParse(fx['elapsed']?.toString() ?? '');
    final bool aoVivo = ss != 'FT' && ss != 'NS';
    final bool encerrado = ss == 'FT';
    final Color minutoColor = aoVivo ? AppTheme.flashLiveRed : Colors.white54;

    final Color sinalCor = sinalColor(sinal);
    final String sinalLegenda = sinalLabel(sinal);
    final int confPct = confianca ??
        (sinal == 'apostar'
            ? 70
            : sinal == 'nao_apostar'
                ? 80
                : 50);

    String minutoTxt;
    if (aoVivo) {
      minutoTxt = (ss == '1H' || ss == '2H' || ss == 'ET')
          ? '${elapsed ?? ''}\''
          : (ss == 'HT' ? 'HT' : 'LIVE');
    } else if (encerrado) {
      minutoTxt = 'FT';
    } else {
      minutoTxt = (fx['time'] as String?) ?? '--:--';
    }

    final String home = h['name']?.toString() ?? '';
    final String away = a['name']?.toString() ?? '';
    final String homeLogo = h['logo']?.toString() ?? '';
    final String awayLogo = a['logo']?.toString() ?? '';
    final int? gc = goals['home'] is int
        ? goals['home'] as int
        : int.tryParse(goals['home']?.toString() ?? '');
    final int? ga = goals['away'] is int
        ? goals['away'] as int
        : int.tryParse(goals['away']?.toString() ?? '');
    final String o1 = odds['home_win']?.toString() ?? '--';
    final String ox = odds['draw']?.toString() ?? '--';
    final String o2 = odds['away_win']?.toString() ?? '--';
    final bool temOdds = o1 != '--' && ox != '--' && o2 != '--';

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Row(
        children: <Widget>[
          IconButton(
              onPressed: onFavoritoTap,
              icon: Icon(
                  favoritado ? Icons.star_rounded : Icons.star_border_rounded,
                  color: favoritado
                      ? Colors.orangeAccent
                      : Colors.white.withValues(alpha: 0.45),
                  size: 20),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(2),
              visualDensity: VisualDensity.compact),
          const SizedBox(width: 6),
          SizedBox(
              width: 46,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(minutoTxt,
                      style: TextStyle(
                          color: minutoColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
                  const SizedBox(height: 3),
                  Row(children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: sinalCor,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: sinalCor.withValues(alpha: 0.35), width: 1),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                              color: sinalCor.withValues(alpha: 0.30),
                              blurRadius: 4,
                              spreadRadius: 0.5),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('$confPct%',
                          style: TextStyle(
                              color: sinalCor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ],
              )),
          const SizedBox(width: 6),
          Expanded(
              child: Column(
            children: <Widget>[
              _timeRow(homeLogo, home),
              const SizedBox(height: 6),
              _timeRow(awayLogo, away),
            ],
          )),
          const SizedBox(width: 6),
          SizedBox(
            width: 96,
            child: Column(
              children: <Widget>[
                _placar(gc, ga, aoVivo),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    if (aoVivo)
                      Icon(Icons.live_tv_rounded,
                          size: 14,
                          color: AppTheme.flashLiveRed.withValues(alpha: 0.85))
                    else
                      const SizedBox(width: 14),
                    Icon(Icons.equalizer_rounded,
                        size: 15,
                        color: Colors.white
                            .withValues(alpha: temOdds ? 0.6 : 0.25)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: temOdds
                            ? const Color(0xff1c2f3e)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: temOdds
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.white10,
                            width: 0.6),
                      ),
                      child: Text(
                          o1.isEmpty
                              ? o1
                              : o1.substring(
                                  0, (o1.length > 5) ? 5 : o1.length),
                          style: TextStyle(
                              color: temOdds
                                  ? const Color(0xff00e676)
                                  : Colors.white.withValues(alpha: 0.35),
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeRow(String logo, String name) {
    return Row(
      children: <Widget>[
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white10, width: 0.5)),
          child: logo.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                  logo,
                  width: 18,
                  height: 18,
                  errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer,
                      size: 12, color: Colors.white38),
                  fit: BoxFit.cover,
                ))
              : const Icon(Icons.sports_soccer,
                  size: 12, color: Colors.white38),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _placar(int? gH, int? gA, bool aoVivo) {
    if (gH == null && gA == null) {
      return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('-',
                style: TextStyle(
                    color: aoVivo ? AppTheme.flashLiveRed : Colors.white54,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
            const SizedBox(width: 10),
            Text('-',
                style: TextStyle(
                    color: aoVivo ? AppTheme.flashLiveRed : Colors.white54,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
          ]);
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      Text('${gH ?? '-'}',
          style: TextStyle(
              color: aoVivo ? AppTheme.flashLiveRed : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18)),
      const SizedBox(width: 8),
      Text(':',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontWeight: FontWeight.w900,
              fontSize: 16)),
      const SizedBox(width: 8),
      Text('${gA ?? '-'}',
          style: TextStyle(
              color: aoVivo ? AppTheme.flashLiveRed : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18)),
    ]);
  }
}
