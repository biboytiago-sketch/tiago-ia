import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/bookmaker_registry.dart';

typedef SelecaoBilhete = ({
  int numero,
  String timeCasa,
  String timeFora,
  String mercado,
  double odd,
  String? liga,
  String? horario,
});

typedef BilhetePronto = ({
  DateTime data,
  List<SelecaoBilhete> selecoes,
  double oddsTotais,
  double stakeBRL,
  double? retornoPotencialBRL,
  String? perfil,
  String? risco,
});

abstract class BetExportEngine {
  static String formatarBilheteTexto(BilhetePronto b) {
    final StringBuffer buf = StringBuffer();
    final String data =
        '${b.data.day.toString().padLeft(2, '0')}/${b.data.month.toString().padLeft(2, '0')}/${b.data.year}';
    buf.writeln('🎯 Bilhete IA - $data');
    if (b.perfil != null && b.perfil!.isNotEmpty) {
      buf.writeln(
          '📊 Perfil: ${b.perfil}${b.risco != null ? ' · Risco ${b.risco}' : ''}');
    }
    buf.writeln('');
    for (int i = 0; i < b.selecoes.length; i++) {
      final SelecaoBilhete s = b.selecoes[i];
      final String linha =
          '${i + 1}. ${s.timeCasa} x ${s.timeFora} - ${s.mercado} @ ${s.odd.toStringAsFixed(2)}';
      buf.writeln(linha);
      if (s.liga != null && s.liga!.isNotEmpty) {
        String extra = '    📍 ${s.liga!}';
        if (s.horario != null && s.horario!.isNotEmpty) {
          extra += ' · 🕒 ${s.horario!}';
        }
        buf.writeln(extra);
      }
    }
    buf.writeln('');
    buf.writeln('Odds Totais: ${b.oddsTotais.toStringAsFixed(2)}');
    if (b.retornoPotencialBRL != null) {
      buf.writeln(
          'Retorno Potencial (R\$ ${b.stakeBRL.toStringAsFixed(2)}): R\$ ${b.retornoPotencialBRL!.toStringAsFixed(2)}');
    }
    buf.writeln('Aposta Sugerida: R\$ ${b.stakeBRL.toStringAsFixed(2)}');
    return buf.toString();
  }

  static Future<void> copiarParaClipboard(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
  }

  static Future<bool> temAppInstalado(BookmakerConfig casa) async {
    if (casa.appScheme == null || casa.appScheme!.isEmpty) return false;
    try {
      final Uri uri = Uri.parse(casa.appScheme!);
      return await canLaunchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> abrirCasaDeApostas(BookmakerConfig casa) async {
    try {
      if (casa.appScheme != null && casa.appScheme!.isNotEmpty) {
        final Uri appUri = Uri.parse(casa.appScheme!);
        if (await canLaunchUrl(appUri)) {
          if (await launchUrl(appUri,
              mode: LaunchMode.externalNonBrowserApplication,
              webOnlyWindowName: '_self')) {
            return true;
          }
        }
      }
      final Uri webUri = Uri.parse(casa.webUrl);
      return launchUrl(webUri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      final Uri webUri = Uri.parse(casa.webUrl);
      return launchUrl(webUri,
          mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank');
    }
  }

  static Future<String?> exportarParaArquivo(BilhetePronto b) async {
    final String texto = formatarBilheteTexto(b);
    return texto;
  }

  static bool get isWeb => identical(0, 1.0)
      ? false
      : const bool.fromEnvironment('dart.library.js_util');

  static String plataformaLabel() {
    if (isWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Desconhecido';
  }
}
