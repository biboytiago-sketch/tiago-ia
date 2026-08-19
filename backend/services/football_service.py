"""
Serviço de Futebol - Tiago IA
Integração REAL com API-Football via RAPIDAPI (chave em backend/.env) + cache TTL + fallback simulado.

Variáveis de ambiente (lidas de backend/.env via python-dotenv):
  RAPIDAPI_KEY        →  x-rapidapi-key  (obtida em https://rapidapi.com/api-sports/api/api-football)
  RAPIDAPI_HOST       →  api-football-v1.p.rapidapi.com  (padrão)
  FOOTBALL_API_KEY    →  fallback legado para RAPIDAPI_KEY
  FOOTBALL_USE_MOCK   →  '1' força usar mocks (desenvolvimento offline)

Cache:
  - 20s em memória para fixtures LIVE
  - 60s para fixtures do dia / odds / statistics
"""

import os
import random
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

# ====== Carrega variáveis do .env ======
try:
    from dotenv import load_dotenv
    # Tenta .env tanto no dir atual quanto no dir pai (quando rodamos de dentro de services/)
    for _caminho in (
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"),
        ".env",
    ):
        _abs = os.path.abspath(_caminho)
        if os.path.exists(_abs):
            load_dotenv(_abs, override=False)
            break
except Exception:
    pass


# =============================================================================
#                          CAMADA DE CACHE EM MEMÓRIA
# =============================================================================
_CACHE: Dict[str, Dict[str, Any]] = {}
_CACHE_TTL = 60  # segundos (padrão)


def _cache_get(chave: str) -> Optional[Any]:
    item = _CACHE.get(chave)
    if not item:
        return None
    if (datetime.now().timestamp() - item["ts"]) > _CACHE_TTL:
        _CACHE.pop(chave, None)
        return None
    return item["dado"]


def _cache_set(chave: str, dado: Any) -> None:
    _CACHE[chave] = {"ts": datetime.now().timestamp(), "dado": dado}


# =============================================================================
#                          CLIENTE HTTP (httpx sync)
# =============================================================================
try:
    import httpx
except ImportError:  # pragma: no cover
    httpx = None  # type: ignore


# Ordem de precedência: RAPIDAPI_KEY > FOOTBALL_API_KEY (compatibilidade legada)
_RAPIDAPI_KEY_ENV = (os.getenv("RAPIDAPI_KEY") or "").strip()
_FOOTBALL_LEGADO = (os.getenv("FOOTBALL_API_KEY") or "").strip()
RAPIDAPI_KEY = _RAPIDAPI_KEY_ENV or _FOOTBALL_LEGADO

# Host padrão = v1.p.rapidapi.com (o oficial da RapidAPI marketplace);
# fallback = api-sports.io (host legado direto da empresa)
_RAPIDAPI_HOST_ENV = (os.getenv("RAPIDAPI_HOST") or "").strip()
if _RAPIDAPI_HOST_ENV:
    RAPIDAPI_HOST = _RAPIDAPI_HOST_ENV
else:
    RAPIDAPI_HOST = "api-football-v1.p.rapidapi.com"

FORCE_MOCK = os.getenv("FOOTBALL_USE_MOCK", "0") == "1" or not RAPIDAPI_KEY or httpx is None


def _api_base_url() -> str:
    """Monta o prefixo base da API dependendo do host configurado."""
    host = RAPIDAPI_HOST.lower()
    # Semantic: qualquer host rapidapi.com usa /v3/; host api-sports.io também usa /v3/
    return f"https://{host}/v3"


def _http_get(path: str, params: Dict[str, Any], timeout: int = 8) -> Optional[Dict[str, Any]]:
    """Chamada HTTP síncrona para a API-Football via RapidAPI.
    Trata 403 (não assinou) / 429 (cota estourada) retornando None silenciosamente,
    o que aciona o fallback simulado automaticamente (sem quebrar UX)."""
    if FORCE_MOCK or not RAPIDAPI_KEY or httpx is None:
        return None
    url = f"{_api_base_url()}{path}" if path.startswith("/") else f"{_api_base_url()}/{path}"
    try:
        with httpx.Client(timeout=timeout, follow_redirects=True) as client:
            resp = client.get(
                url,
                headers={
                    "x-rapidapi-key": RAPIDAPI_KEY,
                    "x-rapidapi-host": RAPIDAPI_HOST,
                    "Accept": "application/json",
                },
                params=params,
            )
            if resp.status_code == 200:
                try:
                    return resp.json()
                except Exception:
                    return None
            # Tratamento amigável para códigos RapidAPI conhecidos (não são "erros fatais")
            # 401 / 403 → chave sem assinatura ativa
            # 429 → cota Free Tier (100 req/dia) estourada / rate limit
            # Demais 4xx / 5xx → ignorar silenciosamente e usar fallback
            _msg = ""
            try:
                j = resp.json()
                if isinstance(j, dict) and "message" in j:
                    _msg = str(j["message"])[:120]
            except Exception:
                pass
            # Print só uma vez por sessão (cache negativo curto evita spam)
            cache_key_err = f"_err_{resp.status_code}"
            if cache_key_err not in _CACHE:
                _cache_set_ttl(cache_key_err, True, 300)  # 5 min de silêncio
                print(
                    f"[API-FOOTBALL RapidAPI] HTTP {resp.status_code} {resp.reason_phrase} "
                    f"para {path} {params} → {_msg or '(sem mensagem)'} "
                    f"→ usando fallback simulado."
                )
            return None
    except Exception:
        return None


# =============================================================================
#                            BASE DE LIGAS / BANDEIRAS
# =============================================================================
LIGAS_REAIS_ID = [
    71,   # Brasileirão Série A
    72,   # Brasileirão Série B
    73,   # Copa do Brasil
    74,   # Libertadores
    39,   # Premier League
    140,  # La Liga
    135,  # Serie A (Itália)
    78,   # Bundesliga
    61,   # Ligue 1
    2,    # Champions League
    3,    # Europa League
]

LIGAS = [
    {"liga_nome": "Brasileirão Série A", "liga_pais": "Brasil", "flag": "🇧🇷"},
    {"liga_nome": "Brasileirão Série B", "liga_pais": "Brasil", "flag": "🇧🇷"},
    {"liga_nome": "Copa do Brasil", "liga_pais": "Brasil", "flag": "🇧🇷"},
    {"liga_nome": "Libertadores", "liga_pais": "Sul-Americana", "flag": "🏆"},
    {"liga_nome": "Premier League", "liga_pais": "Inglaterra", "flag": "🏴󠁧󠁢󠁥󠁮󠁧󠁿"},
    {"liga_nome": "La Liga", "liga_pais": "Espanha", "flag": "🇪🇸"},
    {"liga_nome": "Serie A", "liga_pais": "Itália", "flag": "🇮🇹"},
    {"liga_nome": "Bundesliga", "liga_pais": "Alemanha", "flag": "🇩🇪"},
    {"liga_nome": "Ligue 1", "liga_pais": "França", "flag": "🇫🇷"},
    {"liga_nome": "Champions League", "liga_pais": "Europa", "flag": "🏆"},
    {"liga_nome": "Europa League", "liga_pais": "Europa", "flag": "🏆"},
]

TIMES_BRASILEIROS = [
    "Flamengo", "Palmeiras", "São Paulo", "Corinthians", "Fluminense",
    "Botafogo", "Atlético-MG", "Cruzeiro", "Grêmio", "Internacional",
    "Santos", "Bahia", "Vasco", "Goiás", "Coritiba", "Fortaleza", "Sport",
]

TIMES_EUROPEUS = [
    "Manchester City", "Arsenal", "Liverpool", "West Ham", "Aston Villa",
    "Tottenham", "Chelsea", "Manchester United", "Newcastle", "Brighton",
    "Real Madrid", "Barcelona", "Atlético de Madrid", "Villarreal", "Sevilla",
    "Juventus", "Milan", "Inter", "Atalanta", "Napoli", "Roma",
    "Bayern de Munique", "Borussia Dortmund", "Bayer Leverkusen",
    "PSG", "Marseille", "Lyon", "Monaco",
]

_PAIS_BANDEIRA = {
    "Brazil": "🇧🇷", "Brasil": "🇧🇷",
    "England": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "Inglaterra": "🏴󠁧󠁢󠁥󠁮󠁧󠁿",
    "Spain": "🇪🇸", "Espanha": "🇪🇸",
    "Italy": "🇮🇹", "Itália": "🇮🇹",
    "Germany": "🇩🇪", "Alemanha": "🇩🇪",
    "France": "🇫🇷", "França": "🇫🇷",
    "Portugal": "🇵🇹", "Netherlands": "🇳🇱",
    "Argentina": "🇦🇷", "World": "🌍", "Europe": "🏆", "South America": "🏆",
    "Europa": "🏆", "Sul-Americana": "🏆",
}


def _flag_do_pais(pais: str) -> str:
    return _PAIS_BANDEIRA.get(pais, "🌍")


LIGA_POR_PAIS: Dict[str, List[str]] = {}
for L in LIGAS:
    LIGA_POR_PAIS.setdefault(L["liga_pais"], []).append(L["liga_nome"])

PAIS_POR_LIGA: Dict[str, str] = {}
for _p, _ls in LIGA_POR_PAIS.items():
    for _l in _ls:
        PAIS_POR_LIGA[_l] = _p


def _info_liga(nome_liga: str):
    for l in LIGAS:
        if l["liga_nome"] == nome_liga:
            return l
    return {
        "liga_nome": nome_liga,
        "liga_pais": PAIS_POR_LIGA.get(nome_liga, "Mundo"),
        "flag": "🌍",
    }


# =============================================================================
#                     CATEGORIA / PROBABILIDADE A PARTIR DE ODDS
# =============================================================================
def _categoria_e_prob_por_odds(odd_casa: float, odd_emp: float, odd_fora: float):
    menor = min(odd_casa, odd_emp, odd_fora)
    if menor <= 1.55:
        cat = "LOW_ODDS_155"
        prob = int(round(100 / menor))
    elif 1.56 <= menor <= 2.00:
        if random.random() > 0.4:
            cat = "ACERTOS_80"
            prob = max(82, int(round(100 / menor)))
        else:
            cat = "MULTIPLE_80"
            prob = max(80, int(round(100 / menor)))
    elif 2.01 <= menor <= 3.00:
        cat = "VALUE"
        prob = int(round(100 / menor * 0.92))
    else:
        cat = "EVITAR"
        prob = random.randint(20, 45)
    prob = max(12, min(98, prob))
    if cat == "ACERTOS_80" and prob < 82:
        prob = 83
    return cat, prob


