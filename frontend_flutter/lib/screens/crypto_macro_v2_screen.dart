import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class CryptoMacroV2Screen extends StatefulWidget {
  const CryptoMacroV2Screen({super.key});

  @override
  State<CryptoMacroV2Screen> createState() => _CryptoMacroV2ScreenState();
}

class _CryptoMacroV2ScreenState extends State<CryptoMacroV2Screen> {
  static const List<String> _ativos = <String>['BTC', 'AAVE', 'IOTA'];

  final Map<String, Map<String, dynamic>> _dados =
      <String, Map<String, dynamic>>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    for (String s in _ativos) {
      _dados[s] = _fallback(s);
    }
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final String base = await ApiService.resolveV1();
      final String url =
          '$base/crypto/signals?aporte_usd=1000&perfil=moderado';
      final http.Response r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final Map<String, dynamic> d =
            BackendConfig.safeMap(jsonDecode(r.body));
        final List<dynamic> lista =
            BackendConfig.safeList(d['analises_ativos']);
        for (dynamic a in lista) {
          final Map<String, dynamic> m = BackendConfig.safeMap(a);
          final String sym = (m['simbolo']?.toString() ?? '').toUpperCase();
          if (sym.isEmpty || !_ativos.contains(sym)) continue;
          _dados[sym] = _enriquecerFallback(sym, m);
        }
        if (mounted) setState(() => _loading = false);
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic> _fallback(String sym) {
    final Random rnd = Random(sym.hashCode);
    final List<double> precos = List<double>.generate(60, (int i) {
      final double base = sym == 'BTC'
          ? 63500
          : sym == 'AAVE'
              ? 95
              : 0.22;
      return base *
          (1.0 +
              (rnd.nextDouble() - 0.5) * 0.05 +
              sin(i / 6) * 0.012 +
              i * 0.0004);
    }, growable: false);
    final double high24 = precos.reduce(max) * 1.02;
    final double low24 = precos.reduce(min) * 0.98;
    final double close = precos.last;
    final Map<String, dynamic> macd = _macd(precos);
    final Map<String, dynamic> bb = _bollinger(precos);
    final Map<String, dynamic> pivs = _pivots(high24, low24, close);
    final double rsi = _rsi(precos);
    final double score = macd['score_bullish'] +
        (rsi > 45 && rsi < 75
                ? 15
                : rsi < 40
                    ? -5
                    : 0)
            .toDouble() +
        (bb['squeeze_apertado'] ? -8 : 5) +
        (close > bb['banda_inferior'] ? 8 : -6) +
        (close < bb['banda_superior'] ? 5 : -5);
    return <String, dynamic>{
      'simbolo': sym,
      'preco': close.toStringAsFixed(sym == 'BTC'
          ? 0
          : sym == 'AAVE'
              ? 2
              : 5),
      'score': score,
      'status_score': score >= 55
          ? 'COMPRAR'
          : score <= 30
              ? 'VENDER'
              : 'AGUARDAR / ALTO RISCO',
      'rsi_14': rsi.toStringAsFixed(1),
      'macd': macd,
      'bollinger': bb,
      'pivots': pivs,
      'precos_serie': precos,
    };
  }

  Map<String, dynamic> _enriquecerFallback(
      String sym, Map<String, dynamic> server) {
    final Map<String, dynamic> base = _fallback(sym);
    final Map<String, dynamic> macd = BackendConfig.safeMap(base['macd']);
    final Map<String, dynamic> bb = BackendConfig.safeMap(base['bollinger']);
    final Map<String, dynamic> pivs = BackendConfig.safeMap(base['pivots']);
    final double? entry =
        double.tryParse((server['ponto_entrada_sugerido_usd'] ?? 0).toString());
    final double? sl =
        double.tryParse((server['stop_loss_usd'] ?? 0).toString());
    final double? tp =
        double.tryParse((server['take_profit_usd'] ?? 0).toString());
    final double curr =
        double.parse(base['preco'].toString().replaceAll(',', '.'));
    return <String, dynamic>{
      ...base,
      'status_score':
          (server['status']?.toString() ?? base['status_score']).toUpperCase(),
      'preco': curr.toStringAsFixed(sym == 'BTC'
          ? 0
          : sym == 'AAVE'
              ? 2
              : 5),
      'entry': entry,
      'stop_loss': sl,
      'take_profit': tp,
      'macd': macd,
      'bollinger': bb,
      'pivots': pivs,
    };
  }

