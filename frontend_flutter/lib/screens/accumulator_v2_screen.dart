import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'accumulator_auto_builder_modal.dart';

class AccumulatorV2Screen extends StatefulWidget {
  const AccumulatorV2Screen({super.key});

  @override
  State<AccumulatorV2Screen> createState() => _AccumulatorV2ScreenState();
}

class _AccumulatorV2ScreenState extends State<AccumulatorV2Screen> {
  static const List<Map<String, dynamic>> _jogosHoje = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'v2_01',
      'casa': 'Palmeiras',
      'fora': 'São Paulo',
      'liga': 'Brasileirão',
      'hr': '16:00',
      'odds_casa': 1.55,
      'odds_emp': 3.80,
      'odds_fora': 5.20,
      'esc_med_casa': 5.4,
      'esc_med_fora': 4.8,
      'cart_med_casa': 2.1,
      'cart_med_fora': 2.0,
      'rivalidade_ult5': 1.35,
      'chute_jogador': 'Endrick',
      'chute_med_alvo': 1.3,
      'prob_ia_casa': 68,
      'prob_ia_escanteios': 60,
    },
    <String, dynamic>{
      'id': 'v2_02',
      'casa': 'Flamengo',
      'fora': 'Fluminense',
      'liga': 'Brasileirão',
      'hr': '18:30',
      'odds_casa': 1.90,
      'odds_emp': 3.30,
      'odds_fora': 3.95,
      'esc_med_casa': 6.1,
      'esc_med_fora': 5.2,
      'cart_med_casa': 2.3,
      'cart_med_fora': 2.6,
      'rivalidade_ult5': 1.45,
      'chute_jogador': 'Pedro',
      'chute_med_alvo': 1.6,
      'prob_ia_casa': 58,
      'prob_ia_escanteios': 63,
    },
    <String, dynamic>{
      'id': 'v2_03',
      'casa': 'Botafogo',
      'fora': 'Vasco da Gama',
      'liga': 'Brasileirão',
      'hr': '20:00',
      'odds_casa': 1.75,
      'odds_emp': 3.60,
      'odds_fora': 4.50,
      'esc_med_casa': 5.8,
      'esc_med_fora': 4.5,
      'cart_med_casa': 2.5,
      'cart_med_fora': 2.3,
      'rivalidade_ult5': 1.30,
      'chute_jogador': 'Tiquinho Soares',
      'chute_med_alvo': 1.5,
      'prob_ia_casa': 62,
      'prob_ia_escanteios': 57,
    },
    <String, dynamic>{
      'id': 'v2_04',
      'casa': 'Grêmio',
      'fora': 'Internacional',
      'liga': 'Brasileirão',
      'hr': '21:30',
      'odds_casa': 2.15,
      'odds_emp': 3.10,
      'odds_fora': 3.40,
      'esc_med_casa': 6.0,
      'esc_med_fora': 5.6,
      'cart_med_casa': 2.8,
      'cart_med_fora': 2.9,
      'rivalidade_ult5': 1.55,
      'chute_jogador': 'Luis Suárez',
      'chute_med_alvo': 1.8,
      'prob_ia_casa': 54,
      'prob_ia_escanteios': 68,
    },
    <String, dynamic>{
      'id': 'v2_05',
      'casa': 'Atlético Mineiro',
      'fora': 'Cruzeiro',
      'liga': 'Brasileirão',
      'hr': '19:00',
      'odds_casa': 2.00,
      'odds_emp': 3.20,
      'odds_fora': 3.75,
      'esc_med_casa': 5.7,
      'esc_med_fora': 5.0,
      'cart_med_casa': 2.9,
      'cart_med_fora': 2.8,
      'rivalidade_ult5': 1.50,
      'chute_jogador': 'Hulk',
      'chute_med_alvo': 1.7,
      'prob_ia_casa': 56,
      'prob_ia_escanteios': 62,
    },
    <String, dynamic>{
      'id': 'v2_06',
      'casa': 'Corinthians',
      'fora': 'Santos',
      'liga': 'Brasileirão',
      'hr': '16:00',
      'odds_casa': 1.65,
      'odds_emp': 3.50,
      'odds_fora': 4.90,
      'esc_med_casa': 5.2,
      'esc_med_fora': 4.3,
      'cart_med_casa': 2.2,
      'cart_med_fora': 2.0,
      'rivalidade_ult5': 1.40,
      'chute_jogador': 'Yuri Alberto',
      'chute_med_alvo': 1.4,
      'prob_ia_casa': 65,
      'prob_ia_escanteios': 55,
    },
    <String, dynamic>{
      'id': 'v2_07',
      'casa': 'Red Bull Bragantino',
      'fora': 'Bahia',
      'liga': 'Brasileirão',
      'hr': '18:00',
      'odds_casa': 2.25,
      'odds_emp': 3.15,
      'odds_fora': 3.10,
      'esc_med_casa': 5.6,
      'esc_med_fora': 5.0,
      'cart_med_casa': 2.4,
      'cart_med_fora': 2.4,
      'rivalidade_ult5': 1.15,
      'chute_jogador': 'Sasha',
      'chute_med_alvo': 1.2,
      'prob_ia_casa': 50,
      'prob_ia_escanteios': 59,
    },
    <String, dynamic>{
      'id': 'v2_08',
      'casa': 'Fortaleza',
      'fora': 'Ceará',
      'liga': 'Brasileirão',
      'hr': '21:00',
      'odds_casa': 1.85,
      'odds_emp': 3.40,
      'odds_fora': 4.10,
      'esc_med_casa': 6.2,
      'esc_med_fora': 5.4,
      'cart_med_casa': 2.9,
      'cart_med_fora': 2.8,
      'rivalidade_ult5': 1.52,
      'chute_jogador': 'Thiago Galhardo',
      'chute_med_alvo': 1.5,
      'prob_ia_casa': 59,
      'prob_ia_escanteios': 69,
    },
  ];

  static const List<String> _mercados = <String>[
    'Resultado Final',
    'Escanteios',
    'Cartões',
    'Chutes a Gol / Jogador',
  ];

  final Map<String, bool> _sel = <String, bool>{};
  final Map<String, String> _mercado = <String, String>{};
  final Map<String, String> _opcao = <String, String>{};
  final Map<String, double> _linha = <String, double>{};
  final Map<String, double> _oddSelecionada = <String, double>{};

  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFn = FocusNode();

  List<Map<String, dynamic>> _liveJogos = <Map<String, dynamic>>[];
  bool _liveLoading = true;
  bool _optLoading = false;
  Map<String, dynamic> _ultimaOtimizacao = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    for (Map<String, dynamic> j in _jogosHoje) {
      _sel[j['id']] = false;
      _mercado[j['id']] = _mercados.first;
      _opcao[j['id']] = '';
      _linha[j['id']] = 9.5;
      _oddSelecionada[j['id']] = 0.0;
    }
    _carregarLive();
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    _chatFn.dispose();
    super.dispose();
  }

  List<String> get _idsSelecionados => _sel.entries
      .where((MapEntry<String, bool> e) => e.value)
      .map((MapEntry<String, bool> e) => e.key)
      .toList();

  double get _oddAcumulada {
    double odd = 1.0;
    for (String id in _idsSelecionados) {
      final double? o = _oddSelecionada[id];
      if (o != null && o > 1.0) {
        odd *= o;
      }
    }
    return odd > 1 ? odd : 0;
  }

  Future<void> _carregarLive() async {
    setState(() => _liveLoading = true);
    try {
      final String base = await ApiService.resolveV1();
      final String url = '$base/sports/live-list';
      final http.Response r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final Map<String, dynamic> d =
            Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        final List<dynamic> list =
            (d['jogos'] as List<dynamic>?) ?? <dynamic>[];
        if (!mounted) return;
        setState(() {
          _liveJogos = list
              .map<Map<String, dynamic>>(
                  (dynamic e) => Map<String, dynamic>.from(e as Map))
              .toList(growable: false);
          _liveLoading = false;
        });
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _liveJogos = List<Map<String, dynamic>>.unmodifiable(
          _jogosHoje.map<Map<String, dynamic>>(
              (Map<String, dynamic> j) => <String, dynamic>{
                    'casa': j['casa'],
                    'fora': j['fora'],
                    'liga': j['liga'],
                    'horario_local': j['hr'],
                    'status_sigla': 'AGENDADO',
                    'status_texto': 'AGENDADO',
                    'minuto_jogo': 0,
                    'placar_casa': 0,
                    'placar_fora': 0,
                    'em_jogo_agora': false,
                    'atualizado_por': 'IA do Tiago',
                  }));
      _liveLoading = false;
    });
  }

  List<Map<String, dynamic>> _opcoesMercado(
      String mercadoId, Map<String, dynamic> jogo) {
    final List<double> r = <double>[
      jogo['odds_casa'] as double,
      jogo['odds_emp'] as double,
      jogo['odds_fora'] as double,
    ];
    switch (mercadoId) {
      case 'Resultado Final':
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Casa',
            'label':
                'Casa (${jogo['casa'].toString().substring(0, jogo['casa'].toString().length > 3 ? 3 : jogo['casa'].toString().length)})',
            'odd': r[0],
            'linha': 0.0,
            'prob': jogo['prob_ia_casa']
          },
          <String, dynamic>{
            'chave': 'Empate',
            'label': 'Empate',
            'odd': r[1],
            'linha': 0.0,
            'prob': 100 - (jogo['prob_ia_casa'] as int)
          },
          <String, dynamic>{
            'chave': 'Fora',
            'label': 'Fora (${jogo['fora'].toString().substring(0, 3)})',
            'odd': r[2],
            'linha': 0.0,
            'prob': 100 - (jogo['prob_ia_casa'] as int)
          },
        ];
      case 'Escanteios':
        final double prob = jogo['prob_ia_escanteios'] as double;
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Mais 8.5',
            'label': '+8.5 escanteios',
            'odd': 1.75,
            'linha': 8.5,
            'prob': prob
          },
          <String, dynamic>{
            'chave': 'Mais 9.5',
            'label': '+9.5 escanteios',
            'odd': 1.95,
            'linha': 9.5,
            'prob': prob - 3
          },
          <String, dynamic>{
            'chave': 'Mais 10.5',
            'label': '+10.5 escanteios',
            'odd': 2.30,
            'linha': 10.5,
            'prob': prob - 9
          },
        ];
      case 'Cartões':
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Mais 4.5',
            'label': '+4.5 cartões',
            'odd': 1.55,
            'linha': 4.5,
            'prob': 70
          },
          <String, dynamic>{
            'chave': 'Mais 5.5',
            'label': '+5.5 cartões',
            'odd': 1.82,
            'linha': 5.5,
            'prob': 65
          },
          <String, dynamic>{
            'chave': 'Mais 6.5',
            'label': '+6.5 cartões',
            'odd': 2.12,
            'linha': 6.5,
            'prob': 59
          },
        ];
      case 'Chutes a Gol / Jogador':
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'chave': 'Sim',
            'label': '${jogo['chute_jogador']} · 1+ chute no alvo',
            'odd': (jogo['chute_med_alvo'] as double) < 1.5 ? 1.80 : 2.15,
            'linha': 0.5,
            'prob': 58
          },
        ];
      default:
        return const <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _selecoesPayload() {
    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
    for (String id in _idsSelecionados) {
      final Map<String, dynamic> j =
          _jogosHoje.firstWhere((Map<String, dynamic> e) => e['id'] == id);
      final String opc = _opcao[id] ?? '';
      final Map<String, dynamic> stats = <String, dynamic>{
        'media_casa': 0.0,
        'media_fora': 0.0,
        'rivalidade_ult5': j['rivalidade_ult5'],
      };
      final String mercado = _mercado[id] ?? '';
      if (mercado == 'Escanteios') {
        stats['media_casa'] = j['esc_med_casa'] as double;
        stats['media_fora'] = j['esc_med_fora'] as double;
      } else if (mercado == 'Cartões') {
        stats['media_casa'] = j['cart_med_casa'] as double;
        stats['media_fora'] = j['cart_med_fora'] as double;
      } else if (mercado == 'Chutes a Gol / Jogador') {
        stats['media_casa'] = j['chute_med_alvo'] as double;
        stats['media_fora'] = 0.3;
      }
      payload.add(<String, dynamic>{
        'id': id,
        'casa': j['casa'],
        'fora': j['fora'],
        'mercado': mercado,
        'escolha': opc,
        'escolha_linha_numerica': _linha[id],
        'odd_apostada': _oddSelecionada[id] ?? 0,
        'probabilidade_ia': (_opcoesMercado(mercado, j)
                    .cast<Map<String, dynamic>?>()
                    .firstWhere(
                        (Map<String, dynamic>? m) => (m?['chave'] ?? '') == opc,
                        orElse: () => <String, dynamic>{'prob': 50}) ??
                <String, dynamic>{'prob': 50})['prob'] as double? ??
            50,
        'estatisticas': stats,
      });
    }
    return <String, dynamic>{
      'selecoes': payload,
      'stake_total_usd': 100.0,
      'perfil_risco_usuario': 'moderado',
      'meta_pct_hit_alvo': 70.0,
    };
  }

  Future<void> _ajustarComIA({String? comando}) async {
    final Map<String, dynamic> data = _selecoesPayload();
    if ((data['selecoes'] as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AppTheme.flashLiveRed,
          content: Text('Selecione pelo menos 1 jogo.',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700))));
      return;
    }
    setState(() => _optLoading = true);
    try {
      final Map<String, dynamic> body = <String, dynamic>{
        'user_id': 'default',
        'stake_total_usd': data['stake_total_usd'],
        'perfil_risco_usuario': data['perfil_risco_usuario'],
        'meta_pct_hit_alvo': data['meta_pct_hit_alvo'],
        'selecoes': data['selecoes'],
        if (comando != null && comando.trim().isNotEmpty)
          'comando_usuario': comando,
      };
      final String base = await ApiService.resolveV1();
      final String url = '$base/sports/optimize-accumulator';
      final http.Response r = await http
          .post(Uri.parse(url),
              headers: const <String, String>{
                'Content-Type': 'application/json'
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final Map<String, dynamic> opt =
            Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        _aplicarOtimizacao(opt);
        if (!mounted) return;
        setState(() {
          _ultimaOtimizacao = opt;
          _optLoading = false;
        });
        _mostrarModalOtimizacao(opt);
        return;
      }
    } catch (_) {}
    final Map<String, dynamic> fallback =
        _fallbackOtimizacao(data, comando: comando);
    _aplicarOtimizacao(fallback);
    if (!mounted) return;
    setState(() {
      _ultimaOtimizacao = fallback;
      _optLoading = false;
    });
    _mostrarModalOtimizacao(fallback);
  }

  void _aplicarOtimizacao(Map<String, dynamic> opt) {
    final List<dynamic> finalSel =
        (opt['selecoes_ajustadas_finais'] as List<dynamic>?) ?? <dynamic>[];
    final Set<String> manter = <String>{};
    for (dynamic s in finalSel) {
      final String? id = (s as Map)['id']?.toString();
      if (id == null) continue;
      manter.add(id);
      final double? novaLinha =
          double.tryParse((s['escolha_linha_numerica'] ?? 0).toString());
      if (novaLinha != null) {
        _linha[id] = novaLinha;
      }
    }
    for (String id in List<String>.from(_sel.keys)) {
      if (_sel[id] == true && !manter.contains(id)) {
        _sel[id] = false;
      }
    }
  }

  Map<String, dynamic> _fallbackOtimizacao(Map<String, dynamic> data,
      {String? comando}) {
    final List<Map<String, dynamic>> orig =
        List<Map<String, dynamic>>.from((data['selecoes'] as List).cast<Map>());
    final bool removerArriscados =
        (comando ?? '').toLowerCase().contains('arrisc');
    final bool baixarLinha = (comando ?? '').toLowerCase().contains('baix') ||
        (comando ?? '').toLowerCase().contains('segur');
    final List<Map<String, dynamic>> ajustadas = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> porSel = <Map<String, dynamic>>[];
    for (Map<String, dynamic> sel in orig) {
      final double prob = (sel['probabilidade_ia'] as num?)?.toDouble() ?? 50;
      final double linha =
          (sel['escolha_linha_numerica'] as num?)?.toDouble() ?? 0;
      final Map<String, dynamic> stats = Map<String, dynamic>.from(
          sel['estatisticas'] as Map? ?? const <String, dynamic>{});
      final double mc = (stats['media_casa'] as num?)?.toDouble() ?? 0;
      final double mf = (stats['media_fora'] as num?)?.toDouble() ?? 0;
      final double rival = (stats['rivalidade_ult5'] as num?)?.toDouble() ?? 1;
      final String mercado = sel['mercado']?.toString().toLowerCase() ?? '';
      bool mantem = !removerArriscados || prob >= 56;
      double novaLinha = linha;
      double pctAntes = prob;
      double pctDepois = prob;
      double melhoria = 0;
      bool ajuste = false;
      String orientacao = 'Linha atual consistente.';
      if (mercado.contains('escan') ||
          mercado.contains('cartao') ||
          mercado.contains('chute')) {
        final double proj = (mc + mf) * (0.85 + 0.15 * rival);
        if ((baixarLinha || (proj > 0 && linha - proj > 1.3)) && linha > 3.0) {
          novaLinha = linha - 1.0;
          ajuste = true;
          pctDepois = pctAntes + (mercado.contains('escan') ? 11 : 8);
          melhoria = pctDepois - pctAntes;
          orientacao =
              'Baixe a linha de +${linha.toStringAsFixed(1)} para +${novaLinha.toStringAsFixed(1)}. Chance de acerto: ${pctAntes.toStringAsFixed(0)}% → ${pctDepois.toStringAsFixed(0)}% (melhoria de +${melhoria.toStringAsFixed(1)}pp).';
        }
      }
      porSel.add(<String, dynamic>{
        'entrada': sel,
        'calibracao_linha': <String, dynamic>{
          'assinatura': 'IA do Tiago',
          'ajuste_recomendado': ajuste,
          'linha_atual': linha,
          'linha_sugerida': novaLinha,
          'probabilidade_hit_antes_pct': pctAntes,
          'probabilidade_hit_depois_pct': pctDepois,
          'melhoria_pontos_pct': melhoria,
          'orientacao_texto': orientacao,
          'projecao_mercado_90min': (mc + mf) * 1.0,
        },
      });
      if (mantem) {
        ajustadas.add(<String, dynamic>{
          ...sel,
          'escolha_linha_numerica': novaLinha,
        });
      }
    }
    return <String, dynamic>{
      'assinatura': 'IA do Tiago',
      'servicos_utilizados':
          'IA do Tiago (referência) + IA do Tiago (calibragem/guia/comando)',
      'perfil_risco_usuario': data['perfil_risco_usuario'],
      'stake_total_usd': data['stake_total_usd'],
      'meta_pct_hit_alvo': data['meta_pct_hit_alvo'],
      'por_selecao': porSel,
      'guia_como_apostar_para_ganhar': <String, dynamic>{
        'assinatura': 'IA do Tiago',
        'perfil_risco': data['perfil_risco_usuario'],
        'momento_ideal_entrada': ajustadas.length >= (orig.length / 2).ceil()
            ? '🟡 Entrada Híbrida: metade Pré-Jogo + metade após 15min Ao Vivo confirmando padrão de posse, cantos e pressão.'
            : '✅ Pode entrar Pré-Jogo — confiabilidade média >= 60%.',
        'tipo_bilhete_ideal': ajustadas.length <= 2
            ? 'Bilhete simples / dupla.'
            : ajustadas.length <= 4
                ? 'Múltipla 3-4 jogos · ideal para Favoritos + Linha.'
                : 'Múltipla longa · dividir em 2 bilhetes de 3-4 jogos.',
        'gestao_banca': <String, dynamic>{
          'max_stake_por_jogo_pct_banca': 2.5,
          'max_stake_por_jogo_usd': 25,
          'max_stake_bilhete_inteiro_usd': 50,
          'nivel_gerenciamento': 'médio',
        },
      },
      'comando_usuario': comando == null
          ? null
          : <String, dynamic>{
              'comando_recebido': comando,
              'acoes_aplicadas_resumo': <String>[
                if (removerArriscados)
                  'Removidas ${orig.length - ajustadas.length} seleção(ões) arriscada(s).',
                if (baixarLinha)
                  '${porSel.where((Map<String, dynamic> m) => (m['calibracao_linha'] as Map)['ajuste_recomendado'] == true).length} linha(s) reduzida(s).',
              ],
              'quantidade_selecoes_antes': orig.length,
              'quantidade_selecoes_depois': ajustadas.length,
            },
      'selecoes_ajustadas_finais': ajustadas,
    };
  }

  void _mostrarModalOtimizacao(Map<String, dynamic> opt) {
    showModalBottomSheet<dynamic>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            _OptModal(opt: opt, onCopiar: _copiar, onWhats: _whats));
  }

  String _textoBilhete() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('🎯 BILHETE MÚLTIPLA · IA do Tiago');
    sb.writeln('================================');
    double odd = 1.0;
    int n = 0;
    for (String id in _idsSelecionados) {
      final Map<String, dynamic> j =
          _jogosHoje.firstWhere((Map<String, dynamic> e) => e['id'] == id);
      final double? o = _oddSelecionada[id];
      if (o == null || o <= 1) continue;
      n++;
      odd *= o;
      sb.writeln('\n$n. ${j['casa']} x ${j['fora']} · ${_mercado[id]}');
      sb.writeln('   ${_opcao[id]} · Odd ${o.toStringAsFixed(2)}');
    }
    if (n == 0) return 'Nenhuma seleção ativa.';
    sb.writeln('\n================================');
    sb.writeln('Odd acumulada final: ${odd.toStringAsFixed(2)}');
    sb.writeln('Assinatura: IA do Tiago');
    return sb.toString();
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _textoBilhete()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AppTheme.neonGreen,
          content: Text('📋 Copiado · assinatura IA do Tiago',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700))));
    }
  }

  Future<void> _whats() async {
    final Uri u = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(_textoBilhete())}');
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
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
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white70, size: 22)),
        title: const Row(children: <Widget>[
          Icon(Icons.sports_soccer_rounded, color: Color(0xff00e676), size: 23),
          SizedBox(width: 9),
          Text('Múltiplas V2 · IA do Tiago',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
        ]),
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 280),
              child: CustomScrollView(
                slivers: <Widget>[
                  SliverToBoxAdapter(child: _livePainel()),
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),
                  SliverToBoxAdapter(child: _chatRapido()),
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),
                  SliverToBoxAdapter(child: _botaoMontarMultiplaPelaIA()),
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext c, int i) {
                        final Map<String, dynamic> j = _jogosHoje[i];
                        final Map<String, dynamic> l = _liveJogos
                                .cast<Map<String, dynamic>?>()
                                .firstWhere(
                                    (Map<String, dynamic>? m) =>
                                        (m?['casa'] == j['casa'] &&
                                            m?['fora'] == j['fora']),
                                    orElse: () => <String, dynamic>{}) ??
                            <String, dynamic>{};
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _JogoV2(
                              jogo: j,
                              liveInfo: l,
                              sel: _sel[j['id']] ?? false,
                              mercado: _mercado[j['id']] ?? '',
                              opcao: _opcao[j['id']] ?? '',
                              mercados: _mercados,
                              opcoes:
                                  _opcoesMercado(_mercado[j['id']] ?? '', j),
                              onSel: (bool v) => setState(() {
                                    _sel[j['id']] = v;
                                    if (!v) {
                                      _opcao[j['id']] = '';
                                      _oddSelecionada[j['id']] = 0;
                                    }
                                  }),
                              onMercado: (String? m) => setState(() {
                                    _mercado[j['id']] = m ?? _mercados.first;
                                    _opcao[j['id']] = '';
                                    _oddSelecionada[j['id']] = 0;
                                  }),
                              onOpcao:
                                  (String? chave, double odd, double linha) {
                                setState(() {
                                  _opcao[j['id']] = chave ?? '';
                                  _linha[j['id']] = linha;
                                  _oddSelecionada[j['id']] = odd;
                                  _sel[j['id']] = true;
                                });
                              }),
                        );
                      },
                      childCount: _jogosHoje.length,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _rodapeFixado()),
          ],
        ),
      ),
    );
  }

  Widget _livePainel() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: const Color(0xff121f29),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: AppTheme.flashLiveRed.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.flashLiveRed.withValues(alpha: 0.5))),
                child: const Icon(Icons.live_tv_rounded,
                    color: AppTheme.flashLiveRed, size: 17)),
            const SizedBox(width: 9),
            const Expanded(
                child: Text('Jogos de Hoje · Atualizado por IA do Tiago',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900))),
            TextButton.icon(
                onPressed: _liveLoading ? null : _carregarLive,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppTheme.neonGreen),
                icon: _liveLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.neonGreen)))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Atualizar',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 7),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 7),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _liveJogos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (BuildContext c, int i) {
                final Map<String, dynamic> l = _liveJogos[i];
                final bool aoVivo = (l['em_jogo_agora']?.toString() ==
                        'true') ||
                    (l['status_sigla']?.toString().startsWith('1H') ?? false) ||
                    (l['status_sigla']?.toString().startsWith('2H') ?? false);
                final Color cor =
                    aoVivo ? AppTheme.flashLiveRed : Colors.white30;
                return Container(
                  padding: const EdgeInsets.all(8.5),
                  width: 165,
                  decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cor.withValues(alpha: 0.45))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(children: <Widget>[
                          if (aoVivo)
                            Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                    color: AppTheme.flashLiveRed,
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('AO VIVO ${l['minuto_jogo']}\'',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900)))
                          else
                            Text(l['horario_local']?.toString() ?? '--:--',
                                style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text(l['placar_casa']?.toString() ?? '0',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900)),
                          const Text(' x ',
                              style: TextStyle(
                                  color: Colors.white30,
                                  fontWeight: FontWeight.w900)),
                          Text(l['placar_fora']?.toString() ?? '0',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900)),
                        ]),
                        const SizedBox(height: 5),
                        Text('${l['casa']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                        Text('${l['fora']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatRapido() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: const Color(0xff121f29),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: const Color(0xff9c27b0).withValues(alpha: 0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(children: <Widget>[
            Icon(Icons.auto_awesome_rounded,
                color: Color(0xffce93d8), size: 17),
            SizedBox(width: 7),
            Flexible(
                child: Text('💬 Peça para a IA do Tiago Ajustar',
                    style: TextStyle(
                        color: Color(0xffce93d8),
                        fontSize: 12,
                        fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 7),
          const Text(
              'Exemplos:\n• "Tiago, tire os jogos arriscados e deixe o bilhete com 80% de chance"\n• "Tiago, otimize essa múltipla" / "Baixe todas as linhas para ficar mais seguro".',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 10.5,
                  height: 1.4,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                focusNode: _chatFn,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  hintText: 'Diga o que quer ajustar...',
                  hintStyle: TextStyle(color: Colors.white38),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _ajustarComIA(comando: _chatCtrl.text),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
                height: 45,
                child: ElevatedButton.icon(
                    onPressed: _optLoading
                        ? null
                        : () => _ajustarComIA(comando: _chatCtrl.text),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff9c27b0),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    icon: _optLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white)))
                        : const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Enviar',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w900)))),
          ]),
        ],
      ),
    );
  }

  Widget _botaoMontarMultiplaPelaIA() {
    return GestureDetector(
        onTap: () => AccumulatorAutoBuilderModal.show(context),
        child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: <Color>[Color(0xff121f29), Color(0xff1a2a40)]),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: const Color(0xff9c27b0).withValues(alpha: 0.6)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: const Color(0xff9c27b0).withValues(alpha: 0.12),
                      blurRadius: 12)
                ]),
            child: Row(children: <Widget>[
              Container(
                  padding: const EdgeInsets.all(9.5),
                  decoration: BoxDecoration(
                      color: const Color(0xffce93d8).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color:
                              const Color(0xffce93d8).withValues(alpha: 0.6))),
                  child: const Icon(Icons.smart_toy_rounded,
                      color: Color(0xffce93d8), size: 20)),
              const SizedBox(width: 10),
              const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                    Text(
                        '🤖 Pedir para a IA do Tiago Montar Minha Múltipla Completa',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.2,
                            height: 1.25,
                            fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text(
                        'Seleciona Cartões / Escanteios / Chutes a Gol · Autocorreção · Odd Total calculada',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10.2,
                            height: 1.25,
                            fontWeight: FontWeight.w700)),
                  ])),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Color(0xffce93d8), size: 16)
            ])));
  }

  Widget _rodapeFixado() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      decoration: BoxDecoration(
          color: const Color(0xff0f1c25),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: Colors.white12),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 22,
                spreadRadius: 4)
          ]),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                const Text('Bilhete · IA do Tiago',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                    '${_idsSelecionados.length} jogos · Odd acumulada ${_oddAcumulada > 1 ? _oddAcumulada.toStringAsFixed(2) : '--'}',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ])),
          Row(children: <Widget>[
            IconButton(
                onPressed: _idsSelecionados.isEmpty ? null : _copiar,
                icon: const Icon(Icons.copy_rounded,
                    color: AppTheme.neonGreen, size: 21)),
            IconButton(
                onPressed: _idsSelecionados.isEmpty ? null : _whats,
                icon: const Icon(Icons.chat_bubble_rounded,
                    color: Color(0xff25d366), size: 22)),
          ]),
        ]),
        const SizedBox(height: 9),
        Row(children: <Widget>[
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: _optLoading || _idsSelecionados.isEmpty
                      ? null
                      : () => _ajustarComIA(),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.neonGreen,
                      side: const BorderSide(
                          color: AppTheme.neonGreen, width: 1.2),
                      backgroundColor:
                          AppTheme.neonGreen.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.bolt_rounded, size: 17),
                  label: const FittedBox(
                      child: Text('⚡ Ajustar Conforme IA do Tiago',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w900))))),
        ]),
      ]),
    );
  }
}