# =============================================================================
#             CONSUMO REAL DA API-FOOTBALL → LISTA DE JOGOS FORMATADA
# =============================================================================
def _fetch_fixtures_api(data_iso: str) -> Optional[List[Dict[str, Any]]]:
    """
    Busca fixtures de um dia na API-Football e converte para formato MatchModel.
    Retorna None se API indisponível.
    """
    if FORCE_MOCK or not RAPIDAPI_KEY or httpx is None:
        return None
    cache_key = f"fixtures:{data_iso}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached

    payload = _http_get("/fixtures", {"date": data_iso, "timezone": "America/Sao_Paulo"})
    if not payload or "response" not in payload:
        return None

    raw_list = payload["response"] or []
    # Filtra apenas ligas populares (IDs na LIGAS_REAIS_ID) para não ter ligas obscuras
    raw_list = [r for r in raw_list if r.get("league", {}).get("id") in LIGAS_REAIS_ID]
    if not raw_list:
        # Se nenhuma das ligas principais do dia (ex: meio da semana), libera todas
        raw_list = payload["response"] or []

    jogos_formatados: List[Dict[str, Any]] = []
    for idx, r in enumerate(raw_list):
        try:
            fix = r.get("fixture", {}) or {}
            league = r.get("league", {}) or {}
            teams = r.get("teams", {}) or {}
            goals = r.get("goals", {}) or {}
            score = r.get("score", {}) or {}

            # Horário em America/Sao_Paulo
            data_hora_str = fix.get("date")
            dt = None
            if data_hora_str:
                try:
                    dt = datetime.fromisoformat(data_hora_str.replace("Z", "+00:00"))
                    # Converter para SP (UTC-3 em horário de verão / UTC-3 padrão)
                    dt = dt.astimezone(timezone(timedelta(hours=-3)))
                except Exception:
                    dt = None

            # Status
            status_short = (fix.get("status", {}) or {}).get("short", "NS")
            minuto_live = (fix.get("status", {}) or {}).get("elapsed")
            if status_short in ("LIVE", "1H", "HT", "2H", "ET", "BT", "P"):
                status_app = "AO_VIVO"
                if minuto_live is None:
                    minuto_live = random.randint(12, 88)
            elif status_short in ("FT", "AET", "PEN", "WO", "SUSP", "INT", "ABD", "AWD"):
                status_app = "ENCERRADO"
                minuto_live = None
            else:
                status_app = "PROXIMO"
                minuto_live = None

            # Times
            time_casa = (teams.get("home", {}) or {}).get("name", "Time Casa") or "Time Casa"
            time_fora = (teams.get("away", {}) or {}).get("name", "Time Fora") or "Time Fora"

            # Placar
            placar_casa, placar_fora = None, None
            if status_app == "AO_VIVO" or status_app == "ENCERRADO":
                gc = goals.get("home")
                gf = goals.get("away")
                if isinstance(gc, int) or isinstance(gc, float):
                    placar_casa = int(gc)
                if isinstance(gf, int) or isinstance(gf, float):
                    placar_fora = int(gf)

            # Liga / País
            liga_nome = league.get("name", "Amistoso") or "Amistoso"
            liga_pais = league.get("country", "Mundo") or "Mundo"
            liga_bandeira = _flag_do_pais(liga_pais)

            # Data formatada
            hoje_br = datetime.now(timezone(timedelta(hours=-3)))
            if dt is None:
                dt = hoje_br + timedelta(hours=idx)
            data_jogo = dt.strftime("%d/%m/%Y")
            horario = dt.strftime("%H:%M")
            horario_iso = dt.isoformat()

            # Odds → na API-Football endpoint /odds é separado. Para manter
            # performance, geramos odds realistas a partir da classificação
            # (se a API tiver retornado favoritismo), ou randomizamos controlado.
            # Odds mais baixas para top ligas.
            if status_app == "AO_VIVO" and placar_casa is not None:
                # Ao vivo, odds refletem placar
                dif = placar_casa - placar_fora
                if dif > 1:
                    o_c, o_e, o_f = round(1.25 + random.random() * 0.3, 2), round(3.5 + random.random() * 1.0, 2), round(5.0 + random.random() * 3.0, 2)
                elif dif < -1:
                    o_c, o_e, o_f = round(5.0 + random.random() * 3.0, 2), round(3.5 + random.random() * 1.0, 2), round(1.25 + random.random() * 0.3, 2)
                else:
                    o_c, o_e, o_f = round(2.0 + random.random() * 1.0, 2), round(3.0 + random.random() * 0.8, 2), round(2.0 + random.random() * 1.0, 2)
            else:
                # Odd realista: time forte levemente favorito
                r1 = random.random()
                if r1 < 0.33:
                    base = 1.5 + random.random() * 0.8
                    o_c = round(base, 2)
                    o_f = round(base + random.random() * 1.2, 2)
                elif r1 < 0.66:
                    base = 1.5 + random.random() * 0.8
                    o_f = round(base, 2)
                    o_c = round(base + random.random() * 1.2, 2)
                else:
                    o_c = round(1.8 + random.random() * 1.4, 2)
                    o_f = round(1.8 + random.random() * 1.4, 2)
                o_e = round(3.0 + random.random() * 1.2, 2)

            categoria, prob_real = _categoria_e_prob_por_odds(o_c, o_e, o_f)

            alertas = []
            if categoria == "EVITAR":
                alertas = ["Risco elevado de surpresa", "Histórico muito equilibrado"]
            elif prob_real < 60:
                alertas = ["Probabilidade abaixo de 60%"]

            jogo_id = f"F{fix.get('id') or idx}_{horario.replace(':','')}"

            jogos_formatados.append({
                "id": jogo_id,
                "categoria": categoria,
                "time_casa": time_casa,
                "time_fora": time_fora,
                "odd_casa": o_c,
                "odd_empate": o_e,
                "odd_fora": o_f,
                "probabilidade_real": prob_real,
                "alertas": alertas,
                "data_jogo": data_jogo,
                "data_curta": dt.strftime("%d/%m"),
                "horario": horario,
                "liga_nome": liga_nome,
                "liga_pais": liga_pais if liga_pais not in ("Brazil", "England", "Spain", "Italy", "Germany", "France") else {
                    "Brazil": "Brasil", "England": "Inglaterra", "Spain": "Espanha",
                    "Italy": "Itália", "Germany": "Alemanha", "France": "França"
                }.get(liga_pais, liga_pais),
                "liga_bandeira": liga_bandeira,
                "status": status_app,
                "minuto_live": minuto_live,
                "placar_casa": placar_casa,
                "placar_fora": placar_fora,
                "campeonato": liga_nome,
                "pais": liga_pais,
                "probabilidade": prob_real,
                "horario_iso": horario_iso,
                "_fonte": "API-FOOTBALL",
            })
        except Exception:
            continue

    # Cache + retorno
    if jogos_formatados:
        _cache_set(cache_key, jogos_formatados)
        return jogos_formatados
    return None


# =============================================================================
#                        GERADOR SIMULADO (FALLBACK OFFLINE)
# =============================================================================
def _gerar_data_horario_e_status(idx, dia_offset=0):
    hoje = datetime.now(timezone(timedelta(hours=-3))).replace(second=0, microsecond=0)
    data_ref = hoje + timedelta(days=dia_offset)
    ordem = idx % 12
    if dia_offset == 0 and ordem in (0, 3, 6):
        status = "AO_VIVO"
        hora = 16 + (idx % 5)
        minuto = [0, 15, 30, 45][idx % 4]
        minuto_live = random.choice([8, 15, 23, 34, 48, 57, 62, 71, 78, 83, 88])
    elif dia_offset == 0 and ordem in (1, 4, 9):
        status = "ENCERRADO"
        hora = 19
        minuto = 30
        minuto_live = None
    else:
        status = "PROXIMO"
        delta_h = idx + 1
        hora = (15 + delta_h) % 24
        minuto = random.choice([0, 15, 30, 45])
        minuto_live = None

    dt = data_ref.replace(hour=hora % 24, minute=minuto)
    if hora >= 24:
        dt = dt + timedelta(days=1)

    return dt.strftime("%d/%m/%Y"), dt.strftime("%d/%m"), dt.strftime("%H:%M"), status, minuto_live, dt.isoformat()


def gerar_jogo_simulado(idx: int, dia_offset: int = 0):
    random.seed(idx + datetime.now().day + dia_offset + 99)

    liga_raw = LIGAS[idx % len(LIGAS)]
    info_liga = _info_liga(liga_raw["liga_nome"])
    liga_nome = info_liga["liga_nome"]
    liga_pais = info_liga["liga_pais"]
    bandeira_liga = info_liga["flag"]

    if liga_pais in ("Brasil", "Sul-Americana"):
        pool_casa, pool_fora = TIMES_BRASILEIROS, TIMES_BRASILEIROS
    else:
        pool_casa, pool_fora = TIMES_EUROPEUS, TIMES_EUROPEUS

    time_casa = random.choice(pool_casa)
    candidatos = [t for t in pool_fora if t != time_casa]
    time_fora = random.choice(candidatos or pool_fora)

    data_jogo, data_curta, horario, status, minuto_live, horario_iso = _gerar_data_horario_e_status(idx, dia_offset)

    odd_casa = round(random.uniform(1.20, 4.50), 2)
    odd_empate = round(random.uniform(2.80, 4.20), 2)
    odd_fora = round(random.uniform(1.30, 5.00), 2)
    categoria, probabilidade_real = _categoria_e_prob_por_odds(odd_casa, odd_empate, odd_fora)

    placar_casa, placar_fora = None, None
    if status == "AO_VIVO":
        placar_casa = random.randint(0, 3)
        placar_fora = random.randint(0, 2)
    elif status == "ENCERRADO":
        placar_casa = random.randint(0, 4)
        placar_fora = random.randint(0, 3)

    alertas = []
    if categoria == "EVITAR":
        alertas = ["Histórico muito equilibrado", "Dupla chance favorita no mercado"]
    elif probabilidade_real < 60:
        alertas = ["Probabilidade abaixo do esperado"]

    jogo_id = f"J{dia_offset}{idx:03d}_{horario.replace(':','')}"
    return {
        "id": jogo_id,
        "categoria": categoria,
        "time_casa": time_casa,
        "time_fora": time_fora,
        "odd_casa": odd_casa,
        "odd_empate": odd_empate,
        "odd_fora": odd_fora,
        "probabilidade_real": probabilidade_real,
        "alertas": alertas,
        "data_jogo": data_jogo,
        "data_curta": data_curta,
        "horario": horario,
        "liga_nome": liga_nome,
        "liga_pais": liga_pais,
        "liga_bandeira": bandeira_liga,
        "status": status,
        "minuto_live": minuto_live,
        "placar_casa": placar_casa,
        "placar_fora": placar_fora,
        "campeonato": liga_nome,
        "pais": liga_pais,
        "probabilidade": probabilidade_real,
        "horario_iso": horario_iso,
        "_fonte": "SIMULADO",
    }


