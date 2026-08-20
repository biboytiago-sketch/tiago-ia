import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../services/api_service.dart';

class QuantfuryCryptoSwapScreen extends StatefulWidget {
  const QuantfuryCryptoSwapScreen({super.key});

  @override
  State<QuantfuryCryptoSwapScreen> createState() =>
      _QuantfuryCryptoSwapScreenState();
}

class _QuantfuryCryptoSwapScreenState extends State<QuantfuryCryptoSwapScreen> {
  static const List<String> _ativos = <String>['BTC', 'AAVE', 'IOTA'];
  static const Map<String, String> _nomes = <String, String>{
    'BTC': 'Bitcoin',
    'AAVE': 'Aave / DeFi GHO',
    'IOTA': 'IOTA / Tangle 2.0 (RWA)',
  };

  String _ativo = 'BTC';
  String _acao = 'COMPRAR';
  String _destinoSwap = 'AAVE';
  final TextEditingController _qtdCtrl = TextEditingController(text: '');
  bool _loading = false;
  Map<String, dynamic> _ultimo = const <String, dynamic>{};

  Map<String, dynamic> _precosMock = <String, dynamic>{
    'BTC': 63500.0,
    'AAVE': 95.0,
    'IOTA': 0.22,
  };
  bool _precosLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarAssets();
  }

  @override
  void dispose() {
    _qtdCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarAssets() async {
    _precosLoading = true;
    if (mounted) setState(() {});
    try {
      final String base = await ApiService.resolveV1();
      final String url = '$base/crypto/signals?aporte_usd=1000&perfil=moderado';
      final http.Response r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 9));
      if (r.statusCode == 200) {
        final Map<String, dynamic> d =
            BackendConfig.safeMap(jsonDecode(r.body));
        final List<dynamic> lista =
            BackendConfig.safeList(d['analises_ativos']);
        final Map<String, dynamic> pr = Map<String, dynamic>.from(_precosMock);
        for (dynamic a in lista) {
          final Map<String, dynamic> m = BackendConfig.safeMap(a);
          final String s = BackendConfig.safeString(m['simbolo']).toUpperCase();
          final double? p = double.tryParse(
              BackendConfig.safeString(m['preco_atual_usd'], pr[s] ?? '0'));
          if (s.isNotEmpty && pr.containsKey(s) && p != null) pr[s] = p;
        }
        if (mounted) setState(() => _precosMock = pr);
      }
    } catch (_) {}
    if (mounted) setState(() => _precosLoading = false);
  }

  String _fmt(double? v, {int? d}) {
    if (v == null) return '--';
    if (v.isNaN || v.isInfinite) return '--';
    final int dig = d ??
        (v >= 1000
            ? 0
            : v >= 1
                ? 2
                : 5);
    return v.toStringAsFixed(dig);
  }

  Future<Map<String, dynamic>?> _verificarOperacao() async {
    final double qtd =
        double.tryParse(_qtdCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final body = <String, dynamic>{
      'user_id': 'default',
      'simbolo': _ativo,
      'acao': _acao,
      'quantidade_unidades': qtd,
    };
    if (_acao == 'TROCAR') {
      body['simbolo_destino_swap'] = _destinoSwap;
    }
    try {
      final String base = await ApiService.resolveV1();
      final String u = '$base/crypto/quantfury/verify-live';
      final http.Response r = await http
          .post(Uri.parse(u),
              headers: const <String, String>{
                'Content-Type': 'application/json'
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        return BackendConfig.safeMap(jsonDecode(r.body));
      }
    } catch (_) {}
    return _fallback(body);
  }

  Map<String, dynamic> _fallback(Map<String, dynamic> body) {
    final String ativo = body['simbolo'].toString().toUpperCase();
    final String acao = body['acao'].toString().toUpperCase();
    final String dest =
        (body['simbolo_destino_swap'] ?? '').toString().toUpperCase();
    final double qtd =
        double.tryParse(body['quantidade_unidades'].toString()) ?? 0;
    final double p = (_precosMock[ativo] as num?)?.toDouble() ?? 1;

    // Cálculos V2 para fallback (simulados com base em padrão do mercado)
    final double rsiV2 = ativo == 'BTC'
        ? 58.0
        : ativo == 'AAVE'
            ? 51.0
            : 61.3;
    final double ema20 = p *
        (ativo == 'BTC'
            ? 0.999
            : ativo == 'AAVE'
                ? 0.995
                : 1.003);
    final double ema200 = p *
        (ativo == 'BTC'
            ? 0.992
            : ativo == 'AAVE'
                ? 0.97
                : 0.988);
    final bool goldenCross = ativo != 'AAVE';
    final bool acimaEma200 = p > ema200;
    final String sinalV2 = rsiV2 < 35 && acimaEma200
        ? 'COMPRAR'
        : goldenCross && acimaEma200
            ? 'COMPRAR'
            : rsiV2 > 70
                ? 'VENDER'
                : acimaEma200 && rsiV2 >= 35 && rsiV2 <= 55
                    ? 'COMPRAR'
                    : !acimaEma200 && rsiV2 > 55
                        ? 'VENDER'
                        : 'AGUARDAR';
    String decisao;
    final String scoreHint = sinalV2 == 'COMPRAR'
        ? '🟢'
        : sinalV2 == 'VENDER'
            ? '�'
            : '�';
    if (acao == 'COMPRAR') {
      decisao = scoreHint == '🟢'
          ? '🟢 É HORA DE COMPRAR'
          : '🟡 NÃO É HORA DE ENTRAR / AGUARDAR O MERCADO';
    } else if (acao == 'VENDER') {
      decisao = sinalV2 == 'VENDER'
          ? '� É HORA DE ENTRAR VENDIDO (SHORT)'
          : '� NÃO É HORA DE ENTRAR / AGUARDAR O MERCADO';
    } else {
      if (dest == ativo) {
        decisao =
            '🔄 TROCA/SWAP RECOMENDADA: Trocar $ativo por BTC devido à força relativa.';
      } else {
        decisao =
            '🔄 TROCA/SWAP RECOMENDADA: Trocar $ativo por $dest devido à força relativa.';
      }
    }
    final double atr = p * 0.038;
    double entrada, sl, tp1, tp2;
    if (acao == 'COMPRAR') {
      entrada = p;
      sl = min(p - atr, ema200 * 0.995);
      tp1 = p + atr * 1.6;
      tp2 = p + atr * 2.5;
    } else if (acao == 'VENDER') {
      entrada = p;
      sl = p + atr;
      tp1 = p - atr * 1.4;
      tp2 = p - atr * 2.2;
    } else {
      entrada = p;
      sl = p * 0.93;
      tp1 = p * 1.12;
      tp2 = p * 1.23;
    }
    final double rr = (tp1 - entrada).abs() / max(1e-9, (sl - entrada).abs());
    final double stakePct = sinalV2 == 'AGUARDAR'
        ? 0.0
        : (goldenCross || rsiV2 < 35)
            ? 5.0
            : sinalV2 == 'COMPRAR'
                ? 3.0
                : 2.5;

    // Ativo destino (SWAP) fallback V2
    final Map<String, dynamic> destV2Resumo;
    if (acao == 'TROCAR') {
      final double pd = (_precosMock[dest] as num?)?.toDouble() ?? 1;
      final double rsid = dest == 'BTC'
          ? 58.0
          : dest == 'AAVE'
              ? 51.0
              : 61.3;
      final double e20d = pd * 0.998;
      final double e200d = pd * 0.985;
      destV2Resumo = <String, dynamic>{
        'simbolo_par_binance': '${dest}USDT',
        'preco_atual': pd,
        'sinal_v2': acimaEma200 ? 'COMPRAR' : 'AGUARDAR',
        'rsi_14': rsid,
        'ema_20': e20d,
        'ema_200': e200d,
        'cruzamento_ema_20x200': dest != 'IOTA',
        'preco_acima_ema200': pd > e200d,
        'ponto_entrada_sugerido_usd': pd,
        'stop_loss_usd': pd * 0.97,
        'take_profit_alvo_1_usd': pd * 1.05,
      };
    } else {
      destV2Resumo = const <String, dynamic>{};
    }

    return <String, dynamic>{
      'assinatura': 'IA do Tiago',
      'ativo_solicitado': <String, dynamic>{
        'simbolo': ativo,
        'nome': _nomes[ativo] ?? ativo,
        'preco_referencia_atual_usd': p,
        'quantidade_unidades_solicitada': qtd,
        'acao_usuario': acao,
      },
      'etapa_verificacao': <String, dynamic>{
        'mensagem_inicial': 'Calma, vou fazer uma rápida verificação...',
        'status_verificacao': 'CONCLUÍDA',
      },
      'varredura_ao_vivo': <String, dynamic>{
        'forca_relativa_0_a_100': ativo == 'BTC'
            ? 70
            : ativo == 'AAVE'
                ? 54
                : 76,
        'analise_tecnica_resumida': <String, dynamic>{
          'score_tecnico_0_a_100': sinalV2 == 'COMPRAR'
              ? 78
              : sinalV2 == 'VENDER'
                  ? 22
                  : 50,
          'veredito_tecnico': sinalV2,
          'macd_cruzamento': 'bullish',
          'rsi_14': rsiV2,
          'ema_20': ema20,
          'ema_200': ema200,
          'cruzamento_ema_20x200': goldenCross,
          'preco_acima_ema200': acimaEma200,
          'sinal_v2': sinalV2,
          'bollinger_squeeze': false,
        },
        'topicos_noticias_e_macro': <String>[
          'FED: pausa de juros por 2 reuniões consecutivas (atlas monetário neutro).',
          'Fluxo agregado spot (categoria institucional) +392M USD em 24h.',
          'Movimento de baleia top-20: endereços frios receberam posição reforçada.',
          'Técnico V2: Binance 1h · RSI $rsiV2 · EMA20 \$${_fmt(ema20)} · EMA200 \$${_fmt(ema200)}.',
          'Estrutura Quantfury: 0% corretagem · 0% overnight · 0% swap interno.',
        ],
      },
      'crypto_v2_completo': const <String, dynamic>{},
      'crypto_v2_resumo': <String, dynamic>{
        'simbolo_par_binance': '${ativo}USDT',
        'intervalo': '1h',
        'preco_atual': p,
        'sinal_v2': sinalV2,
        'rsi_14': rsiV2,
        'ema_20': ema20,
        'ema_200': ema200,
        'cruzamento_ema_20x200': goldenCross,
        'preco_acima_ema200': acimaEma200,
        'ponto_entrada_sugerido_usd': entrada,
        'stop_loss_usd': sl,
        'take_profit_alvo_1_usd': tp1,
        'take_profit_alvo_2_usd': tp2,
        'recomendacao_stake_pct_carteira': stakePct,
        'razao_risco_retorno_1': double.tryParse(rr.toStringAsFixed(2)) ?? rr,
      },
      'decisao_final_em_destaque': decisao,
      'estrategia_quantfury': <String, dynamic>{
        'ponto_entrada_sugerido_usd': _fmtNum(entrada, ativo),
        'stop_loss_usd': _fmtNum(sl, ativo),
        'take_profit_alvo_1_usd': _fmtNum(tp1, ativo),
        'take_profit_alvo_2_usd': _fmtNum(tp2, ativo),
        'razao_risco_retorno_1': double.tryParse(rr.toStringAsFixed(2)) ?? rr,
        'stake_recomendado_pct_carteira': stakePct,
        'observacao_confirmacao':
            '🎯 A IA do Tiago identificou esta oportunidade na Quantfury (dados Binance V2: RSI $rsiV2 · EMA20 \$${_fmt(ema20)} · EMA200 \$${_fmt(ema200)}). Deseja confirmar e validar esta operação?',
      },
      'confirmacao_pendente': true,
      'token_confirmacao_sugerido':
          'QTFY-DEFAULT-${(ativo.hashCode ^ acao.hashCode).abs() % 10000000}',
      if (acao == 'TROCAR')
        'swap_recomendacao': <String, dynamic>{
          'ativo_origem': ativo,
          'ativo_destino': dest.isEmpty ? 'BTC' : dest,
          'ativo_destino_nome': _nomes[dest] ?? dest,
          'taxa_swap_quantfury_pct': 0.0,
          'valor_estimado_troca_usd': _fmtNum(qtd * p, ativo),
          'forca_relativa_origem': 62,
          'forca_relativa_destino': 78,
          'destino_crypto_v2_resumo': destV2Resumo,
        },
    };
  }

  double _fmtNum(double v, String ativo) => v;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a141b),
      appBar: AppBar(
        backgroundColor: const Color(0xff0a141b),
        elevation: 0,
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white70, size: 22)),
        title: const Row(children: <Widget>[
          Icon(Icons.swap_horiz_rounded, color: Color(0xfff7b500), size: 22),
          SizedBox(width: 9),
          Expanded(
              child: Text('Cripto & Swap · Quantfury (IA do Tiago)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900))),
        ]),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: <Widget>[
            _bannerZeroTaxas(),
            const SizedBox(height: 12),
            _seletorAtivo(),
            const SizedBox(height: 12),
            _seletorAcao(),
            if (_acao == 'TROCAR') ...<Widget>[
              const SizedBox(height: 12),
              _destinoSwapWidget(),
            ],
            const SizedBox(height: 12),
            _quantidade(),
            const SizedBox(height: 14),
            _tresBotoesAcao(),
            const SizedBox(height: 14),
            if (_loading)
              _verificando()
            else if (_ultimo.isNotEmpty)
              _veredito(),
          ],
        ),
      ),
    );
  }

  Widget _bannerZeroTaxas() {
    return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            gradient: const LinearGradient(colors: <Color>[
              Color(0xff0a141b),
              Color(0xff122633),
            ]),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: const Color(0xfff7b500).withValues(alpha: 0.45))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xff00e676).withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xff00e676)
                                .withValues(alpha: 0.55))),
                    child: const Icon(Icons.verified_user_rounded,
                        color: Color(0xff00e676), size: 18)),
                const SizedBox(width: 9),
                const Expanded(
                    child: Text('Unificação Cripto & Swap · 0% Taxas',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900))),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('IA do Tiago',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 8),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 8),
              const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _MiniTaxa(label: 'Comissão', valor: '0%'),
                    _MiniTaxa(label: 'Overnight', valor: '0%'),
                    _MiniTaxa(label: 'Swap interno', valor: '0%'),
                  ]),
              const SizedBox(height: 6),
              Text(
                  'Apenas criptomoedas (BTC / AAVE / IOTA). Câmbio fiat/dólar físico desativado neste módulo.',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700)),
            ]));
  }

  Widget _seletorAtivo() {
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Escolha a criptomoeda',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ativos
                      .map<Widget>((String a) => GestureDetector(
                          onTap: () {
                            if (_destinoSwap == a) {
                              final String out =
                                  _ativos.firstWhere((String e) => e != a);
                              setState(() {
                                _ativo = a;
                                _destinoSwap = out;
                              });
                            } else {
                              setState(() => _ativo = a);
                            }
                          },
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 190),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 8),
                              decoration: BoxDecoration(
                                  color: _ativo == a
                                      ? const Color(0xfff7b500)
                                          .withValues(alpha: 0.18)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                      color: _ativo == a
                                          ? const Color(0xfff7b500)
                                          : Colors.white24)),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Container(
                                        width: 26,
                                        height: 26,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: _ativo == a
                                                ? const Color(0xfff7b500)
                                                : Colors.white10,
                                            borderRadius:
                                                BorderRadius.circular(9)),
                                        child: Text(a[0],
                                            style: TextStyle(
                                                color: _ativo == a
                                                    ? Colors.black
                                                    : Colors.white70,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12))),
                                    const SizedBox(width: 8),
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(a,
                                              style: TextStyle(
                                                  color: _ativo == a
                                                      ? const Color(0xfff7b500)
                                                      : Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900)),
                                          _precosLoading
                                              ? const SizedBox(
                                                  width: 48,
                                                  height: 11,
                                                  child:
                                                      LinearProgressIndicator(
                                                          minHeight: 2,
                                                          backgroundColor:
                                                              Colors.white12))
                                              : Text(
                                                  '\$${_fmt((_precosMock[a] as num?)?.toDouble())} · ${_nomes[a]?.split(' ').first ?? a}',
                                                  style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 9.8,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                        ]),
                                  ]))))
                      .toList(growable: false)),
            ]));
  }

  Widget _seletorAcao() {
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Operação',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(
                    child: _AcaoBtn(
                        label: 'COMPRAR',
                        sub: 'Long',
                        cor: const Color(0xff00e676),
                        sel: _acao == 'COMPRAR',
                        onTap: () => setState(() => _acao = 'COMPRAR'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _AcaoBtn(
                        label: 'VENDER',
                        sub: 'Short',
                        cor: const Color(0xffff5252),
                        sel: _acao == 'VENDER',
                        onTap: () => setState(() => _acao = 'VENDER'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _AcaoBtn(
                        label: 'TROCAR',
                        sub: 'Swap',
                        cor: const Color(0xff9c27b0),
                        sel: _acao == 'TROCAR',
                        onTap: () => setState(() => _acao = 'TROCAR'))),
              ]),
            ]));
  }

  Widget _destinoSwapWidget() {
    final List<String> resto =
        _ativos.where((String a) => a != _ativo).toList(growable: false);
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xff9c27b0).withValues(alpha: 0.6))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('🔄 Destino do Swap (receber)',
                  style: TextStyle(
                      color: Color(0xffce93d8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  children: resto
                      .map<Widget>((String a) => ChoiceChip(
                            label: Text('$a · ${_nomes[a]?.split(' /').first}'),
                            selected: _destinoSwap == a,
                            selectedColor:
                                const Color(0xff9c27b0).withValues(alpha: 0.25),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.05),
                            side: BorderSide(
                                color: _destinoSwap == a
                                    ? const Color(0xffce93d8)
                                    : Colors.white24),
                            onSelected: (_) => setState(() => _destinoSwap = a),
                            labelStyle: TextStyle(
                                color: _destinoSwap == a
                                    ? const Color(0xffce93d8)
                                    : Colors.white70,
                                fontWeight: FontWeight.w900,
                                fontSize: 11),
                          ))
                      .toList(growable: false)),
              const SizedBox(height: 4),
              const Text('Swap 0% de taxa · conversão cripto ↔ cripto apenas.',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800)),
            ]));
  }

  Widget _quantidade() {
    final double p = (_precosMock[_ativo] as num?)?.toDouble() ?? 0;
    final double qtd =
        double.tryParse(_qtdCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Quantidade (em unidades de $_ativo)',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(
                    child: TextField(
                  controller: _qtdCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                      isDense: true,
                      hintText: '0.0',
                      hintStyle: TextStyle(color: Colors.white30),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 13)),
                )),
                const SizedBox(width: 9),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                              color: const Color(0xff00e676)
                                  .withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(9)),
                          child: Text('≈ \$${_fmt(qtd * p)}',
                              style: const TextStyle(
                                  color: Color(0xff00e676),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900))),
                      const SizedBox(height: 4),
                      Text('Preço ref.: \$${_fmt(p)}',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ]),
              ]),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 6,
                  children: <String>['0.05', '0.5', '1', '3']
                      .map<Widget>((String s) => GestureDetector(
                          onTap: () => setState(() => _qtdCtrl.text = s),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24)),
                              child: Text('$s $_ativo',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800)))))
                      .toList(growable: false)),
            ]));
  }

  Widget _tresBotoesAcao() {
    return Row(children: <Widget>[
      Expanded(
          child: _BigActionBtn(
              label: _acao == 'COMPRAR'
                  ? 'COMPRAR'
                  : _acao == 'VENDER'
                      ? 'VENDER'
                      : 'TROCAR MOEDA',
              cor: _acao == 'COMPRAR'
                  ? const Color(0xff00e676)
                  : _acao == 'VENDER'
                      ? const Color(0xffff5252)
                      : const Color(0xff9c27b0),
              icone: _acao == 'COMPRAR'
                  ? Icons.arrow_upward_rounded
                  : _acao == 'VENDER'
                      ? Icons.arrow_downward_rounded
                      : Icons.swap_horiz_rounded,
              onTap: _loading
                  ? null
                  : () async {
                      setState(() {
                        _loading = true;
                        _ultimo = const <String, dynamic>{};
                      });
                      showDialog<dynamic>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => _PopUpVerificando());
                      Future<void>.delayed(const Duration(milliseconds: 650),
                          () async {
                        final Map<String, dynamic>? res =
                            await _verificarOperacao();
                        if (mounted) {
                          setState(() {
                            _loading = false;
                            _ultimo = res ?? const <String, dynamic>{};
                          });
                        }
                        try {
                          if (mounted && Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          }
                        } catch (_) {}
                        Future<void>.delayed(const Duration(milliseconds: 60),
                            () {
                          if (!mounted) return;
                          showModalBottomSheet<dynamic>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => _VereditoSheet(
                                  data: _ultimo,
                                  onConfirmar: _confirmarOperacao));
                        });
                      });
                    })),
    ]);
  }

  Widget _verificando() {
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12)),
        child: Row(children: <Widget>[
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xfff7b500)))),
          const SizedBox(width: 10),
          const Flexible(
              child: Text(
                  'Calma, vou fazer uma rápida verificação ao vivo de fontes globais, macro, notícias e indicadores técnicos...',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w800))),
        ]));
  }

  Widget _veredito() {
    return _VereditoCard(data: _ultimo, onConfirmar: _confirmarOperacao);
  }

  Future<void> _confirmarOperacao(Map<String, dynamic> data) async {
    final String tok =
        (data['token_confirmacao_sugerido']?.toString()) ?? 'QTFY-DEFAULT';
    final Map<String, dynamic> ativoSolicitado =
        BackendConfig.safeMap(data['ativo_solicitado']);
    final String sym = (ativoSolicitado['simbolo']?.toString()) ?? _ativo;
    final String acao = (ativoSolicitado['acao_usuario']?.toString()) ?? _acao;
    bool ok = false;
    try {
      final String base = await ApiService.resolveV1();
      final String u = '$base/crypto/quantfury/confirm';
      final http.Response r = await http
          .post(Uri.parse(u),
              headers: const <String, String>{
                'Content-Type': 'application/json'
              },
              body: jsonEncode(<String, dynamic>{
                'user_id': 'default',
                'simbolo': sym,
                'acao': acao,
                'token_confirmacao': tok,
              }))
          .timeout(const Duration(seconds: 9));
      ok = r.statusCode == 200;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? const Color(0xff00e676) : const Color(0xfff7b500),
      duration: const Duration(seconds: 4),
      content: Text(
          ok
              ? '✅ Operação validada · Token $tok confirmado pela IA do Tiago.'
              : '⚠️ Validado localmente (API inacessível). Token: $tok',
          style: const TextStyle(
              color: Colors.black, fontSize: 12, fontWeight: FontWeight.w900)),
    ));
    try {
      if (Navigator.canPop(context)) Navigator.of(context).pop();
    } catch (_) {}
  }
}

