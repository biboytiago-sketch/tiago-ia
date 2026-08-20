import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/backend_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class CryptoMacroScreen extends StatefulWidget {
  const CryptoMacroScreen({super.key});

  @override
  State<CryptoMacroScreen> createState() => _CryptoMacroScreenState();
}

class _CryptoMacroScreenState extends State<CryptoMacroScreen> {
  final ApiService _api = ApiService();
  final List<String> _todosAtivos = <String>['BTC', 'AAVE', 'IOTA'];
  final Map<String, bool> _selecionados = <String, bool>{
    'BTC': true,
    'AAVE': true,
    'IOTA': true,
  };
  double _valorAporte = 1000.0;
  int _horizonteDias = 7;
  bool _loading = false;
  Map<String, dynamic> _resultado = const <String, dynamic>{};
  final TextEditingController _aporteCtrl = TextEditingController(text: '1000');

  @override
  void dispose() {
    _aporteCtrl.dispose();
    super.dispose();
  }

  List<String> get _ativosSelecionados => _selecionados.entries
      .where((MapEntry<String, bool> e) => e.value)
      .map((MapEntry<String, bool> e) => e.key)
      .toList();

  Future<void> _analisar() async {
    if (_ativosSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione pelo menos 1 ativo.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.flashLiveRed,
      ));
      return;
    }
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> r = await _api.postCryptoAnalyze(
        userId: 'default',
        ativos: _ativosSelecionados,
        horizonteDias: _horizonteDias,
        valorAporteUsd: _valorAporte,
      );
      if (!mounted) return;
      setState(() {
        _resultado = r;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _textoRelatorio() {
    if (_resultado.isEmpty) return '';
    final StringBuffer sb = StringBuffer();
    sb.writeln('🌐 ANÁLISE CENÁRIO MACRO CRIPTO');
    sb.writeln('================================');
    final String perfil =
        BackendConfig.safeMap(_resultado['perfil_risco_usuario'])['perfil']
                ?.toString() ??
            'Moderado';
    final Map<String, dynamic> fg =
        BackendConfig.safeMap(_resultado['fear_and_greed_global']);
    sb.writeln('Perfil: $perfil · Horizonte: $_horizonteDias dias');
    sb.writeln('Fear & Greed: ${fg['indice']} · ${fg['rotulo']}');
    sb.writeln('Aporte: \$${_valorAporte.toStringAsFixed(2)}');
    sb.writeln('');
    final List<dynamic> ativos =
        BackendConfig.safeList(_resultado['analises_ativos']);
    for (dynamic a in ativos) {
      final Map<String, dynamic> am = BackendConfig.safeMap(a);
      sb.writeln(
          '\n=== ${am['nome']} (${am['simbolo']}) @ \$${BackendConfig.safeDouble(am['preco_atual_usd']).toStringAsFixed(2)} ===');
      sb.writeln(
          'STATUS: ${am['status']} · Score ${BackendConfig.safeDouble(am['score_sinal_0_100']).toStringAsFixed(1)}');
      sb.writeln(
          'Entrada: \$${BackendConfig.safeDouble(am['ponto_entrada_sugerido_usd']).toStringAsFixed(2)}');
      sb.writeln(
          'Stop Loss: \$${BackendConfig.safeDouble(am['stop_loss_usd']).toStringAsFixed(2)}');
      sb.writeln(
          'Take Profit: \$${BackendConfig.safeDouble(am['take_profit_usd']).toStringAsFixed(2)}');
      sb.writeln(
          'Risco/Retorno: 1:${BackendConfig.safeDouble(am['razao_risco_retorno']).toStringAsFixed(1)}');
      sb.writeln(
          'Alocação: ${BackendConfig.safeDouble(am['alocacao_sugerida_pct']).toStringAsFixed(0)}% · \$${BackendConfig.safeDouble(am['valor_alocado_aporte_usd']).toStringAsFixed(2)}');
    }
    return sb.toString();
  }

  Future<void> _copiar() async {
    final String t = _textoRelatorio();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('📋 Dados copiados!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.neonGreen,
      ));
    }
  }

  Future<void> _whatsapp() async {
    final String t = _textoRelatorio();
    if (t.isEmpty) return;
    final Uri url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(t)}');
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
            Icon(Icons.candlestick_chart_rounded,
                color: Color(0xffef5350), size: 24),
            SizedBox(width: 10),
            Text('Crypto Macro • BTC / AAVE / IOTA',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          child: Column(
            children: <Widget>[
              _buildPainelControles(),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xffef5350))),
                              SizedBox(height: 12),
                              Text('Analisando cenário mundial...',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      )
                    : _resultado.isEmpty
                        ? _empty()
                        : _buildResultado(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: const Color(0xffef5350).withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            const Color(0xffef5350).withValues(alpha: 0.35))),
                child: const Icon(Icons.public_rounded,
                    color: Color(0xffef5350), size: 44)),
            const SizedBox(height: 18),
            const Text('Clique em "Analisar Cenário Mundial"',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'Serão analisados: Geopolítica, Notícias Globais, Técnico On-Chain e Ecossistema de cada ativo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _buildPainelControles() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff121f29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 1.1),
      ),
      child: Column(
        children: <Widget>[
          Row(
              children: _todosAtivos
                  .map<Widget>((String a) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              left: a == 'BTC' ? 0 : 6,
                              right: a == 'IOTA' ? 0 : 6),
                          child: _AtivoChip(
                            nome: a,
                            selecionado: _selecionados[a] ?? false,
                            onTap: () => setState(() => _selecionados[a] =
                                !(_selecionados[a] ?? false)),
                          ),
                        ),
                      ))
                  .toList(growable: false)),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _aporteCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  labelText: 'Aporte (USDT \$)',
                  labelStyle: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                  prefixText: '\$ ',
                  isDense: true,
                ),
                onChanged: (String v) {
                  _valorAporte = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                value: _horizonteDias,
                dropdownColor: const Color(0xff121f29),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  labelText: 'Horizonte',
                  labelStyle: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                  isDense: true,
                ),
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem<int>(value: 1, child: Text('1 dia')),
                  DropdownMenuItem<int>(value: 7, child: Text('7 dias')),
                  DropdownMenuItem<int>(value: 30, child: Text('30 dias')),
                  DropdownMenuItem<int>(value: 90, child: Text('90 dias')),
                ],
                onChanged: (int? v) => setState(() => _horizonteDias = v ?? 7),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading || _resultado.isEmpty ? null : _copiar,
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xff00e676),
                    side:
                        const BorderSide(color: Color(0xff00e676), width: 1.2),
                    backgroundColor:
                        const Color(0xff00e676).withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('Copiar Dados',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading || _resultado.isEmpty ? null : _whatsapp,
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xff25d366),
                    side:
                        const BorderSide(color: Color(0xff25d366), width: 1.2),
                    backgroundColor:
                        const Color(0xff25d366).withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.chat_bubble_rounded, size: 17),
                label: const Text('WhatsApp',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _analisar,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffef5350),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.psychology_alt_rounded, size: 18),
                label: const Text('Analisar Cenário',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildResultado() {
    final List<dynamic> ativos =
        BackendConfig.safeList(_resultado['analises_ativos']);
    final Map<String, dynamic> fg =
        BackendConfig.safeMap(_resultado['fear_and_greed_global']);
    final Map<String, dynamic> macro =
        BackendConfig.safeMap(_resultado['macro_geopolitico']);
    final Map<String, dynamic> carteira =
        BackendConfig.safeMap(_resultado['recomendacao_geral_carteira']);
    return ListView(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: const Color(0xff111d27),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white10, width: 1)),
          child: Column(children: <Widget>[
            Row(children: <Widget>[
              _pill(
                  'Perfil: ${(BackendConfig.safeMap(_resultado['perfil_risco_usuario'])['perfil']?.toString() ?? '--')}',
                  const Color(0xff9c27b0)),
              const SizedBox(width: 7),
              _pill('F&G: ${fg['indice'] ?? '--'} · ${fg['rotulo'] ?? '--'}',
                  const Color(0xffffc107)),
            ]),
            if (macro.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              Text('🌍 ${macro['resumo_geral']?.toString() ?? ''}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700)),
            ],
            if (carteira.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xff9c27b0).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              const Color(0xff9c27b0).withValues(alpha: 0.45))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('💼 Alocação Sugerida Carteira',
                            style: TextStyle(
                                color: Color(0xffce93d8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Text(carteira['estrategia']?.toString() ?? '',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.4,
                                fontWeight: FontWeight.w700)),
                      ])),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        for (dynamic a in ativos) ...<Widget>[
          _AtivoAnaliseCard(ativo: BackendConfig.safeMap(a)),
          const SizedBox(height: 11),
        ],
      ],
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withValues(alpha: 0.5))),
        child: Text(t,
            style: TextStyle(
                color: c, fontSize: 10.5, fontWeight: FontWeight.w900)),
      );
}