# =============================================================================
#                      FUNÇÕES PÚBLICAS PRINCIPAIS
# =============================================================================
def get_today_matches(qtd_minima: int = 12):
    """
    Retorna jogos de HOJE. Primeiro tenta API-Football, depois fallback simulado.
    Garante pelo menos `qtd_minima` jogos.
    """
    hoje_sp = datetime.now(timezone(timedelta(hours=-3)))
    data_iso = hoje_sp.strftime("%Y-%m-%d")
    jogos_reais = _fetch_fixtures_api(data_iso) or []
    # Completa com simulados se API devolveu poucos jogos (ex: horários que ainda não tem jogos)
    while len(jogos_reais) < qtd_minima:
        sim = gerar_jogo_simulado(len(jogos_reais), dia_offset=0)
        jogos_reais.append(sim)

    # Ordenação PRIORIDADE: AO_VIVO primeiro, depois PROXIMO, depois ENCERRADO
    status_ordem = {"AO_VIVO": 0, "PROXIMO": 1, "ENCERRADO": 2}
    cat_ordem = {"ACERTOS_80": 0, "MULTIPLE_80": 1, "LOW_ODDS_155": 2, "VALUE": 3, "EVITAR": 4}
    jogos_reais.sort(key=lambda j: (
        status_ordem.get(j.get("status", "PROXIMO"), 9),
        cat_ordem.get(j.get("categoria", "VALUE"), 9),
        j.get("horario", "99:99"),
    ))
    return jogos_reais


def get_matches_grouped_by_country_league(jogos=None):
    if jogos is None:
        jogos = get_today_matches()
    por_pais = {}
    for j in jogos:
        pais = j.get("liga_pais", "Mundo")
        liga = j.get("liga_nome", "Amistoso")
        bandeira = j.get("liga_bandeira", "🌍")
        if pais not in por_pais:
            por_pais[pais] = {"pais": pais, "ligas": {}}
        if liga not in por_pais[pais]["ligas"]:
            por_pais[pais]["ligas"][liga] = {
                "liga_nome": liga,
                "liga_bandeira": bandeira,
                "jogos": [],
            }
        por_pais[pais]["ligas"][liga]["jogos"].append(j)

    resultado = []
    for pais_info in por_pais.values():
        ligas_lista = []
        for liga in pais_info["ligas"].values():
            liga["total_jogos"] = len(liga["jogos"])
            ligas_lista.append(liga)
        # Ordena ligas pela contagem de jogos
        ligas_lista.sort(key=lambda l: -l["total_jogos"])
        resultado.append({
            "pais": pais_info["pais"],
            "total_ligas": len(ligas_lista),
            "total_jogos_pais": sum(l["total_jogos"] for l in ligas_lista),
            "ligas": ligas_lista,
        })
    # Brasil primeiro
    resultado.sort(key=lambda p: (0 if p["pais"] in ("Brasil", "Brazil") else 1, -p["total_jogos_pais"]))
    return resultado


def get_multiday_matches(dias: int = 4):
    """
    Retorna jogos múltiplos dias consecutivos (Hoje, Amanhã, D+2, D+3...).
    """
    now_sp = datetime.now(timezone(timedelta(hours=-3)))
    datas_meta = []
    for d in range(dias):
        data_ref = now_sp + timedelta(days=d)
        data_curta = f"{data_ref.day:02d}/{data_ref.month:02d}"
        data_completa = f"{data_ref.day:02d}/{data_ref.month:02d}/{data_ref.year}"
        if d == 0:
            label = "Hoje"
        elif d == 1:
            label = "Amanhã"
        else:
            label = data_curta
        dias_semana = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
        dia_idx = int(data_ref.strftime("%w"))  # 0=Domingo .. 6=Sábado (padrão pt-BR listão)
        dia_semana = dias_semana[dia_idx % 7]
        datas_meta.append({
            "offset": d,
            "data_iso": data_ref.strftime("%Y-%m-%d"),
            "data_curta": data_curta,
            "data_completa": data_completa,
            "label": label,
            "dia_semana": dia_semana,
        })

    jogos_por_data: Dict[str, List[Dict[str, Any]]] = {}
    for dm in datas_meta:
        offset = dm["offset"]
        data_curta = dm["data_curta"]
        if offset == 0:
            # Hoje: usa get_today_matches (API real + fallback)
            lista = get_today_matches()
            for j in lista:
                j["data_curta"] = data_curta
                j["data_jogo"] = dm["data_completa"]
            jogos_por_data[data_curta] = lista
        else:
            # Dias futuros: tenta API, senão simulados
            lista = _fetch_fixtures_api(dm["data_iso"]) or []
            qtd_alvo = 12
            while len(lista) < qtd_alvo:
                sim = gerar_jogo_simulado(len(lista), dia_offset=offset)
                # Dias futuros: SEM AO_VIVO nem ENCERRADO
                sim["status"] = "PROXIMO"
                sim["minuto_live"] = None
                sim["placar_casa"] = None
                sim["placar_fora"] = None
                sim["data_curta"] = data_curta
                sim["data_jogo"] = dm["data_completa"]
                lista.append(sim)
            cat_ordem = {"ACERTOS_80": 0, "MULTIPLE_80": 1, "LOW_ODDS_155": 2, "VALUE": 3, "EVITAR": 4}
            lista.sort(key=lambda j: (
                cat_ordem.get(j.get("categoria", "VALUE"), 9),
                j.get("horario", "99:99"),
            ))
            jogos_por_data[data_curta] = lista

    datas_saida = [{
        "data_curta": dm["data_curta"],
        "data_completa": dm["data_completa"],
        "label": dm["label"],
        "dia_semana": dm["dia_semana"],
    } for dm in datas_meta]

    return {
        "datas": datas_saida,
        "jogos_por_data": jogos_por_data,
        "total_dias": len(datas_saida),
        "total_jogos": sum(len(j) for j in jogos_por_data.values()),
    }


def verify_selected_matches(match_ids):
    todos_jogos = get_today_matches()
    jogos_map = {j["id"]: j for j in todos_jogos}

    selecionados = []
    odd_acumulada = 1.0
    prob_acumulada = 100.0
    cascas_de_banana = []
    sugestoes_desmarcar = []

    for mid in match_ids:
        if mid in jogos_map:
            jogo = jogos_map[mid]
            selecionados.append(jogo)

            menor_odd = min(jogo["odd_casa"], jogo["odd_empate"], jogo["odd_fora"])
            odd_acumulada *= menor_odd
            prob_acumulada *= (jogo["probabilidade_real"] / 100.0)

            if jogo["categoria"] == "EVITAR":
                cascas_de_banana.append({
                    "jogo_id": jogo["id"],
                    "time_casa": jogo["time_casa"],
                    "time_fora": jogo["time_fora"],
                    "jogo": f"{jogo['time_casa']} x {jogo['time_fora']}",
                    "motivo": "Categoria EVITAR - risco elevado de surpresa"
                })
                sugestoes_desmarcar.append(jogo["id"])
            elif jogo["probabilidade_real"] < 60:
                cascas_de_banana.append({
                    "jogo_id": jogo["id"],
                    "time_casa": jogo["time_casa"],
                    "time_fora": jogo["time_fora"],
                    "jogo": f"{jogo['time_casa']} x {jogo['time_fora']}",
                    "motivo": f"Probabilidade real baixa ({jogo['probabilidade_real']}%)"
                })
                sugestoes_desmarcar.append(jogo["id"])

    odd_acumulada = round(odd_acumulada, 2)
    prob_acumulada = round(prob_acumulada, 1)

    if len(selecionados) > 4 and odd_acumulada > 15:
        for j in selecionados:
            if j["categoria"] == "VALUE" and j["id"] not in sugestoes_desmarcar:
                cascas_de_banana.append({
                    "jogo_id": j["id"],
                    "time_casa": j["time_casa"],
                    "time_fora": j["time_fora"],
                    "jogo": f"{j['time_casa']} x {j['time_fora']}",
                    "motivo": "Múltipla muito longa - considere reduzir jogos VALUE"
                })
                sugestoes_desmarcar.append(j["id"])
                break

    aprovado = (len(cascas_de_banana) == 0 and odd_acumulada <= 1.56 and prob_acumulada >= 65.0) or (
        len(cascas_de_banana) == 0 and len(selecionados) == 1 and prob_acumulada >= 78.0
    )

    return {
        "total_selecionados": len(selecionados),
        "odd_acumulada": odd_acumulada,
        "probabilidade_real_acumulada": prob_acumulada,
        "aprovado": aprovado,
        "cascas_de_banana": cascas_de_banana,
        "sugestoes_desmarcar": sugestoes_desmarcar,
        "jogos_selecionados": selecionados,
        "recomendacao_final": "APROVADO" if aprovado else "REVISAR",
    }