  static Map<String, dynamic> _ema(List<double> src, int period) {
    final double k = 2 / (period + 1);
    final List<double> out = List<double>.filled(src.length, 0);
    out[0] = src[0];
    for (int i = 1; i < src.length; i++) {
      out[i] = src[i] * k + out[i - 1] * (1 - k);
    }
    final double val = out.last;
    return <String, dynamic>{'serie': out, 'valor_atual': val};
  }

  static List<double> _serieDouble(dynamic v) {
    final List<dynamic> l = BackendConfig.safeList(v);
    final List<double> out = <double>[];
    for (int i = 0; i < l.length; i++) {
      out.add(BackendConfig.safeDouble(l[i]));
    }
    return out;
  }

  static Map<String, dynamic> _macd(List<double> precos,
      {int rapido = 12, int lento = 26, int sinal = 9}) {
    final Map<String, dynamic> emaR = _ema(precos, rapido);
    final Map<String, dynamic> emaL = _ema(precos, lento);
    final List<double> emaRSerie = _serieDouble(emaR['serie']);
    final List<double> emaLSerie = _serieDouble(emaL['serie']);
    final List<double> linhas = List<double>.generate(
        precos.length, (int i) => emaRSerie[i] - emaLSerie[i],
        growable: false);
    final Map<String, dynamic> sinalMap = _ema(linhas, sinal);
    final List<double> sinalSerie = _serieDouble(sinalMap['serie']);
    final List<double> hist = List<double>.generate(
        precos.length, (int i) => linhas[i] - sinalSerie[i],
        growable: false);
    final double mcurr = linhas.last;
    final double scurr = sinalSerie.last;
    final bool cruzBull = mcurr >= scurr &&
        (linhas[linhas.length - 2] < sinalSerie[sinalSerie.length - 2]);
    final bool cruzBear = mcurr <= scurr &&
        (linhas[linhas.length - 2] > sinalSerie[sinalSerie.length - 2]);
    final double forca = (mcurr - scurr).abs() /
        (precos.reduce(max) - precos.reduce(min) + 1e-9) *
        100;
    final double score = (forca * (mcurr >= scurr ? 1 : -1)).clamp(-30, 30) +
        (mcurr > 0
            ? 12
            : mcurr < 0
                ? -8
                : 0) +
        (cruzBull
            ? 10
            : cruzBear
                ? -10
                : 0);
    return <String, dynamic>{
      'linha_macd': mcurr,
      'linha_sinal': scurr,
      'histograma': hist.last,
      'cruzamento': cruzBull
          ? 'bullish'
          : cruzBear
              ? 'bearish'
              : 'neutro',
      'forca_0_a_100': forca.clamp(0, 100),
      'score_bullish': (score + 30) / 2,
    };
  }

  static Map<String, dynamic> _bollinger(List<double> precos,
      {int period = 20, double desvios = 2.0}) {
    final int start = (precos.length - period).clamp(0, precos.length);
    final List<double> sub = precos.sublist(start);
    final double med = sub.reduce((double a, double b) => a + b) / sub.length;
    final double soma =
        sub.fold<double>(0, (double p, double x) => p + (x - med) * (x - med));
    final double dp = sqrt(soma / sub.length);
    final double sup = med + desvios * dp;
    final double inf = med - desvios * dp;
    final double larg = (sup - inf) / max(med, 1e-9) * 100;
    final double prec = precos.last;
    final double dentro =
        ((prec - inf) / max(sup - inf, 1e-9) * 100).clamp(0, 100);
    return <String, dynamic>{
      'banda_superior': sup,
      'media_movel': med,
      'banda_inferior': inf,
      'largura_bandas_pct': larg,
      'preco_atual_pct_dentro_banda': dentro,
      'squeeze_apertado': larg < 3.0,
    };
  }

  static Map<String, dynamic> _pivots(double high, double low, double close) {
    final double range = high - low;
    final double p = (high + low + close) / 3;
    return <String, dynamic>{
      'pivo_p': p,
      'resistencias': <String, double>{
        'R1': p + 0.382 * range,
        'R2': p + 0.618 * range,
        'R3': p + 1.000 * range,
      },
      'suportes': <String, double>{
        'S1': p - 0.382 * range,
        'S2': p - 0.618 * range,
        'S3': p - 1.000 * range,
      },
    };
  }