class _JogoV2 extends StatelessWidget {
  final Map<String, dynamic> jogo, liveInfo;
  final bool sel;
  final String mercado, opcao;
  final List<String> mercados;
  final List<Map<String, dynamic>> opcoes;
  final ValueChanged<bool> onSel;
  final ValueChanged<String?> onMercado;
  final void Function(String?, double odd, double linha) onOpcao;
  const _JogoV2({
    required this.jogo,
    required this.liveInfo,
    required this.sel,
    required this.mercado,
    required this.opcao,
    required this.mercados,
    required this.opcoes,
    required this.onSel,
    required this.onMercado,
    required this.onOpcao,
  });

  @override
  Widget build(BuildContext context) {
    final bool aoVivo = (liveInfo['em_jogo_agora'] == true) ||
        (liveInfo['status_sigla']?.toString().startsWith('1H') ?? false) ||
        (liveInfo['status_sigla']?.toString().startsWith('2H') ?? false);
    final Color liveCor = sel
        ? AppTheme.neonGreen
        : aoVivo
            ? AppTheme.flashLiveRed
            : Colors.white24;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xff121f29),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: liveCor.withValues(alpha: 0.5), width: 1.2),
          boxShadow: sel
              ? <BoxShadow>[
                  BoxShadow(
                      color: AppTheme.neonGreen.withValues(alpha: 0.12),
                      blurRadius: 12)
                ]
              : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                    value: sel,
                    activeColor: AppTheme.neonGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    side: const BorderSide(color: Colors.white38),
                    onChanged: (bool? v) => onSel(v ?? false))),
            const SizedBox(width: 7),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(
                        child: Text('${jogo['casa']} × ${jogo['fora']}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900))),
                    if (aoVivo)
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppTheme.flashLiveRed,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(
                              'AO VIVO ${liveInfo['minuto_jogo'] ?? '--'}\'',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900)))
                    else
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('${jogo['hr']} · ${jogo['liga']}',
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800))),
                  ]),
                ])),
          ]),
          if (sel) ...<Widget>[
            const SizedBox(height: 9),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: mercados
                    .map<Widget>((String m) => GestureDetector(
                        onTap: () => onMercado(m),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                                color: mercado == m
                                    ? const Color(0xff9c27b0)
                                        .withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                    color: mercado == m
                                        ? const Color(0xffce93d8)
                                        : Colors.white24)),
                            child: Text(m,
                                style: TextStyle(
                                    color:
                                        mercado == m ? const Color(0xffce93d8) : Colors.white70,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800)))))
                    .toList(growable: false)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: opcoes
                    .map<Widget>((Map<String, dynamic> o) => ChoiceChip(
                        label: Text('${o['label']} · @ ${(o['odd'] as double).toStringAsFixed(2)}',
                            style: TextStyle(
                                color: opcao == o['chave']
                                    ? Colors.black
                                    : Colors.white70,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800)),
                        selected: opcao == o['chave'],
                        selectedColor: AppTheme.neonGreen,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        side: BorderSide(
                            color: opcao == o['chave']
                                ? AppTheme.neonGreen
                                : Colors.white24),
                        onSelected: (_) => onOpcao(
                            o['chave'] as String?,
                            (o['odd'] as num).toDouble(),
                            (o['linha'] as num).toDouble()),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9))))
                    .toList(growable: false)),
          ],
        ],
      ),
    );
  }
}