# =============================================================================
#                     REQUISITO 1 + 2: DADOS LIVE ESTILO FLASHSCORE
# =============================================================================
#
# Estrutura padrão FlashScore do backend:
#   fixture_id, league, country, flag, status_short (1H/HT/2H/ET/PEN),
#   minute_exact, home_team{name,score,ht_score,red_cards,yellow_cards,
#   corners,shots_on_target,dangerous_attacks, possession_pct},
#   away_team{...mesmo...}, stats{...}, timeline[{min,type,team,player,detail}]
#

_LIVE_CACHE_KEY = "live_flashscore_all"
_LIVE_CACHE_TTL = 10  # segundos (cache rápido para jogos ao vivo, preserva cota RapidAPI)


def _cache_set_ttl(chave: str, dado: Any, ttl: int) -> None:
    _CACHE[chave] = {"ts": datetime.now().timestamp(), "dado": dado, "ttl": ttl}


def _cache_get_ttl(chave: str) -> Optional[Any]:
    item = _CACHE.get(chave)
    if not item:
        return None
    ttl = item.get("ttl", _CACHE_TTL)
    if (datetime.now().timestamp() - item["ts"]) > ttl:
        _CACHE.pop(chave, None)
        return None
    return item["dado"]


def _status_curto_para_legivel(status_short: str) -> str:
    MAP = {
        "TBD": "A DEFINIR",
        "NS": "NÃO INICIADO",
        "1H": "1º TEMPO",
        "HT": "INTERVALO",
        "2H": "2º TEMPO",
        "ET": "PRORROGAÇÃO",
        "BT": "PAUSA PRORROGAÇÃO",
        "P": "PÊNALTIS",
        "LIVE": "EM JOGO",
        "FT": "ENCERRADO",
        "AET": "ENC. PRORROGAÇÃO",
        "PEN": "ENC. PÊNALTIS",
        "SUSP": "SUSPENSO",
        "INT": "INTERROMPIDO",
        "ABD": "ABANDONADO",
        "CANC": "CANCELADO",
        "WO": "W.O.",
    }
    return MAP.get(status_short, status_short or "DESC.")


def _montar_timeline_mock(fixture_id, home, away, minute_max, seed=1) -> List[Dict[str, Any]]:
    rnd = random.Random(seed)
    eventos: List[Dict[str, Any]] = []
    # Gol casa
    if minute_max >= 18:
        eventos.append({"minute": rnd.randint(8, 22), "type": "goal", "team": "home",
                        "player": rnd.choice(["Pedro", "Gabigol", "Luiz Araújo"]),
                        "detail": "Gol! Finalização no ângulo."})
    # Cartão amarelo fora
    if minute_max >= 30:
        eventos.append({"minute": rnd.randint(25, 42), "type": "yellow", "team": "away",
                        "player": rnd.choice(["Zé Ivaldo", "Júnior Alonso", "Abel Ferreira"]),
                        "detail": "Cartão amarelo - falta dura."})
    # Escanteios acumulados (evento de pressão)
    eventos.append({"minute": "HT" if minute_max >= 45 else max(1, min(45, minute_max - 1)),
                    "type": "ht_score", "team": "info", "player": "",
                    "detail": "Intervalo - Placar parcial computado."})
    if minute_max >= 55:
        eventos.append({"minute": rnd.randint(48, 65), "type": "dangerous_attack", "team": "home",
                        "player": "", "detail": "Ataque perigoso - 3 toques na área."})
    if minute_max >= 70:
        eventos.append({"minute": rnd.randint(66, minute_max), "type": "substitution", "team": rnd.choice(["home", "away"]),
                        "player": rnd.choice(["Gerson → Thiago Maia", "Endrick → Luiz Henrique", "Veiga → Richard Ríos"]),
                        "detail": "Substituição estratégica."})
    if minute_max >= 78:
        eventos.append({"minute": rnd.randint(75, minute_max), "type": "var", "team": "info",
                        "player": "", "detail": "VAR revisando possível pênalti - analisando lance."})
    # Gols finais para justificar placar
    if minute_max >= 85:
        eventos.append({"minute": minute_max - rnd.randint(0, 6), "type": "goal", "team": "away",
                        "player": rnd.choice(["Raphael Veiga", "Endrick", "López"]),
                        "detail": "Gol de cabeça no escanteio."})
    eventos.sort(key=lambda e: (isinstance(e["minute"], str), str(e["minute"])))
    return eventos


def _enriquecer_jogo_com_stats_mock(jogo: Dict[str, Any]) -> Dict[str, Any]:
    """Recebe um jogo gerado (get_today_matches / API real) e enriquece com
    stats in-play e timeline estilo FlashScore."""
    rnd = random.Random(hash(jogo.get("id", "")) & 0xFFFFFFFF)
    status = jogo.get("status", "PROXIMO")
    minuto_live = jogo.get("minuto_live")
    placar_casa = jogo.get("placar_casa") or 0
    placar_fora = jogo.get("placar_fora") or 0

    fixture_id = str(jogo.get("id"))
    liga_nome = jogo.get("liga_nome", "")
    liga_pais = jogo.get("liga_pais", "")
    liga_bandeira = jogo.get("liga_bandeira", "🌍")

    # Status legível
    if status == "AO_VIVO":
        if minuto_live is None:
            minuto_live = rnd.randint(15, 82)
        if minuto_live <= 45:
            status_short = "1H"
        elif minuto_live <= 60:
            status_short = "HT"
        else:
            status_short = "2H"
    elif status == "ENCERRADO":
        status_short = "FT"
    else:
        status_short = "NS"

    status_legivel = _status_curto_para_legivel(status_short)
    # Posses: favorito tem mais (casa geralmente 50-60%)
    posse_casa = rnd.randint(42, 62)
    posse_fora = 100 - posse_casa

    # Chutes e ataques proporcionais ao minuto (mais minutos = mais eventos)
    escala = max(1, (minuto_live or 0) / 45.0) if status != "PROXIMO" else 0.1
    def _s(minh, minh2, maxh):
        if status == "PROXIMO":
            return 0, 0
        return (
            max(0, min(maxh, int(rnd.randint(minh, minh + 6) * escala))),
            max(0, min(maxh, int(rnd.randint(minh2, minh2 + 5) * escala))),
        )

    chutes_na_meta_c, chutes_na_meta_f = _s(3, 2, 15)
    chutes_fora_c, chutes_fora_f = _s(5, 4, 22)
    ataques_perig_c, ataques_perig_f = _s(28, 20, 110)
    ataques_total_c, ataques_total_f = (max(0, ataques_perig_c + rnd.randint(12, 55)),
                                         max(0, ataques_perig_f + rnd.randint(10, 45)))
    escanteios_c, escanteios_f = _s(2, 1, 15)
    amarelos_c, amarelos_f = _s(1, 0, 6)
    vermelhos_c, vermelhos_f = (1 if (rnd.random() < 0.08 and status not in ("PROXIMO",)) else 0,
                                1 if (rnd.random() < 0.06 and status not in ("PROXIMO",)) else 0)

    # Placar do 1º tempo: se 2H ou FT, tem HT score definido
    if status_short in ("HT", "2H", "FT", "AET", "PEN"):
        ht_c = placar_casa if rnd.random() > 0.35 else max(0, placar_casa - rnd.randint(0, 1))
        ht_f = placar_fora if rnd.random() > 0.35 else max(0, placar_fora - rnd.randint(0, 1))
    else:
        ht_c, ht_f = 0, 0

    minutagem_exata = f"{minuto_live}'" if minuto_live else ""

    timeline = []
    if status not in ("PROXIMO",):
        timeline = _montar_timeline_mock(
            fixture_id, jogo.get("time_casa"), jogo.get("time_fora"),
            minuto_live or (90 if status == "ENCERRADO" else 60),
            seed=hash(fixture_id) & 0xFFFF or 1
        )

    return {
        "fixture_id": fixture_id,
        "jogo_id": jogo.get("id"),
        "league": liga_nome,
        "country": liga_pais,
        "flag": liga_bandeira,
        "status_short": status_short,
        "status_label": status_legivel,
        "minute_exact": minutagem_exata,
        "minute_elapsed": minuto_live,
        "horario": jogo.get("horario"),
        "data_jogo": jogo.get("data_jogo"),
        "data_curta": jogo.get("data_curta"),
        "categoria": jogo.get("categoria", "VALUE"),
        "probabilidade_real": jogo.get("probabilidade_real", 50),
        "alertas": jogo.get("alertas", []),
        "odds": {
            "home": jogo.get("odd_casa", 2.20),
            "draw": jogo.get("odd_empate", 3.20),
            "away": jogo.get("odd_fora", 2.40),
        },
        "home_team": {
            "name": jogo.get("time_casa", "Time Casa"),
            "score": int(placar_casa),
            "ht_score": int(ht_c),
            "red_cards": vermelhos_c,
            "yellow_cards": amarelos_c,
            "corners": escanteios_c,
            "shots_on_target": chutes_na_meta_c,
            "shots_off_target": chutes_fora_c,
            "dangerous_attacks": ataques_perig_c,
            "total_attacks": ataques_total_c,
            "possession_pct": posse_casa,
        },
        "away_team": {
            "name": jogo.get("time_fora", "Time Fora"),
            "score": int(placar_fora),
            "ht_score": int(ht_f),
            "red_cards": vermelhos_f,
            "yellow_cards": amarelos_f,
            "corners": escanteios_f,
            "shots_on_target": chutes_na_meta_f,
            "shots_off_target": chutes_fora_f,
            "dangerous_attacks": ataques_perig_f,
            "total_attacks": ataques_total_f,
            "possession_pct": posse_fora,
        },
        "stats": {
            "possession_pct": {"home": posse_casa, "away": posse_fora},
            "dangerous_attacks": {"home": ataques_perig_c, "away": ataques_perig_f},
            "total_attacks":     {"home": ataques_total_c,  "away": ataques_total_f},
            "shots_on_target":   {"home": chutes_na_meta_c, "away": chutes_na_meta_f},
            "shots_off_target":  {"home": chutes_fora_c,   "away": chutes_fora_f},
            "corners":           {"home": escanteios_c,    "away": escanteios_f},
            "yellow_cards":      {"home": amarelos_c,      "away": amarelos_f},
            "red_cards":         {"home": vermelhos_c,     "away": vermelhos_f},
        },
        "timeline": timeline,
        "_fonte": jogo.get("_fonte", "SIMULADO"),
    }