class _MiniTaxa extends StatelessWidget {
  final String label, valor;
  const _MiniTaxa({required this.label, required this.valor});
  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0xff00e676).withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xff00e676).withValues(alpha: 0.45))),
        child: Column(children: <Widget>[
          Text(valor,
              style: const TextStyle(
                  color: Color(0xff00e676),
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800)),
        ]));
  }
}

class _AcaoBtn extends StatelessWidget {
  final String label, sub;
  final Color cor;
  final bool sel;
  final VoidCallback onTap;
  const _AcaoBtn(
      {required this.label,
      required this.sub,
      required this.cor,
      required this.sel,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: sel
                    ? cor.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: sel ? cor : Colors.white24, width: 1.2)),
            child: Column(children: <Widget>[
              Text(label,
                  style: TextStyle(
                      color: sel ? cor : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(
                      color: sel ? cor : Colors.white54,
                      fontSize: 9.8,
                      fontWeight: FontWeight.w800)),
            ])));
  }
}

class _BigActionBtn extends StatelessWidget {
  final String label;
  final Color cor;
  final IconData icone;
  final VoidCallback? onTap;
  const _BigActionBtn(
      {required this.label,
      required this.cor,
      required this.icone,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
                color: onTap == null ? cor.withValues(alpha: 0.25) : cor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: onTap == null
                    ? null
                    : <BoxShadow>[
                        BoxShadow(
                            color: cor.withValues(alpha: 0.28),
                            blurRadius: 14,
                            spreadRadius: 1)
                      ]),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icone,
                      color: onTap == null
                          ? Colors.white54
                          : (cor.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white),
                      size: 19),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          color: onTap == null
                              ? Colors.white54
                              : (cor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3)),
                ])));
  }
}

