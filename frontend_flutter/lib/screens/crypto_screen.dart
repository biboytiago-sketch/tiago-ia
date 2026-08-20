import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../theme/app_theme.dart';

class CryptoScreen extends StatefulWidget {
  final String backendBaseUrl;
  const CryptoScreen({
    super.key,
    this.backendBaseUrl = BackendConfig.baseRoot,
  });

  @override
  State<CryptoScreen> createState() => _CryptoScreenState();
}

class _CryptoScreenState extends State<CryptoScreen> {
  bool _loading = true;
  String? _erro;
  List<Map<String, dynamic>> _pares = <Map<String, dynamic>>[];
  Timer? _timer;
  String _intervaloSelecionado = '1h';
  String _perfilRiscoSelecionado = 'moderado';
  static const List<String> _intervalos = <String>[
    '5m',
    '15m',
    '1h',
    '4h',
    '1d'
  ];
  static const List<String> _perfisRisco = <String>[
    'conservador',
    'moderado',
    'agressivo',
  ];
  String? _simboloCarregandoIA;

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _carregar(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregar({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    setState(() => _erro = null);
    try {
      final Uri uri = Uri.parse(
        '${widget.backendBaseUrl}/api/v3/crypto/resumo?interval=$_intervaloSelecionado',
      );
      final http.Response r =
          await http.get(uri).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final Map<String, dynamic> data =
          BackendConfig.safeMap(jsonDecode(r.body));
      final List<dynamic> lst = BackendConfig.safeList(data['pares']);
      setState(() {
        _pares = lst
            .map<Map<String, dynamic>>((dynamic e) => BackendConfig.safeMap(e))
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Falha: ${e.toString().split('\n').first}';
        _loading = false;
      });
    }
  }

  Future<void> _acionarIA(Map<String, dynamic> par) async {
    final String simboloBase = BackendConfig.safeString(
            par['label'],
            par['simbolo']?.toString().replaceAll('USDT', '') ?? '')
        .trim();
    if (simboloBase.isEmpty) return;
    setState(() => _simboloCarregandoIA = simboloBase);
    try {
      final Uri uri = Uri.parse(
        '${widget.backendBaseUrl}/api/v3/crypto/ia-sinal-automatico/'
        '$simboloBase'
        '?intervalo=$_intervaloSelecionado'
        '&perfil_risco=$_perfilRiscoSelecionado'
        '&valor_carteira_usd=1000'
        '&usar_gemini=true',
      );
      final http.Response r =
          await http.get(uri).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}: ${r.body}');
      }
      final Map<String, dynamic> payload =
          BackendConfig.safeMap(jsonDecode(r.body));
      if (!mounted) return;
      _exibirModalSinalIA(payload, simboloBase);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.flashCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.red),
          ),
          content: Text(
            'Falha na IA: ${e.toString().split('\n').first}',
            style: const TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            label: 'Fechar',
            textColor: AppTheme.neonGreen,
            onPressed: () {},
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _simboloCarregandoIA = null);
    }
  }

  void _exibirModalSinalIA(Map<String, dynamic> payload, String simboloFallback) {
    final Map<String, dynamic> ativo = BackendConfig.safeMap(payload['ativo']);
    final String nome = BackendConfig.safeString(
        ativo['nome'],
        BackendConfig.safeString(ativo['simbolo_base'], simboloFallback));
    final String sym = BackendConfig.safeString(
        ativo['simbolo_completo'],
        BackendConfig.safeString(ativo['simbolo_base'], simboloFallback) +
            'USDT');
    final num preco = BackendConfig.safeNum(ativo['preco_atual_usd']);
    final String vereditoSigla =
        BackendConfig.safeString(payload['veredito_sigla'], 'AGUARDAR');
    final String vereditoTexto =
        BackendConfig.safeString(payload['veredito_final']);
    final num score = BackendConfig.safeNum(payload['score_global_0_100'], 50);
    final String assinatura = BackendConfig.safeString(
        payload['assinatura'], 'IA do Tiago · Oficial');
    final Map<String, dynamic> gestao =
        BackendConfig.safeMap(payload['gestao_completa_operacao']);
    final num entrada = BackendConfig.safeNum(gestao['entrada_sugerida_usd']);
    final num sl = BackendConfig.safeNum(gestao['stop_loss_usd']);
    final List<dynamic> tps = BackendConfig.safeList(gestao['take_profits']);
    final List<dynamic> motivos =
        BackendConfig.safeList(payload['pontuacao_detalhada_motivos']);
    final List<dynamic> regrasSaida = BackendConfig.safeList(
        gestao['regras_quando_tirar_tudo_automaticamente']);
    final List<dynamic> checklist =
        BackendConfig.safeList(gestao['checklist_antes_de_executar']);
    final num stakePct =
        BackendConfig.safeNum(gestao['stake_sugerido_pct_da_banca']);
    final num stakeUsd = BackendConfig.safeNum(
        gestao['stake_valor_usd_referencia_1k_carteira']);
    final num qtdUnidades =
        BackendConfig.safeNum(gestao['quantidade_unidades_simbolo_base']);
    final num riscoPct = BackendConfig.safeNum(gestao['risco_por_operacao_pct']);
    final bool usouGemini =
        BackendConfig.safeMap(payload['ia_gemini_enriquecimento'])
            .isNotEmpty &&
        BackendConfig.safeBool(
            BackendConfig.safeMap(payload['ia_gemini_enriquecimento'])
                ['aplicado']);

    Color corVeredito = AppTheme.yellow;
    IconData iconeVeredito = Icons.pause_circle_filled;
    switch (vereditoSigla.toUpperCase()) {
      case 'COMPRAR':
      case 'BUY':
      case 'LONG':
        corVeredito = AppTheme.neonGreen;
        iconeVeredito = Icons.trending_up;
        break;
      case 'VENDER':
      case 'SELL':
      case 'SHORT':
        corVeredito = AppTheme.red;
        iconeVeredito = Icons.trending_down;
        break;
      default:
        corVeredito = AppTheme.yellow;
        iconeVeredito = Icons.pause_circle_filled;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        expand: false,
        builder: (_, ScrollController scroll) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.flashBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: <Widget>[
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.flashLine,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(iconeVeredito, color: corVeredito, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '$nome · $sym',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            assinatura,
                            style: const TextStyle(
                                color: AppTheme.flashSub, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          _fmtPreco(preco),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: corVeredito.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: corVeredito),
                          ),
                          child: Text(
                            vereditoSigla.toUpperCase(),
                            style: TextStyle(
                                color: corVeredito,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.flashLine, height: 1),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  controller: scroll,
                  children: <Widget>[
                    _secaoHeader('🎯 Veredito e Score'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: corVeredito.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: corVeredito.withOpacity(0.5)),
                      ),
                      child: Column(
                        children: <Widget>[
                          Text(
                            vereditoTexto,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: corVeredito,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                height: 1.3),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: <Widget>[
                              _miniStat('Score', '${score.toStringAsFixed(0)}/100',
                                  corVeredito),
                              _miniStat(
                                  'Stake',
                                  '${stakePct.toStringAsFixed(1)}% · \$${stakeUsd.toStringAsFixed(0)}',
                                  AppTheme.yellow),
                              _miniStat(
                                  'Risco/Op',
                                  '${riscoPct.toStringAsFixed(2)}%',
                                  AppTheme.red),
                            ],
                          ),
                          if (usouGemini) ...<Widget>[
                            const SizedBox(height: 8),
                            const Text(
                              '✨ Enriquecido com GEMINI',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.deepPurpleAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _secaoHeader('💰 Gestão da Operação · Entrada/Saídas'),
                    const SizedBox(height: 8),
                    _gestaoRow('🎯 Entrada', _fmtPreco(entrada), Colors.white,
                        AppTheme.flashCard),
                    _gestaoRow('🛑 Stop Loss', _fmtPreco(sl), AppTheme.red,
                        AppTheme.red.withOpacity(0.08)),
                    ...List<Widget>.generate(tps.length, (int i) {
                      final Map<String, dynamic> tp =
                          BackendConfig.safeMap(tps[i]);
                      final String nivel =
                          BackendConfig.safeString(tp['nivel'], 'TP${i + 1}');
                      final num precoTp =
                          BackendConfig.safeNum(tp['preco_usd']);
                      final num pctSaida = BackendConfig.safeNum(
                          tp['porcentagem_sair_posicao']);
                      final num ret = BackendConfig.safeNum(
                          tp['retorno_esperado_pct']);
                      final num rr = BackendConfig.safeNum(tp['risco_retorno']);
                      final String detalhe =
                          BackendConfig.safeString(tp['detalhe']);
                      final Color corTp = i == tps.length - 1
                          ? Colors.purpleAccent
                          : AppTheme.neonGreen;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _gestaoRow(
                          '🎯 $nivel · ${pctSaida.toStringAsFixed(0)}% posição',
                          '${_fmtPreco(precoTp)}  ·  +${ret.toStringAsFixed(1)}%  ·  R:R ${rr.toStringAsFixed(1)}',
                          corTp,
                          corTp.withOpacity(0.07),
                          subLabel: detalhe.isNotEmpty ? detalhe : null,
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
                      ),
                      child: Text(
                        '💡 Quantidade p/ referência (carteira \$1000): '
                        '${qtdUnidades.toStringAsFixed(6)} ${BackendConfig.safeString(ativo['simbolo_base'], simboloFallback)}',
                        style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _secaoHeader('🚨 Quando TIRAR TUDO automaticamente'),
                    const SizedBox(height: 8),
                    ...List<Widget>.generate(regrasSaida.length, (int i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Icon(Icons.warning_amber_rounded,
                                  color: AppTheme.red.withOpacity(0.8),
                                  size: 14),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                BackendConfig.safeString(
                                    regrasSaida[i], ''),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    _secaoHeader('🧠 Motivos da Decisão (score detalhado)'),
                    const SizedBox(height: 8),
                    ...List<Widget>.generate(motivos.length, (int i) {
                      final String m = BackendConfig.safeString(motivos[i], '');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle,
                                  color: AppTheme.neonGreen, size: 13),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                    height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (checklist.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _secaoHeader('✅ Checklist antes de executar'),
                      const SizedBox(height: 8),
                      ...List<Widget>.generate(checklist.length, (int i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.task_alt,
                                    color: AppTheme.neonGreen, size: 13),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  BackendConfig.safeString(checklist[i], ''),
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'IA do Tiago · Oficial — Dados são referência. Não é recomendação financeira.',
                        style: TextStyle(
                            color: AppTheme.flashSub, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String valor, Color cor) => Column(
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  color: cor.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 13, fontWeight: FontWeight.w900)),
        ],
      );

  Widget _secaoHeader(String titulo) => Row(
        children: <Widget>[
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );

  Widget _gestaoRow(String label, String valor, Color cor, Color fundo,
      {String? subLabel}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.flashSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              Text(valor,
                  style: TextStyle(
                      color: cor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          if (subLabel != null && subLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(subLabel,
                style: TextStyle(
                    color: cor.withOpacity(0.8),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.flashBg,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.show_chart, color: AppTheme.neonGreen),
            SizedBox(width: 8),
            Text('IA do Tiago · Crypto v2'),
          ],
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppTheme.flashCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.flashLine),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _perfilRiscoSelecionado,
                  dropdownColor: AppTheme.flashCard,
                  iconEnabledColor: AppTheme.neonGreen,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11),
                  items: _perfisRisco
                      .map<DropdownMenuItem<String>>(
                          (String p) => DropdownMenuItem<String>(
                                value: p,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(p.toUpperCase()),
                                ),
                              ))
                      .toList(growable: false),
                  onChanged: (String? v) {
                    if (v == null || v == _perfilRiscoSelecionado) return;
                    setState(() => _perfilRiscoSelecionado = v);
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppTheme.flashCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.flashLine),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _intervaloSelecionado,
                  dropdownColor: AppTheme.flashCard,
                  iconEnabledColor: AppTheme.neonGreen,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                  items: _intervalos
                      .map<DropdownMenuItem<String>>(
                          (String iv) => DropdownMenuItem<String>(
                                value: iv,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(iv),
                                ),
                              ))
                      .toList(growable: false),
                  onChanged: (String? v) {
                    if (v == null || v == _intervaloSelecionado) return;
                    setState(() => _intervaloSelecionado = v);
                    _carregar();
                  },
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh, color: AppTheme.neonGreen),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _pares.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.neonGreen));
    }
    if (_erro != null && _pares.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.red),
              const SizedBox(height: 12),
              Text(_erro!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _carregar,
                child: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppTheme.neonGreen,
      backgroundColor: AppTheme.flashCard,
      onRefresh: _carregar,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        itemCount: _pares.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (BuildContext _, int i) {
          if (i == _pares.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Align(
                child: Text(
                  'RSI(14) · EMA 20 · EMA 200 · IA do Tiago · Clique em 🤖IA para análise completa',
                  style: TextStyle(color: AppTheme.flashSub, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _CardAtivo(
            par: _pares[i],
            intervalo: _intervaloSelecionado,
            onAcionarIA: _acionarIA,
            carregandoIA: _simboloCarregandoIA ==
                BackendConfig.safeString(
                    _pares[i]['label'],
                    BackendConfig.safeString(_pares[i]['simbolo'])
                        .replaceAll('USDT', '')),
          );
        },
      ),
    );
  }

  String _fmtPreco(num v) {
    final double val = v.toDouble();
    if (val >= 1000) {
      return val.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    }
    if (val >= 1) return val.toStringAsFixed(2);
    if (val >= 0.01) return val.toStringAsFixed(4);
    return val.toStringAsFixed(6);
  }
}

class _CardAtivo extends StatelessWidget {
  final Map<String, dynamic> par;
  final String intervalo;
  final void Function(Map<String, dynamic>) onAcionarIA;
  final bool carregandoIA;
  const _CardAtivo({
    required this.par,
    required this.intervalo,
    required this.onAcionarIA,
    this.carregandoIA = false,
  });

  String _d(Object? o, [String fallback = '—']) =>
      (o?.toString().isNotEmpty ?? false) ? o.toString() : fallback;

  Color _corSinal(String s) {
    switch (s.toUpperCase()) {
      case 'COMPRAR':
      case 'BUY':
      case 'LONG':
        return AppTheme.neonGreen;
      case 'VENDER':
      case 'SELL':
      case 'SHORT':
        return AppTheme.red;
      default:
        return AppTheme.yellow;
    }
  }

  String _fmtPreco(num v) {
    final double val = v.toDouble();
    if (val >= 1000) {
      return val.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    }
    if (val >= 1) return val.toStringAsFixed(2);
    if (val >= 0.01) return val.toStringAsFixed(4);
    return val.toStringAsFixed(6);
  }

  @override
  Widget build(BuildContext context) {
    final String sinal = _d(par['sinal'], 'AGUARDAR');
    final Color corSinal = _corSinal(sinal);
    final Map<String, dynamic> ind = BackendConfig.safeMap(par['indicadores']);
    final Map<String, dynamic> gr = BackendConfig.safeMap(par['gestao_risco']);
    final num preco = BackendConfig.safeNum(par['preco_atual']);
    final num rsi = BackendConfig.safeNum(ind['rsi_14'], 50);
    final num ema20 = BackendConfig.safeNum(ind['ema_20']);
    final num ema200 = BackendConfig.safeNum(ind['ema_200']);
    final num entrada = BackendConfig.safeNum(gr['ponto_entrada']);
    final num stop = BackendConfig.safeNum(gr['stop_loss']);
    final num tp = BackendConfig.safeNum(gr['take_profit']);
    final num stake = BackendConfig.safeNum(gr['recomendacao_stake_pct'], 0.5);
    final bool acimaEma200 = BackendConfig.safeBool(ind['preco_acima_ema200']);
    final bool golden = BackendConfig.safeBool(ind['cruzamento_ema_20x200']);
    final String? rr = gr['relacao_risco_retorno']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.flashCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: corSinal.withOpacity(0.4), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(color: corSinal.withOpacity(0.08), blurRadius: 10),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: corSinal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sinal.toUpperCase(),
                  style: TextStyle(
                      color: corSinal,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${_d(par['label'], par['simbolo'])} · ${_d(par['simbolo'])}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Intervalo: $intervalo · Atualizado ${_d(par['atualizado_em'], '').replaceAll('T', ' ').split('.').first}',
                      style: const TextStyle(
                          color: AppTheme.flashSub, fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _fmtPreco(preco),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900),
                  ),
                  if (rr != null && rr.isNotEmpty && rr != 'null')
                    Text(
                      'R:R $rr',
                      style: TextStyle(
                          color: double.tryParse(rr) != null &&
                                  double.parse(rr) >= 1.5
                              ? AppTheme.neonGreen
                              : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '💡 ${_d(par['motivo'])}',
            style: TextStyle(
                color: corSinal.withOpacity(0.95),
                fontSize: 12.5,
                height: 1.3),
          ),
          if (golden || acimaEma200) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: <Widget>[
                if (golden) _tag('🌟 Golden Cross', Colors.purpleAccent),
                if (acimaEma200) _tag('📈 Acima EMA200', AppTheme.neonGreen),
                if (!acimaEma200 && sinal != 'COMPRAR')
                  _tag('📉 Abaixo EMA200', AppTheme.red),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _indicadorMini(
                  label: 'RSI(14)',
                  valor: rsi.toStringAsFixed(1),
                  cor: rsi < 35
                      ? AppTheme.neonGreen
                      : (rsi > 70 ? AppTheme.red : AppTheme.yellow),
                  sub: rsi < 35
                      ? 'Sobrevendido'
                      : (rsi > 70 ? 'Sobrecomprado' : 'Neutro'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _indicadorMini(
                  label: 'EMA 20',
                  valor: _fmtPreco(ema20),
                  cor: preco >= ema20 ? AppTheme.neonGreen : AppTheme.red,
                  sub: preco >= ema20 ? 'Preço ≥ EMA20' : 'Preço < EMA20',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _indicadorMini(
                  label: 'EMA 200',
                  valor: _fmtPreco(ema200),
                  cor: acimaEma200 ? AppTheme.neonGreen : AppTheme.red,
                  sub: acimaEma200 ? 'Tendência Alta' : 'Tendência Baixa',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.flashBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.flashLine),
            ),
            child: Column(
              children: <Widget>[
                _grRow('🎯 Entrada', _fmtPreco(entrada), Colors.white),
                const SizedBox(height: 6),
                _grRow('🛑 Stop Loss', _fmtPreco(stop), AppTheme.red),
                const SizedBox(height: 6),
                _grRow('🎯 Take Profit', _fmtPreco(tp), AppTheme.neonGreen),
                const SizedBox(height: 6),
                _grRow('💰 Stake Sugerido',
                    '${stake.toStringAsFixed(1)}% da banca', AppTheme.yellow),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  carregandoIA ? null : () => onAcionarIA(par),
              style: ElevatedButton.styleFrom(
                backgroundColor: corSinal.withOpacity(0.14),
                foregroundColor: corSinal,
                disabledBackgroundColor: AppTheme.flashCard,
                disabledForegroundColor: AppTheme.flashSub,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: corSinal.withOpacity(0.55)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
                elevation: 0,
              ),
              icon: carregandoIA
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppTheme.neonGreen, strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 17),
              label: Text(
                carregandoIA
                    ? 'Processando IA...'
                    : '🤖  ACIONAR IA ANÁLISE COMPLETA',
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String texto, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cor.withOpacity(0.5)),
        ),
        child: Text(
          texto,
          style: TextStyle(
              color: cor, fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
      );

  Widget _indicadorMini(
      {required String label,
      required String valor,
      required Color cor,
      required String sub}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  color: cor, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
        ],
      ),
    );
  }

  Widget _grRow(String label, String valor, Color cor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: AppTheme.flashSub, fontSize: 12)),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 12.5, fontWeight: FontWeight.w800)),
        ],
      );
}