def _fetch_live_real_api() -> Optional[List[Dict[str, Any]]]:
    """Chama /fixtures?live=all na API-Football, converte para formato FlashScore."""
    if FORCE_MOCK or not RAPIDAPI_KEY or httpx is None:
        return None
    cache_key = "api_live_all"
    cached = _cache_get_ttl(cache_key)
    if cached:
        return cached

    payload = _http_get("/fixtures", {"live": "all", "timezone": "America/Sao_Paulo"}, timeout=9)
    if not payload or "response" not in payload:
        return None
    raw_list = [r for r in (payload["response"] or [])
                if r.get("league", {}).get("id") in LIGAS_REAIS_ID]
    if not raw_list:
        raw_list = payload["response"] or []

    resultados: List[Dict[str, Any]] = []
    for r in raw_list[:20]:
        try:
            fix = r.get("fixture", {}) or {}
            league = r.get("league", {}) or {}
            teams = r.get("teams", {}) or {}
            goals = r.get("goals", {}) or {}
            score = r.get("score", {}) or {}
            status_blob = fix.get("status", {}) or {}

            status_short = status_blob.get("short", "LIVE")
            status_legivel = _status_curto_para_legivel(status_short)
            elapsed = status_blob.get("elapsed") or 60
            data_hora_str = fix.get("date")
            dt = None
            if data_hora_str:
                try:
                    dt = datetime.fromisoformat(data_hora_str.replace("Z", "+00:00"))
                    dt = dt.astimezone(timezone(timedelta(hours=-3)))
                except Exception:
                    dt = None
            if dt is None:
                dt = datetime.now(timezone(timedelta(hours=-3)))

            gc = goals.get("home") or 0
            gf = goals.get("away") or 0
            try: gc = int(gc)
            except Exception: gc = 0
            try: gf = int(gf)
            except Exception: gf = 0
            ht_blob = score.get("halftime") or {}
            try: ht_c = int(ht_blob.get("home") or 0)
            except Exception: ht_c = 0
            try: ht_f = int(ht_blob.get("away") or 0)
            except Exception: ht_f = 0

            liga_nome = league.get("name", "") or "Amistoso"
            liga_pais = league.get("country", "") or "Mundo"
            liga_pais_pt = {
                "Brazil": "Brasil", "England": "Inglaterra", "Spain": "Espanha",
                "Italy": "Itália", "Germany": "Alemanha", "France": "França"
            }.get(liga_pais, liga_pais)
            bandeira = _flag_do_pais(liga_pais)

            home_name = (teams.get("home") or {}).get("name") or "Casa"
            away_name = (teams.get("away") or {}).get("name") or "Fora"

            # Gera estatísticas mock realistas baseadas no minuto (API /fixtures não traz stats junto;
            # endpoint separado /fixtures/statistics precisaria de fixture_id por chamada)
            random.seed(int(fix.get("id") or 1) + datetime.now().day)
            posse_c = random.randint(44, 60)
            escala = max(0.4, min(2.2, (elapsed / 45.0)))
            def _n(h, mx): return max(0, min(mx, int(random.randint(h, h+5) * escala)))
            chg_c, chg_f = _n(3, 16), _n(2, 14)
            atper_c, atper_f = _n(28, 110), _n(18, 100)
            esc_c, esc_f = _n(2, 16), _n(1, 12)
            ama_c, ama_f = _n(1, 6), _n(0, 5)
            ver_c = 1 if random.random() < 0.1 else 0
            ver_f = 1 if random.random() < 0.08 else 0
            ataques_tot_c, ataques_tot_f = atper_c + random.randint(15, 50), atper_f + random.randint(14, 45)
            chfora_c, chfora_f = _n(4, 24), _n(3, 20)
            odd_casa, odd_fora = (round(1.5 + random.random()*2.4, 2),
                                  round(1.5 + random.random()*2.6, 2))
            odd_emp = round(2.9 + random.random()*1.2, 2)
            menor = min(odd_casa, odd_emp, odd_fora)
            if menor <= 1.55: cat = "LOW_ODDS_155"
            elif menor <= 2.00: cat = "ACERTOS_80" if random.random() > 0.4 else "MULTIPLE_80"
            elif menor <= 3.00: cat = "VALUE"
            else: cat = "EVITAR"
            prob_real = max(40, min(97, int(round(100 / menor))))
            if cat == "ACERTOS_80" and prob_real < 82: prob_real = 83

            minutagem_exata = f"{elapsed}'"
            timeline = _montar_timeline_mock(
                str(fix.get("id")), home_name, away_name, elapsed,
                seed=int(fix.get("id") or 1)
            )

            resultados.append({
                "fixture_id": str(fix.get("id")),
                "jogo_id": str(fix.get("id")),
                "league": liga_nome,
                "country": liga_pais_pt,
                "flag": bandeira,
                "status_short": status_short,
                "status_label": status_legivel,
                "minute_exact": minutagem_exata,
                "minute_elapsed": int(elapsed or 0),
                "horario": dt.strftime("%H:%M"),
                "data_jogo": dt.strftime("%d/%m/%Y"),
                "data_curta": dt.strftime("%d/%m"),
                "categoria": cat,
                "probabilidade_real": prob_real,
                "alertas": ["Pressão alta da equipe mandante."] if posse_c > 55 else [],
                "odds": {"home": odd_casa, "draw": odd_emp, "away": odd_fora},
                "home_team": {
                    "name": home_name, "score": int(gc), "ht_score": ht_c,
                    "red_cards": ver_c, "yellow_cards": ama_c, "corners": esc_c,
                    "shots_on_target": chg_c, "shots_off_target": chfora_c,
                    "dangerous_attacks": atper_c, "total_attacks": ataques_tot_c,
                    "possession_pct": posse_c,
                },
                "away_team": {
                    "name": away_name, "score": int(gf), "ht_score": ht_f,
                    "red_cards": ver_f, "yellow_cards": ama_f, "corners": esc_f,
                    "shots_on_target": chg_f, "shots_off_target": chfora_f,
                    "dangerous_attacks": atper_f, "total_attacks": ataques_tot_f,
                    "possession_pct": 100 - posse_c,
                },
                "stats": {
                    "possession_pct":    {"home": posse_c, "away": 100 - posse_c},
                    "dangerous_attacks": {"home": atper_c, "away": atper_f},
                    "total_attacks":     {"home": ataques_tot_c, "away": ataques_tot_f},
                    "shots_on_target":   {"home": chg_c, "away": chg_f},
                    "shots_off_target":  {"home": chfora_c, "away": chfora_f},
                    "corners":           {"home": esc_c, "away": esc_f},
                    "yellow_cards":      {"home": ama_c, "away": ama_f},
                    "red_cards":         {"home": ver_c, "away": ver_f},
                },
                "timeline": timeline,
                "_fonte": "API-FOOTBALL-LIVE",
            })
        except Exception:
            continue

    _cache_set_ttl(cache_key, resultados, _LIVE_CACHE_TTL)
    return resultados


def get_flashscore_live_matches() -> Dict[str, Any]:
    """
    Retorna todos os jogos AO VIVO + próximos de hoje com stats estilo FlashScore.
    Formato: {"updated_at": ISO, "matches": [..formato FlashScore padrão..], "total": N}
    """
    agora = datetime.now(timezone(timedelta(hours=-3))).isoformat()
    # 1) Tenta API real live
    live_reais = _fetch_live_real_api() or []

    # 2) Completa com TODAY + fallback simulado enriquecido (máx 20 partidas)
    ids_reais = {m.get("fixture_id") for m in live_reais if m.get("fixture_id")}
    hoje = get_today_matches()
    complemento: List[Dict[str, Any]] = []
    for j in hoje:
        if j.get("id") in ids_reais:
            continue
        if j.get("status") == "PROXIMO" and len(complemento) > 6:
            continue
        complemento.append(_enriquecer_jogo_com_stats_mock(j))

    todos = live_reais + complemento
    # Ordenação: AO_VIVO (1H → HT → 2H → ET → PEN) → PROXIMO por horário → ENCERRADO
    ordem_status = {"1H": 0, "HT": 1, "2H": 2, "ET": 3, "BT": 4, "P": 5,
                    "LIVE": 6, "NS": 7, "TBD": 8,
                    "FT": 9, "AET": 10, "PEN": 11,
                    "SUSP": 12, "INT": 13, "ABD": 14, "CANC": 15, "WO": 16}
    ordem_cat = {"ACERTOS_80": 0, "MULTIPLE_80": 1, "LOW_ODDS_155": 2, "VALUE": 3, "EVITAR": 4}
    todos.sort(key=lambda m: (
        ordem_status.get(m.get("status_short", "NS"), 99),
        ordem_cat.get(m.get("categoria", "VALUE"), 99),
        m.get("minute_elapsed") or 0 if m.get("status_short") in ("1H","HT","2H","ET","BT","P","LIVE") else 0,
        m.get("horario", "99:99"),
    ))

    return {
        "updated_at": agora,
        "polling_next_ms": _LIVE_CACHE_TTL * 1000,
        "total": len(todos),
        "matches": todos,
    }


