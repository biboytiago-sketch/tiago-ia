import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/backend_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'flashscore_home_screen.dart';
import 'accumulator_screen.dart';
import 'crypto_macro_screen.dart';
import 'futebol_screen.dart';
import 'crypto_screen.dart';
import 'gerar_bilhete_ia_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ApiService _api = ApiService();
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  List<Map<String, dynamic>> _sinais = <Map<String, dynamic>>[];
  bool _sinaisLoading = true;
  Timer? _timerSinais;
  Set<String> _idsNotificados = <String>{};

  Map<String, dynamic>? _statusFontes;
  bool _statusFontesCarregando = true;
  Timer? _timerStatusFontes;

  @override
  void initState() {
    super.initState();
    _carregarSinais();
    _carregarStatusFontes();
    _timerSinais = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _carregarSinais(silent: true);
    });
    _timerStatusFontes = Timer.periodic(const Duration(seconds: 90), (_) {
      if (mounted) _carregarStatusFontes(silent: true);
    });
  }

  @override
  void dispose() {
    _timerSinais?.cancel();
    _timerStatusFontes?.cancel();
    super.dispose();
  }

  Future<void> _notificarOportunidade(
      {String titulo = '🎯 Entrada de Alto Valor',
      String corpo = 'IA detectou uma oportunidade VERDE.',
      int id = 0}) async {
    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'tiago_ia_alertas',
      'Alertas de Entradas IA',
      channelDescription:
          'Notificações sonoras quando a IA acha entradas verdes.',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const NotificationDetails details = NotificationDetails(android: android);
    try {
      await _notif.show(id, titulo, corpo, details);
    } catch (_) {}
  }

  void _abrirAccumulator() {
    Navigator.of(context).push(MaterialPageRoute<dynamic>(
      builder: (_) => const AccumulatorScreen(),
    ));
  }

  void _abrirCrypto() {
    Navigator.of(context).push(MaterialPageRoute<dynamic>(
      builder: (_) => const CryptoMacroScreen(),
    ));
  }

  void _abrirFutebolV3() {
    Navigator.of(context).push(MaterialPageRoute<dynamic>(
      builder: (_) => const FutebolScreen(),
    ));
  }

  void _abrirCryptoV2() {
    Navigator.of(context).push(MaterialPageRoute<dynamic>(
      builder: (_) => const CryptoScreen(),
    ));
  }

  void _abrirGeradorIABilhetes() {
    Navigator.of(context).push(MaterialPageRoute<dynamic>(
      builder: (_) => const GerarBilheteIAScreen(),
    ));
  }

  Future<void> _carregarStatusFontes({bool silent = false}) async {
    if (!silent && mounted) setState(() => _statusFontesCarregando = true);
    try {
      final bool probe = !silent;
      final Map<String, dynamic> res =
          await ApiService.getSportsApiStatus(probe: probe);
      if (mounted) {
        setState(() {
          _statusFontes = res;
          _statusFontesCarregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statusFontesCarregando = false);
    }
  }

  // ── STEP 1 · WIDGET: API STATUS BADGE ─────────────────────────
  Widget _buildApiStatusBadge() {
    final Map<String, dynamic>? st = _statusFontes;
    final bool loading = _statusFontesCarregando && st == null;

    int online = 0;
    int total = 6;
    int chavesOk = 0;
    String statusGeral = 'CARREGANDO';
    List<Map<String, dynamic>> fontesDetalhe = <Map<String, dynamic>>[];

    if (st != null) {
      online = BackendConfig.safeInt(st['fontes_online'], 0);
      total = BackendConfig.safeInt(st['total_fontes'], 6);
      chavesOk = BackendConfig.safeInt(st['fontes_chave_ok'], 0);
      statusGeral = (st['status_geral'] as String?) ?? 'DESCONHECIDO';
      final List<dynamic> fd = BackendConfig.safeList(st['fontes']);
      fontesDetalhe = fd
          .map((dynamic e) => BackendConfig.safeMap(e))
          .toList(growable: false);
    }

    Color badgeBg;
    Color badgeCorBorda;
    Color pontoCor;
    String rotulo;
    String subRotulo;

    if (loading) {
      badgeBg = const Color(0xff1a2332);
      badgeCorBorda = Colors.grey.withValues(alpha: 0.30);
      pontoCor = Colors.grey;
      rotulo = 'Carregando fontes…';
      subRotulo = 'Ping em 6 fontes reais';
    } else if (statusGeral == 'EXCELENTE' || (online >= 5 && total >= 5)) {
      badgeBg = const Color(0xff0f3d2e);
      badgeCorBorda = const Color(0xff00e676);
      pontoCor = const Color(0xff00e676);
      rotulo = '🟢 Excelente · $online/$total fontes ativas';
      subRotulo = '$chavesOk chaves configuradas · Fallback IA sempre ativo';
    } else if (online >= 3 || statusGeral == 'BOM') {
      badgeBg = const Color(0xff3d320f);
      badgeCorBorda = const Color(0xffffca28);
      pontoCor = const Color(0xffffca28);
      rotulo = '🟡 Bom · $online/$total fontes ativas';
      subRotulo = '$chavesOk chaves · algumas fontes podem estar indisponíveis';
    } else if (online >= 1 || statusGeral == 'REDUZIDO') {
      badgeBg = const Color(0xff3d1f0f);
      badgeCorBorda = const Color(0xffff9100);
      pontoCor = const Color(0xffff9100);
      rotulo = '🟠 Reduzido · $online/$total fontes ativas';
      subRotulo = 'Dados parciais · confie mais no Fallback IA';
    } else {
      badgeBg = const Color(0xff3d1212);
      badgeCorBorda = const Color(0xffef5350);
      pontoCor = const Color(0xffef5350);
      rotulo = '🔴 Somente Fallback IA · 0/$total online';
      subRotulo = 'Todas as 6 fontes off · seed local por data está ativa';
    }

    Widget badgeContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: badgeCorBorda, width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: badgeCorBorda.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: pontoCor,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: pontoCor.withValues(alpha: 0.60), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(rotulo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2)),
                const SizedBox(height: 3),
                Text(subRotulo,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xff80deea),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xff80deea))),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Detalhe das fontes',
              icon: const Icon(Icons.info_outline_rounded,
                  color: Colors.white70, size: 20),
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text('Status $total fontes · $statusGeral',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const PopupMenuDivider(),
                ...fontesDetalhe.map((Map<String, dynamic> f) {
                  final String id = (f['id'] as String?) ?? '?';
                  final String label = (f['label'] as String?) ?? id;
                  final int ordem = BackendConfig.safeInt(f['ordem'], 99);
                  final String camada = (f['camada'] as String?) ?? '?';
                  final bool chaveCfg = f['chave_configurada'] == true;
                  final dynamic probe = f['probe_online'];
                  final bool onlineF =
                      probe == true || probe == 'EMPTY' || probe == 'MOCK';
                  final String lat =
                      (f['latencia_ms'] == null || f['latencia_ms'] is String)
                          ? (f['latencia_ms']?.toString() ?? '-')
                          : '${f['latencia_ms']} ms';
                  final String err = (f['ultimo_erro'] as String?) ?? '';
                  final int qtd =
                      BackendConfig.safeInt(f['quantidade_jogos_recente'], 0);
                  final Color ponto = onlineF
                      ? (chaveCfg
                          ? const Color(0xff00e676)
                          : const Color(0xffffca28))
                      : const Color(0xffef5350);
                  return PopupMenuItem<String>(
                    enabled: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                  color: ponto, shape: BoxShape.circle)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('$ordem. $label',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                    '· $camada · Chave: ${chaveCfg ? '✅' : '❌'} · Online: ${onlineF ? 'SIM' : 'NÃO'}\n'
                                    '· Latência: $lat · Jogos recentes: $qtd'
                                    '${err.isNotEmpty ? '\n· Erro: $err' : ''}',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.65),
                                        fontSize: 11,
                                        height: 1.35)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                      'Fallback IA: Sempre ativo 🤖\n'
                      'Atualização automática a cada ~90s\n'
                      'Toque para recarregar agora.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 11,
                          height: 1.35)),
                ),
              ],
            ),
          const SizedBox(width: 6),
          if (!loading)
            IconButton(
              tooltip: 'Recarregar status das fontes',
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.refresh_rounded,
                  color: Colors.white70, size: 18),
              onPressed: () => _carregarStatusFontes(),
            ),
        ],
      ),
    );

    if (loading || st == null) {
      return badgeContent;
    }
    return InkWell(
      onTap: () => _carregarStatusFontes(),
      borderRadius: BorderRadius.circular(14),
      child: badgeContent,
    );
  }

  Future<void> _carregarSinais({bool silent = false}) async {
    if (!silent && mounted) setState(() => _sinaisLoading = true);
    try {
      final Map<String, dynamic> res =
          await _api.getIaSinais(usarGemini: false, apenasHojeLive: true);
      if (!mounted) return;
      final List<dynamic> rawSinais = BackendConfig.safeList(res['sinais']);
      final List<Map<String, dynamic>> novos = <Map<String, dynamic>>[
        for (int i = 0; i < rawSinais.length; i++)
          BackendConfig.safeMap(rawSinais[i]),
      ];
      setState(() {
        _sinais = novos;
        _sinaisLoading = false;
      });
      final List<Map<String, dynamic>> verdesAltos = novos
          .where((Map<String, dynamic> s) =>
              s['sinal'] == 'apostar' &&
              BackendConfig.safeInt(s['confianca']) >= 72)
          .toList(growable: false);
      if (verdesAltos.isNotEmpty) {
        for (final Map<String, dynamic> s in verdesAltos) {
          final String fid = s['fixture_id']?.toString() ?? '';
          if (fid.isEmpty || _idsNotificados.contains(fid)) continue;
          _idsNotificados.add(fid);
          final Map<String, dynamic> teams = BackendConfig.safeMap(s['teams']);
          final Map<String, dynamic> tHome =
              BackendConfig.safeMap(teams['home']);
          final Map<String, dynamic> tAway =
              BackendConfig.safeMap(teams['away']);
          final String home = tHome['name']?.toString() ?? 'Casa';
          final String away = tAway['name']?.toString() ?? 'Fora';
          final int conf = BackendConfig.safeInt(s['confianca'], 70);
          _notificarOportunidade(
              id: fid.hashCode.abs(),
              corpo: '🎯 $home × $away · Confiança $conf%');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _sinaisLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0d1821),
      appBar: AppBar(
        backgroundColor: const Color(0xff0a141b),
        elevation: 0,
        title: Row(
          children: <Widget>[
            const Icon(Icons.auto_awesome_rounded,
                color: Color(0xff00e676), size: 26),
            const SizedBox(width: 10),
            const Text('Tiago IA • Painel',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
          ],
        ),
        actions: <Widget>[
          IconButton(
              tooltip: 'Deslogar',
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed('/login'),
              icon: const Icon(Icons.logout_rounded,
                  color: Colors.white70, size: 22)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: (MediaQuery.of(context).size.width < 700)
              ? ListView(
                  children: <Widget>[
                    _buildApiStatusBadge(),
                    const SizedBox(height: 14),
                    _buildCardIAResumo(),
                    const SizedBox(height: 14),
                    _cardModulo(
                        titulo: 'FlashScore • Jogos Ao Vivo',
                        subtitulo:
                            'Todas as ligas · Odds · Favoritos · Live 20s',
                        icon: Icons.sports_soccer_rounded,
                        corFundo:
                            const Color(0xff00e676).withValues(alpha: 0.10),
                        corBorda: const Color(0xff00e676),
                        corIcone: const Color(0xff00e676),
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute<dynamic>(
                            builder: (_) => const FlashScoreHomeScreen(),
                          ));
                        }),
                    const SizedBox(height: 14),
                    _cardModulo(
                        titulo: 'Chat com IA • Tiago GPT',
                        subtitulo:
                            'Gemini Streaming · Análise de jogos · Dicas',
                        icon: Icons.psychology_alt_rounded,
                        corFundo:
                            const Color(0xff9c27b0).withValues(alpha: 0.12),
                        corBorda: const Color(0xff9c27b0),
                        corIcone: const Color(0xffce93d8),
                        onTap: () => _abrirIaPageFull()),
                    const SizedBox(height: 14),
                    Row(children: <Widget>[
                      Expanded(
                          child: _cardModulo(
                              titulo: '⚽ Futebol V3 • Abas',
                              subtitulo:
                                  'Ao Vivo · Hoje · Amanhã · FDS · Stats',
                              icon: Icons.sports_football_rounded,
                              corFundo: const Color(0xff00bcd4)
                                  .withValues(alpha: 0.10),
                              corBorda: const Color(0xff00bcd4),
                              corIcone: const Color(0xff80deea),
                              onTap: () => _abrirFutebolV3())),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _cardModulo(
                              titulo: '📈 Crypto V2 • RSI/EMA',
                              subtitulo: 'Binance · BTC ETH SOL · Entry SL TP',
                              icon: Icons.query_stats_rounded,
                              corFundo: const Color(0xff26c6da)
                                  .withValues(alpha: 0.10),
                              corBorda: const Color(0xff26c6da),
                              corIcone: const Color(0xff84ffff),
                              onTap: () => _abrirCryptoV2())),
                    ]),
                    const SizedBox(height: 14),
                    _cardModulo(
                        titulo: '🤖 Gerador IA · Bilhetes Prontos',
                        subtitulo:
                            '3 perfis automáticos · Seguro / Balanceado / Agressivo · Validador em 1 clique · Escanteios/Gols/Chutes/Vencedor',
                        icon: Icons.auto_awesome_rounded,
                        corFundo:
                            const Color(0xffd500f9).withValues(alpha: 0.12),
                        corBorda: const Color(0xffd500f9),
                        corIcone: const Color(0xffea80fc),
                        onTap: () => _abrirGeradorIABilhetes()),
                    const SizedBox(height: 14),
                    Row(children: <Widget>[
                      Expanded(
                          child: _cardModulo(
                              titulo: 'Banca • Histórico + PDF',
                              subtitulo:
                                  'Stake · Risco · Gerenciamento · Relatórios',
                              icon: Icons.account_balance_wallet_rounded,
                              corFundo: const Color(0xffffc107)
                                  .withValues(alpha: 0.10),
                              corBorda: const Color(0xffffc107),
                              corIcone: const Color(0xffffd54f),
                              onTap: () => _abrirAccumulator())),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _cardModulo(
                              titulo: 'Crypto Sinais • Trading',
                              subtitulo:
                                  'Sinais BTC · ETH · Altcoins · Momentum',
                              icon: Icons.candlestick_chart_rounded,
                              corFundo: const Color(0xffef5350)
                                  .withValues(alpha: 0.10),
                              corBorda: const Color(0xffef5350),
                              corIcone: const Color(0xffef9a9a),
                              onTap: () => _abrirCrypto())),
                    ]),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 6,
                      child: ListView(
                        children: <Widget>[
                          _buildApiStatusBadge(),
                          const SizedBox(height: 14),
                          _buildCardIAResumo(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                        flex: 5,
                        child: ListView(
                          children: <Widget>[
                            _cardModulo(
                                titulo: 'FlashScore • Jogos Ao Vivo',
                                subtitulo:
                                    'Ligas · Odds · Favoritos · Live 20s',
                                icon: Icons.sports_soccer_rounded,
                                corFundo: const Color(0xff00e676)
                                    .withValues(alpha: 0.10),
                                corBorda: const Color(0xff00e676),
                                corIcone: const Color(0xff00e676),
                                onTap: () {
                                  Navigator.of(context)
                                      .push(MaterialPageRoute<dynamic>(
                                    builder: (_) =>
                                        const FlashScoreHomeScreen(),
                                  ));
                                }),
                            const SizedBox(height: 14),
                            _cardModulo(
                                titulo: 'Chat com IA • Tiago GPT',
                                subtitulo: 'Gemini Streaming · Análise · Dicas',
                                icon: Icons.psychology_alt_rounded,
                                corFundo: const Color(0xff9c27b0)
                                    .withValues(alpha: 0.12),
                                corBorda: const Color(0xff9c27b0),
                                corIcone: const Color(0xffce93d8),
                                onTap: () => _abrirIaPageFull()),
                            const SizedBox(height: 14),
                            Row(children: <Widget>[
                              Expanded(
                                  child: _cardModulo(
                                      titulo: '⚽ Futebol V3',
                                      subtitulo: '4 Abas · Stats Ao Vivo',
                                      icon: Icons.sports_football_rounded,
                                      corFundo: const Color(0xff00bcd4)
                                          .withValues(alpha: 0.10),
                                      corBorda: const Color(0xff00bcd4),
                                      corIcone: const Color(0xff80deea),
                                      onTap: () => _abrirFutebolV3())),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: _cardModulo(
                                      titulo: '📈 Crypto V2',
                                      subtitulo: 'RSI · EMA20/200 · R:R',
                                      icon: Icons.query_stats_rounded,
                                      corFundo: const Color(0xff26c6da)
                                          .withValues(alpha: 0.10),
                                      corBorda: const Color(0xff26c6da),
                                      corIcone: const Color(0xff84ffff),
                                      onTap: () => _abrirCryptoV2())),
                            ]),
                            const SizedBox(height: 14),
                            _cardModulo(
                                titulo: '🤖 Gerador IA · Bilhetes Prontos',
                                subtitulo:
                                    '3 Perfis · Escanteios/Gols/Chutes/Vencedor · Validador Integrado',
                                icon: Icons.auto_awesome_rounded,
                                corFundo: const Color(0xffd500f9)
                                    .withValues(alpha: 0.12),
                                corBorda: const Color(0xffd500f9),
                                corIcone: const Color(0xffea80fc),
                                onTap: () => _abrirGeradorIABilhetes()),
                            const SizedBox(height: 14),
                            Row(children: <Widget>[
                              Expanded(
                                  child: _cardModulo(
                                      titulo: 'Banca • Histórico',
                                      subtitulo: 'Stake · Risco · Relatórios',
                                      icon:
                                          Icons.account_balance_wallet_rounded,
                                      corFundo: const Color(0xffffc107)
                                          .withValues(alpha: 0.10),
                                      corBorda: const Color(0xffffc107),
                                      corIcone: const Color(0xffffd54f),
                                      onTap: () => _abrirAccumulator())),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: _cardModulo(
                                      titulo: 'Crypto • Trading',
                                      subtitulo: 'BTC · ETH · Altcoins',
                                      icon: Icons.candlestick_chart_rounded,
                                      corFundo: const Color(0xffef5350)
                                          .withValues(alpha: 0.10),
                                      corBorda: const Color(0xffef5350),
                                      corIcone: const Color(0xffef9a9a),
                                      onTap: () => _abrirCrypto())),
                            ]),
                          ],
                        )),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCardIAResumo() {
    final int totApostar = _sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'apostar')
        .length;
    final int totCuidado = _sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'cuidado')
        .length;
    final int totNao = _sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'nao_apostar')
        .length;
    final List<Map<String, dynamic>> topVerdes =
        List<Map<String, dynamic>>.from(
            _sinais.where((Map<String, dynamic> s) => s['sinal'] == 'apostar'));
    return Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xff121f29),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xff9c27b0).withValues(alpha: 0.45),
              width: 1.3),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: const Color(0xff9c27b0).withValues(alpha: 0.10),
                blurRadius: 18,
                spreadRadius: 1)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xffce93d8).withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xffce93d8).withValues(alpha: 0.5),
                          width: 1)),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Color(0xffce93d8), size: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('🔮 Tiago IA • Análise de Hoje',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(
                          _sinaisLoading
                              ? 'Carregando sinais...'
                              : '${_sinais.length} partidas analisadas · ${topVerdes.length} oportunidades verdes',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
              IconButton(
                  onPressed: _sinaisLoading ? null : () => _abrirIaPageFull(),
                  icon: const Icon(Icons.open_in_new_rounded,
                      color: Color(0xffce93d8), size: 21)),
            ]),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              _chipR('✅ $totApostar', 'Verde Apostar', const Color(0xff00e676)),
              const SizedBox(width: 8),
              _chipR('⚠️ $totCuidado', 'Cuidado', const Color(0xffffc107)),
              const SizedBox(width: 8),
              _chipR('❌ $totNao', 'Evitar', const Color(0xffef5350)),
              const Spacer(),
              if (_sinaisLoading)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xffce93d8))))
              else
                TextButton.icon(
                    onPressed: () => _carregarSinais(),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xff00e676)),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Recalcular',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
            if (_sinaisLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                    child: Text('Buscando melhores jogos de hoje...',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700))),
              )
            else if (topVerdes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                      const Icon(Icons.eco_outlined,
                          size: 32, color: Colors.white24),
                      const SizedBox(height: 8),
                      Text(
                          _sinais.isEmpty
                              ? 'Sem partidas. Tente novamente em breve.'
                              : 'Nenhum sinal VERDE seguro encontrado hoje.',
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ])),
              )
            else
              Column(
                children: <Widget>[
                  for (Map<String, dynamic> s
                      in topVerdes.take(4).toList(growable: false))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _IaSinalCardResumo(
                          sinal: s,
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute<dynamic>(
                              builder: (_) => const FlashScoreHomeScreen(),
                            ));
                          }),
                    ),
                  const SizedBox(height: 6),
                  Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                          onPressed: () => _abrirIaPageFull(),
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xffce93d8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact),
                          icon:
                              const Icon(Icons.arrow_forward_rounded, size: 16),
                          label: const Text(
                            'Ver todos os sinais e razões',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800),
                          ))),
                ],
              ),
          ],
        ));
  }

  Widget _chipR(String v, String subtitle, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.45), width: 1)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(v,
                style: TextStyle(
                    color: c, fontSize: 12.5, fontWeight: FontWeight.w900)),
            Text(subtitle,
                style: TextStyle(
                    color: c.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ]));

  void _abrirIaPageFull() {
    Navigator.of(context).push(MaterialPageRoute<dynamic>(
      builder: (_) => _IaSinaisPage(api: _api),
    ));
  }

  Widget _cardModulo(
      {required String titulo,
      required String subtitulo,
      required IconData icon,
      required Color corFundo,
      required Color corBorda,
      required Color corIcone,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: corFundo,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: corBorda.withValues(alpha: 0.75), width: 1.3),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: corBorda.withValues(alpha: 0.10),
                blurRadius: 16,
                spreadRadius: 1),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: corIcone.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: corIcone.withValues(alpha: 0.45), width: 1)),
                child: Icon(icon, color: corIcone, size: 34)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(titulo,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text(subtitulo,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Text('Abrir',
                          style: TextStyle(
                              color: corBorda,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          color: corBorda, size: 15),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _snackInexistente(BuildContext ctx, String nome) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(
          '🔜 $nome será integrado em breve. Use o FlashScore enquanto isso!',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700)),
      backgroundColor: AppTheme.flashLiveRed.withValues(alpha: 0.9),
      duration: const Duration(seconds: 3),
    ));
  }
}