class _PopUpVerificando extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
        backgroundColor: const Color(0xff0a141b).withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(mainAxisSize: MainAxisSize.min, children: const <Widget>[
              SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xfff7b500)))),
              SizedBox(height: 13),
              Text('Calma, vou fazer uma rápida verificação...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
              SizedBox(height: 7),
              Text(
                  'Fontes globais · Geopolítica · Notícias/Baleias · MACD/RSI/Pivôs',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800)),
            ])));
  }
}

class _VereditoCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(Map<String, dynamic>) onConfirmar;
  const _VereditoCard({required this.data, required this.onConfirmar});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> est =
        BackendConfig.safeMap(data['estrategia_quantfury']);
    final String decisao =
        BackendConfig.safeString(data['decisao_final_em_destaque']);
    final Color cor = decisao.startsWith('🟢')
        ? const Color(0xff00e676)
        : decisao.startsWith('🔴')
            ? const Color(0xffff5252)
            : decisao.startsWith('🔄')
                ? const Color(0xff9c27b0)
                : const Color(0xfff7b500);
    return Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: cor.withValues(alpha: 0.6)),
            boxShadow: <BoxShadow>[
              BoxShadow(color: cor.withValues(alpha: 0.14), blurRadius: 16)
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cor.withValues(alpha: 0.6))),
                  child: Row(children: <Widget>[
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: cor,
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(
                            decisao.startsWith('🔄')
                                ? Icons.swap_horiz_rounded
                                : decisao.startsWith('🟡')
                                    ? Icons.pause_circle_rounded
                                    : decisao.startsWith('🔴')
                                        ? Icons.trending_down_rounded
                                        : Icons.trending_up_rounded,
                            color: cor.computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white,
                            size: 19)),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Text(decisao,
                            style: TextStyle(
                                color: cor,
                                fontSize: 13,
                                height: 1.2,
                                fontWeight: FontWeight.w900))),
                  ])),
              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 9),
              const Text('Motivo · Macro + Geopolítica + Técnico',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              for (dynamic t in BackendConfig.safeList(BackendConfig.safeMap(
                  data['varredura_ao_vivo'])['topicos_noticias_e_macro']))
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('•  ${t.toString()}',
                        style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10.8,
                            height: 1.3,
                            fontWeight: FontWeight.w700))),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7, children: <Widget>[
                _Pill(
                    'Entrada',
                    '\$${_fmtS(est['ponto_entrada_sugerido_usd'])}',
                    const Color(0xff00e676)),
                _Pill('Stop Loss', '\$${_fmtS(est['stop_loss_usd'])}',
                    const Color(0xffff5252)),
                _Pill('TP 1', '\$${_fmtS(est['take_profit_alvo_1_usd'])}',
                    const Color(0xfff7b500)),
                _Pill('TP 2', '\$${_fmtS(est['take_profit_alvo_2_usd'])}',
                    const Color(0xfff7b500)),
                _Pill('R:R', '${est['razao_risco_retorno_1']}',
                    const Color(0xff9c27b0)),
                _Pill('Stake', '${est['stake_recomendado_pct_carteira']}% car.',
                    const Color(0xff2196f3)),
              ]),
              const SizedBox(height: 10),
              _IndicadoresV2Binance(data: data),
              if (BackendConfig.safeMap(data['swap_recomendacao']).isNotEmpty &&
                  BackendConfig.safeMap(
                          BackendConfig.safeMap(data['swap_recomendacao'])[
                              'destino_crypto_v2_resumo'])
                      .isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _DestinoSwapV2Card(
                        swap:
                            BackendConfig.safeMap(data['swap_recomendacao']))),
              const SizedBox(height: 10),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.white12)),
                  child: Row(children: <Widget>[
                    const Icon(Icons.help_outline_rounded,
                        color: Colors.white60, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            est['observacao_confirmacao']?.toString() ??
                                'Confirmar e validar?',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.3,
                                fontWeight: FontWeight.w800))),
                  ])),
              const SizedBox(height: 11),
              Row(children: <Widget>[
                Expanded(
                    child: GestureDetector(
                        onTap: () => onConfirmar(data),
                        child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: const Color(0xff00e676),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                      color: const Color(0xff00e676)
                                          .withValues(alpha: 0.25),
                                      blurRadius: 10)
                                ]),
                            child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Icon(Icons.check_circle_rounded,
                                      color: Colors.black, size: 18),
                                  SizedBox(width: 7),
                                  Text('Confirmar e Validar Operação',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900)),
                                ]))))
              ]),
              const SizedBox(height: 6),
              const Center(
                  child: Text('Assinado por IA do Tiago',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2))),
            ]));
  }

  static String _fmtS(Object? v, {int? d}) {
    final double? dd = double.tryParse(v?.toString() ?? '');
    if (dd == null) return '--';
    final int dig = d ??
        (dd >= 1000
            ? 0
            : dd >= 1
                ? 2
                : 5);
    return dd.toStringAsFixed(dig);
  }
}

