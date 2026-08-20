class CryptoSignal {
  final String pair;
  final String side;
  final double entry;
  final double stop;
  final double target;
  final double rsi;
  final double ema;
  final double precoAtual;
  final String tendencia;
  final String mensagemFormatada;
  final String analiseMacro;

  CryptoSignal({
    this.pair = '',
    this.side = '',
    this.entry = 0.0,
    this.stop = 0.0,
    this.target = 0.0,
    this.rsi = 0.0,
    this.ema = 0.0,
    this.precoAtual = 0.0,
    this.tendencia = '',
    this.mensagemFormatada = '',
    this.analiseMacro = '',
  });

  String get par => pair;
  double get rsi14 => rsi;
  double get ema20 => ema;
  String get quantfuryCopy => mensagemFormatada;

  factory CryptoSignal.fromJson(Map<String, dynamic> json) {
    return CryptoSignal(
      pair: json['pair'] ?? json['symbol'] ?? json['par'] ?? '',
      side: json['side'] ?? json['lado'] ?? '',
      entry: (json['entry'] as num?)?.toDouble() ??
          (json['entrada'] as num?)?.toDouble() ?? 0.0,
      stop: (json['stop'] as num?)?.toDouble() ??
          (json['stop_loss'] as num?)?.toDouble() ?? 0.0,
      target: (json['target'] as num?)?.toDouble() ??
          (json['alvo'] as num?)?.toDouble() ?? 0.0,
      rsi: (json['rsi'] as num?)?.toDouble() ??
          (json['rsi_14'] as num?)?.toDouble() ??
          (json['rsi14'] as num?)?.toDouble() ?? 0.0,
      ema: (json['ema'] as num?)?.toDouble() ??
          (json['ema_20'] as num?)?.toDouble() ??
          (json['ema20'] as num?)?.toDouble() ?? 0.0,
      precoAtual: (json['precoAtual'] as num?)?.toDouble() ??
          (json['current_price'] as num?)?.toDouble() ??
          (json['preco_atual'] as num?)?.toDouble() ?? 0.0,
      tendencia: json['tendencia'] ?? json['trend'] ?? '',
      mensagemFormatada: json['mensagemFormatada'] ??
          json['signal_quantfury'] ??
          json['quantfury_copy'] ??
          json['quantfuryCopy'] ??
          '',
      analiseMacro: json['analiseMacro'] ??
          json['analise_macro'] ??
          json['macro_analysis'] ??
          '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pair': pair,
      'side': side,
      'entry': entry,
      'stop': stop,
      'target': target,
      'rsi': rsi,
      'ema': ema,
      'precoAtual': precoAtual,
      'tendencia': tendencia,
      'mensagemFormatada': mensagemFormatada,
      'analiseMacro': analiseMacro,
    };
  }

  CryptoSignal copyWith({
    String? pair,
    String? side,
    double? entry,
    double? stop,
    double? target,
    double? rsi,
    double? ema,
    double? precoAtual,
    String? tendencia,
    String? mensagemFormatada,
    String? analiseMacro,
  }) {
    return CryptoSignal(
      pair: pair ?? this.pair,
      side: side ?? this.side,
      entry: entry ?? this.entry,
      stop: stop ?? this.stop,
      target: target ?? this.target,
      rsi: rsi ?? this.rsi,
      ema: ema ?? this.ema,
      precoAtual: precoAtual ?? this.precoAtual,
      tendencia: tendencia ?? this.tendencia,
      mensagemFormatada: mensagemFormatada ?? this.mensagemFormatada,
      analiseMacro: analiseMacro ?? this.analiseMacro,
    );
  }
}
