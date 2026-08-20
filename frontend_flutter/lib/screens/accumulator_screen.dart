import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AccumulatorScreen extends StatefulWidget {
  const AccumulatorScreen({super.key});

  @override
  State<AccumulatorScreen> createState() => _AccumulatorScreenState();
}

class _AccumulatorScreenState extends State<AccumulatorScreen> {
  final ApiService _api = ApiService();

  static const List<Map<String, dynamic>> _jogosBrasileirao =
      <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'bra_01',
      'home': 'Palmeiras',
      'away': 'São Paulo',
      'home_abr': 'PAL',
      'away_abr': 'SAO',
      'horario': '16:00',
      'estadio': 'Allianz Parque',
      'odds_resultado': <double>[1.55, 3.80, 5.20],
      'odds_btts': <double>[1.62, 2.25],
      'odds_canto': <double>[1.95, 1.85],
      'odds_cartoes': <double>[2.10, 1.72],
      'jogador_destaque': 'Endrick',
      'odds_jogador_chute': 1.80,
    },
    <String, dynamic>{
      'id': 'bra_02',
      'home': 'Flamengo',
      'away': 'Fluminense',
      'home_abr': 'FLA',
      'away_abr': 'FLU',
      'horario': '18:30',
      'estadio': 'Maracanã',
      'odds_resultado': <double>[1.90, 3.30, 3.95],
      'odds_btts': <double>[1.45, 2.60],
      'odds_canto': <double>[1.80, 2.00],
      'odds_cartoes': <double>[1.88, 1.92],
      'jogador_destaque': 'Pedro',
      'odds_jogador_chute': 1.95,
    },
    <String, dynamic>{
      'id': 'bra_03',
      'home': 'Botafogo',
      'away': 'Vasco',
      'home_abr': 'BOT',
      'away_abr': 'VAS',
      'horario': '20:00',
      'estadio': 'Nilton Santos',
      'odds_resultado': <double>[1.75, 3.60, 4.50],
      'odds_btts': <double>[1.55, 2.40],
      'odds_canto': <double>[1.90, 1.90],
      'odds_cartoes': <double>[1.65, 2.15],
      'jogador_destaque': 'Tiquinho Soares',
      'odds_jogador_chute': 2.05,
    },
    <String, dynamic>{
      'id': 'bra_04',
      'home': 'Grêmio',
      'away': 'Internacional',
      'home_abr': 'GRE',
      'away_abr': 'INT',
      'horario': '21:30',
      'estadio': 'Arena do Grêmio',
      'odds_resultado': <double>[2.15, 3.10, 3.40],
      'odds_btts': <double>[1.40, 2.75],
      'odds_canto': <double>[1.75, 2.05],
      'odds_cartoes': <double>[1.55, 2.35],
      'jogador_destaque': 'Luis Suárez',
      'odds_jogador_chute': 1.70,
    },
    <String, dynamic>{
      'id': 'bra_05',
      'home': 'Atlético Mineiro',
      'away': 'Cruzeiro',
      'home_abr': 'CAM',
      'away_abr': 'CRU',
      'horario': '19:00',
      'estadio': 'Mineirão',
      'odds_resultado': <double>[2.00, 3.20, 3.75],
      'odds_btts': <double>[1.50, 2.55],
      'odds_canto': <double>[1.88, 1.95],
      'odds_cartoes': <double>[1.50, 2.45],
      'jogador_destaque': 'Hulk',
      'odds_jogador_chute': 1.85,
    },
    <String, dynamic>{
      'id': 'bra_06',
      'home': 'Corinthians',
      'away': 'Santos',
      'home_abr': 'COR',
      'away_abr': 'SAN',
      'horario': '16:00',
      'estadio': 'Neo Química Arena',
      'odds_resultado': <double>[1.65, 3.50, 4.90],
      'odds_btts': <double>[1.70, 2.15],
      'odds_canto': <double>[1.92, 1.90],
      'odds_cartoes': <double>[1.78, 2.00],
      'jogador_destaque': 'Yuri Alberto',
      'odds_jogador_chute': 1.90,
    },
    <String, dynamic>{
      'id': 'bra_07',
      'home': 'Red Bull Bragantino',
      'away': 'Bahia',
      'home_abr': 'RBB',
      'away_abr': 'BAH',
      'horario': '18:00',
      'estadio': 'Nabi Abi Chedid',
      'odds_resultado': <double>[2.25, 3.15, 3.10],
      'odds_btts': <double>[1.60, 2.35],
      'odds_canto': <double>[1.82, 1.98],
      'odds_cartoes': <double>[1.90, 1.90],
      'jogador_destaque': 'Sasha',
      'odds_jogador_chute': 2.10,
    },
    <String, dynamic>{
      'id': 'bra_08',
      'home': 'Fortaleza',
      'away': 'Ceará',
      'home_abr': 'FOR',
      'away_abr': 'CEA',
      'horario': '21:00',
      'estadio': 'Arena Castelão',
      'odds_resultado': <double>[1.85, 3.40, 4.10],
      'odds_btts': <double>[1.48, 2.65],
      'odds_canto': <double>[1.78, 2.02],
      'odds_cartoes': <double>[1.52, 2.40],
      'jogador_destaque': 'Thiago Galhardo',
      'odds_jogador_chute': 1.98,
    },
  ];

  static const List<String> _mercados = <String>[
    'Resultado Final',
    'Escanteios',
    'Cartões',
    'Chutes a Gol / Jogador',
  ];

  final Map<String, bool> _selecionados = <String, bool>{};
  final Map<String, String> _mercadoPorJogo = <String, String>{};
  final Map<String, String> _escolhaPorJogo = <String, String>{};
  final Map<String, double> _oddPorSelecao = <String, double>{};

  Map<String, dynamic> _analiseCache = <String, dynamic>{};
  bool _analisando = false;

  @override
  void initState() {
    super.initState();
    for (Map<String, dynamic> j in _jogosBrasileirao) {
      _selecionados[j['id']] = false;
      _mercadoPorJogo[j['id']] = _mercados.first;
      _escolhaPorJogo[j['id']] = '';
      _oddPorSelecao[j['id']] = 0.0;
    }
  }

  List<String> get _idsSelecionados => _selecionados.entries
      .where((MapEntry<String, bool> e) => e.value)
      .map((MapEntry<String, bool> e) => e.key)
      .toList();

  double get _oddAcumulada {
    double odd = 1.0;
    for (String id in _idsSelecionados) {
      if (_analiseCache[id]?['recomendacao_acao'] ==
          'REMOVER ESTE JOGO DO BILHETE') {
        continue;
      }
      final double? o = _oddPorSelecao[id];
      if (o != null && o > 1.0) {
        odd *= o;
      }
    }
    return odd > 1.0 ? odd : 0.0;
  }

  int get _quantosManter {
    if (_analiseCache.isEmpty) return _idsSelecionados.length;
    return _idsSelecionados
        .where((String id) =>
            _analiseCache[id]?['recomendacao_acao'] !=
            'REMOVER ESTE JOGO DO BILHETE')
        .length;
  }

  void _atualizarOdd(String jogoId) {
    final Map<String, dynamic> jogo = _jogosBrasileirao.firstWhere(
        (Map<String, dynamic> e) => e['id'] == jogoId,
        orElse: () => const <String, dynamic>{});
    if (jogo.isEmpty) return;
    final String mercado = _mercadoPorJogo[jogoId] ?? '';
    final String escolha = _escolhaPorJogo[jogoId] ?? '';
    double odd = 0.0;
    switch (mercado) {
      case 'Resultado Final':
        final List<double> od = List<double>.from(
            (jogo['odds_resultado'] as List<dynamic>?) ?? <double>[]);
        if (od.length >= 3) {
          if (escolha == 'Casa') odd = od[0];
          if (escolha == 'Empate') odd = od[1];
          if (escolha == 'Fora') odd = od[2];
        }
        break;
      case 'Escanteios':
        final List<double> od = List<double>.from(
            (jogo['odds_canto'] as List<dynamic>?) ?? <double>[]);
        if (od.length >= 2) {
          if (escolha == 'Mais de 9.5') odd = od[0];
          if (escolha == 'Menos de 9.5') odd = od[1];
        }
        break;
      case 'Cartões':
        final List<double> od = List<double>.from(
            (jogo['odds_cartoes'] as List<dynamic>?) ?? <double>[]);
        if (od.length >= 2) {
          if (escolha == 'Mais de 6.5') odd = od[0];
          if (escolha == 'Menos de 6.5') odd = od[1];
        }
        break;
      case 'Chutes a Gol / Jogador':
        if (escolha == 'Sim' || escolha.isNotEmpty) {
          odd = (jogo['odds_jogador_chute'] as double?) ?? 0.0;
        }
        break;
    }
    _oddPorSelecao[jogoId] = odd;
  }

  List<Map<String, dynamic>> _opcoesPorMercado(
      String mercado, Map<String, dynamic> jogo) {
    switch (mercado) {
      case 'Resultado Final':
        final List<double> od = List<double>.from(
            (jogo['odds_resultado'] as List<dynamic>?) ?? <double>[0, 0, 0]);
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Casa',
            'label': '${jogo['home_abr']} (Casa)',
            'odd': od.length >= 3 ? od[0] : 0
          },
          <String, dynamic>{
            'chave': 'Empate',
            'label': 'Empate',
            'odd': od.length >= 3 ? od[1] : 0
          },
          <String, dynamic>{
            'chave': 'Fora',
            'label': '${jogo['away_abr']} (Fora)',
            'odd': od.length >= 3 ? od[2] : 0
          },
        ];
      case 'Escanteios':
        final List<double> od = List<double>.from(
            (jogo['odds_canto'] as List<dynamic>?) ?? <double>[0, 0]);
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Mais de 9.5',
            'label': 'Mais 9.5 cantos',
            'odd': od.isNotEmpty ? od[0] : 0
          },
          <String, dynamic>{
            'chave': 'Menos de 9.5',
            'label': 'Menos 9.5 cantos',
            'odd': od.length >= 2 ? od[1] : 0
          },
        ];
      case 'Cartões':
        final List<double> od = List<double>.from(
            (jogo['odds_cartoes'] as List<dynamic>?) ?? <double>[0, 0]);
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Mais de 6.5',
            'label': 'Mais 6.5 cartões',
            'odd': od.isNotEmpty ? od[0] : 0
          },
          <String, dynamic>{
            'chave': 'Menos de 6.5',
            'label': 'Menos 6.5 cartões',
            'odd': od.length >= 2 ? od[1] : 0
          },
        ];
      case 'Chutes a Gol / Jogador':
        final double od = (jogo['odds_jogador_chute'] as double?) ?? 0;
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Sim',
            'label': '${jogo['jogador_destaque']} tem 1+ chute no alvo',
            'odd': od
          },
        ];
      default:
        return <Map<String, dynamic>>[];
    }
  }

  Future<void> _analisarBilhete() async {
    if (_idsSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione pelo menos 1 jogo.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.flashLiveRed,
      ));
      return;
    }
    setState(() => _analisando = true);
    final List<Map<String, dynamic>> selecoes = <Map<String, dynamic>>[];
    for (String id in _idsSelecionados) {
      final Map<String, dynamic> j = _jogosBrasileirao
          .firstWhere((Map<String, dynamic> e) => e['id'] == id);
      selecoes.add(<String, dynamic>{
        'fixture_id': id,
        'home_name': j['home'],
        'away_name': j['away'],
        'liga': 'Brasileirão',
        'mercado': _mercadoPorJogo[id],
        'escolha': _escolhaPorJogo[id],
        'odd_apostada': _oddPorSelecao[id] ?? 1.0,
        'horario': j['horario'],
      });
    }
    try {
      final Map<String, dynamic> res = await _api.postAnalyzeAccumulator(
        selecoes: selecoes,
        userId: 'default',
      );
      final List<dynamic> selRes =
          (res['selecoes'] as List<dynamic>?) ?? <dynamic>[];
      final Map<String, dynamic> novoCache = <String, dynamic>{};
      for (dynamic s in selRes) {
        final Map<String, dynamic> sm = Map<String, dynamic>.from(s as Map);
        final String? fid = sm['fixture_id']?.toString();
        if (fid != null) novoCache[fid] = sm;
      }
      if (!mounted) return;
      setState(() {
        _analiseCache = novoCache;
        _analisando = false;
      });
      _mostrarModalAnalise(res);
    } catch (_) {
      if (mounted) setState(() => _analisando = false);
    }
  }

  void _mostrarModalAnalise(Map<String, dynamic> res) {
    showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnaliseModal(
        res: res,
        analiseCache: _analiseCache,
        onRemover: (String id) {
          setState(() {
            _analiseCache[id] = <String, dynamic>{
              ...Map<String, dynamic>.from(
                  _analiseCache[id] as Map? ?? const <String, dynamic>{}),
              'recomendacao_acao': 'REMOVER ESTE JOGO DO BILHETE',
            };
          });
        },
        onCopiar: _copiarEntrada,
        onWhatsapp: _enviarWhatsapp,
      ),
    );
  }

  String _textoBilhete() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('🎯 BILHETE MÚLTIPLA • BRASILEIRÃO');
    sb.writeln('==============================');
    double oddTotal = 1.0;
    int n = 0;
    for (String id in _idsSelecionados) {
      if (_analiseCache[id]?['recomendacao_acao'] ==
          'REMOVER ESTE JOGO DO BILHETE') {
        continue;
      }
      final Map<String, dynamic> j = _jogosBrasileirao
          .firstWhere((Map<String, dynamic> e) => e['id'] == id);
      final double? o = _oddPorSelecao[id];
      if (o == null || o <= 1.0) continue;
      n++;
      oddTotal *= o;
      final String status = _analiseCache[id]?['status']?.toString() ?? '';
      sb.writeln('\n$n. ${j['home']} x ${j['away']} (${j['horario']})');
      sb.writeln(
          '   ${_mercadoPorJogo[id]} → ${_escolhaPorJogo[id]} @ ${o.toStringAsFixed(2)}');
      if (status.isNotEmpty) {
        sb.writeln('   Verdict IA: $status');
      }
    }
    if (n == 0) return 'Nenhuma seleção válida.';
    sb.writeln('\n==============================');
    sb.writeln('Odd Total: ${oddTotal.toStringAsFixed(2)}');
    sb.writeln('Jogos MANTIDOS: $n');
    return sb.toString();
  }

  Future<void> _copiarEntrada() async {
    await Clipboard.setData(ClipboardData(text: _textoBilhete()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('📋 Bilhete copiado!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.neonGreen,
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _enviarWhatsapp() async {
    final String texto = Uri.encodeComponent(_textoBilhete());
    final Uri url = Uri.parse('https://wa.me/?text=$texto');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a141b),
      appBar: AppBar(
        backgroundColor: const Color(0xff0a141b),
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white70, size: 22),
            onPressed: () => Navigator.of(context).pop()),
        title: const Row(
          children: <Widget>[
            Icon(Icons.sports_soccer_rounded,
                color: Color(0xff00e676), size: 24),
            SizedBox(width: 10),
            Text('Aposta Múltipla • Brasileirão',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 180),
              child: ListView(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(children: <Widget>[
                      _chipR('${_idsSelecionados.length} selecionado(s)',
                          const Color(0xff00e676)),
                      const SizedBox(width: 7),
                      _chipR(
                          'Odd acumulada: ${_oddAcumulada > 1 ? _oddAcumulada.toStringAsFixed(2) : '--'}',
                          const Color(0xffffc107)),
                      const Spacer(),
                      if (_analiseCache.isNotEmpty)
                        _chipR('Mantidos: $_quantosManter',
                            const Color(0xff9c27b0)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  for (Map<String, dynamic> j in _jogosBrasileirao) ...<Widget>[
                    _JogoCard(
                      jogo: j,
                      selecionado: _selecionados[j['id']] ?? false,
                      mercado: _mercadoPorJogo[j['id']] ?? _mercados.first,
                      escolha: _escolhaPorJogo[j['id']] ?? '',
                      analise: _analiseCache[j['id']],
                      mercados: _mercados,
                      opcoesEscolha:
                          _opcoesPorMercado(_mercadoPorJogo[j['id']] ?? '', j),
                      onToggle: (bool v) {
                        setState(() {
                          _selecionados[j['id']] = v;
                          if (!v) {
                            _analiseCache.remove(j['id']);
                          }
                        });
                      },
                      onMercado: (String? m) {
                        if (m == null) return;
                        setState(() {
                          _mercadoPorJogo[j['id']] = m;
                          _escolhaPorJogo[j['id']] = '';
                          _atualizarOdd(j['id']);
                        });
                      },
                      onEscolha: (String? e) {
                        if (e == null) return;
                        setState(() {
                          _escolhaPorJogo[j['id']] = e;
                          _selecionados[j['id']] = true;
                          _atualizarOdd(j['id']);
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                decoration: BoxDecoration(
                  color: const Color(0xff0f1c25),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
                  border: Border.all(color: Colors.white12, width: 1),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 22,
                        spreadRadius: 4),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('Bilhete de Múltipla',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text(
                                  '${_idsSelecionados.length} jogos · Odd ${_oddAcumulada > 1 ? _oddAcumulada.toStringAsFixed(2) : '--'}',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                      const SizedBox(width: 10),
                      Row(children: <Widget>[
                        IconButton(
                            tooltip: 'Copiar',
                            onPressed: _idsSelecionados.isEmpty
                                ? null
                                : _copiarEntrada,
                            icon: const Icon(Icons.copy_rounded,
                                color: Color(0xff00e676), size: 22)),
                        IconButton(
                            tooltip: 'WhatsApp',
                            onPressed: _idsSelecionados.isEmpty
                                ? null
                                : _enviarWhatsapp,
                            icon: const Icon(Icons.chat_bubble_rounded,
                                color: Color(0xff25d366), size: 24)),
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _analisando ? null : _analisarBilhete,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff9c27b0),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        icon: _analisando
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white)))
                            : const Icon(Icons.psychology_alt_rounded,
                                size: 19),
                        label: Text(
                            _analisando
                                ? 'Analisando...'
                                : '🧠 Analisar Bilhete com IA',
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipR(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.45), width: 1)),
      child: Text(t,
          style: TextStyle(
              color: c, fontSize: 11.5, fontWeight: FontWeight.w900)));
}

class _JogoCard extends StatelessWidget {
  final Map<String, dynamic> jogo;
  final bool selecionado;
  final String mercado;
  final String escolha;
  final Map<String, dynamic>? analise;
  final List<String> mercados;
  final List<Map<String, dynamic>> opcoesEscolha;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String?> onMercado;
  final ValueChanged<String?> onEscolha;
  const _JogoCard({
    required this.jogo,
    required this.selecionado,
    required this.mercado,
    required this.escolha,
    required this.analise,
    required this.mercados,
    required this.opcoesEscolha,
    required this.onToggle,
    required this.onMercado,
    required this.onEscolha,
  });

  static Color _corStatus(String? s) {
    if (s == 'VALE A PENA ARRISCAR') {
      return const Color(0xff00e676);
    }
    if (s == 'NÃO VALE A PENA / MUITO ARRISCADO') {
      return const Color(0xffef5350);
    }
    return Colors.white24;
  }

  @override
  Widget build(BuildContext context) {
    final Color statusCor = _corStatus(analise?['status']?.toString());
    final bool removido = analise?['recomendacao_acao']?.toString() ==
        'REMOVER ESTE JOGO DO BILHETE';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xff121f29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: selecionado
                ? removido
                    ? const Color(0xffef5350).withValues(alpha: 0.6)
                    : const Color(0xff00e676).withValues(alpha: 0.55)
                : Colors.white10,
            width: 1.2),
        boxShadow: selecionado
            ? <BoxShadow>[
                BoxShadow(
                    color: (removido
                            ? const Color(0xffef5350)
                            : const Color(0xff00e676))
                        .withValues(alpha: 0.12),
                    blurRadius: 12,
                    spreadRadius: 0.5),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                  value: selecionado,
                  activeColor: const Color(0xff00e676),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  side: const BorderSide(color: Colors.white38, width: 1.2),
                  onChanged: (bool? v) => onToggle(v ?? false)),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Text('${jogo['home']}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 7),
                      Text('×',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontWeight: FontWeight.w900)),
                      const SizedBox(width: 7),
                      Expanded(
                          child: Text('${jogo['away']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800))),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('${jogo['horario']}',
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 3),
                    Text('🏟 ${jogo['estadio']}',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
            if (analise != null) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: statusCor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: statusCor.withValues(alpha: 0.5))),
                  child: Text(
                      removido
                          ? 'REMOVIDO'
                          : ((analise!['nivel_de_risco']?.toString() ?? '--')),
                      style: TextStyle(
                          color: statusCor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900))),
            ],
          ]),
          if (selecionado) ...<Widget>[
            const SizedBox(height: 10),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 9),
            Wrap(
                spacing: 7,
                runSpacing: 7,
                children: mercados
                    .map<Widget>((String m) =>
                        _mercadoChip(m == mercado, m, () => onMercado(m)))
                    .toList(growable: false)),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: opcoesEscolha
                  .map<Widget>((Map<String, dynamic> op) => ChoiceChip(
                        label: Text(
                            '${op['label']} @ ${(op['odd'] as double).toStringAsFixed(2)}',
                            style: TextStyle(
                                color: escolha == op['chave']
                                    ? Colors.black
                                    : Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800)),
                        selected: escolha == op['chave'],
                        selectedColor: const Color(0xff00e676),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(
                            color: escolha == op['chave']
                                ? const Color(0xff00e676)
                                : Colors.white24,
                            width: 1.1),
                        onSelected: (_) => onEscolha(op['chave']),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mercadoChip(bool sel, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
              color: sel
                  ? const Color(0xff9c27b0).withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: sel
                      ? const Color(0xff9c27b0).withValues(alpha: 0.65)
                      : Colors.white24,
                  width: 1.1)),
          child: Text(label,
              style: TextStyle(
                  color: sel ? const Color(0xffce93d8) : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ),
      );
}

class _AnaliseModal extends StatelessWidget {
  final Map<String, dynamic> res;
  final Map<String, dynamic> analiseCache;
  final ValueChanged<String> onRemover;
  final VoidCallback onCopiar;
  final VoidCallback onWhatsapp;
  const _AnaliseModal({
    required this.res,
    required this.analiseCache,
    required this.onRemover,
    required this.onCopiar,
    required this.onWhatsapp,
  });

  @override
  Widget build(BuildContext context) {
    final double sh = MediaQuery.of(context).size.height;
    final List<dynamic> sel =
        (res['selecoes'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> resumo = Map<String, dynamic>.from(
        (res['resumo_bilhete'] as Map<String, dynamic>?) ??
            const <String, dynamic>{});
    return Container(
      height: sh * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xff0a141b),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: <Widget>[
                Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(999))),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white60, size: 22)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xff9c27b0).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xff9c27b0).withValues(alpha: 0.5)),
                ),
                child: Row(children: <Widget>[
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color:
                              const Color(0xff9c27b0).withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xff9c27b0)
                                  .withValues(alpha: 0.5))),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Color(0xffce93d8), size: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                        const Text('Análise da IA • Verdetos',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(
                            'Total: ${resumo['total_selecoes']} · Manter: ${resumo['total_manter']} · Remover: ${resumo['total_remover']} · Odd: ${(resumo['odd_acumulada_manter'] as double? ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ])),
                  const SizedBox(width: 8),
                  Row(children: <Widget>[
                    IconButton(
                        onPressed: onCopiar,
                        tooltip: 'Copiar bilhete',
                        icon: const Icon(Icons.copy_rounded,
                            color: Color(0xff00e676), size: 22)),
                    IconButton(
                        onPressed: onWhatsapp,
                        tooltip: 'Enviar WhatsApp',
                        icon: const Icon(Icons.chat_bubble_rounded,
                            color: Color(0xff25d366), size: 24)),
                  ]),
                ]),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.white12, height: 1),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                children: <Widget>[
                  for (dynamic s in sel) ...<Widget>[
                    _BuildAnaliseItem(
                      item: Map<String, dynamic>.from(s as Map),
                      onRemover: () =>
                          onRemover(s['fixture_id']?.toString() ?? ''),
                    ),
                    const SizedBox(height: 11),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildAnaliseItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRemover;
  const _BuildAnaliseItem({required this.item, required this.onRemover});

  @override
  Widget build(BuildContext context) {
    final String status = item['status']?.toString() ?? '--';
    final bool vale = status == 'VALE A PENA ARRISCAR';
    final Color cor = vale ? const Color(0xff00e676) : const Color(0xffef5350);
    final String home = item['home_name']?.toString() ?? 'Casa';
    final String away = item['away_name']?.toString() ?? 'Fora';
    final String mercado = item['mercado']?.toString() ?? '--';
    final String escolha = item['escolha']?.toString() ?? '--';
    final dynamic odd = item['odd_apostada'];
    final String oddStr =
        odd is double ? odd.toStringAsFixed(2) : odd?.toString() ?? '--';
    final String risco = item['nivel_de_risco']?.toString() ?? '--';
    final String prob =
        (item['probabilidade_real_pct']?.toDouble() ?? 0.0).toStringAsFixed(1);
    final String oddJusta =
        (item['odd_justa']?.toDouble() ?? 0.0).toStringAsFixed(2);
    final List<dynamic> razoes =
        (item['motivo_detalhado'] as List<dynamic>?) ?? <dynamic>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xff111d27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.55), width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: cor.withValues(alpha: 0.10),
              blurRadius: 12,
              spreadRadius: 0.5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: cor.withValues(alpha: 0.5))),
                child: Text(status,
                    style: TextStyle(
                        color: cor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900))),
            const SizedBox(width: 7),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Risco: $risco',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800))),
            const Spacer(),
            Text('Prob: $prob%',
                style: TextStyle(
                    color: cor, fontSize: 11, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 9),
          Row(children: <Widget>[
            const Icon(Icons.home_rounded, size: 12, color: Colors.white60),
            const SizedBox(width: 4),
            Expanded(
                child: Text(home,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800))),
            Text(' × ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontWeight: FontWeight.w900)),
            Expanded(
                child: Text(away,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800))),
            const SizedBox(width: 4),
            const Icon(Icons.flight_takeoff_rounded,
                size: 12, color: Colors.white60),
          ]),
          const SizedBox(height: 9),
          Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cor.withValues(alpha: 0.35))),
              child: Row(children: <Widget>[
                Expanded(
                    child: Text('$mercado → $escolha',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Text('Odd $oddStr / Justa $oddJusta',
                    style: TextStyle(
                        color: cor, fontSize: 11, fontWeight: FontWeight.w900)),
              ])),
          if (razoes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 9),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 7),
            for (dynamic r in razoes)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                            padding: const EdgeInsets.only(top: 2.5),
                            child: Icon(Icons.info_outline_rounded,
                                color: cor, size: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(r.toString(),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w700))),
                      ])),
          ],
          const SizedBox(height: 9),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRemover,
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xffef5350),
                    side:
                        const BorderSide(color: Color(0xffef5350), width: 1.2),
                    backgroundColor:
                        const Color(0xffef5350).withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 17),
                label: const Text('Remover este jogo do bilhete',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              )),
        ],
      ),
    );
  }
}