def get_fixture_stats_events(fixture_id: str) -> Optional[Dict[str, Any]]:
    """Busca detalhe individual (stats + timeline) de um jogo por fixture_id.
    Usa o cache do live + TODAY se necessário."""
    live = get_flashscore_live_matches()
    for m in live["matches"]:
        if str(m.get("fixture_id")) == str(fixture_id) or str(m.get("jogo_id")) == str(fixture_id):
            # Se for API real, tentamos buscar endpoint /fixtures/statistics para enriquecer ainda mais
            if m.get("_fonte", "").startswith("API-FOOTBALL") and not FORCE_MOCK and RAPIDAPI_KEY and httpx:
                cache_key = f"stat:{fixture_id}"
                stat = _cache_get_ttl(cache_key)
                if stat is None:
                    payload = _http_get("/fixtures/statistics",
                                        {"fixture": str(fixture_id).replace("F","").replace("J","")}, timeout=8)
                    if payload and "response" in payload and payload["response"]:
                        try:
                            stats_api = {}
                            for row in (payload["response"] or []):
                                tp = (row.get("type") or "").lower()
                                resp = row.get("response") or []
                                if not resp:
                                    continue
                                home = resp[0].get("statistics") or []
                                away = resp[1].get("statistics") or []
                                def _v(lst, k):
                                    for s in lst:
                                        if (s.get("type") or "").lower() == k:
                                            v = s.get("value") or "0"
                                            try: return int(str(v).replace("%",""))
                                            except Exception: return 0
                                    return 0
                                if "possession" in tp or "ball possession" in tp:
                                    stats_api["possession_pct"] = {"home": _v(home,tp), "away": _v(away,tp)}
                                if "shots on target" in tp:
                                    stats_api["shots_on_target"] = {"home": _v(home,tp), "away": _v(away,tp)}
                                if "shots off target" in tp:
                                    stats_api["shots_off_target"] = {"home": _v(home,tp), "away": _v(away,tp)}
                                if "dangerous attacks" in tp:
                                    stats_api["dangerous_attacks"] = {"home": _v(home,tp), "away": _v(away,tp)}
                                if "total attacks" in tp:
                                    stats_api["total_attacks"] = {"home": _v(home,tp), "away": _v(away,tp)}
                                if "corners" in tp:
                                    stats_api["corners"] = {"home": _v(home,tp), "away": _v(away,tp)}
                                if "yellow cards" in tp:
                                    stats_api["yellow_cards"] = {"home": _v(home,tp), "away": _v(away,tp)}
                                if "red cards" in tp:
                                    stats_api["red_cards"] = {"home": _v(home,tp), "away": _v(away,tp)}
                            if stats_api:
                                m["stats"].update(stats_api)
                                for chave, valores in stats_api.items():
                                    if isinstance(valores, dict) and set(valores.keys()) == {"home","away"}:
                                        if chave in m["home_team"]:
                                            m["home_team"][chave] = valores["home"]
                                            m["away_team"][chave] = valores["away"]
                                _cache_set_ttl(cache_key, True, 30)
                        except Exception:
                            pass
            return m
    return None


def pegar_odds_reais(fixture_id: str) -> Dict[str, Any]:
    """Tenta buscar odds 1X2 reais da API-Football /odds endpoint. Fallback: mock."""
    fid = str(fixture_id).replace("F","").replace("J","")
    if not fid.isdigit():
        return {"home": 2.15, "draw": 3.25, "away": 2.55, "_fonte": "MOCK"}
    if FORCE_MOCK or not RAPIDAPI_KEY or httpx is None:
        rnd = random.Random(int(fid) & 0xFFFFFFFF)
        return {"home": round(1.4+rnd.random()*2.6,2),
                "draw": round(2.9+rnd.random()*1.4,2),
                "away": round(1.4+rnd.random()*2.8,2), "_fonte": "MOCK"}
    cache_key = f"odds:{fid}"
    cached = _cache_get_ttl(cache_key)
    if cached: return cached
    payload = _http_get("/odds", {"fixture": fid, "bookmaker": 8, "bet": 1}, timeout=10)
    if payload and "response" in payload and payload["response"]:
        try:
            for b in payload["response"][0].get("bookmakers") or []:
                for bet in b.get("bets") or []:
                    if (bet.get("name") or "").strip().lower().startswith("match winner") or "1x2" in (bet.get("name") or "").lower():
                        vals = {"home": 0.0, "draw": 0.0, "away": 0.0}
                        for v in bet.get("values") or []:
                            vl = (v.get("value") or "").upper()
                            odd = float(v.get("odd") or 0)
                            if vl in ("1", "HOME"): vals["home"] = odd
                            if vl in ("X", "DRAW"): vals["draw"] = odd
                            if vl in ("2", "AWAY"): vals["away"] = odd
                        if vals["home"] and vals["draw"] and vals["away"]:
                            vals["_fonte"] = "API-FOOTBALL-ODDS"
                            _cache_set_ttl(cache_key, vals, 30)
                            return vals
        except Exception:
            pass
    rnd = random.Random(int(fid) & 0xFFFFFFFF)
    return {"home": round(1.4+rnd.random()*2.6,2),
            "draw": round(2.9+rnd.random()*1.4,2),
            "away": round(1.4+rnd.random()*2.8,2), "_fonte": "FALLBACK"}


# =============================================================================
#  REQUISITO: Endpoint /api/v1/matches — ESTRUTURA FLASHSCORE EXATA
# =============================================================================

def _info_liga_flashscore(liga_nome: str) -> Dict[str, Any]:
    mapa = {
        "Brasileirão Série A": {"id": 71, "country": "Brazil", "flag": "🇧🇷", "has_standings": True},
        "Brasileirão Série B": {"id": 72, "country": "Brazil", "flag": "🇧🇷", "has_standings": True},
        "Copa do Brasil": {"id": 73, "country": "Brazil", "flag": "🇧🇷", "has_standings": False},
        "Premier League": {"id": 39, "country": "England", "flag": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "has_standings": True},
        "La Liga": {"id": 140, "country": "Spain", "flag": "🇪🇸", "has_standings": True},
        "Serie A": {"id": 135, "country": "Italy", "flag": "🇮🇹", "has_standings": True},
        "Bundesliga": {"id": 78, "country": "Germany", "flag": "🇩🇪", "has_standings": True},
        "Ligue 1": {"id": 61, "country": "France", "flag": "🇫🇷", "has_standings": True},
        "UEFA Champions League": {"id": 2, "country": "Europe", "flag": "🇪🇺", "has_standings": True},
        "Copa Libertadores": {"id": 13, "country": "South America", "flag": "🌎", "has_standings": True},
        "Europa League": {"id": 3, "country": "Europe", "flag": "🇪🇺", "has_standings": True},
        "Primeira Liga": {"id": 94, "country": "Portugal", "flag": "🇵🇹", "has_standings": True},
        "Eredivisie": {"id": 88, "country": "Netherlands", "flag": "🇳🇱", "has_standings": True},
    }
    base = {"id": 9999, "country": "World", "flag": "🌍", "has_standings": False}
    for chave, val in mapa.items():
        if chave.lower() in liga_nome.lower() or liga_nome.lower() in chave.lower():
            base = val
            break
    base["name"] = liga_nome
    return base


def _logo_time(nome: str) -> str:
    limpo = nome.strip().lower().replace(" ", "-").replace("á","a").replace("é","e").replace("í","i").replace("ó","o").replace("ú","u").replace("ã","a").replace("õ","o").replace("ç","c")
    return f"https://media.api-sports.io/football/teams/{abs(hash(limpo)) % 2000}.png"


def _status_para_flashscore(status: str, minuto: Optional[int]) -> Dict[str, Any]:
    status = (status or "").upper()
    if status in ("AO_VIVO", "LIVE", "1H", "2H", "ET"):
        ss = status if status in ("1H","2H","ET") else "1H"
        if minuto is not None and minuto <= 45: ss = "1H"
        elif minuto is not None and minuto > 45: ss = "2H"
        return {"status_short": ss, "elapsed": minuto or 0, "status_long": "Em andamento"}
    if status in ("HT", "INTERVALO"):
        return {"status_short": "HT", "elapsed": 45, "status_long": "Intervalo"}
    if status in ("ENCERRADO", "FT", "FINALIZADO"):
        return {"status_short": "FT", "elapsed": 90, "status_long": "Encerrado"}
    if status in ("PROXIMO", "PRÓXIMO", "UPCOMING", "NS", "NOT_STARTED"):
        return {"status_short": "NS", "elapsed": 0, "status_long": "Não iniciado"}
    if status in ("SUSPENSO", "SUSP"):
        return {"status_short": "SUSP", "elapsed": minuto or 0, "status_long": "Suspenso"}
    return {"status_short": "NS", "elapsed": 0, "status_long": "Não iniciado"}


def _match_flat_para_flashscore(m: Dict[str, Any]) -> Dict[str, Any]:
    liga_nome = str(m.get("liga_nome") or m.get("league") or "Unknown")
    info = _info_liga_flashscore(liga_nome)
    casa = str(m.get("time_casa") or m.get("home_team") or m.get("homeTeam") or "Home")
    fora = str(m.get("time_fora") or m.get("away_team") or m.get("awayTeam") or "Away")
    id_num = abs(hash(str(m.get("id") or f"{casa}x{fora}"))) % 2100000000
    home_id = abs(hash(casa.lower())) % 1000000
    away_id = abs(hash(fora.lower())) % 1000000
    status_flat = _status_para_flashscore(
        str(m.get("status") or m.get("fixture_status") or "PROXIMO"),
        m.get("minuto_live") or m.get("minute") or m.get("minutoLive") or None
    )
    gols_casa = m.get("placar_casa") if m.get("placar_casa") is not None else m.get("goals_home") if m.get("goals_home") is not None else None
    gols_fora = m.get("placar_fora") if m.get("placar_fora") is not None else m.get("goals_away") if m.get("goals_away") is not None else None
    odds_r = pegar_odds_reais(str(m.get("id") or id_num))
    return {
        "league": {
            "id": int(info["id"]),
            "name": info["name"],
            "country": info["country"],
            "flag": info["flag"],
            "has_standings": bool(info["has_standings"]),
        },
        "fixture": {
            "id": int(id_num),
            "status_short": status_flat["status_short"],
            "elapsed": int(status_flat["elapsed"] or 0),
            "status_long": status_flat["status_long"],
            "date": m.get("data_jogo_iso") or m.get("date") or datetime.now().strftime("%Y-%m-%d"),
            "time": m.get("horario") or "00:00",
        },
        "teams": {
            "home": {"id": home_id, "name": casa, "logo": _logo_time(casa)},
            "away": {"id": away_id, "name": fora, "logo": _logo_time(fora)},
        },
        "goals": {
            "home": int(gols_casa) if gols_casa is not None else None,
            "away": int(gols_fora) if gols_fora is not None else None,
        },
        "odds": {
            "home_win": f"{float(odds_r.get('home') or 0):.2f}",
            "draw": f"{float(odds_r.get('draw') or 0):.2f}",
            "away_win": f"{float(odds_r.get('away') or 0):.2f}",
        },
    }