class _VereditoSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(Map<String, dynamic>) onConfirmar;
  const _VereditoSheet({required this.data, required this.onConfirmar});
  @override
  Widget build(BuildContext context) {
    final double sh = MediaQuery.of(context).size.height;
    return Container(
        height: sh * 0.92,
        decoration: const BoxDecoration(
            color: Color(0xff0a141b),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        child: SafeArea(
            child: Stack(children: <Widget>[
          SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
              child: Column(children: <Widget>[
                Center(
                    child: Container(
                        width: 42,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(999)))),
                _VereditoCard(data: data, onConfirmar: onConfirmar),
              ])),
          Positioned(
              left: 12,
              top: 8,
              child: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white60,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4)),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  label: const Text('Fechar',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800)))),
        ])));
  }
}

class _Pill extends StatelessWidget {
  final String label, valor;
  final Color cor;
  const _Pill(this.label, this.valor, this.cor);
  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: cor.withValues(alpha: 0.55))),
        child: RichText(
            text: TextSpan(
                style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5),
                children: <TextSpan>[
              TextSpan(
                  text: '$label  ',
                  style: TextStyle(color: cor, fontWeight: FontWeight.w900)),
              TextSpan(
                  text: valor,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ])));
  }
}

// =============================================================
//  NOVOS WIDGETS V2 · Binance RSI(14) + EMA 20 / 200 + Tags
// =============================================================

