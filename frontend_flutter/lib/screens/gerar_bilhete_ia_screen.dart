import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/backend_config.dart';
import '../core/bookmaker_registry.dart';
import '../services/api_service.dart';
import '../services/bet_export_engine.dart';
import '../theme/app_theme.dart';

class GerarBilheteIAScreen extends StatefulWidget {
  final String backendBaseUrl;
  const GerarBilheteIAScreen({
    super.key,
    this.backendBaseUrl = BackendConfig.baseRoot,
  });

  @override
  State<GerarBilheteIAScreen> createState() => _GerarBilheteIAScreenState();
}

class _GerarBilheteIAScreenState extends State<GerarBilheteIAScreen>
    with SingleTickerProviderStateMixin {
  static const List<Map<String, dynamic>> _perfis = <Map<String, dynamic>>[
    {
      'key': 'SEGURO',
      'label': 'Seguro',
      'icone': Icons.lock,
      'cor': Color(0xFF1FB453),
      'sombra': Color(0x661FB453)
    },
    {
      'key': 'BALANCEADO',
      'label': 'Balanceado',
      'icone': Icons.balance,
      'cor': Color(0xFFFF9800),
      'sombra': Color(0x66FF9800)
    },
    {
      'key': 'AGRESSIVO',
      'label': 'Agressivo',
      'icone': Icons.local_fire_department,
      'cor': Color(0xFFFF3B30),
      'sombra': Color(0x66FF3B30)
    },
  ];

  late TabController _tab;
  int _abaAtual = 0;

  Map<String, dynamic>? _dados;
  bool _loading = true;
  String? _erro;
  final Set<String> _selecionadas = <String>{};
  Map<String, Map<String, dynamic>> _validacaoPorPerfil =
      <String, Map<String, dynamic>>{};

  String _baseResolvida = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _perfis.length, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging || _abaAtual == _tab.index) return;
      setState(() => _abaAtual = _tab.index);
    });
    _gerar();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<String> _resolverBackend({bool forcar = false}) async {
    if (_baseResolvida.isNotEmpty && !forcar) return _baseResolvida;
    final String root =
        await ApiService.resolveBaseUrl(forcarRedeteccao: forcar);
    if (root.isNotEmpty) {
      _baseResolvida = root;
      return _baseResolvida;
    }
    return widget.backendBaseUrl;
  }

  Future<void> _gerar() async {
    setState(() {
      _loading = true;
      _erro = null;
      _selecionadas.clear();
      _validacaoPorPerfil.clear();
    });
    try {
      final String base = await _resolverBackend();
      final Uri uri = Uri.parse('$base/api/v3/sports/gerar-bilhetes-ia')
          .replace(queryParameters: <String, String>{
        'quantidade_bilhetes': '3',
        'jogos_minimo': '2',
        'jogos_maximo': '6',
      });
      final http.Response r = await http.get(uri).timeout(
          const Duration(seconds: 45)); // 🟢 antes 20s (Render pode cold start)
      if (r.statusCode != 200)
        throw Exception(
            'HTTP ${r.statusCode}: ${r.body.substring(0, r.body.length.clamp(0, 120))}');
      final Map<String, dynamic> data =
          BackendConfig.safeMap(jsonDecode(r.body));
      final List<dynamic> bilhetes =
          BackendConfig.safeList(data['bilhetes_sugeridos']);
      for (final dynamic b in bilhetes) {
        final Map<String, dynamic> bm = BackendConfig.safeMap(b);
        final List<dynamic> sel = BackendConfig.safeList(bm['selecoes']);
        for (final dynamic s in sel) {
          final Map<String, dynamic> sm = BackendConfig.safeMap(s);
          final Map<String, dynamic> se =
              BackendConfig.safeMap(sm['selecao_escolhida']);
          final String id =
              '${bm['perfil']}_${sm['fixture_id']}_${se['mercado']}';
          _selecionadas.add(id);
        }
      }
      setState(() => _dados = data);
    } catch (e) {
      setState(() =>
          _erro = 'Erro ao gerar bilhetes: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _bilhetes() {
    final List<dynamic> lst =
        BackendConfig.safeList(_dados?['bilhetes_sugeridos']);
    return lst
        .map<Map<String, dynamic>>((dynamic e) => BackendConfig.safeMap(e))
        .toList(growable: false);
  }

  Map<String, dynamic>? _bilheteAtual() {
    final List<Map<String, dynamic>> bs = _bilhetes();
    if (_abaAtual < 0 || _abaAtual >= bs.length) return null;
    return bs[_abaAtual];
  }

  bool get _isOrigemReal {
    final String origem =
        BackendConfig.safeString(_dados?['origem_dados_geral']);
    return origem == 'RAPIDAPI_REAL';
  }

  void _toggleSelecao(String idPerfil, Map<String, dynamic> selecao) {
    final Map<String, dynamic> sel =
        BackendConfig.safeMap(selecao['selecao_escolhida']);
    final String id = '${idPerfil}_${selecao['fixture_id']}_${sel['mercado']}';
    setState(() {
      if (_selecionadas.contains(id)) {
        _selecionadas.remove(id);
      } else {
        _selecionadas.add(id);
      }
    });
  }

  Future<void> _usarBilhete() async {
    final Map<String, dynamic>? b = _bilheteAtual();
    if (b == null) return;
    final String perfil = BackendConfig.safeString(b['perfil']);
    final List<dynamic> selecoesAll = BackendConfig.safeList(b['selecoes']);
    final List<Map<String, dynamic>> usadas = <Map<String, dynamic>>[];
    for (final dynamic s in selecoesAll) {
      final Map<String, dynamic> sm = BackendConfig.safeMap(s);
      final Map<String, dynamic> sel =
          BackendConfig.safeMap(sm['selecao_escolhida']);
      final String id = '${perfil}_${sm['fixture_id']}_${sel['mercado']}';
      if (_selecionadas.contains(id)) {
        usadas.add(<String, dynamic>{
          'mercado': sel['mercado'],
          'opcao': sel['opcao_escolhida'],
          'odd_apostada': sel['odd_alvo'],
          'fixture_id': sm['fixture_id'],
          'time_casa': sm['time_casa'],
          'time_fora': sm['time_fora'],
          'linha': sel['linha'],
        });
      }
    }
    if (usadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.flashCard,
          content: const Text('Selecione pelo menos 1 jogada no bilhete.',
              style: TextStyle(color: Colors.white)),
          action: SnackBarAction(
              label: 'OK', textColor: AppTheme.yellow, onPressed: () {}),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final Uri uri =
          Uri.parse('${widget.backendBaseUrl}/api/v3/sports/validar-multipla');
      final http.Response r = await http
          .post(
            uri,
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(
                <String, dynamic>{'selecoes': usadas, 'stake_total': 100.0}),
          )
          .timeout(const Duration(
              seconds: 45)); // 🟢 antes 15s (validacao multipla pode chamar IA)
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final Map<String, dynamic> valid =
          BackendConfig.safeMap(jsonDecode(r.body));
      setState(() => _validacaoPorPerfil[perfil] = valid);
      if (!mounted) return;
      _showVeredito(perfil, valid);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.flashCard,
          content: Text('Validação: ${e.toString().split('\n').first}',
              style: const TextStyle(color: Colors.white)),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showVeredito(String perfil, Map<String, dynamic> valid) {
    final bool aprovado =
        BackendConfig.safeString(valid['veredito']) == 'APROVADO';
    final Color cor =
        aprovado ? const Color(0xFF1FB453) : const Color(0xFFFF3B30);
    final String odds =
        BackendConfig.safeNum(valid['odds_acumulada']).toStringAsFixed(2);
    final String prob = BackendConfig.safeNum(valid['probabilidade_geral_pct'])
        .toStringAsFixed(1);
    final String stake = BackendConfig.safeNum(valid['stake_recomendado_pct'])
        .toStringAsFixed(1);
    final String risco = BackendConfig.safeString(valid['risco_geral']);
    final String retorno =
        BackendConfig.safeNum(valid['retorno_potencial']).toStringAsFixed(2);
    final List<dynamic> sugs =
        BackendConfig.safeList(valid['sugestoes_ajuste']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.flashBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                        color: cor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cor, width: 2)),
                    child: Row(
                      children: <Widget>[
                        Icon(
                            aprovado ? Icons.check_circle : Icons.error_outline,
                            color: cor,
                            size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                  'Bilhete $perfil · ${aprovado ? 'APROVADO' : 'REVERTER'}',
                                  style: TextStyle(
                                      color: cor,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17)),
                              const SizedBox(height: 2),
                              Text('Risco $risco · Odds $odds · Chance $prob%',
                                  style: const TextStyle(
                                      color: AppTheme.flashSub, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      _miniStat('Odds', odds, AppTheme.yellow),
                      _miniStat('Chance', '$prob%', AppTheme.neonGreen),
                      _miniStat('Stake%', '$stake%', AppTheme.yellow),
                      _miniStat('Retorno \$100', 'R\$ $retorno',
                          const Color(0xFFCE93D8)),
                    ],
                  ),
                  if (sugs.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    const Text('💡 Sugestões de Ajuste',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    for (final dynamic s in sugs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('  •  ${s.toString()}',
                            style: const TextStyle(
                                color: AppTheme.flashSub,
                                fontSize: 12,
                                height: 1.4)),
                      ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _copiarSomenteBilhete();
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.flashCard,
                                foregroundColor: AppTheme.yellow,
                                side: const BorderSide(
                                    color: AppTheme.yellow, width: 1.4),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            icon: const Icon(Icons.copy_all_rounded, size: 18),
                            label: const Text('COPIAR BILHETE',
                                style: TextStyle(
                                    color: AppTheme.yellow,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _abrirSeletorCasas();
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: cor,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            icon: const Icon(Icons.rocket_launch_rounded,
                                size: 18, color: Colors.white),
                            label: const Text('🚀 APOSTAR NO APP',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
          color: AppTheme.flashCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.flashLine)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  color: AppTheme.flashSub,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? atual = _bilheteAtual();
    return Scaffold(
      backgroundColor: AppTheme.flashBg,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.auto_awesome, color: AppTheme.yellow),
            SizedBox(width: 8),
            Text('Gerador IA · Bilhetes Prontos'),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Regerar bilhetes',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _gerar,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: false,
          dividerColor: AppTheme.flashLine,
          indicatorColor: _perfis[_abaAtual]['cor'] as Color,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.flashSub,
          tabs: _perfis.map((Map<String, dynamic> a) {
            return Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(a['icone'] as IconData,
                      size: 14, color: a['cor'] as Color),
                  const SizedBox(width: 5),
                  Text(a['label'] as String),
                ],
              ),
            );
          }).toList(growable: false),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.yellow))
          : (_erro != null)
              ? _erroTela()
              : Column(
                  children: <Widget>[
                    if (!_isOrigemReal)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                        child: _AvisoOrigemGerador(
                            origem: _dados?['origem_dados_geral'] as String? ??
                                'FALLBACK_TODOS'),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: List<Widget>.generate(_perfis.length,
                            (int i) => _corpoPerfil(_bilhetes()[i])),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: atual == null || _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _usarBilhete,
              backgroundColor: _perfis[_abaAtual]['cor'] as Color,
              icon: const Icon(Icons.playlist_add_check, color: Colors.white),
              label: Text(
                'USAR ESTE BILHETE · ${_countSelecionadas(atual)} jogadas',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
    );
  }

  int _countSelecionadas(Map<String, dynamic> b) {
    final String perfil = b['perfil'] as String? ?? '';
    final List<dynamic> sel = BackendConfig.safeList(b['selecoes']);
    int c = 0;
    for (final dynamic s in sel) {
      final Map<String, dynamic> sm = BackendConfig.safeMap(s);
      final Map<String, dynamic> selMap =
          BackendConfig.safeMap(sm['selecao_escolhida']);
      final String id = '${perfil}_${sm['fixture_id']}_${selMap['mercado']}';
      if (_selecionadas.contains(id)) c++;
    }
    return c;
  }

  BilhetePronto? _montarBilheteExport() {
    final Map<String, dynamic>? b = _bilheteAtual();
    if (b == null) return null;
    final String perfil = BackendConfig.safeString(b['perfil']);
    final List<dynamic> selecoesRaw = BackendConfig.safeList(b['selecoes']);
    final Map<String, dynamic> validacao =
        _validacaoPorPerfil[perfil] ?? BackendConfig.safeMap(b['validacao']);
    final double oddsTotais = BackendConfig.safeDouble(
        validacao['odds_acumulada'] ?? b['odds_acumulada_ia'] ?? 1.0);
    final double stake = BackendConfig.safeDouble(
        validacao['stake_recomendado_pct'] ??
            b['stake_recomendado_padrao'] ??
            100.0);
    final double stakeBRL = (stake > 1 && stake < 50)
        ? stake * 1.0
        : (stake > 50 && stake <= 100)
            ? stake
            : (stake * 0.0).clamp(10, 100);
    final double stakeReal = stakeBRL < 5 ? 100 : stakeBRL;
    final double? ret = validacao['retorno_potencial'] != null
        ? BackendConfig.safeDouble(validacao['retorno_potencial'])
        : b['retorno_potencial_exemplo_100'] != null
            ? BackendConfig.safeDouble(b['retorno_potencial_exemplo_100'])
            : null;
    final String risco = BackendConfig.safeString(
        validacao['risco_geral'] ?? b['risco_geral'] ?? '');
    final DateTime data = DateTime.now();
    final List<SelecaoBilhete> list = <SelecaoBilhete>[];
    int idx = 1;
    for (final dynamic s in selecoesRaw) {
      final Map<String, dynamic> sm = BackendConfig.safeMap(s);
      final Map<String, dynamic> sel =
          BackendConfig.safeMap(sm['selecao_escolhida']);
      final String id = '${perfil}_${sm['fixture_id']}_${sel['mercado']}';
      if (!_selecionadas.contains(id)) continue;
      list.add((
        numero: idx++,
        timeCasa: BackendConfig.safeString(sm['time_casa']),
        timeFora: BackendConfig.safeString(sm['time_fora']),
        mercado: BackendConfig.safeString(sel['label']).isEmpty
            ? BackendConfig.safeString(sel['mercado'])
            : BackendConfig.safeString(sel['label']) +
                (sel['linha'] != null && sel['linha'].toString().isNotEmpty
                    ? ' (Linha ${sel['linha']})'
                    : ''),
        odd: BackendConfig.safeDouble(sel['odd_alvo']),
        liga: sm['liga']?.toString(),
        horario: sm['horario_br']?.toString(),
      ));
    }
    if (list.isEmpty) return null;
    return (
      data: data,
      selecoes: list,
      oddsTotais: oddsTotais < 1.01 ? 1.01 : oddsTotais,
      stakeBRL: stakeReal < 1 ? 50 : stakeReal,
      retornoPotencialBRL: ret,
      perfil: perfil,
      risco: risco.isEmpty ? null : risco,
    );
  }

  Future<void> _copiarSomenteBilhete() async {
    final BilhetePronto? bilhete = _montarBilheteExport();
    if (bilhete == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Color(0xFFFF3B30),
            content: Text('Selecione pelo menos 1 jogada para exportar.',
                style: TextStyle(color: Colors.white))),
      );
      return;
    }
    final String texto = BetExportEngine.formatarBilheteTexto(bilhete);
    await BetExportEngine.copiarParaClipboard(texto);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          backgroundColor: Color(0xFF1FB453),
          duration: Duration(seconds: 3),
          content: Row(
            children: <Widget>[
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Flexible(
                  child: Text(
                      '📋 Bilhete copiado! Já pode colar no grupo do Telegram / WhatsApp.',
                      style: TextStyle(color: Colors.white))),
            ],
          )),
    );
  }

  Future<void> _exportarEAbrirCasa(BookmakerConfig casa) async {
    final BilhetePronto? bilhete = _montarBilheteExport();
    if (bilhete == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Color(0xFFFF3B30),
            content: Text('Selecione jogadas no bilhete antes de exportar.',
                style: TextStyle(color: Colors.white))),
      );
      return;
    }
    final String texto = BetExportEngine.formatarBilheteTexto(bilhete);
    await BetExportEngine.copiarParaClipboard(texto);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          backgroundColor: casa.accentColor,
          duration: const Duration(seconds: 4),
          content: Row(
            children: <Widget>[
              const Icon(Icons.copy_all, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Flexible(
                  child: Text(
                      '📋 Bilhete copiado! Abrindo ${casa.name} para você fazer login...',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.3))),
            ],
          )),
    );
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await BetExportEngine.abrirCasaDeApostas(casa);
  }

  void _abrirSeletorCasas() {
    final BilhetePronto? tmp = _montarBilheteExport();
    if (tmp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Color(0xFFFF3B30),
            content: Text('Selecione ao menos 1 jogada no bilhete primeiro.',
                style: TextStyle(color: Colors.white))),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1418),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 54,
                      height: 5,
                      decoration: BoxDecoration(
                          color: AppTheme.flashLine,
                          borderRadius: BorderRadius.circular(5)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: AppTheme.yellow.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.rocket_launch_rounded,
                              color: AppTheme.yellow)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('🚀 Apostar no App / Web',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 3),
                            Text(
                                'Escolha a casa. O bilhete é copiado automaticamente.',
                                style: TextStyle(
                                    color: AppTheme.flashSub, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.25,
                    ),
                    itemCount: SUPPORTED_BOOKMAKERS.length,
                    itemBuilder: (_, int i) {
                      final BookmakerConfig casa = SUPPORTED_BOOKMAKERS[i];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          splashColor: casa.accentColor.withOpacity(0.25),
                          highlightColor: casa.accentColor.withOpacity(0.1),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _exportarEAbrirCasa(casa);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                                color: AppTheme.flashCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: casa.accentColor.withOpacity(0.65),
                                    width: 1.2)),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                      color: casa.accentColor.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Icon(casa.icon,
                                      color: casa.accentColor, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Text(casa.name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 2),
                                      Text(
                                          casa.supportsDirectCouponImport
                                              ? 'Importa cupom'
                                              : 'Link Web / App',
                                          style: const TextStyle(
                                              color: AppTheme.flashSub,
                                              fontSize: 10.5)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _copiarSomenteBilhete();
                      },
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppTheme.flashLine, width: 1.3),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13))),
                      icon: const Icon(Icons.copy_all_rounded,
                          color: AppTheme.flashSub, size: 18),
                      label: const Text(
                          'Apenas Copiar Bilhete (para WhatsApp / Telegram)',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _erroTela() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.warning_amber, size: 50, color: AppTheme.yellow),
            const SizedBox(height: 14),
            Text(_erro!,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            SizedBox(
              width: 240,
              height: 48,
              child: ElevatedButton(
                onPressed: _gerar,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.yellow,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: const Text('TENTAR NOVAMENTE',
                    style: TextStyle(
                        color: Color(0xFF10191E), fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _corpoPerfil(Map<String, dynamic> bilhete) {
    final String perfil = bilhete['perfil'] as String? ?? '';
    final Color cor = _perfis.firstWhere(
        (Map<String, dynamic> p) => p['label'] == perfil,
        orElse: () => _perfis[0])['cor'] as Color;
    final Color sombra = _perfis.firstWhere(
        (Map<String, dynamic> p) => p['label'] == perfil,
        orElse: () => _perfis[0])['sombra'] as Color;
    final String odds =
        (bilhete['odds_acumulada_ia'] as num?)?.toStringAsFixed(2) ?? '--';
    final String prob =
        (bilhete['probabilidade_geral_ia_pct'] as num?)?.toStringAsFixed(1) ??
            '--';
    final String ret = (bilhete['retorno_potencial_exemplo_100'] as num?)
            ?.toStringAsFixed(2) ??
        '--';
    final int qtd = (bilhete['quantidade_jogos'] as num?)?.toInt() ?? 0;
    final Map<String, dynamic> validacao =
        BackendConfig.safeMap(bilhete['validacao']);
    final String stake =
        BackendConfig.safeNum(validacao['stake_recomendado_pct'])
            .toStringAsFixed(1);
    final String veredito = validacao['veredito']?.toString() ?? '';
    final String risco = validacao['risco_geral']?.toString() ?? '';
    final List<dynamic> selecoes = BackendConfig.safeList(bilhete['selecoes']);

    return RefreshIndicator(
      color: cor,
      onRefresh: _gerar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.flashCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cor.withOpacity(0.6), width: 1.6),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: sombra,
                      blurRadius: 22,
                      spreadRadius: -6,
                      offset: const Offset(0, 10))
                ],
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: cor.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(14)),
                        child: Icon(
                            _perfis.firstWhere(
                                (Map<String, dynamic> p) =>
                                    p['label'] == perfil,
                                orElse: () => _perfis[0])['icone'] as IconData,
                            color: cor,
                            size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('$perfil · $qtd Jogadas',
                                style: TextStyle(
                                    color: cor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(
                                'Gerado ${_fmtData(_dados?['gerado_em'] as String?) ?? ''}',
                                style: const TextStyle(
                                    color: AppTheme.flashSub, fontSize: 11)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 10),
                        decoration: BoxDecoration(
                          color: veredito == 'APROVADO'
                              ? const Color(0xFF1FB453)
                              : (veredito == 'REVERTER'
                                  ? const Color(0xFFFF3B30)
                                  : cor),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                            veredito.isEmpty ? 'IA · Pré-vali.' : veredito,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(child: _kpi('Odds', odds, AppTheme.yellow)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _kpi('Chance', '$prob%', AppTheme.neonGreen)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _kpi(
                              'R\$100 →', 'R\$ $ret', const Color(0xFFCE93D8))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _kpi(
                              'Stake', '$stake%', const Color(0xFF80DEEA))),
                    ],
                  ),
                  if (risco.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Text('Risco: ',
                            style: const TextStyle(
                                color: AppTheme.flashSub,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: risco == 'Baixo'
                                ? const Color(0xFF1FB453)
                                : (risco == 'Médio'
                                    ? const Color(0xFFFF9800)
                                    : (risco == 'Alto'
                                        ? const Color(0xFFFF6B00)
                                        : const Color(0xFFFF3B30))),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(risco,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11)),
                        ),
                        const Spacer(),
                        const Icon(Icons.verified_user,
                            size: 14, color: AppTheme.flashSub),
                        const SizedBox(width: 4),
                        Text('Assinatura IA do Tiago',
                            style: TextStyle(
                                color: AppTheme.flashSub.withOpacity(0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: Text(
                  '🎯 Jogadas Sugeridas pela IA  (desmarque para remover)',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < selecoes.length; i++) ...<Widget>[
              _selecaoCard(
                  perfil, cor, i + 1, BackendConfig.safeMap(selecoes[i])),
              const SizedBox(height: 10),
            ],
            if (_dados?['recomendacao_final'] != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppTheme.flashCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.flashLine)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.info_outline,
                          color: const Color(0xFF80DEEA), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_dados!['recomendacao_final'] as String,
                            style: const TextStyle(
                                color: AppTheme.flashSub,
                                fontSize: 11.5,
                                height: 1.4))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(
          color: const Color(0xFF10191E),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  color: AppTheme.flashSub,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _selecaoCard(
      String perfil, Color cor, int idx, Map<String, dynamic> s) {
    final Map<String, dynamic> sel =
        BackendConfig.safeMap(s['selecao_escolhida']);
    final String mercado = sel['mercado'] as String? ?? '';
    final String labelMercado = sel['label'] as String? ?? '';
    final String odd =
        BackendConfig.safeNum(sel['odd_alvo']).toStringAsFixed(2);
    final String prob =
        BackendConfig.safeNum(sel['probabilidade_pct']).toStringAsFixed(1);
    final double score = BackendConfig.safeDouble(sel['score_ia']);
    final String? linha = sel['linha'] as String?;
    final String casa = s['time_casa'] as String? ?? '';
    final String fora = s['time_fora'] as String? ?? '';
    final String liga = s['liga'] as String? ?? '';
    final String horario = s['horario_br'] as String? ?? '';
    final String statusFlag = s['status_flag'] as String? ?? '';
    final int? minuto = s['tempo_decorrido'] as int?;
    final String justificativa = sel['justificativa'] as String? ?? '';
    final List<dynamic> desfalques =
        BackendConfig.safeList(s['desfalques_alertas']);
    final String id = '${perfil}_${s['fixture_id']}_${sel['mercado']}';
    final bool selecionada = _selecionadas.contains(id);
    final Color corMercado =
        mercado.contains('Escanteio') || mercado.contains('Canto')
            ? const Color(0xFFCE93D8)
            : mercado.contains('Gol')
                ? AppTheme.neonGreen
                : mercado.contains('Chute')
                    ? const Color(0xFF80DEEA)
                    : AppTheme.yellow;

    return GestureDetector(
      onTap: () => _toggleSelecao(perfil, s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selecionada ? cor.withOpacity(0.10) : AppTheme.flashCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selecionada ? cor : AppTheme.flashLine,
              width: selecionada ? 1.8 : 1),
          boxShadow: selecionada
              ? <BoxShadow>[
                  BoxShadow(
                      color: cor.withOpacity(0.22),
                      blurRadius: 16,
                      spreadRadius: -5)
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: selecionada ? cor : corMercado.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(9)),
                  alignment: Alignment.center,
                  child: selecionada
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text('$idx',
                          style: TextStyle(
                              color: corMercado,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('$casa  x  $fora',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5)),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          Text('$liga  ·  ',
                              style: const TextStyle(
                                  color: AppTheme.flashSub, fontSize: 11)),
                          if (statusFlag == 'EM_ANDAMENTO') ...<Widget>[
                            const Icon(Icons.circle,
                                color: Color(0xFFFF3B30), size: 7),
                            const SizedBox(width: 4),
                            Text('Ao Vivo · ${minuto ?? 0}\'',
                                style: const TextStyle(
                                    color: Color(0xFFFF3B30),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ] else
                            Text('📅 $horario',
                                style: const TextStyle(
                                    color: AppTheme.flashSub, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text('$score',
                        style: TextStyle(
                            color: cor,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const Text('Score IA',
                        style: TextStyle(
                            color: AppTheme.flashSub,
                            fontSize: 9,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                  decoration: BoxDecoration(
                      color: corMercado.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: corMercado.withOpacity(0.4))),
                  child: Text(labelMercado,
                      style: TextStyle(
                          color: corMercado,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5)),
                ),
                if (linha != null && linha.toString().isNotEmpty) ...<Widget>[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 7, horizontal: 9),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0E2128),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.flashLine)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.linear_scale,
                            size: 11, color: AppTheme.flashSub),
                        const SizedBox(width: 4),
                        Text('Linha: ${linha.toString()}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11)),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                _miniPill(Icons.monetization_on, 'Odd $odd', AppTheme.yellow),
                const SizedBox(width: 6),
                _miniPill(Icons.trending_up, '$prob%', AppTheme.neonGreen),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFF0E1B21),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('💡  $justificativa',
                  style: const TextStyle(
                      color: AppTheme.flashSub, fontSize: 11.2, height: 1.4)),
            ),
            if (desfalques.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: desfalques
                    .map<Widget>((dynamic d) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFFF3B30)
                                      .withOpacity(0.35))),
                          child: Text(
                              d.toString().length > 80
                                  ? '${d.toString().substring(0, 80)}...'
                                  : d.toString(),
                              style: const TextStyle(
                                  color: Color(0xFFFF6B61),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3)),
                        ))
                    .toList(growable: false),
              ),
            ],
            if (s['stats_resumo'] != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                      child: _statResumo(
                          'Cantos C/F',
                          '${s['stats_resumo']['escanteios_casa'] ?? '-'} / ${s['stats_resumo']['escanteios_fora'] ?? '-'}',
                          const Color(0xFFCE93D8))),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _statResumo(
                          'Chutes AG C/F',
                          '${s['stats_resumo']['chutes_gol_casa'] ?? '-'} / ${s['stats_resumo']['chutes_gol_fora'] ?? '-'}',
                          const Color(0xFF80DEEA))),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _statResumo(
                          'Posse',
                          '${s['stats_resumo']['posse_casa'] ?? '-'}',
                          AppTheme.neonGreen)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statResumo(String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
          color: const Color(0xFF0E1B21),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppTheme.flashLine)),
      child: Column(
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  color: AppTheme.flashSub,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(valor,
              style: TextStyle(
                  color: cor, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _miniPill(IconData icone, String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
          color: cor.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icone, size: 11, color: cor),
          const SizedBox(width: 4),
          Text(texto,
              style: TextStyle(
                  color: cor, fontWeight: FontWeight.w800, fontSize: 11)),
        ],
      ),
    );
  }

  String? _fmtData(String? iso) {
    if (iso == null || iso.length < 16) return null;
    try {
      final DateTime d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.substring(0, 16).replaceFirst('T', ' · ');
    }
  }
}

class _AvisoOrigemGerador extends StatelessWidget {
  final String origem;
  const _AvisoOrigemGerador({required this.origem});

  @override
  Widget build(BuildContext context) {
    final Color cor = origem.contains('RAPIDAPI')
        ? const Color(0xFF1FB453)
        : origem.contains('MISTO')
            ? const Color(0xFFFF9800)
            : const Color(0xFFFF3B30);
    final String title = origem == 'RAPIDAPI_REAL'
        ? 'Bilhetes com Jogos Oficiais · API-Football'
        : origem == 'MISTO_RAPIDAPI_MAIS_FALLBACK'
            ? '⚠️ Bilhete Misto (API + Simulados)'
            : origem == 'FALLBACK_VAZIO'
                ? '⛔ Sem Conexão (Offline)'
                : '🔁 Modo Offline · Bilhetes com Seed Dinâmico';
    final String subtitle = origem == 'RAPIDAPI_REAL'
        ? '100% dos confrontos, odds e linhas de escanteio vieram da API oficial.'
        : origem == 'MISTO_RAPIDAPI_MAIS_FALLBACK'
            ? 'Algumas partidas foram simuladas localmente. Verifique confrontos no book antes de apostar.'
            : origem == 'FALLBACK_VAZIO'
                ? 'Verifique sua conexão e clique em 🔄 Regerar bilhetes.'
                : 'Jogos gerados automaticamente por horário e seed do dia (times 25/26 atualizados · 40+ ligas, diferente a cada dia). Para jogos reais do dia, tente novamente mais tarde.';
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
          Icon(
            origem == 'RAPIDAPI_REAL'
                ? Icons.verified
                : origem == 'MISTO_RAPIDAPI_MAIS_FALLBACK'
                    ? Icons.warning_amber
                    : Icons.cloud_off_rounded,
            color: cor,
            size: 20,
          ),
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