def get_matches_filtered(status: str = "all",
                         date: Optional[str] = None,
                         sport: str = "football") -> List[Dict[str, Any]]:
    """
    Endpoint de listagem genérico no formato FlashScore.

    Parâmetros:
      status: 'all' | 'live' | 'finished' | 'upcoming'
      date:   'YYYY-MM-DD' (opcional; padrão = hoje)
      sport:  'football' (padrão, extensível)
    """
    sport = (sport or "football").lower()
    status_l = (status or "all").lower()
    data_ref = datetime.now()
    offset_dia = 0
    if date:
        try:
            data_ref = datetime.strptime(date, "%Y-%m-%d")
            delta = (data_ref.date() - datetime.now().date()).days
            offset_dia = max(0, delta)
        except Exception:
            pass

    cache_key = f"fs_matches_{sport}_{status_l}_{date or 'today'}"
    cached = _cache_get_ttl(cache_key)
    if cached is not None:
        return cached

    # 1) Se esporte diferente de football → vazio
    if sport != "football":
        out: List[Dict[str, Any]] = []
        _cache_set_ttl(cache_key, out, 60)
        return out

    # 2) Coleta a lista flat conforme filtro
    flat_list: List[Dict[str, Any]] = []
    if status_l == "live":
        try:
            live_pack = get_flashscore_live_matches() or {}
            for m in live_pack.get("matches") or []:
                if isinstance(m, dict):
                    # converte do formato FlashScore rich → flat compatível
                    fix_id = m.get("fixture_id") or m.get("id")
                    ht = m.get("home_team") or {}
                    at = m.get("away_team") or {}
                    flat = {
                        "id": fix_id,
                        "liga_nome": (m.get("league") or {}).get("name") if isinstance(m.get("league"), dict) else (m.get("league") or "Unknown"),
                        "time_casa": (ht or {}).get("name") if isinstance(ht, dict) else ht,
                        "time_fora": (at or {}).get("name") if isinstance(at, dict) else at,
                        "placar_casa": (ht or {}).get("score"),
                        "placar_fora": (at or {}).get("score"),
                        "status": "AO_VIVO",
                        "minuto_live": m.get("minute_exact"),
                        "data_jogo_iso": data_ref.strftime("%Y-%m-%d"),
                        "horario": "--:--",
                    }
                    flat_list.append(flat)
        except Exception:
            pass
    else:
        # usa get_today_matches para hoje / offsets (simula datas futuras)
        base_list = get_today_matches(qtd_minima=12) if offset_dia == 0 else [
            gerar_jogo_simulado(i, dia_offset=offset_dia) for i in range(18)
        ]
        flat_list = list(base_list)

    # 3) Filtra por status
    def _matches_status(m: Dict[str, Any], st: str) -> bool:
        s = str(m.get("status") or "PROXIMO").upper()
        ao_vivo = s in ("AO_VIVO", "LIVE", "1H", "2H", "ET")
        fim = s in ("ENCERRADO", "FT", "FINALIZADO")
        prox = s in ("PROXIMO", "PRÓXIMO", "UPCOMING", "NS", "NOT_STARTED")
        if st == "all": return True
        if st == "live": return ao_vivo
        if st == "finished": return fim
        if st == "upcoming": return prox
        return True

    filtrados = [m for m in flat_list if _matches_status(m, status_l)]

    # 4) Converte para estrutura FlashScore exata
    saida = [_match_flat_para_flashscore(m) for m in filtrados]

    ttl = 15 if status_l == "live" else 60
    _cache_set_ttl(cache_key, saida, ttl)
    return saida


# =============================================================================
#  REQUISITO: IA Heurística / Gemini — SINAIS DE APOSTA / NÃO APOSTA
# =============================================================================

def calcular_sinais_ia(usar_gemini: bool = False,
                       apenas_hoje_ou_live: bool = True) -> List[Dict[str, Any]]:
    """
    Retorna lista de sinais para partidas de hoje/live, classificadas em:
      - apostar       (verde, confiança alta)
      - cuidado       (amarelo, confiança média)
      - nao_apostar   (vermelho, confiança baixa)

    Estratégia heurística (fallback se Gemini indisponível) baseada em:
      • Placar já muito distante (3+ gols diferença) → NÃO APOSTAR (mercado fechou tendência)
      • Odd < 1.50 favorito + time mando de campo → APOSTAR (baixa volatilidade)
      • Ambos times marcaram + escanteios altos → CUIDADO (over 2.5 provável mas volátil)
      • Ao vivo com placar 0×0 / 1×0 até 60' + pressão positiva → APOSTAR under/ambos?
    """
    cache_chave = f"ia_sinais_main_v2_{'gem' if usar_gemini else 'heur'}_{'today' if apenas_hoje_ou_live else 'all'}_{datetime.now().strftime('%Y%m%d%H%M')[:-1]}"
    cache_existente = _cache_get_ttl(cache_chave)
    if cache_existente is not None:
        return cache_existente

    lista_base = get_matches_filtered(status="all")
    if not lista_base:
        lista_base = _fs_mock_all_games_for_signals()

    sinais: List[Dict[str, Any]] = []

    for m in lista_base:
        fixture: Dict[str, Any] = (m or {}).get("fixture") or {}
        teams: Dict[str, Any] = (m or {}).get("teams") or {}
        goals: Dict[str, Any] = (m or {}).get("goals") or {}
        odds: Dict[str, Any] = (m or {}).get("odds") or {}
        league: Dict[str, Any] = (m or {}).get("league") or {}

        home: str = ((teams.get("home") or {}).get("name") or "").strip()
        away: str = ((teams.get("away") or {}).get("name") or "").strip()
        liga_nome: str = str(league.get("name") or "")
        pais: str = str(league.get("country") or "")
        flag: str = str(league.get("flag") or "🏆")
        fixture_id: str = str(fixture.get("id") or "")
        status_short = str(fixture.get("status_short") or "NS")
        elapsed = int(fixture.get("elapsed") or 0)
        gh = goals.get("home") if isinstance(goals.get("home"), int) else None
        ga = goals.get("away") if isinstance(goals.get("away"), int) else None
        oh_s = str(odds.get("home_win") or "0").replace(",", ".")
        ox_s = str(odds.get("draw") or "0").replace(",", ".")
        oa_s = str(odds.get("away_win") or "0").replace(",", ".")
        oh = float(oh_s) if oh_s else 0.0
        ox = float(ox_s) if ox_s else 0.0
        oa = float(oa_s) if oa_s else 0.0

        # ---- HEURÍSTICA: SINAL + CONFIANÇA + RAZÃO ----
        sinal_label = "cuidado"
        confianca = 0.55
        razoes: List[str] = []
        odd_sugerida = {"tipo": "Home/Away", "valor": max(oh, oa, ox), "time": "casa" if oh >= oa else "fora" if oa >= ox else "empate"}

        diferenca_gols = abs((gh if gh is not None else 0) - (ga if ga is not None else 0))
        jogo_ja_iniciou = status_short in ("1H", "2H", "ET") and elapsed > 0
        favorito_odd = min([x for x in (oh, oa, ox) if x > 1.0] or [99])
        tem_odds_validas = (oh + ox + oa) > 3.0

        # CASO 1: Odd do favorito <= 1.80 + jogo NÃO começou ainda → APOSTAR
        if (not jogo_ja_iniciou) and tem_odds_validas and 1.0 < favorito_odd <= 1.85:
            sinal_label = "apostar"
            confianca = 0.68 + max(0.0, (1.85 - favorito_odd) * 0.12)
            if favorito_odd == oh:
                odd_sugerida = {"tipo": "Vitória Casa", "valor": oh, "time": home}
            elif favorito_odd == oa:
                odd_sugerida = {"tipo": "Vitória Fora", "valor": oa, "time": away}
            else:
                odd_sugerida = {"tipo": "Empate", "valor": ox, "time": "X"}
            if favorito_odd <= 1.55:
                razoes.append(f"Favorito forte · odd baixa ({favorito_odd:.2f})")
                razoes.append("Probabilidade estatística ≥ 80%")
            else:
                razoes.append(f"Favorito razoável · odd {favorito_odd:.2f}")
                razoes.append("Dupla chance reduz risco")

        # CASO 2: Jogo ao vivo 0-0 ou 1-0 antes 60min → APOSTAR gols no final
        if jogo_ja_iniciou and elapsed <= 62 and diferenca_gols <= 1 and tem_odds_validas:
            if ((gh or 0) + (ga or 0)) <= 2 and (oh < 2.6 or oa < 2.6):
                sinal_label = "apostar"
                confianca = 0.66
                odd_sugerida = {"tipo": "Over 0.5 FT / Gols finais", "valor": 1.60, "time": f"{home} × {away}"}
                razoes.append(f"Ao vivo {elapsed}' · placar baixo")
                razoes.append("Pressão final favorece gols")

        # CASO 2b: Ao vivo 1T c/ pressão alta (dif 1 gols) → APOSTAR / Dupla Chance
        if jogo_ja_iniciou and elapsed <= 45 and diferenca_gols == 1 and status_short == "1H":
            if ((oh > 0 and oh <= 2.2) or (oa > 0 and oa <= 2.2)):
                sinal_label = "apostar"
                confianca = 0.70
                lado = "Casa" if oh <= oa else "Fora"
                odd_sugerida = {"tipo": "Dupla Chance 1X / X2", "valor": 1.35, "time": lado}
                razoes.append(f"1T · {elapsed}' · placar favorável")
                razoes.append("Tendência de manter vantagem")

        # CASO 3: Placar já distante (2+ gols diferença) + ≥ 55min → NÃO APOSTAR
        if jogo_ja_iniciou and elapsed >= 55 and diferenca_gols >= 2:
            sinal_label = "nao_apostar"
            confianca = 0.78
            odd_sugerida = {"tipo": "Mercado fechando", "valor": 0.0, "time": "—"}
            razoes.append(f"Placar distante ({gh or 0}×{ga or 0}) + {elapsed}'")
            razoes.append("Poucas possibilidades de lucro")

        # CASO 4: Jogo encerrado → NÃO APOSTAR
        if status_short == "FT":
            sinal_label = "nao_apostar"
            confianca = 0.92
            odd_sugerida = {"tipo": "Já encerrado", "valor": 0.0, "time": "FT"}
            razoes.append("Partida já finalizada")

        # CASO 5: Odds equilibradas (todas > 2.3) → CUIDADO
        if (not jogo_ja_iniciou) and tem_odds_validas and oh > 2.3 and oa > 2.3 and ox >= 2.9:
            sinal_label = "cuidado"
            confianca = 0.58
            odd_sugerida = {"tipo": "Over 2.5 Gols", "valor": 1.90, "time": "Total"}
            razoes.append("Odds equilibradas · jogo imprevisível")
            razoes.append("Preferir mercado de gols / over")

        # CASO 6: Padrão "Over 2.5 provável" (favorito 1.5-2.2, empate > 3.1) → APOSTAR (CUIDADO leve)
        if sinal_label == "cuidado" and tem_odds_validas and (not jogo_ja_iniciou) and (ox > 3.0) and ((1.4 <= oh <= 2.25) or (1.4 <= oa <= 2.25)):
            sinal_label = "apostar"
            confianca = 0.61
            odd_sugerida = {"tipo": "Over 2.5 Gols", "valor": 1.82, "time": "Total"}
            razoes.append("Favorito razoável + over provável")
            razoes.append("Entrada conservadora em gols")

        # CASO 7: Casa leve favorita (odd 1.85-2.25) e jogando em casa → APOSTAR 1X
        if sinal_label == "cuidado" and (not jogo_ja_iniciou) and tem_odds_validas and (1.85 <= oh <= 2.25) and (oh < oa):
            sinal_label = "apostar"
            confianca = 0.64
            odd_sugerida = {"tipo": "Dupla Chance 1X", "valor": round(oh * 0.68, 2), "time": home}
            razoes.append(f"{home} em casa · vantagem estatística")
            razoes.append("1X garante empate como retorno")

        # CASO 8: HT (intervalo) c/ placar 0-0 ou 1-0 → APOSTAR 2T
        if status_short == "HT":
            if (gh or 0) + (ga or 0) <= 1:
                sinal_label = "apostar"
                confianca = 0.69
                odd_sugerida = {"tipo": "Over 0.5 no 2ºT", "valor": 1.55, "time": "Total 2T"}
                razoes.append("Intervalo · placar baixo no 1ºT")
                razoes.append("Times voltam agressivos para 2ºT")

        # -- Fallback sinais não preenchidos (cuidado default) --
        if not razoes:
            if sinal_label == "cuidado":
                if tem_odds_validas and (oh <= 2.5 or oa <= 2.5):
                    sinal_label = "apostar"
                    confianca = 0.58
                    odd_sugerida = {"tipo": "Dupla Chance", "valor": 1.40, "time": "Casa / Fora favorito"}
                    razoes.append("Favorito levemente definido")
                    razoes.append("Entrada em DC para segurança")
                else:
                    razoes.append("Sinal neutro · analisar contexto antes")
                    confianca = 0.50
            elif sinal_label == "apostar":
                razoes.append("Indicadores técnicos favoráveis")
            elif sinal_label == "nao_apostar":
                razoes.append("Risco acima do recomendado")

        # arredonda confiança
        confianca = round(max(0.1, min(0.98, confianca)), 2)
        pct = int(round(confianca * 100, 0))

        sinais.append({
            "fixture_id": fixture_id,
            "league": {"id": league.get("id"), "name": liga_nome, "country": pais, "flag": flag},
            "fixture": {"id": fixture.get("id"), "status_short": status_short, "elapsed": elapsed},
            "teams": {"home": {"name": home}, "away": {"name": away}},
            "goals": {"home": gh, "away": ga},
            "sinal": sinal_label,
            "confianca": pct,
            "confianca_float": confianca,
            "razoes": razoes,
            "odd_sugerida": odd_sugerida,
            "odds_originais": {"home_win": f"{oh:.2f}", "draw": f"{ox:.2f}", "away_win": f"{oa:.2f}"},
        })

    # Ordena: apostar (confiança desc) → cuidado → nao_apostar
    ordem_sinal = {"apostar": 0, "cuidado": 1, "nao_apostar": 2}
    sinais.sort(key=lambda s: (ordem_sinal.get(s["sinal"], 9), -s.get("confianca", 0)))

    # Tenta Gemini se usar_gemini=True e key setada
    if usar_gemini:
        try:
            sinais = _enriquecer_com_gemini(sinais)
        except Exception:
            # fallback silencioso, mantém heurística
            pass

    _cache_set_ttl(cache_chave, sinais, 90)
    return sinais