class _IaSinalCardResumo extends StatelessWidget {
  final Map<String, dynamic> sinal;
  final VoidCallback? onTap;
  const _IaSinalCardResumo({required this.sinal, this.onTap});

  static Color sinalColor(String s) => switch (s) {
        'apostar' => const Color(0xff00e676),
        'nao_apostar' => const Color(0xffef5350),
        _ => const Color(0xffffc107),
      };
  static String sinalLabel(String s) => switch (s) {
        'apostar' => '✅ APOSTAR',
        'nao_apostar' => '❌ NÃO APOSTAR',
        _ => '⚠️ CUIDADO',
      };

  @override
  Widget build(BuildContext context) {
    final String s = (sinal['sinal'] as String?) ?? 'cuidado';
    final Color cor = sinalColor(s);
    final int conf = BackendConfig.safeInt(sinal['confianca'], 50);
    final Map<String, dynamic> teams = BackendConfig.safeMap(sinal['teams']);
    final Map<String, dynamic> tHome = BackendConfig.safeMap(teams['home']);
    final Map<String, dynamic> tAway = BackendConfig.safeMap(teams['away']);
    final String home = tHome['name']?.toString() ?? 'Casa';
    final String away = tAway['name']?.toString() ?? 'Fora';
    final Map<String, dynamic> odd =
        BackendConfig.safeMap(sinal['odd_sugerida']);
    final Map<String, dynamic> league = BackendConfig.safeMap(sinal['league']);
    final String ligaNome = league['name']?.toString() ?? '';
    final String paisFl = league['flag']?.toString() ?? '';
    final String oddV = odd['valor']?.toStringAsFixed(2) ?? '--';
    final String oddT = odd['tipo']?.toString() ?? 'HT/DC';
    final String oddTime = odd['time']?.toString() ?? '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: cor.withValues(alpha: 0.45), width: 1.1),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: cor.withValues(alpha: 0.09),
                    blurRadius: 12,
                    spreadRadius: 0.5),
              ]),
          child: Row(children: <Widget>[
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cor.withValues(alpha: 0.5))),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.sports_soccer_rounded, color: cor, size: 18),
                      const SizedBox(height: 1),
                      Text('$conf%',
                          style: TextStyle(
                              color: cor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900)),
                    ])),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Text('${sinalLabel(s)} · $conf%',
                          style: TextStyle(
                              color: cor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(width: 7),
                      if (paisFl.isNotEmpty)
                        Text(paisFl, style: const TextStyle(fontSize: 11)),
                      if (ligaNome.isNotEmpty)
                        Expanded(
                          child: Text(' $ligaNome',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: <Widget>[
                      Icon(Icons.home_rounded,
                          size: 12,
                          color: Colors.white.withValues(alpha: 0.65)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(home,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      Text('×',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w900)),
                      const SizedBox(width: 6),
                      Icon(Icons.flight_takeoff_rounded,
                          size: 12,
                          color: Colors.white.withValues(alpha: 0.65)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(away,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    Row(children: <Widget>[
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: cor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: cor.withValues(alpha: 0.4))),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.attach_money_rounded,
                                    color: cor, size: 13),
                                const SizedBox(width: 3),
                                Text(
                                    '$oddT $oddV${oddTime.isNotEmpty ? ' · $oddTime' : ''}',
                                    style: TextStyle(
                                        color: cor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900)),
                              ])),
                      const Spacer(),
                      Icon(Icons.arrow_forward_rounded,
                          color: cor.withValues(alpha: 0.8), size: 14),
                    ]),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _IaSinaisPage extends StatefulWidget {
  final ApiService api;
  const _IaSinaisPage({required this.api});

  @override
  State<_IaSinaisPage> createState() => _IaSinaisPageState();
}

class _IaSinaisPageState extends State<_IaSinaisPage> {
  List<Map<String, dynamic>> _sinais = <Map<String, dynamic>>[];
  bool _loading = true;
  String _fonte = 'Heurística';

  @override
  void initState() {
    super.initState();
    _buscar(usarGemini: false);
  }

  Future<void> _buscar({required bool usarGemini}) async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> res = await widget.api
          .getIaSinais(usarGemini: usarGemini, apenasHojeLive: true);
      if (!mounted) return;
      setState(() {
        final List<dynamic> raw = BackendConfig.safeList(res['sinais']);
        _sinais = <Map<String, dynamic>>[
          for (int i = 0; i < raw.length; i++) BackendConfig.safeMap(raw[i]),
        ];
        _fonte = (res['fonte'] as String?) ?? 'Heurística';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int totA = _sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'apostar')
        .length;
    final int totC = _sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'cuidado')
        .length;
    final int totN = _sinais
        .where((Map<String, dynamic> s) => s['sinal'] == 'nao_apostar')
        .length;
    return Scaffold(
      backgroundColor: const Color(0xff0a141b),
      appBar: AppBar(
        backgroundColor: const Color(0xff0a141b),
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white70, size: 22),
            onPressed: () => Navigator.of(context).pop()),
        title: Row(
          children: <Widget>[
            const Icon(Icons.auto_awesome_rounded,
                color: Color(0xffce93d8), size: 24),
            const SizedBox(width: 10),
            const Text('Sinais da IA Tiago',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xffce93d8).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: const Color(0xffce93d8).withValues(alpha: 0.4))),
                child: Text('Fonte: $_fonte',
                    style: const TextStyle(
                        color: Color(0xffce93d8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900))),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(children: <Widget>[
                _chip('✅ $totA Apostar', const Color(0xff00e676)),
                const SizedBox(width: 7),
                _chip('⚠️ $totC Cuidado', const Color(0xffffc107)),
                const SizedBox(width: 7),
                _chip('❌ $totN Não', const Color(0xffef5350)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed:
                          _loading ? null : () => _buscar(usarGemini: false),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xff00e676),
                          side: const BorderSide(
                              color: Color(0xff00e676), width: 1.3),
                          backgroundColor:
                              const Color(0xff00e676).withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text('⚡ Recalcular Heurística',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w900))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                      onPressed:
                          _loading ? null : () => _buscar(usarGemini: true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff9c27b0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 11),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      icon: const Icon(Icons.psychology_alt_rounded, size: 18),
                      label: const Text('🧠 Consultar Gemini IA',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w900))),
                ),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xffce93d8))),
                        SizedBox(height: 12),
                        Text('Analisando partidas...',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ))
                  : _sinais.isEmpty
                      ? const Center(
                          child: Text('Sem sinais no momento.',
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                          children: <Widget>[
                              for (Map<String, dynamic> s
                                  in _sinais) ...<Widget>[
                                _buildCard(s),
                                const SizedBox(height: 11),
                              ],
                            ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.4), width: 1)),
      child: Text(t,
          style: TextStyle(
              color: c, fontSize: 11.5, fontWeight: FontWeight.w900)));

  Widget _buildCard(Map<String, dynamic> s) {
    final String tipo = (s['sinal'] as String?) ?? 'cuidado';
    final Color cor = _IaSinalCardResumo.sinalColor(tipo);
    final String label = _IaSinalCardResumo.sinalLabel(tipo);
    final int conf = BackendConfig.safeInt(s['confianca'], 50);
    final Map<String, dynamic> teams = BackendConfig.safeMap(s['teams']);
    final Map<String, dynamic> tHome = BackendConfig.safeMap(teams['home']);
    final Map<String, dynamic> tAway = BackendConfig.safeMap(teams['away']);
    final String home = tHome['name']?.toString() ?? 'Casa';
    final String away = tAway['name']?.toString() ?? 'Fora';
    final Map<String, dynamic> league = BackendConfig.safeMap(s['league']);
    final String ligaNome = league['name']?.toString() ?? '';
    final String flag = league['flag']?.toString() ?? '';
    final Map<String, dynamic> odd = BackendConfig.safeMap(s['odd_sugerida']);
    final String oddV = odd['valor']?.toStringAsFixed(2) ?? '--';
    final String oddT = odd['tipo']?.toString() ?? 'DC';
    final String oddTime = odd['time']?.toString() ?? '';
    final List<dynamic> razoes = BackendConfig.safeList(s['razoes']);
    return Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
            color: const Color(0xff111d27),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cor.withValues(alpha: 0.55), width: 1.2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: cor.withValues(alpha: 0.10),
                  blurRadius: 14,
                  spreadRadius: 0.5),
            ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Text('$label · $conf%',
                  style: TextStyle(
                      color: cor, fontSize: 12.5, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              if (flag.isNotEmpty)
                Text(flag, style: const TextStyle(fontSize: 12)),
              if (ligaNome.isNotEmpty)
                Expanded(
                    child: Text(' $ligaNome',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 9),
            Row(children: <Widget>[
              const Icon(Icons.home_rounded, size: 13, color: Colors.white60),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(home,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800))),
              const SizedBox(width: 4),
              const Icon(Icons.flight_takeoff_rounded,
                  size: 13, color: Colors.white60),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(children: <Widget>[
                  Container(
                      height: 9,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(999),
                      )),
                  Container(
                      height: 9,
                      width: (MediaQuery.of(context).size.width - 60) *
                          (conf / 100.0),
                      decoration: BoxDecoration(
                          color: cor,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                                color: cor.withValues(alpha: 0.45),
                                blurRadius: 10,
                                spreadRadius: 1),
                          ])),
                ])),
            const SizedBox(height: 10),
            Row(children: <Widget>[
              Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                  decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cor.withValues(alpha: 0.45))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Icon(Icons.attach_money_rounded, color: cor, size: 15),
                    const SizedBox(width: 4),
                    Text(
                        '$oddT $oddV${oddTime.isNotEmpty ? ' · $oddTime' : ''}',
                        style: TextStyle(
                            color: cor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900)),
                  ])),
              const Spacer(),
              Icon(Icons.info_outline_rounded,
                  color: cor.withValues(alpha: 0.85), size: 15),
            ]),
            if (razoes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
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
                            child: Icon(Icons.check_circle_outline_rounded,
                                color: cor, size: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(r.toString(),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1.35,
                                    fontWeight: FontWeight.w700))),
                      ]),
                ),
            ],
          ],
        ));
  }
}
