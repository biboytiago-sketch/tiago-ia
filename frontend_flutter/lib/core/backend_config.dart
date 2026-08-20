class BackendConfig {
  // ============================================================
  // MODO RENDER NUVEM (oficial): FORA DE CASA ou REDE MUITO RUIM
  // - Acesse https://dashboard.render.com
  // - Ligue o serviço "tiago-ia-backend"
  // ============================================================
  static const String _baseRender = 'https://tiago-ia-1.onrender.com';

  // ============================================================
  // MODO REDE LOCAL WI-FI (mesmo roteador do PC)
  // - IPv4 do PC Windows pode mudar via DHCP
  // ============================================================
  static const int _porta = 8000;

  // ============================================================
  // ESTRATÉGIA AUTOMÁTICA:
  // 1. Tentar Render (nuvem) primeiro se internet boa
  // 2. Senão, testar IPs LAN em ordem até achar o backend online
  // 3. ApiService.resolveBaseUrl() faz o health-check automático
  // ============================================================

  // Lista ORDENADA de todos os backends possíveis (Render + LAN + emulador)
  // ApiService testa em ordem e trava no primeiro que responder /ping = "pong"
  static final List<String> candidatosBaseRoot = <String>[
    _baseRender, // 1º Prioridade: Render (oficial)
    'http://192.168.1.42:$_porta', // IP atual (detectado 2026-08-19)
    'http://192.168.1.35:$_porta', // IP antigo (ainda válido se IP fixo)
    'http://192.168.1.30:$_porta', // Range comum roteadores Intelbras/Tenda
    'http://192.168.1.100:$_porta',
    'http://192.168.0.10:$_porta',
    'http://192.168.0.100:$_porta',
    'http://10.0.0.10:$_porta',
    'http://10.0.0.100:$_porta',
    'http://127.0.0.1:$_porta', // Fallback localhost
    'http://10.0.2.2:$_porta', // Android Emulator bridge -> 127.0.0.1
  ];

  // Builda os prefixos de API a partir de um ROOT descoberto
  static String baseV1FromRoot(String root) => '$root/api/v1';
  static String baseV3FromRoot(String root) => '$root/api/v3';

  // Cache da base descoberta (evita rodar health check em toda requisição)
  static String _cachedBaseRoot = '';
  static DateTime _cacheExpiraEm = DateTime(2000);

  static bool get temCacheValido {
    if (_cachedBaseRoot.isEmpty) return false;
    return DateTime.now().isBefore(_cacheExpiraEm);
  }

  static void cachearBaseRoot(String root,
      {Duration validoPor = const Duration(hours: 6)}) {
    _cachedBaseRoot = root;
    _cacheExpiraEm = DateTime.now().add(validoPor);
  }

  static void invalidarCache() {
    _cachedBaseRoot = '';
    _cacheExpiraEm = DateTime(2000);
  }

  static String get cachedBaseRoot => _cachedBaseRoot;
  static String get cachedBaseV1 =>
      _cachedBaseRoot.isEmpty ? '' : '$_cachedBaseRoot/api/v1';
  static String get cachedBaseV3 =>
      _cachedBaseRoot.isEmpty ? '' : '$_cachedBaseRoot/api/v3';

  // ============================================================
  // MODO DEFAULT (compatibilidade com código antigo):
  // 💡 USA RENDER NUVEM COMO DEFAULT (NAO MAIS IP LOCAL).
  //    Se o usuario estiver em 5G / 4G / rede externa: RENDER funciona.
  //    Se estiver no Wi-Fi do PC: as telas que usam resolveV3() testam LAN.
  // ============================================================
  static const String _ipLocal = '192.168.1.42';
  static const String _baseLocal = 'http://$_ipLocal:$_porta';
  static const String _base =
      _baseRender; // 🟢 MUDANCA CRITICA: DEFAULT = RENDER (nuvem), nao mais IP LAN!

  static const String baseRoot = _base;
  static const String baseV1 = '$_base/api/v1';
  static const String baseV3 = '$_base/api/v3';

  static const String baseRender = _baseRender;

  // ============================================================
  // HELPERS DE CAST SEGURO — NUNCA MAIS TELA VERMELHA por cast
  // ============================================================
  static Map<String, dynamic> safeMap(dynamic v,
      [Map<String, dynamic> fallback = const <String, dynamic>{}]) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return fallback;
  }

  static List<dynamic> safeList(dynamic v,
      [List<dynamic> fallback = const <dynamic>[]]) {
    if (v is List<dynamic>) return v;
    if (v is List) return List<dynamic>.from(v);
    return fallback;
  }

  static num safeNum(dynamic v, [num fallback = 0]) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? fallback;
    return fallback;
  }

  static double safeDouble(dynamic v, [double fallback = 0.0]) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static int safeInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String safeString(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    return v.toString();
  }

  static bool safeBool(dynamic v, [bool fallback = false]) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final String s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'sim' || s == 'yes') {
        return true;
      }
      if (s == 'false' || s == '0' || s == 'nao' || s == 'não' || s == 'no') {
        return false;
      }
    }
    return fallback;
  }
}
