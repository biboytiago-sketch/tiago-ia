class BankrollStatus {
  final double dailyLimit;
  final double currentLoss;
  final bool isLocked;
  final double assertividade;
  final int totalGreens;
  final int totalReds;

  BankrollStatus({
    this.dailyLimit = 0.0,
    this.currentLoss = 0.0,
    this.isLocked = false,
    this.assertividade = 0.0,
    this.totalGreens = 0,
    this.totalReds = 0,
  });

  factory BankrollStatus.fromJson(Map<String, dynamic> json) {
    bool readBool(String camel, String snake) =>
        json[camel] as bool? ?? json[snake] as bool? ?? false;
    double readNum(String camel, String snake) {
      final v = json[camel] ?? json[snake];
      return (v as num?)?.toDouble() ?? 0.0;
    }

    int readInt(String camel, String snake) {
      final v = json[camel] ?? json[snake];
      return (v as num?)?.toInt() ?? 0;
    }

    final greens = readInt('totalGreens', 'total_greens');
    final reds = readInt('totalReds', 'total_reds');
    final assertividadeBase = readNum('assertividade', 'assertividade');
    final double assertividadeCalc;
    if (assertividadeBase > 0) {
      assertividadeCalc = assertividadeBase;
    } else if (greens + reds > 0) {
      assertividadeCalc = greens / (greens + reds) * 100;
    } else {
      assertividadeCalc = 0.0;
    }
    return BankrollStatus(
      dailyLimit: readNum('dailyLimit', 'daily_limit'),
      currentLoss: readNum('currentLoss', 'current_loss'),
      isLocked: readBool('isLocked', 'is_locked'),
      assertividade: assertividadeCalc,
      totalGreens: greens,
      totalReds: reds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dailyLimit': dailyLimit,
      'currentLoss': currentLoss,
      'isLocked': isLocked,
      'assertividade': assertividade,
      'totalGreens': totalGreens,
      'totalReds': totalReds,
    };
  }

  BankrollStatus copyWith({
    double? dailyLimit,
    double? currentLoss,
    bool? isLocked,
    double? assertividade,
    int? totalGreens,
    int? totalReds,
  }) {
    return BankrollStatus(
      dailyLimit: dailyLimit ?? this.dailyLimit,
      currentLoss: currentLoss ?? this.currentLoss,
      isLocked: isLocked ?? this.isLocked,
      assertividade: assertividade ?? this.assertividade,
      totalGreens: totalGreens ?? this.totalGreens,
      totalReds: totalReds ?? this.totalReds,
    );
  }
}