class _AtivoChip extends StatelessWidget {
  final String nome;
  final bool selecionado;
  final VoidCallback onTap;
  const _AtivoChip(
      {required this.nome, required this.selecionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color cor = selecionado
        ? (nome == 'BTC'
            ? const Color(0xfff7931a)
            : nome == 'AAVE'
                ? const Color(0xffb6509e)
                : const Color(0xff00e676))
        : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
            color: selecionado
                ? cor.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color:
                    selecionado ? cor.withValues(alpha: 0.6) : Colors.white12,
                width: 1.15)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.currency_bitcoin_rounded, color: cor, size: 16),
            const SizedBox(width: 7),
            Text(nome,
                style: TextStyle(
                    color: selecionado ? cor : Colors.white60,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _AtivoAnaliseCard extends StatelessWidget {
  final Map<String, dynamic> ativo;
  const _AtivoAnaliseCard({required this.ativo});

  static Color corStatus(String s) {
    if (s.contains('COMPRAR')) return const Color(0xff00e676);
    if (s.contains('VENDER')) return const Color(0xffef5350);
    return const Color(0xffffc107);
  }

  @override
  Widget build(BuildContext context) {
    final String simbolo = ativo['simbolo']?.toString() ?? '?';
    final String nome = ativo['nome']?.toString() ?? simbolo;
    final double preco = ativo['preco_atual_usd']?.toDouble() ?? 0;
    final String status = ativo['status']?.toString() ?? '--';
    final double score = ativo['score_sinal_0_100']?.toDouble() ?? 0;
    final Color cor = corStatus(status);
    final double entrada = ativo['ponto_entrada_sugerido_usd']?.toDouble() ?? 0;
    final double sl = ativo['stop_loss_usd']?.toDouble() ?? 0;
    final double tp = ativo['take_profit_usd']?.toDouble() ?? 0;
    final double rr = ativo['razao_risco_retorno']?.toDouble() ?? 0;
    final double alocPct = ativo['alocacao_sugerida_pct']?.toDouble() ?? 0;
    final double alocUsd = ativo['valor_alocado_aporte_usd']?.toDouble() ?? 0;
    final Map<String, dynamic> pilares =
        BackendConfig.safeMap(ativo['pilares']);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xff121f29),
            cor.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: cor.withValues(alpha: 0.5), width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: cor.withValues(alpha: 0.12),
              blurRadius: 14,
              spreadRadius: 0.5),
        ],
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.10),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(17)),
              border: Border(
                  bottom:
                      BorderSide(color: cor.withValues(alpha: 0.35), width: 1)),
            ),
            child: Row(children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(8.5),
                  decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cor.withValues(alpha: 0.5))),
                  child: Icon(
                      simbolo == 'BTC'
                          ? Icons.currency_bitcoin_rounded
                          : simbolo == 'AAVE'
                              ? Icons.account_balance_rounded
                              : Icons.hub_rounded,
                      color: cor,
                      size: 21)),
              const SizedBox(width: 11),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Row(children: <Widget>[
                      Text('$nome ($simbolo)',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900)),
                      const Spacer(),
                      Text('\$${preco.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: <Widget>[
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: cor.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: cor.withValues(alpha: 0.6))),
                          child: Text(status,
                              style: TextStyle(
                                  color: cor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900))),
                      const SizedBox(width: 6),
                      Text('Score ${score.toStringAsFixed(1)}/100',
                          style: TextStyle(
                              color: cor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                    ]),
                  ])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 4),
            child: Column(
              children: <Widget>[
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
                        width: (MediaQuery.of(context).size.width - 82) *
                            (score / 100.0),
                        decoration: BoxDecoration(
                            color: cor,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                  color: cor.withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  spreadRadius: 0.5),
                            ])),
                  ]),
                ),
                const SizedBox(height: 11),
                Row(children: <Widget>[
                  Expanded(
                      child: _kv('Entrada', '\$${entrada.toStringAsFixed(2)}',
                          const Color(0xff00e676))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _kv('Stop Loss', '\$${sl.toStringAsFixed(2)}',
                          const Color(0xffef5350))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _kv('Take Profit', '\$${tp.toStringAsFixed(2)}',
                          const Color(0xffffc107))),
                ]),
                const SizedBox(height: 8),
                Row(children: <Widget>[
                  _pill('R:R 1:${rr.toStringAsFixed(1)}', cor),
                  const SizedBox(width: 7),
                  _pill(
                      '${alocPct.toStringAsFixed(0)}% · \$${alocUsd.toStringAsFixed(0)}',
                      const Color(0xff9c27b0)),
                ]),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(color: Colors.white10, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 13),
            child: Column(
              children: <Widget>[
                _PilarTile(
                  icone: Icons.public_rounded,
                  titulo: '🌍 Geopolítica & Macroeconomia',
                  texto: pilares['geopolitica_macro']?.toString() ?? '--',
                  cor: const Color(0xff9c27b0),
                ),
                const SizedBox(height: 8),
                _PilarTile(
                  icone: Icons.newspaper_rounded,
                  titulo: '📰 Notícias & Sentimento Global',
                  texto:
                      pilares['noticias_sentimento_global']?.toString() ?? '--',
                  cor: const Color(0xffffc107),
                ),
                const SizedBox(height: 8),
                _PilarTile(
                  icone: Icons.insights_rounded,
                  titulo: '📊 Análise Técnica & On-Chain',
                  texto: pilares['analise_tecnica_onchain']?.toString() ?? '--',
                  cor: const Color(0xff00e676),
                ),
                const SizedBox(height: 8),
                _PilarTile(
                  icone: Icons.hub_rounded,
                  titulo: '🔗 Ecossistema & Desenvolvimentos',
                  texto: pilares['ecossistema_desenvolvimentos']?.toString() ??
                      '--',
                  cor: const Color(0xffef5350),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, Color c) => Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.35))),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(k,
                style: TextStyle(
                    color: c.withValues(alpha: 0.9),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(v,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ]));

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withValues(alpha: 0.45))),
        child: Text(t,
            style: TextStyle(
                color: c, fontSize: 10.5, fontWeight: FontWeight.w900)),
      );
}

class _PilarTile extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String texto;
  final Color cor;
  const _PilarTile(
      {required this.icone,
      required this.titulo,
      required this.texto,
      required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: cor.withValues(alpha: 0.30))),
      child:
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Container(
            padding: const EdgeInsets.all(7.5),
            decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, color: cor, size: 16)),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
              Text(titulo,
                  style: TextStyle(
                      color: cor, fontSize: 11, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(texto,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      height: 1.4,
                      fontWeight: FontWeight.w600)),
            ])),
      ]),
    );
  }
}