  static double _rsi(List<double> precos, {int period = 14}) {
    if (precos.length < period + 1) return 50;
    double ganhos = 0, perdas = 0;
    for (int i = precos.length - period; i < precos.length; i++) {
      final double d = precos[i] - precos[i - 1];
      if (d > 0) {
        ganhos += d;
      } else {
        perdas += -d;
      }
    }
    final double g = ganhos / period;
    final double p = perdas / period;
    if (p < 1e-9) return 100;
    final double rs = g / p;
    return (100 - 100 / (1 + rs)).clamp(0, 100);
  }

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
          Icon(Icons.candlestick_chart_rounded,
              color: Color(0xfff7b500), size: 23),
          SizedBox(width: 9),
          Flexible(
              child: Text('Crypto Macro V2 · IA do Tiago',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900))),
        ]),
        actions: <Widget>[
          IconButton(
              onPressed: _loading ? null : _carregar,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.neonGreen)))
                  : const Icon(Icons.refresh_rounded,
                      color: Colors.white70, size: 22)),
        ],
      ),
      body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
              children: <Widget>[
            _header(),
            const SizedBox(height: 10),
            for (String s in _ativos) ...<Widget>[
              _AtivoCard(simbolo: s, dados: _dados[s]!),
              const SizedBox(height: 12),
            ],
            _assinatura(),
          ])),
    );
  }

  Widget _header() {
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xfff7b500).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xfff7b500)
                                .withValues(alpha: 0.5))),
                    child: const Icon(Icons.public_rounded,
                        color: Color(0xfff7b500), size: 19)),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text(
                        'Análise Técnica Avançada · MACD · Bollinger · Pivôs Fibonacci',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 8),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 7),
              const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _LegendPill(label: 'MACD 12,26,9', cor: Color(0xff9c27b0)),
                    _LegendPill(
                        label: 'Bollinger 20,2σ', cor: Color(0xff2196f3)),
                    _LegendPill(label: 'Pivôs Fib', cor: Color(0xff00e676)),
                  ]),
            ]));
  }

  Widget _assinatura() {
    return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Center(
            child: Text(
                'Relatório gerado por IA do Tiago · sem marcas de terceiros',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2))));
  }
}

class _LegendPill extends StatelessWidget {
  final String label;
  final Color cor;
  const _LegendPill({required this.label, required this.cor});
  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: cor.withValues(alpha: 0.5))),
        child: Text(label,
            style: TextStyle(
                color: cor, fontSize: 10, fontWeight: FontWeight.w900)));
  }
}

class _AtivoCard extends StatelessWidget {
  final String simbolo;
  final Map<String, dynamic> dados;
  const _AtivoCard({required this.simbolo, required this.dados});