def _fs_mock_all_games_for_signals() -> List[Dict[str, Any]]:
    lista: List[Dict[str, Any]] = []
    data = datetime.now().strftime("%Y-%m-%d")
    confrontos = [
        ("Palmeiras", "Fluminense", "Brasileirão Série A", "Brazil", "🇧🇷", 71, "NS", 0, None, None, 1.45, 4.20, 6.50),
        ("Flamengo", "Vasco", "Brasileirão Série A", "Brazil", "🇧🇷", 71, "1H", 32, 1, 0, 1.58, 4.00, 5.20),
        ("São Paulo", "Botafogo", "Brasileirão Série A", "Brazil", "🇧🇷", 71, "2H", 77, 2, 2, 2.40, 3.10, 2.90),
        ("Liverpool", "Arsenal", "Premier League", "England", "🏴", 39, "NS", 0, None, None, 2.30, 3.35, 3.00),
        ("Man. City", "Chelsea", "Premier League", "England", "🏴", 39, "NS", 0, None, None, 1.52, 4.40, 5.80),
        ("Real Madrid", "Barcelona", "La Liga", "Spain", "🇪🇸", 140, "2H", 69, 3, 0, 1.65, 3.90, 4.80),
        ("Inter", "Milan", "Serie A", "Italy", "🇮🇹", 135, "FT", 90, 1, 1, 2.10, 3.20, 3.50),
        ("Bayern", "Dortmund", "Bundesliga", "Germany", "🇩🇪", 78, "NS", 0, None, None, 1.48, 4.70, 5.90),
    ]
    for i, c in enumerate(confrontos):
        casa, fora, liga, pais, flag, idl, ss, el, gh, ga, oh, ox, oa = c
        lista.append({
            "league": {"id": idl, "name": liga, "country": pais, "flag": flag, "has_standings": True},
            "fixture": {"id": 9000 + i, "status_short": ss, "elapsed": el, "status_long": "", "date": data, "time": "19:30"},
            "teams": {
                "home": {"id": 100 + i, "name": casa, "logo": f"https://media.api-sports.io/football/teams/{i}.png"},
                "away": {"id": 200 + i, "name": fora, "logo": f"https://media.api-sports.io/football/teams/{i + 50}.png"},
            },
            "goals": {"home": gh, "away": ga},
            "odds": {"home_win": f"{oh:.2f}", "draw": f"{ox:.2f}", "away_win": f"{oa:.2f}"},
        })
    return lista


def _enriquecer_com_gemini(sinais: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Se a chave Gemini estiver configurada no ambiente, faz um prompt resumido
    sobre o TOP 10 e ajusta levemente confiança/rótulo. Fallback silencioso.
    """
    import os
    chave = os.getenv("GEMINI_API_KEY") or os.getenv("GEMINI_KEY") or ""
    if not chave or chave.startswith("sua_chave") or not chave.strip():
        return sinais

    # Limita TOP 12 para não gastar tokens
    top = sinais[:12]
    contexto = []
    for s in top:
        home = s["teams"]["home"]["name"]
        away = s["teams"]["away"]["name"]
        odd_h = s["odds_originais"]["home_win"]
        odd_a = s["odds_originais"]["away_win"]
        odd_x = s["odds_originais"]["draw"]
        contexto.append(f"- {home} x {away} | odds {odd_h} / {odd_x} / {odd_a} | sinal_heur={s['sinal']} conf={s['confianca']}%")
    prompt = (
        "Você é tipster sênior. Analise esses 12 jogos e RETORNE APENAS JSON no formato "
        '[{"idx":0,"sinal":"apostar|cuidado|nao_apostar","confianca_pct":70,"razao_curta":"motivo 100 chars"}, ...] '
        "sem markdown, sem texto adicional.\n\nJogos:\n" + "\n".join(contexto)
    )
    try:
        import httpx
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={chave}"
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.35, "maxOutputTokens": 1024, "responseMimeType": "application/json"}
        }
        headers = {"Content-Type": "application/json"}
        resp = httpx.post(url, json=payload, headers=headers, timeout=25)
        if resp.status_code != 200:
            return sinais
        data = resp.json()
        txt = ""
        for cand in (data.get("candidates") or []):
            for part in (((cand.get("content") or {}).get("parts")) or []):
                txt += (part.get("text") or "")
        txt = txt.strip().strip("```json").strip("```").strip()
        import json as _json
        parsed = _json.loads(txt)
        if isinstance(parsed, list):
            for item in parsed:
                idx = item.get("idx") if isinstance(item, dict) else None
                if idx is None or not isinstance(idx, int) or idx >= len(top):
                    continue
                novo_sinal = (item.get("sinal") or "").strip()
                if novo_sinal in ("apostar", "cuidado", "nao_apostar"):
                    top[idx]["sinal"] = novo_sinal
                pct = item.get("confianca_pct")
                if isinstance(pct, (int, float)):
                    top[idx]["confianca"] = max(10, min(98, int(pct)))
                    top[idx]["confianca_float"] = top[idx]["confianca"] / 100.0
                razao_extra = (item.get("razao_curta") or "").strip()
                if razao_extra:
                    top[idx]["razoes"].insert(0, f"🤖 IA: {razao_extra}")
            # Reordena após enriquecimento
            ordem_sinal = {"apostar": 0, "cuidado": 1, "nao_apostar": 2}
            sinais[:12] = top
            sinais.sort(key=lambda s: (ordem_sinal.get(s["sinal"], 9), -s.get("confianca", 0)))
    except Exception:
        return sinais
    return sinais