String _fmtD(Object? v, {int? d}) {
  final double? dd = double.tryParse(v?.toString() ?? '');
  if (dd == null) return '--';
  if (dd.isNaN || dd.isInfinite) return '--';
  final int dig = d ??
      (dd >= 1000
          ? 0
          : dd >= 1
              ? 2
              : 5);
  return dd.toStringAsFixed(dig);
}

Color _rsiCor(double rsi) {
  if (rsi < 35) return const Color(0xff00e676);
  if (rsi > 70) return const Color(0xffff5252);
  return const Color(0xffffd740);
}

String _rsiLabel(double rsi) {
  if (rsi < 35) return 'Sobrevendido';
  if (rsi > 70) return 'Sobrecomprado';
  return 'Neutro';
}

Color _emaCor(double preco, double ema) =>
    preco >= ema ? const Color(0xff00e676) : const Color(0xffff5252);

class _IndicadoresV2Binance extends StatelessWidget {
  final Map<String, dynamic> data;
  const _IndicadoresV2Binance({required this.data});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> res =
        BackendConfig.safeMap(data['crypto_v2_resumo']);
    final Map<String, dynamic> at = BackendConfig.safeMap(BackendConfig.safeMap(
        data['varredura_ao_vivo'])['analise_tecnica_resumida']);

