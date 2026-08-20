enum StatusJogo { AO_VIVO, PROXIMO, ENCERRADO, DESCONHECIDO }

StatusJogo _statusFromString(String? value) {
  switch (value?.toUpperCase()) {
    case 'AO_VIVO':
    case 'LIVE':
      return StatusJogo.AO_VIVO;
    case 'PROXIMO':
    case 'UPCOMING':
      return StatusJogo.PROXIMO;
    case 'ENCERRADO':
    case 'FINALIZADO':
    case 'FINISHED':
      return StatusJogo.ENCERRADO;
    default:
      return StatusJogo.DESCONHECIDO;
  }
}

enum CategoriaSinal {
  ACERTOS_80,
  MULTIPLE_80,
  LOW_ODDS_155,
  VALUE,
  EVITAR,
}

CategoriaSinal _categoriaFromString(String? value) {
  switch (value?.toUpperCase()) {
    case 'ACERTOS_80':
    case 'SNIPER_80':
      return CategoriaSinal.ACERTOS_80;
    case 'MULTIPLE_80':
      return CategoriaSinal.MULTIPLE_80;
    case 'LOW_ODDS_155':
      return CategoriaSinal.LOW_ODDS_155;
    case 'VALUE':
      return CategoriaSinal.VALUE;
    case 'EVITAR':
      return CategoriaSinal.EVITAR;
    default:
      return CategoriaSinal.VALUE;
  }
}

class MatchModel {
  final String id;
  final String timeCasa;
  final String timeFora;
  final String campeonato;
  final double oddCasa;
  final double oddEmpate;
  final double oddFora;
  final CategoriaSinal categoria;
  final String horario;
  final double probabilidade;
  final bool selecionado;

  // ---- FlashScore obrigatórios ----
  final String dataJogo;
  final String ligaNome;
  final String ligaPais;
  final String ligaBandeira;
  final StatusJogo status;
  final int? minutoLive;
  final int? placarCasa;
  final int? placarFora;
  final List<String> alertas;

  MatchModel({
    this.id = '',
    this.timeCasa = '',
    this.timeFora = '',
    this.campeonato = '',
    this.oddCasa = 0.0,
    this.oddEmpate = 0.0,
    this.oddFora = 0.0,
    this.categoria = CategoriaSinal.VALUE,
    this.horario = '',
    this.probabilidade = 0.0,
    this.selecionado = false,
    this.dataJogo = '',
    this.ligaNome = '',
    this.ligaPais = '',
    this.ligaBandeira = '🌍',
    this.status = StatusJogo.PROXIMO,
    this.minutoLive,
    this.placarCasa,
    this.placarFora,
    this.alertas = const <String>[],
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    String readStr(String camel, String snake) =>
        (json[camel] as String?) ?? (json[snake] as String?) ?? '';
    double readNum(String camel, String snake) {
      final v = json[camel] ?? json[snake];
      return (v as num?)?.toDouble() ?? 0.0;
    }

    int? readIntOpt(String camel, String snake) {
      final v = json[camel] ?? json[snake];
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString());
    }

    String horarioVal = readStr('horario', 'horario');
    if (horarioVal.contains('T')) {
      try {
        final dt = DateTime.parse(horarioVal);
        horarioVal =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    final ligaNomeVal = readStr('ligaNome', 'liga_nome');
    final campeonatoFallback = ligaNomeVal.isNotEmpty
        ? ligaNomeVal
        : readStr('campeonato', 'campeonato');

    return MatchModel(
      id: readStr('id', 'id'),
      timeCasa: readStr('timeCasa', 'time_casa'),
      timeFora: readStr('timeFora', 'time_fora'),
      campeonato: campeonatoFallback,
      oddCasa: readNum('oddCasa', 'odd_casa'),
      oddEmpate: readNum('oddEmpate', 'odd_empate'),
      oddFora: readNum('oddFora', 'odd_fora'),
      categoria: _categoriaFromString(json['categoria'] as String?),
      horario: horarioVal,
      probabilidade: readNum('probabilidade', 'probabilidade_real') > 0
          ? readNum('probabilidade', 'probabilidade_real')
          : readNum('probabilidade', 'probabilidade'),
      selecionado: json['selecionado'] as bool? ?? false,
      dataJogo: readStr('dataJogo', 'data_jogo'),
      ligaNome: ligaNomeVal,
      ligaPais: readStr('ligaPais', 'liga_pais'),
      ligaBandeira: readStr('ligaBandeira', 'liga_bandeira').isEmpty
          ? '🌍'
          : readStr('ligaBandeira', 'liga_bandeira'),
      status: _statusFromString(readStr('status', 'status')),
      minutoLive: readIntOpt('minutoLive', 'minuto_live'),
      placarCasa: readIntOpt('placarCasa', 'placar_casa'),
      placarFora: readIntOpt('placarFora', 'placar_fora'),
      alertas: (json['alertas'] as List<dynamic>?)
              ?.map((dynamic e) => e.toString())
              .toList() ??
          <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'timeCasa': timeCasa,
      'timeFora': timeFora,
      'campeonato': campeonato,
      'oddCasa': oddCasa,
      'oddEmpate': oddEmpate,
      'oddFora': oddFora,
      'categoria': categoria.name,
      'horario': horario,
      'probabilidade': probabilidade,
      'selecionado': selecionado,
      'dataJogo': dataJogo,
      'ligaNome': ligaNome,
      'ligaPais': ligaPais,
      'ligaBandeira': ligaBandeira,
      'status': status.name,
      'minutoLive': minutoLive,
      'placarCasa': placarCasa,
      'placarFora': placarFora,
      'alertas': alertas,
    };
  }

  MatchModel copyWith({
    String? id,
    String? timeCasa,
    String? timeFora,
    String? campeonato,
    double? oddCasa,
    double? oddEmpate,
    double? oddFora,
    CategoriaSinal? categoria,
    String? horario,
    double? probabilidade,
    bool? selecionado,
    String? dataJogo,
    String? ligaNome,
    String? ligaPais,
    String? ligaBandeira,
    StatusJogo? status,
    int? minutoLive,
    int? placarCasa,
    int? placarFora,
    List<String>? alertas,
  }) {
    return MatchModel(
      id: id ?? this.id,
      timeCasa: timeCasa ?? this.timeCasa,
      timeFora: timeFora ?? this.timeFora,
      campeonato: campeonato ?? this.campeonato,
      oddCasa: oddCasa ?? this.oddCasa,
      oddEmpate: oddEmpate ?? this.oddEmpate,
      oddFora: oddFora ?? this.oddFora,
      categoria: categoria ?? this.categoria,
      horario: horario ?? this.horario,
      probabilidade: probabilidade ?? this.probabilidade,
      selecionado: selecionado ?? this.selecionado,
      dataJogo: dataJogo ?? this.dataJogo,
      ligaNome: ligaNome ?? this.ligaNome,
      ligaPais: ligaPais ?? this.ligaPais,
      ligaBandeira: ligaBandeira ?? this.ligaBandeira,
      status: status ?? this.status,
      minutoLive: minutoLive ?? this.minutoLive,
      placarCasa: placarCasa ?? this.placarCasa,
      placarFora: placarFora ?? this.placarFora,
      alertas: alertas ?? this.alertas,
    );
  }
}