class _OptModal extends StatelessWidget {
  final Map<String, dynamic> opt;
  final VoidCallback onCopiar, onWhats;
  const _OptModal(
      {required this.opt, required this.onCopiar, required this.onWhats});

  @override
  Widget build(BuildContext context) {
    final double sh = MediaQuery.of(context).size.height;
    final List<dynamic> por =
        (opt['por_selecao'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> guia = Map<String, dynamic>.from(
        (opt['guia_como_apostar_para_ganhar'] as Map<String, dynamic>?) ??
            const <String, dynamic>{});
    final Map<String, dynamic>? cmd = opt['comando_usuario'] == null
        ? null
        : Map<String, dynamic>.from(opt['comando_usuario'] as Map);
    return Container(
      height: sh * 0.92,
      decoration: const BoxDecoration(
          color: Color(0xff0a141b),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        child: Column(children: <Widget>[
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                      color: const Color(0xff9c27b0).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color:
                              const Color(0xff9c27b0).withValues(alpha: 0.5))),
                  child: Row(children: <Widget>[
                    Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                            color:
                                const Color(0xffce93d8).withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: const Color(0xffce93d8)
                                    .withValues(alpha: 0.5))),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Color(0xffce93d8), size: 22)),
                    const SizedBox(width: 11),
                    const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                          Text('IA do Tiago · Otimização Concluída',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900)),
                          SizedBox(height: 3),
                          Text(
                              'Ajustes de linha + recomendações · Assinatura IA do Tiago',
                              style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ])),
                    const SizedBox(width: 8),
                    Row(children: <Widget>[
                      IconButton(
                          onPressed: onCopiar,
                          icon: const Icon(Icons.copy_rounded,
                              color: AppTheme.neonGreen, size: 21)),
                      IconButton(
                          onPressed: onWhats,
                          icon: const Icon(Icons.chat_bubble_rounded,
                              color: Color(0xff25d366), size: 22)),
                    ]),
                  ]))),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Divider(color: Colors.white12, height: 1)),
          const SizedBox(height: 7),
          if (guia.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.neonGreen.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.neonGreen.withValues(alpha: 0.4))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('💡 Como Apostar Para Ganhar',
                            style: TextStyle(
                                color: AppTheme.neonGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Text('${guia['momento_ideal_entrada'] ?? ''}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.4,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text('• ${guia['tipo_bilhete_ideal'] ?? ''}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                            '• Stake: máx ${((guia['gestao_banca'] as Map? ?? const <String, dynamic>{})['max_stake_por_jogo_pct_banca'] ?? 0)}% por jogo · até \$${((guia['gestao_banca'] as Map? ?? const <String, dynamic>{})['max_stake_bilhete_inteiro_usd'] ?? 0)} no bilhete.',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ])),
            ),
          if (cmd != null) ...<Widget>[
            const SizedBox(height: 8),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xff9c27b0).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xff9c27b0)
                                .withValues(alpha: 0.45))),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                              '🤖 Resposta ao comando: "${cmd['comando_recebido']}"',
                              style: const TextStyle(
                                  color: Color(0xffce93d8),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 5),
                          for (dynamic a in (cmd['acoes_aplicadas_resumo']
                                  as List<dynamic>? ??
                              <dynamic>[]))
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 1.5),
                                child: Text('✅ ${a.toString()}',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700))),
                          const SizedBox(height: 4),
                          Text(
                              'Seleções: ${cmd['quantidade_selecoes_antes']} → ${cmd['quantidade_selecoes_depois']}',
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800)),
                        ]))),
          ],
          const SizedBox(height: 8),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                  children: <Widget>[
                for (dynamic s in por) ...<Widget>[
                  _itemCalibracao(Map<String, dynamic>.from(s as Map)),
                  const SizedBox(height: 9),
                ],
              ])),
        ]),
      ),
    );
  }

  Widget _itemCalibracao(Map<String, dynamic> s) {
    final Map<String, dynamic> entrada = Map<String, dynamic>.from(
        s['entrada'] as Map? ?? const <String, dynamic>{});
    final Map<String, dynamic> cal = Map<String, dynamic>.from(
        s['calibracao_linha'] as Map? ?? const <String, dynamic>{});
    final bool ajustou = cal['ajuste_recomendado']?.toString() == 'true';
    final Color cor = ajustou ? AppTheme.neonGreen : Colors.white38;
    final double antes =
        (cal['probabilidade_hit_antes_pct'] as num?)?.toDouble() ?? 0;
    final double depois =
        (cal['probabilidade_hit_depois_pct'] as num?)?.toDouble() ?? 0;
    final double melhoria =
        (cal['melhoria_pontos_pct'] as num?)?.toDouble() ?? 0;
    return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: const Color(0xff111d27),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cor.withValues(alpha: 0.55), width: 1.1),
            boxShadow: <BoxShadow>[
              BoxShadow(color: cor.withValues(alpha: 0.10), blurRadius: 10)
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                    child: Text(
                        '${entrada['casa']} × ${entrada['fora']} · ${entrada['mercado']}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900))),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: cor.withValues(alpha: 0.5))),
                    child: Text(
                        ajustou ? '+${melhoria.toStringAsFixed(1)}pp' : 'OK',
                        style: TextStyle(
                            color: cor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 6),
              Text(
                  'Linha: +${(cal['linha_atual'] as num? ?? 0).toDouble().toStringAsFixed(1)} → '
                  '+${(cal['linha_sugerida'] as num? ?? 0).toDouble().toStringAsFixed(1)} · '
                  'Prob: ${antes.toStringAsFixed(0)}% → ${depois.toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              if ((cal['orientacao_texto']?.toString().length ?? 0) >
                  0) ...<Widget>[
                const SizedBox(height: 5),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(7.5),
                    decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(9)),
                    child: Text('💡 ${cal['orientacao_texto']}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10.5,
                            height: 1.4,
                            fontWeight: FontWeight.w700))),
              ],
            ]));
  }
}