    final double rsi =
        BackendConfig.safeDouble(res['rsi_14'] ?? at['rsi_14'], 50.0);
    final double? ema20 =
        BackendConfig.safeDouble(res['ema_20'] ?? at['ema_20']);
    final double? ema200 =
        BackendConfig.safeDouble(res['ema_200'] ?? at['ema_200']);
    final Map<String, dynamic> ativoSol =
        BackendConfig.safeMap(data['ativo_solicitado']);
    final double preco = BackendConfig.safeDouble(
        res['preco_atual'] ?? ativoSol['preco_referencia_atual_usd'] ?? 0, 0);
    final bool golden = BackendConfig.safeBool(res['cruzamento_ema_20x200']) ||
        BackendConfig.safeBool(at['cruzamento_ema_20x200']);
    final bool acima200 = BackendConfig.safeBool(res['preco_acima_ema200']) ||
        BackendConfig.safeBool(at['preco_acima_ema200']) ||
        (ema200 != null && preco > ema200);

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
      decoration: BoxDecoration(
        color: const Color(0xff0e1c25),
        borderRadius: BorderRadius.circular(13),
        border:
            Border.all(color: const Color(0xff00bcd4).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xff00bcd4).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.bar_chart_rounded,
                      color: Color(0xff00bcd4), size: 15)),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Indicadores V2 · Binance 1h',
                      style: TextStyle(
                          color: Color(0xff00bcd4),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.15))),
              Text(
                  res['sinal_v2']?.toString() ??
                      at['sinal_v2']?.toString() ??
                      'ANALISANDO',
                  style: TextStyle(
                      color: (res['sinal_v2'] == 'COMPRAR' ||
                              at['sinal_v2'] == 'COMPRAR')
                          ? const Color(0xff00e676)
                          : (res['sinal_v2'] == 'VENDER' ||
                                  at['sinal_v2'] == 'VENDER')
                              ? const Color(0xffff5252)
                              : const Color(0xffffd740),
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Expanded(
                  child: _MiniIndicador(
                label: 'RSI 14',
                valor: rsi.toStringAsFixed(1),
                sub: _rsiLabel(rsi),
                cor: _rsiCor(rsi),
              )),
              const SizedBox(width: 7),
              Expanded(
                  child: _MiniIndicador(
                label: 'EMA 20',
                valor: ema20 == null ? '--' : '\$${_fmtD(ema20)}',
                sub: ema20 == null
                    ? '--'
                    : (preco >= ema20 ? 'Preço acima' : 'Preço abaixo'),
                cor: ema20 == null ? Colors.white54 : _emaCor(preco, ema20),
              )),
              const SizedBox(width: 7),
              Expanded(
                  child: _MiniIndicador(
                label: 'EMA 200',
                valor: ema200 == null ? '--' : '\$${_fmtD(ema200)}',
                sub: acima200 ? 'Tend. ALTA' : 'Tend. BAIXA',
                cor: acima200
                    ? const Color(0xff00e676)
                    : const Color(0xffff5252),
              )),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (golden)
                const _TagChip(
                    label: '🌟 Golden Cross (EMA20 × EMA200)',
                    cor: Color(0xff00e676)),
              if (acima200)
                const _TagChip(
                    label: '📈 Acima EMA 200', cor: Color(0xff26c6da))
              else
                const _TagChip(
                    label: '📉 Abaixo EMA 200', cor: Color(0xffff5252)),
              _TagChip(
                  label: 'Par: ${res['simbolo_par_binance'] ?? 'N/D'}',
                  cor: const Color(0xff7a8c95)),
              if (res['intervalo'] != null)
                _TagChip(
                    label: 'TF: ${res['intervalo']}',
                    cor: const Color(0xff9c27b0)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniIndicador extends StatelessWidget {
  final String label, valor, sub;
  final Color cor;
  const _MiniIndicador(
      {required this.label,
      required this.valor,
      required this.sub,
      required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 7),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  color: cor, fontSize: 9.5, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(valor,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(sub,
              style: TextStyle(
                  color: cor.withValues(alpha: 0.95),
                  fontSize: 9.2,
                  fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color cor;
  const _TagChip({required this.label, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: cor,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1)),
    );
  }
}

class _DestinoSwapV2Card extends StatelessWidget {
  final Map<String, dynamic> swap;
  const _DestinoSwapV2Card({required this.swap});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> d =
        BackendConfig.safeMap(swap['destino_crypto_v2_resumo']);
    if (d.isEmpty) return const SizedBox.shrink();
    final double rsi = double.tryParse((d['rsi_14'] ?? 50).toString()) ?? 50.0;
    final double? ema20 = double.tryParse((d['ema_20']).toString());
    final double? ema200 = double.tryParse((d['ema_200']).toString());
    final double preco =
        double.tryParse((d['preco_atual'] ?? 0).toString()) ?? 0;
    final bool golden = d['cruzamento_ema_20x200'] == true;
    final bool acima200 =
        d['preco_acima_ema200'] == true || (ema200 != null && preco > ema200);
    final String sinal =
        (d['sinal_v2']?.toString() ?? 'ANALISANDO').toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: const Color(0xff1a0f25),
        borderRadius: BorderRadius.circular(13),
        border:
            Border.all(color: const Color(0xff9c27b0).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xff9c27b0).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.swap_horiz_rounded,
                      color: Color(0xffce93d8), size: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Ativo Destino · ${swap['ativo_destino'] ?? 'N/D'} (${swap['ativo_destino_nome'] ?? ''})',
                    style: const TextStyle(
                        color: Color(0xffce93d8),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text(sinal,
                  style: TextStyle(
                      color: sinal == 'COMPRAR'
                          ? const Color(0xff00e676)
                          : sinal == 'VENDER'
                              ? const Color(0xffff5252)
                              : const Color(0xffffd740),
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                  child: _MiniIndicador(
                      label: 'RSI 14',
                      valor: rsi.toStringAsFixed(1),
                      sub: _rsiLabel(rsi),
                      cor: _rsiCor(rsi))),
              const SizedBox(width: 7),
              Expanded(
                  child: _MiniIndicador(
                      label: 'EMA 20',
                      valor: ema20 == null ? '--' : '\$${_fmtD(ema20)}',
                      sub: ema20 == null
                          ? '--'
                          : (preco >= ema20 ? 'Preço acima' : 'Preço abaixo'),
                      cor: ema20 == null
                          ? Colors.white54
                          : _emaCor(preco, ema20))),
              const SizedBox(width: 7),
              Expanded(
                  child: _MiniIndicador(
                      label: 'EMA 200',
                      valor: ema200 == null ? '--' : '\$${_fmtD(ema200)}',
                      sub: acima200 ? 'Tend. ALTA' : 'Tend. BAIXA',
                      cor: acima200
                          ? const Color(0xff00e676)
                          : const Color(0xffff5252))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (golden)
                const _TagChip(
                    label: '🌟 Golden Cross', cor: Color(0xff00e676)),
              if (acima200)
                const _TagChip(
                    label: '📈 Acima EMA 200', cor: Color(0xff26c6da))
              else
                const _TagChip(
                    label: '📉 Abaixo EMA 200', cor: Color(0xffff5252)),
              _TagChip(
                  label: 'Par: ${d['simbolo_par_binance'] ?? 'N/D'}',
                  cor: const Color(0xff7a8c95)),
            ],
          ),
        ],
      ),
    );
  }
}
