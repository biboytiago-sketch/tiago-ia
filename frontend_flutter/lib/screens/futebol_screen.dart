import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../theme/app_theme.dart';

class FutebolScreen extends StatefulWidget {
  final String backendBaseUrl;
  const FutebolScreen({
    super.key,
    this.backendBaseUrl = BackendConfig.baseRoot,
  });

  @override
  State<FutebolScreen> createState() => _FutebolScreenState();
}

class _FutebolScreenState extends State<FutebolScreen>
    with SingleTickerProviderStateMixin {
  static const List<Map<String, dynamic>> _abas = <Map<String, dynamic>>[
    {
      'key': 'AO_VIVO',
      'label': 'Ao Vivo',
      'icone': Icons.live_tv,
      'cor': Color(0xFFFF3B30)
    },
    {
      'key': 'HOJE',
      'label': 'Hoje',
      'icone': Icons.today,
      'cor': Color(0xFF1FB453)
    },
    {
      'key': 'AMANHA',
      'label': 'Amanhã',
      'icone': Icons.calendar_today,
      'cor': Color(0xFFFFD600)
    },
    {
      'key': 'FDS',
      'label': 'Fim de Semana',
      'icone': Icons.date_range,
      'cor': Color(0xFF7A8C95)
    },
  ];

  late TabController _tab;
  int _abaAtual = 0;
  Timer? _timerPoll;
  Map<String, List<Map<String, dynamic>>> _cache =
      <String, List<Map<String, dynamic>>>{};
  Map<String, bool> _loading = <String, bool>{};
  Map<String, String> _erro = <String, String>{};
  Map<String, String> _origemPorAba = <String, String>{};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _abas.length, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging || _abaAtual == _tab.index) return;
      setState(() => _abaAtual = _tab.index);
      _carregarAba(_abaAtual);
    });
    _carregarAba(0);
    _timerPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_abaAtual == 0 && mounted) _carregarAba(0, silent: true);
    });
  }

  @override
  void dispose() {
    _timerPoll?.cancel();
    _tab.dispose();
    super.dispose();
  }

  String _rota(int idx) {
    switch (_abas[idx]['key']) {
      case 'AO_VIVO':
        return '/api/v3/sports/live';
      case 'HOJE':
        return '/api/v3/sports/hoje';
      case 'AMANHA':
        return '/api/v3/sports/amanha';
      case 'FDS':
        return '/api/v3/sports/fim-de-semana';
      default:
        return '/api/v3/sports/hoje';
    }
  }

  Future<void> _carregarAba(int idx, {bool silent = false}) async {
    final String key = _abas[idx]['key'] as String;
    if (!silent) setState(() => _loading[key] = true);
    _erro.remove(key);
    try {
      final Uri uri = Uri.parse('${widget.backendBaseUrl}${_rota(idx)}');
      final http.Response r =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final Map<String, dynamic> data =
          BackendConfig.safeMap(jsonDecode(r.body));
      final List<dynamic> lst = BackendConfig.safeList(data['jogos']);
      final List<Map<String, dynamic>> jogos = lst
          .map<Map<String, dynamic>>((dynamic e) => BackendConfig.safeMap(e))
          .toList(growable: false);
      final String? origem = data['origem_dados_geral']?.toString();
      setState(() {
        _cache[key] = jogos;
        if (origem != null) _origemPorAba[key] = origem;
      });
    } catch (e) {
      setState(() {
        _erro[key] = 'Falha: ${e.toString().split('\n').first}';
      });
    } finally {
      if (mounted) setState(() => _loading[key] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.flashBg,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.sports_soccer, color: AppTheme.yellow),
            SizedBox(width: 8),
            Text('IA do Tiago · Futebol'),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          dividerColor: AppTheme.flashLine,
          indicatorColor: AppTheme.neonGreen,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.flashSub,
          tabs: _abas.map((Map<String, dynamic> a) {
            return Tab(
              icon: Icon(a['icone'] as IconData,
                  size: 16, color: a['cor'] as Color),
              text: a['label'] as String,
            );
          }).toList(growable: false),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => _carregarAba(_abaAtual),
            icon: const Icon(Icons.refresh, color: AppTheme.neonGreen),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: List<Widget>.generate(_abas.length, (int i) => _buildAba(i)),
      ),
    );
  }

  Widget _buildAba(int idx) {
    final String key = _abas[idx]['key'];
    final bool loading = _loading[key] ?? false;
    final String? err = _erro[key];
    final List<Map<String, dynamic>> jogos =
        _cache[key] ?? <Map<String, dynamic>>[];

    if (loading && jogos.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.neonGreen));
    }
    if (err != null && jogos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.red),
              const SizedBox(height: 12),
              Text(err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _carregarAba(idx),
                child: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (jogos.isEmpty) {
      return const Center(
        child: Text('Sem jogos disponíveis nesta aba.',
            style: TextStyle(color: AppTheme.flashSub)),
      );
    }

    final String origem = _origemPorAba[key] ?? 'RAPIDAPI_REAL';
    final bool origemReal = origem == 'RAPIDAPI_REAL';

    return RefreshIndicator(
      color: AppTheme.neonGreen,
      backgroundColor: AppTheme.flashCard,
      onRefresh: () => _carregarAba(idx),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        itemCount: jogos.length + (origemReal ? 0 : 1),
        itemBuilder: (BuildContext ctx, int i) {
          if (!origemReal && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AvisoOrigemDados(origem: origem),
            );
          }
          final int jIdx = origemReal ? i : i - 1;
          return Padding(
            padding:
                jIdx == 0 ? EdgeInsets.zero : const EdgeInsets.only(top: 10),
            child: _CardJogo(jogo: jogos[jIdx]),
          );
        },
      ),
    );
  }
}

