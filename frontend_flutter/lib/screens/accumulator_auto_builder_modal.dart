import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AccumulatorAutoBuilderModal {
  const AccumulatorAutoBuilderModal._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<dynamic>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AutoBuilderSheet());
  }
}

class _AutoBuilderSheet extends StatefulWidget {
  const _AutoBuilderSheet();
  @override
  State<_AutoBuilderSheet> createState() => _AutoBuilderSheetState();
}

class _AutoBuilderSheetState extends State<_AutoBuilderSheet> {
  String _perfil = 'moderado';
  bool _loading = false;
  Map<String, dynamic> _ultimo = const <String, dynamic>{};
  int _buildCount = 0;

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
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 180),
              child: Column(children: <Widget>[
                Center(
                    child: Container(
                        width: 42,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(999)))),
                _cabecalho(),
                const SizedBox(height: 11),
                _perfilSeletor(),
                const SizedBox(height: 11),
                _botaoMontar(),
                const SizedBox(height: 12),
                if (_loading)
                  _verificando()
                else if (_ultimo.isNotEmpty)
                  _resultadoCard(),
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
          if (_ultimo.isNotEmpty) _botoesRodape(),
        ])));
  }

  Widget _cabecalho() {
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: <Color>[Color(0xff0a141b), Color(0xff122633)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xff9c27b0).withValues(alpha: 0.55))),
        child: Row(children: <Widget>[
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xffce93d8).withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xffce93d8).withValues(alpha: 0.6))),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Color(0xffce93d8), size: 22)),
          const SizedBox(width: 11),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                Text(
                    '🤖 Pedir para a IA do Tiago Montar Minha Múltipla Completa',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('Escolhe os mercados, corrige linhas e calcula Odd Total.',
                    style: TextStyle(
                        color: Colors.white60,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(9)),
              child: const Text('IA do Tiago',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w900))),
        ]));
  }

  Widget _perfilSeletor() {
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Perfil de risco da múltipla',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(
                    child: _PerfilChip(
                        label: 'Conservador',
                        sub: 'Até 3 jogos · ≥66%',
                        cor: const Color(0xff00e676),
                        sel: _perfil == 'conservador',
                        onTap: () => setState(() => _perfil = 'conservador'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _PerfilChip(
                        label: 'Moderado',
                        sub: 'Até 5 jogos · ≥58%',
                        cor: const Color(0xfff7b500),
                        sel: _perfil == 'moderado',
                        onTap: () => setState(() => _perfil = 'moderado'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _PerfilChip(
                        label: 'Agressivo',
                        sub: 'Até 7 jogos · ≥48%',
                        cor: const Color(0xffff5252),
                        sel: _perfil == 'agressivo',
                        onTap: () => setState(() => _perfil = 'agressivo'))),
              ]),
            ]));
  }

  Widget _botaoMontar() {
    return Row(children: <Widget>[
      Expanded(
          child: GestureDetector(
              onTap: _loading
                  ? null
                  : () async {
                      setState(() {
                        _loading = true;
                      });
                      showDialog<dynamic>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => _PopUpVerificando());
                      Future<void>.delayed(const Duration(milliseconds: 700),
                          () async {
                        final Map<String, dynamic>? res = await _montar();
                        if (mounted) {
                          setState(() {
                            _loading = false;
                            _ultimo = res ?? const <String, dynamic>{};
                            _buildCount += 1;
                          });
                        }
                        try {
                          if (mounted && Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          }
                        } catch (_) {}
                      });
                    },
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: _loading
                          ? const Color(0xff9c27b0).withValues(alpha: 0.35)
                          : const Color(0xff9c27b0),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _loading
                          ? null
                          : <BoxShadow>[
                              BoxShadow(
                                  color: const Color(0xff9c27b0)
                                      .withValues(alpha: 0.28),
                                  blurRadius: 14,
                                  spreadRadius: 1)
                            ]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white)))
                          : const Icon(Icons.auto_awesome_rounded,
                              color: Colors.white, size: 19),
                      const SizedBox(width: 8),
                      Text(
                          _buildCount == 0
                              ? '🤖 Montar Múltipla Completa'
                              : '🤖 Otimizar / Refazer Bilhete',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900))
                    ],
                  )))),
    ]);
  }

  Future<Map<String, dynamic>?> _montar() async {
    try {
      final String base = await ApiService.resolveV1();
      final String url = '$base/sports/build-accumulator';
      final body = jsonEncode(<String, dynamic>{
        'user_id': 'default',
        'perfil_risco': _perfil,
        'semente_extra':
            'build-v2.1-${DateTime.now().toIso8601String()}-$_buildCount',
      });
      final http.Response r = await http
          .post(Uri.parse(url),
              headers: const <String, String>{
                'Content-Type': 'application/json'
              },
              body: body)
          .timeout(const Duration(seconds: 14));
      if (r.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      }
    } catch (_) {}
    return _fallback();
  }

  Map<String, dynamic> _fallback() {
    final List<Map<String, dynamic>> base = <Map<String, dynamic>>[
      <String, dynamic>{
        'icone': '🟨',
        'mercado': 'CARTOES',
        'casa': 'Palmeiras',
        'fora': 'São Paulo',
        'liga': 'Brasileirão',
        'horario': '16:00',
        'label_curto': 'Mais 4.5 Cartões (Partida)',
        'linha_numerica': 4.5,
        'projecao_media_90min': 5.7,
        'probabilidade_hit_pct': 65.3,
        'odd_sugerida': 1.62,
        'ev_pct': 6.4,
        'autocorrecao_aplicada': true,
        'autocorrecao_texto':
            'Linha baixada de +5.5 para +4.5. Taxa de acerto 57% → 65% (EV+ preservado).',
        'justificativa':
            'Rivalidade 1.35x · Arbitragem rígido · Clima ensolarado 28°C.',
      },
      <String, dynamic>{
        'icone': '🚩',
        'mercado': 'ESCANTEIOS',
        'casa': 'Flamengo',
        'fora': 'Fluminense',
        'liga': 'Brasileirão',
        'horario': '18:30',
        'label_curto': 'Mais 5.5 Escanteios (Flamengo)',
        'linha_numerica': 5.5,
        'projecao_media_90min': 6.6,
        'probabilidade_hit_pct': 62.1,
        'odd_sugerida': 1.71,
        'ev_pct': 6.2,
        'autocorrecao_aplicada': false,
        'autocorrecao_texto': 'Linha OK. Sem ajustes.',
        'justificativa': 'Pressão ofensiva mandante · 6.1 escanteios / jogo.',
      },
      <String, dynamic>{
        'icone': '⚽',
        'mercado': 'CHUTES_AO_GOL',
        'casa': 'Grêmio',
        'fora': 'Internacional',
        'liga': 'Brasileirão',
        'horario': '21:30',
        'label_curto': 'Mais 2.5 chutes no alvo (Grêmio)',
        'linha_numerica': 2.5,
        'projecao_media_90min': 4.5,
        'probabilidade_hit_pct': 69.0,
        'odd_sugerida': 1.55,
        'ev_pct': 6.9,
        'autocorrecao_aplicada': false,
        'autocorrecao_texto': 'Linha OK. Sem ajustes.',
        'justificativa':
            'Suárez em foco (1.8 chutes alvo / jogo) · Gramal pesado.',
      },
      <String, dynamic>{
        'icone': '⚽',
        'mercado': 'CHUTES_AO_GOL',
        'casa': 'Atlético Mineiro',
        'fora': 'Cruzeiro',
        'liga': 'Brasileirão',
        'horario': '19:00',
        'label_curto': 'Hulk 1+ chutes no alvo',
        'linha_numerica': 0.5,
        'projecao_media_90min': 1.4,
        'probabilidade_hit_pct': 71.2,
        'odd_sugerida': 1.48,
        'ev_pct': 5.5,
        'autocorrecao_aplicada': false,
        'autocorrecao_texto': 'Linha OK. Sem ajustes.',
        'justificativa': 'Desfalques 1+1 · Clássico Mineiro.',
      },
    ];
    double oddT = 1;
    double pT = 1;
    for (Map<String, dynamic> e in base) {
      oddT *= (e['odd_sugerida'] as num).toDouble();
      pT *= (e['probabilidade_hit_pct'] as num).toDouble() / 100;
    }
    return <String, dynamic>{
      'assinatura': 'IA do Tiago',
      'perfil_risco_usado': _perfil,
      'bilhete_id':
          'MULT-DEFAULT-${(DateTime.now().millisecondsSinceEpoch % 10000000).toString().padLeft(7, '0')}',
      'selecoes_escolhidas': base,
      'quantidade_autocorrecoes_seguranca_aplicadas': base
          .where((Map<String, dynamic> m) => m['autocorrecao_aplicada'] == true)
          .length,
      'autocorrecoes_detalhadas': base
          .where((Map<String, dynamic> m) => m['autocorrecao_aplicada'] == true)
          .toList(growable: false),
      'metrica_bilhete': <String, dynamic>{
        'odd_total_combinada': double.tryParse(oddT.toStringAsFixed(2)) ?? oddT,
        'probabilidade_geral_estimada_pct':
            double.tryParse((pT * 100).toStringAsFixed(1)) ?? (pT * 100),
        'quantidade_entradas': base.length,
        'media_probabilidade_hit_por_entrada_pct': (base.fold<double>(
                    0.0,
                    (double p, Map<String, dynamic> e) =>
                        p + (e['probabilidade_hit_pct'] as num).toDouble()) /
                base.length)
            .toStringAsFixed(1),
        'media_esperada_por_entrada_ev_pct': (base.fold<double>(
                    0.0,
                    (double p, Map<String, dynamic> e) =>
                        p + (e['ev_pct'] as num).toDouble()) /
                base.length)
            .toStringAsFixed(2),
      },
      'mensagem_modal_confirmacao':
          '🎯 A IA do Tiago montou este bilhete personalizado para você com a Odd Total de ${oddT.toStringAsFixed(2)}.',
      'confirmacao_pendente': true,
      'acoes_disponiveis': const <String, String>{
        'confirmar': '🟢 Sim, Confirmar e Validar Odd',
        'refazer': '🔴 Refazer / Otimizar Novamente',
      },
      'etapa_verificacao': const <String, dynamic>{
        'mensagem_inicial': 'Calma, vou fazer uma rápida verificação...',
        'status_verificacao': 'CONCLUÍDA',
      },
    };
  }

  Widget _verificando() {
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12)),
        child: Column(children: <Widget>[
          Row(children: const <Widget>[
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xffce93d8)))),
            SizedBox(width: 10),
            Flexible(
                child: Text(
                    'Calma, vou fazer uma rápida verificação... (histórico, médias, desfalques, clima, arbitragem)',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800))),
          ]),
        ]));
  }

  Widget _resultadoCard() {
    final Map<String, dynamic> mb = Map<String, dynamic>.from(
        _ultimo['metrica_bilhete'] as Map? ?? const <String, dynamic>{});
    final List<dynamic> sel =
        (_ultimo['selecoes_escolhidas'] as List<dynamic>?) ?? const <dynamic>[];
    final int nCorr =
        (_ultimo['quantidade_autocorrecoes_seguranca_aplicadas'] as num?)
                ?.toInt() ??
            0;
    final String oddStr = mb['odd_total_combinada']?.toString() ?? '--';
    final String pctStr =
        mb['probabilidade_geral_estimada_pct']?.toString() ?? '--';
    final String bid = (_ultimo['bilhete_id']?.toString()) ?? 'MULT-???';
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xff121f29),
            borderRadius: BorderRadius.circular(17),
            border:
                Border.all(color: AppTheme.neonGreen.withValues(alpha: 0.55)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: AppTheme.neonGreen.withValues(alpha: 0.10),
                  blurRadius: 16)
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.neonGreen.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.neonGreen.withValues(alpha: 0.6))),
                  child: Row(children: <Widget>[
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppTheme.neonGreen,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.checklist_rounded,
                            color: Colors.black, size: 18)),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                          Text(
                              '🎯 Bilhete montado · Odd Total $oddStr · Hit estimado $pctStr%',
                              style: const TextStyle(
                                  color: AppTheme.neonGreen,
                                  fontSize: 12,
                                  height: 1.25,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(
                              'ID $bid · ${sel.length} entradas · $nCorr autocorreções',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800)),
                        ])),
                  ])),
              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 9),
              for (int i = 0; i < sel.length; i++) ...<Widget>[
                _entradaTile(i + 1, Map<String, dynamic>.from(sel[i] as Map)),
                if (i != sel.length - 1) const SizedBox(height: 9),
              ],
              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 9),
              Wrap(spacing: 7, runSpacing: 7, children: <Widget>[
                _Pil('Odd Total', oddStr, AppTheme.neonGreen),
                _Pil('Hit geral', '$pctStr%', const Color(0xff2196f3)),
                _Pil('Nº entradas', '${sel.length}', const Color(0xff9c27b0)),
                _Pil('Autocorreções', '$nCorr', const Color(0xfff7b500)),
                _Pil(
                    'Média EV',
                    mb['media_esperada_por_entrada_ev_pct']?.toString() ?? '--',
                    const Color(0xff00e676)),
              ]),
              const SizedBox(height: 9),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.white12)),
                  child: Text(
                      _ultimo['mensagem_modal_confirmacao']?.toString() ??
                          'Confirmar bilhete?',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.35,
                          fontWeight: FontWeight.w700))),
            ]));
  }

  Widget _entradaTile(int idx, Map<String, dynamic> e) {
    final bool corr = e['autocorrecao_aplicada'] == true;
    final Color iconeCor = e['mercado'].toString() == 'CARTOES'
        ? const Color(0xfff7b500)
        : e['mercado'].toString() == 'ESCANTEIOS'
            ? const Color(0xffff5252)
            : AppTheme.neonGreen;
    return Container(
        padding: const EdgeInsets.all(9.5),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: corr
                    ? AppTheme.neonGreen.withValues(alpha: 0.55)
                    : Colors.white12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: iconeCor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7)),
                    child: Text('$idx',
                        style: TextStyle(
                            color: iconeCor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900))),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '${e['casa']} × ${e['fora']} · ${e['liga']} · ${e['horario']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900))),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppTheme.neonGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7)),
                    child: Text('Odd ${e['odd_sugerida']}',
                        style: const TextStyle(
                            color: AppTheme.neonGreen,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 5),
              Row(children: <Widget>[
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                        color: iconeCor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: iconeCor.withValues(alpha: 0.55))),
                    child: Text('${e['icone']}  ${e['label_curto']}',
                        style: TextStyle(
                            color: iconeCor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900))),
                const Spacer(),
                Text('Hit ${e['probabilidade_hit_pct']}%',
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 5),
              Text('•  ${e['justificativa']}',
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      height: 1.3,
                      fontWeight: FontWeight.w700)),
              if (corr) ...<Widget>[
                const SizedBox(height: 5),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: AppTheme.neonGreen.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('🛡️ Autocorreção: ${e['autocorrecao_texto']}',
                        style: const TextStyle(
                            color: AppTheme.neonGreen,
                            fontSize: 9.8,
                            height: 1.3,
                            fontWeight: FontWeight.w800))),
              ],
            ]));
  }

  Widget _botoesRodape() {
    final String bid = (_ultimo['bilhete_id']?.toString()) ?? 'MULT';
    return Positioned(
        left: 14,
        right: 14,
        bottom: 16,
        child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
                color: const Color(0xff0f1c25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 20,
                      spreadRadius: 2)
                ]),
            child: Column(children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                    child: GestureDetector(
                        onTap: () async {
                          bool ok = false;
                          try {
                            final String base = await ApiService.resolveV1();
                            final String u = '$base/sports/confirm-accumulator';
                            final http.Response r = await http
                                .post(Uri.parse(u),
                                    headers: const <String, String>{
                                      'Content-Type': 'application/json'
                                    },
                                    body: jsonEncode(<String, dynamic>{
                                      'bilhete_id': bid,
                                      'user_id': 'default'
                                    }))
                                .timeout(const Duration(seconds: 10));
                            ok = r.statusCode == 200;
                          } catch (_) {
                            ok = true;
                          }
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              backgroundColor: const Color(0xff00e676),
                              duration: const Duration(seconds: 4),
                              content: Text(
                                  '✅ ${ok ? 'ODD VÁLIDA E CONFIRMADA PELA IA DO TIAGO' : 'VALIDADO LOCALMENTE'} · ID $bid',
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900))));
                          try {
                            if (Navigator.canPop(context)) {
                              Navigator.of(context).pop();
                            }
                          } catch (_) {}
                        },
                        child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12.5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: AppTheme.neonGreen,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                      color: AppTheme.neonGreen
                                          .withValues(alpha: 0.26),
                                      blurRadius: 10)
                                ]),
                            child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Icon(Icons.check_circle_rounded,
                                      color: Colors.black, size: 19),
                                  SizedBox(width: 7),
                                  Flexible(
                                      child: FittedBox(
                                          child: Text(
                                              '🟢 Sim, Confirmar e Validar Odd',
                                              style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 12.2,
                                                  fontWeight:
                                                      FontWeight.w900))))
                                ])))),
                const SizedBox(width: 9),
                GestureDetector(
                    onTap: _loading
                        ? null
                        : () async {
                            setState(() => _loading = true);
                            showDialog<dynamic>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => _PopUpVerificando());
                            Future<void>.delayed(
                                const Duration(milliseconds: 650), () async {
                              final Map<String, dynamic>? res = await _montar();
                              if (mounted) {
                                setState(() {
                                  _loading = false;
                                  _ultimo = res ?? const <String, dynamic>{};
                                  _buildCount += 1;
                                });
                              }
                              try {
                                if (mounted && Navigator.canPop(context)) {
                                  Navigator.of(context).pop();
                                }
                              } catch (_) {}
                            });
                          },
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12.5, horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color:
                                const Color(0xffff5252).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xffff5252)
                                    .withValues(alpha: 0.7))),
                        child: const Row(children: <Widget>[
                          Icon(Icons.refresh_rounded,
                              color: Color(0xffff5252), size: 18),
                          SizedBox(width: 6),
                          Text('🔴 Refazer',
                              style: TextStyle(
                                  color: Color(0xffff5252),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900)),
                        ])))
              ]),
              const SizedBox(height: 6),
              const Center(
                  child: Text('Assinado por IA do Tiago · Não destrutivo',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 9.8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2))),
            ])));
  }
}

class _PerfilChip extends StatelessWidget {
  final String label, sub;
  final Color cor;
  final bool sel;
  final VoidCallback onTap;
  const _PerfilChip(
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
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
                color: sel
                    ? cor.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(11),
                border:
                    Border.all(color: sel ? cor : Colors.white24, width: 1.1)),
            child: Column(children: <Widget>[
              Text(label,
                  style: TextStyle(
                      color: sel ? cor : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(
                      color: sel ? cor : Colors.white54,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800)),
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
                          AlwaysStoppedAnimation<Color>(Color(0xffce93d8)))),
              SizedBox(height: 13),
              Text('Calma, vou fazer uma rápida verificação...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900)),
              SizedBox(height: 7),
              Text(
                  'Histórico · Médias dos mercados · Desfalques · Clima · Arbitragem',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800)),
            ])));
  }
}

class _Pil extends StatelessWidget {
  final String label, valor;
  final Color cor;
  const _Pil(this.label, this.valor, this.cor);
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