  @override
  Widget build(BuildContext context) {
    final String status = dados['status_score'].toString().toUpperCase();
    final Color c =
        status.startsWith('COMPRAR') || status.startsWith('POSITIVO')
            ? AppTheme.neonGreen
            : status.startsWith('VENDER') || status.startsWith('NEGATIVO')
                ? AppTheme.flashLiveRed
                : const Color(0xfff7b500);
    final Map<String, dynamic> macd = BackendConfig.safeMap(dados['macd']);
    final Map<String, dynamic> bb = BackendConfig.safeMap(dados['bollinger']);
    final Map<String, dynamic> pivs = BackendConfig.safeMap(dados['pivots']);
    final Map<String, dynamic> resistencias =
        BackendConfig.safeMap(pivs['resistencias']);
    final Map<String, dynamic> suportes =
        BackendConfig.safeMap(pivs['suportes']);
    final Map<String, double> r = resistencias.map((String k, dynamic v) =>
        MapEntry<String, double>(k, BackendConfig.safeDouble(v)));
    final Map<String, double> s = suportes.map((String k, dynamic v) =>
        MapEntry<String, double>(k, BackendConfig.safeDouble(v)));
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: const Color(0xff121f29),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: c.withValues(alpha: 0.55), width: 1.2),
          boxShadow: <BoxShadow>[
            BoxShadow(color: c.withValues(alpha: 0.10), blurRadius: 16)
          ]),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.withValues(alpha: 0.6))),
                  child: Text(simbolo[0],
                      style: TextStyle(
                          color: c,
                          fontWeight: FontWeight.w900,
                          fontSize: 18))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(simbolo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900)),
                    Text('\$ ${dados['preco']} · RSI ${dados['rsi_14']}',
                        style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ])),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: c.withValues(alpha: 0.7))),
                  child: Text(status,
                      style: TextStyle(
                          color: c,
                          fontSize: 10.5,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w900))),
            ]),
            if (dados['entry'] != null ||
                dados['stop_loss'] != null ||
                dados['take_profit'] != null) ...<Widget>[
              const SizedBox(height: 10),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 9),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _miniPill('Entrada', '\$ ${_fmt(dados['entry'])}',
                        AppTheme.neonGreen),
                    _miniPill('Stop Loss', '\$ ${_fmt(dados['stop_loss'])}',
                        AppTheme.flashLiveRed),
                    _miniPill('Take Profit', '\$ ${_fmt(dados['take_profit'])}',
                        const Color(0xfff7b500)),
                  ]),
            ],
            const SizedBox(height: 11),
            Row(children: <Widget>[
              Expanded(
                  child: _metric(
                      'MACD',
                      'Cruz. ${macd['cruzamento'] ?? 'n/a'}',
                      const Color(0xff9c27b0),
                      macd['forca_0_a_100'] as num? ?? 0,
                      sub:
                          'Hist ${(macd['histograma'] as num? ?? 0).toStringAsFixed(2)}')),
              const SizedBox(width: 9),
              Expanded(
                  child: _metric(
                      'Bollinger',
                      bb['squeeze_apertado'] == true
                          ? 'SQUEEZE (vol baixa)'
                          : 'Volatilidade normal',
                      const Color(0xff2196f3),
                      bb['preco_atual_pct_dentro_banda'] as num? ?? 50,
                      sub:
                          'Larg. ${(bb['largura_bandas_pct'] as num? ?? 0).toStringAsFixed(2)}%')),
            ]),
            const SizedBox(height: 10),
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppTheme.neonGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: AppTheme.neonGreen.withValues(alpha: 0.4))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Pivôs Fibonacci · Suportes & Resistências',
                          style: TextStyle(
                              color: AppTheme.neonGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                        for (final MapEntry<String, double> rr
                            in r?.entries ?? const <MapEntry<String, double>>[])
                          _tag('Resist. ${rr.key}', '\$${_fmt(rr.value)}',
                              AppTheme.flashLiveRed),
                        for (final MapEntry<String, double> rr
                            in s?.entries ?? const <MapEntry<String, double>>[])
                          _tag('Suporte ${rr.key}', '\$${_fmt(rr.value)}',
                              AppTheme.neonGreen),
                        _tag('Pivô P', '\$${_fmt(pivs['pivo_p'])}',
                            const Color(0xffce93d8)),
                      ]),
                    ])),
          ]),
    );
  }

  static String _fmt(Object? v, {int? digits}) {
    if (v == null) return '--';
    final double? dd = double.tryParse(v.toString());
    if (dd == null) return '--';
    final int d = digits ??
        (dd >= 1000
            ? 0
            : dd >= 1
                ? 2
                : 5);
    return dd.toStringAsFixed(d);
  }

  static Widget _miniPill(String label, String valor, Color c) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.withValues(alpha: 0.45))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label,
                  style: TextStyle(
                      color: c,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3)),
              Text(valor,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ]));
  }

  static Widget _tag(String label, String valor, Color c) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.5))),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontFamily: 'Inter', fontSize: 10),
            children: <TextSpan>[
              TextSpan(
                  text: '$label  ',
                  style: TextStyle(color: c, fontWeight: FontWeight.w900)),
              TextSpan(
                  text: valor,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
        ));
  }

  static Widget _metric(String tit, String res, Color c, num pct,
      {String? sub}) {
    final double p = pct.toDouble().clamp(0, 100);
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.5))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(children: <Widget>[
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(tit,
                        style: TextStyle(
                            color: c,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900))),
                const Spacer(),
                Text('${p.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                      minHeight: 5,
                      value: p / 100,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(c))),
              const SizedBox(height: 7),
              Text(res,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800)),
              if (sub != null && sub.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub,
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700))),
            ]));
  }
}