class _AvisoOrigemDados extends StatelessWidget {
  final String origem;
  const _AvisoOrigemDados({required this.origem});

  @override
  Widget build(BuildContext context) {
    final bool oficial =
        origem == 'RAPIDAPI_REAL' || origem == 'IA_DO_TIAGO_OFICIAL';
    final bool misto = origem == 'MISTO_RAPIDAPI_MAIS_FALLBACK' ||
        origem == 'IA_DO_TIAGO_REAL_MISTO';
    final bool vazio = origem == 'FALLBACK_VAZIO' || origem == 'SEM_JOGOS_HOJE';

    final Color cor = oficial
        ? const Color(0xFF1FB453)
        : misto
            ? const Color(0xFFFF9800)
            : vazio
                ? const Color(0xFFFFB300)
                : const Color(0xFF1FB453);
    final String title = oficial
        ? (origem == 'RAPIDAPI_REAL'
            ? '✅ Dados Oficiais · API-Football Ao Vivo'
            : '🤖 IA do Tiago · Jogos Oficiais do Dia')
        : misto
            ? '⚠️ Dados Mistos (API + IA)'
            : vazio
                ? '⏳ Sem jogos agendados para este dia'
                : '🤖 IA do Tiago · Jogos Oficiais do Dia';
    final String subtitle = oficial
        ? (origem == 'RAPIDAPI_REAL'
            ? 'Times, placar e odds 100% atualizados em tempo real.'
            : 'Times e ligas atualizados temporada 25/26 · análise de odds, mercados, probabilidades e sinais gerados pela IA do Tiago.')
        : misto
            ? 'Algumas partidas são reais (API) e outras foram complementadas pela IA. Confira odds e estatísticas antes de apostar.'
            : vazio
                ? 'Nenhuma partida foi programada para hoje na base. Volte mais tarde ou tente outra data.'
                : 'Times e ligas atualizados temporada 25/26 · análise de odds, mercados, probabilidades e sinais gerados pela IA do Tiago.';
    final IconData icone = oficial
        ? (origem == 'RAPIDAPI_REAL' ? Icons.verified : Icons.auto_awesome)
        : misto
            ? Icons.warning_amber
            : vazio
                ? Icons.event_busy
                : Icons.auto_awesome;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.13),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: cor, width: 1.3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, color: cor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: TextStyle(
                        color: cor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.flashSub, fontSize: 11, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardJogo extends StatelessWidget {
  final Map<String, dynamic> jogo;
  const _CardJogo({required this.jogo});

  String _d(Object? o, [String fallback = '—']) =>
      o?.toString().isNotEmpty == true ? o.toString() : fallback;

  String _corrigir(String? s) {
    if (s == null) return '—';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final bool live =
        BackendConfig.safeString(jogo['status_flag'] ?? jogo['status']) ==
            'EM_ANDAMENTO';
    final Map<String, dynamic> odds = BackendConfig.safeMap(jogo['odds_1x2']);
    final Map<String, dynamic> probs =
        BackendConfig.safeMap(jogo['probabilidades_1x2_pct']);
    final Map<String, dynamic> merc =
        BackendConfig.safeMap(jogo['previsao_mercados']);
    final Map<String, dynamic> esc = BackendConfig.safeMap(merc['escanteios']);
    final Map<String, dynamic> gols = BackendConfig.safeMap(merc['gols']);
    final Map<String, dynamic> venc = BackendConfig.safeMap(merc['vencedor']);
    final Map<String, dynamic> chut =
        BackendConfig.safeMap(merc['chutes_a_gol']);
    final Map<String, dynamic> stats =
        BackendConfig.safeMap(jogo['estatisticas_live']);
    final List<dynamic> alertas =
        BackendConfig.safeList(jogo['desfalques_alertas']);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.flashCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.flashLine, width: 0.9),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: live
                      ? AppTheme.flashLiveRed.withOpacity(0.12)
                      : AppTheme.flashLine,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (live)
                      Container(
                        margin: const EdgeInsets.only(right: 5),
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.flashLiveRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      live
                          ? '${_d(jogo['status_curto'])} ${jogo['tempo_decorrido'] ?? ''}\''
                              .trim()
                          : '📅 ${_d(jogo['status_flag'], 'FUTURO')}',
                      style: TextStyle(
                        color: live ? AppTheme.flashLiveRed : AppTheme.flashSub,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  BackendConfig.safeString(jogo['liga'], '—'),
                  style: const TextStyle(
                      color: AppTheme.flashSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (jogo['horario_br'] != null && !live)
                Text(
                  _d(jogo['horario_br']),
                  style: const TextStyle(
                      color: AppTheme.yellow, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      BackendConfig.safeString(jogo['time_casa'], '—'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      BackendConfig.safeString(jogo['time_fora'], '—'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: <Widget>[
                    Text(
                      _d(jogo['placar'], live ? '0 x 0' : ''),
                      style: TextStyle(
                        color: live ? AppTheme.flashLiveRed : Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (venc['recomendacao'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.neonGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '🎯 ${_d(venc['recomendacao'])}',
                            style: const TextStyle(
                                color: AppTheme.neonGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Casa ${_d(odds['home'], '0.00')} (${_d(probs['casa_pct'], '0')}%)',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Fora ${_d(odds['away'], '0.00')} (${_d(probs['fora_pct'], '0')}%)',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _chipMercado(
                label: '🥅 ${_d(gols['recomendacao'])}',
                sub:
                    'O/U 1.5: ${_d(gols['over_1.5_prob_pct'])}% · 2.5: ${_d(gols['over_2.5_prob_pct'])}%',
                cor: AppTheme.neonGreen,
              ),
              _chipMercado(
                label: '⚽ ${_d(esc['over_linha_85pct'])}',
                sub:
                    'Cantos: ${_d(esc['total_ate_agora'])} agora · + Cantos: ${_d(esc['prob_over_next_pct'])}%',
                cor: const Color(0xFF3DB2FF),
              ),
              _chipMercado(
                label: '👟 ${_d(chut['recomendacao'])}',
                sub:
                    'Total Chutes AG: ${_d(chut['total_ate_agora'])} · Prob: ${_d(chut['over_prob_pct'])}%',
                cor: const Color(0xFFFF9F43),
              ),
              _chipMercado(
                label: 'X  Empate ${_d(odds['draw'], '0.00')}',
                sub: 'Prob: ${_d(probs['empate_pct'], '0')}%',
                cor: AppTheme.yellow,
              ),
            ],
          ),
          if (live && stats.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.flashBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.flashLine),
              ),
              child: Column(
                children: <Widget>[
                  _statRow('Escanteios', '${stats['escanteios_casa']}',
                      '${stats['escanteios_fora']}'),
                  _statRow('Chutes AG', '${stats['chutes_gol_casa']}',
                      '${stats['chutes_gol_fora']}'),
                  _statRow('Posse', '${stats['posse_casa'] ?? '0%'}',
                      '${stats['posse_fora'] ?? '0%'}'),
                  _statRow('Cartões A', '${stats['cartoes_amarelos_casa']}',
                      '${stats['cartoes_amarelos_fora']}'),
                ],
              ),
            ),
          ],
          if (alertas.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            ...alertas.take(2).map<Widget>(
                  (dynamic a) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.info_outline,
                              color: AppTheme.yellow, size: 14),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _d(a),
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11.5),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 2),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'IA do Tiago',
              style: TextStyle(
                  color: AppTheme.flashSub,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipMercado(
      {required String label, required String sub, required Color cor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  color: cor, fontWeight: FontWeight.w800, fontSize: 11)),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _statRow(String label, String casa, String fora) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(casa,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.flashSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          Expanded(
            child: Text(fora,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
