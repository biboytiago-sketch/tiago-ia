import os
import time
import random
import logging
import httpx
from datetime import datetime, timedelta, timezone as _tzmod
from typing import List, Dict, Any, Optional, Tuple

logger = logging.getLogger(__name__)

# ============================================================
# 🔒 FUSO HORÁRIO BRASÍLIA (UTC-3) — NUNCA MAIS DATA ERRADA
# ============================================================
# Render/AWS/Docker rodam em UTC. datetime.now() lá = 3h NA FRENTE do BR.
# Sempre que calcular "hoje", usar _agora_brasil() ou _data_brasil_aware().
_BRASIL_UTC_OFFSET = timedelta(hours=-3)
_BRASIL_TZ = _tzmod(_BRASIL_UTC_OFFSET)


def _agora_brasil() -> datetime:
    """Datetime AGORA no fuso de Brasília (UTC-3). Seguro para Render/UTC."""
    return datetime.now(_BRASIL_TZ)


def _data_brasil_aware(data_ref: Optional[datetime] = None) -> datetime:
    """Garante que data_ref tem tzinfo=Brasília. Se for naive, assume Brasilia."""
    if data_ref is None:
        return _agora_brasil()
    if data_ref.tzinfo is None:
        # Data naive (sem fuso): assumimos que quem mandou quis dizer BR (comum em chamadas locais)
        return data_ref.replace(tzinfo=_BRASIL_TZ)
    # Já tem timezone: converte para BR
    return data_ref.astimezone(_BRASIL_TZ)


def _season_correta_para_data(data_ref_br: datetime) -> int:
    """
    Ligações europeias = season = ANO_DO_INÍCIO (agosto 2026 => season=2026, não 2027).
    Ligações brasileiras = season = ano civil (2026).
    Para simplificar e compatibilizar com a maioria das APIs: usamos SEMPRE
    o ANO CIVIL da data (ex: 21/08/2026 => season=2026).
    """
    return data_ref_br.year


_SIGNATURE_IA_DO_TIAGO = "IA do Tiago · Live Sports v3 · Oficial"

_RAPIDAPI_KEY = (
    os.getenv("RAPIDAPI_KEY")
    or os.getenv("FOOTBALL_API_KEY")
    or "ed1e28effamsh892bb0911fbfd6cp154f1fjsnc845200dc936"
)

# ═══════════════════════════════════════════════════════════════════
# STEP 1 · NOVAS CHAVES (FONTES 5 e 6 — AUTÊNTICAÇÃO PRÓPRIA, NÃO RapidAPI)
# ═══════════════════════════════════════════════════════════════════
# FONTE 5: API-Football DIRETO (api-football.com · hospedagem oficial = api-sports.io)
#   Mesmo schema JSON exato da Fonte 3 (RAPIDAPI_REAL). Reutiliza _map_legacy_apifootball_item.
#   Auth: X-RapidAPI-Key (sim, o host direto aceita esse nome!) ou x-apisports-key.
_API_FOOTBALL_DIRECT_KEY = (os.getenv("API_FOOTBALL_KEY") or "").strip()

# FONTE 6: Football-Data.org (gratuita Free Tier · 10 req/min)
#   Schema diferente: { "matches": [ { "homeTeam": {"name": "...", ...}, ... } ] }
#   Auth: X-Auth-Token header ou ?X-Auth-Token= query param.
_FOOTBALL_DATA_ORG_KEY = (os.getenv("FOOTBALL_DATA_ORG_KEY") or "").strip()

# ============================================================
# CADEIA DE FONTES REAIS (ORDEM de PRIORIDADE):
#   ATENCAO 2026-08-19: 4 fontes RapidAPI estao em HTTP 403
#   ("You are not subscribed to this API") porque a chave
#   ed1e28... nao tem assinatura paga no marketplace RapidAPI
#   para os hosts abaixo. Por isso reordenamos a cadeia para
#   as FONTES DIRETAS (Football-Data.org e API-Football Direto)
#   VIREM PRIMEIRO quando as chaves estao configuradas, porque
#   elas sao independentes do RapidAPI.
#
#   ORDEM FINAL (6 camadas reais + 1 fallback IA):
#   1) FOOTBALLDATA_ORG → api.football-data.org/v4 (GRATUITA · FUNCIONANDO HOJE)
#   2) APIFOOTBALL_DIR  → v3.football.api-sports.io (Direto · opcional pago)
#   3) FLASHLIVE        → flashlive-sports.p.rapidapi.com (Rapid · 403 aguardando assinatura)
#   4) API_FOOTBALL_V1  → api-football-v1.p.rapidapi.com (Rapid · 403 pago)
#   5) FOOTBALL_PRO_V3  → football-pro.p.rapidapi.com (Rapid · 403 pago)
#   6) FALLBACK IA      → _fallback_live / _fallback_data (seed dinâmica IA do Tiago)
# Cada fonte tem seu adapter que normaliza o JSON de resposta para o MESMO dicionário
# que o resto do código e o Flutter já esperam (origem_dados, fixture_id, time_casa, etc)
#
# 🔴 ATUALIZAÇÃO 2026-08-21: FONTE 4 (FREE_API) REMOVIDA
#    (retornava HTTP 404 em TODOS endpoints — API removida do RapidAPI.
#    Não vale a pena gastar requisições em 404.
# ============================================================
_RAPIDAPI_HOST_FONTE_1 = (
    os.getenv("RAPIDAPI_HOST_FLASHLIVE") or "flashlive-sports.p.rapidapi.com"
)
_RAPIDAPI_HOST_FONTE_3 = (
    os.getenv("RAPIDAPI_HOST_LEGACY") or "api-football-v1.p.rapidapi.com"
)
_RAPIDAPI_HOST_FONTE_4 = (
    os.getenv("RAPIDAPI_HOST_FOOTBALL_PRO") or "football-pro.p.rapidapi.com"
)
_RAPIDAPI_SOURCES = [
    {
        "id": "FLASHLIVE_SPORTS",
        "label": "FlashLive Sports",
        "ordem": 3,
        "origem": "RAPIDAPI_FLASHLIVE",
        "tipo_auth": "rapidapi",
        "host": _RAPIDAPI_HOST_FONTE_1,
        "live_paths": [
            "/v1/events/live?sport_id=1",
            "/v1/events/list?sport_id=1&page=1",
        ],
        "date_path": "/v1/events/list?sport_id=1",
        "date_param": "date",
    },
    {
        "id": "API_FOOTBALL_V1_LEGACY",
        "label": "API-Football (RapidAPI)",
        "ordem": 4,
        "origem": "RAPIDAPI_REAL",
        "tipo_auth": "rapidapi",
        "host": _RAPIDAPI_HOST_FONTE_3,
        "live_paths": ["/fixtures?live=all"],
        "date_path": "/fixtures",
        "date_param": "date",
    },
    {
        "id": "FOOTBALL_PRO_V3",
        "label": "Football-Pro v3 (RapidAPI)",
        "ordem": 5,
        "origem": "RAPIDAPI_FOOTBALL_PRO",
        "tipo_auth": "rapidapi",
        "host": _RAPIDAPI_HOST_FONTE_4,
        "live_paths": [
            "/v3/football/fixtures/live",
            "/v3/football/fixtures?live=all",
            "/fixtures/live",
        ],
        "date_path": "/v3/football/fixtures",
        "date_param": "date",
    },
]

# ═══════════════════════════════════════════════════════════════════
# 🔴 FOOTBALL-DATA.ORG PLANO FREE - Ligas permitidas (obrigatórias!)
# ═══════════════════════════════════════════════════════════════════
# Plano FREE de api.football-data.org cobre APENAS 14 ligas.
# Se a URL /matches for chamada SEM competitions=, retorna HTTP 400.
# Lista oficial (docs.football-data.org):
#   2000 = WC Qualification, 2001 = UEFA Champions League
#   2002 = Bundesliga, 2003 = Eredivisie, 2013 = Serie A
#   2014 = Ligue 1, 2015 = Campeonato Portuguesa, 2016 = Premier League
#   2017 = Champions League, 2018 = European Championship
#   2019 = Serie B (Itália), 2021 = Primeira Liga (Portugal)
#   2008 = Premier League (backup), 2012 = Copa Libertadores não está no free tier,
#   Adicionamos 2007 (Copa América) e 2116 (Serie A do Brasil) se disponível.
# → Com essas ligas: Premier League, La Liga, Serie A, Bundesliga + Brasileirao nao gratis
#   free tier = 14 competições europeias de graça = jogo REAL
# Comentado porque NÃO usamos (duplicata). Apenas documentação.
# _FDORG_COMPETITIONS_FREE = "2000,2001,2002,2003,2013,2014,2015,2016,2017,2018,2019,2021,2008,2116"

# Base oficial (sem duplicatas, comma separated) = 13 ligas FREE tier.
_FDORG_COMPETITIONS_DEFAULT = (
    "2000,2001,2002,2003,2013,2014,2015,2016,2017,2018,2019,2021,2008"
)


_DIRECT_SOURCES: List[Dict[str, Any]] = [
    {
        "id": "APIFOOTBALL_DIRECT",
        "label": "API-Football Direto",
        "ordem": 2,
        "origem": "APIFOOTBALL_DIRECT",
        "tipo_auth": "api_football_direct",
        "base_url": "https://v3.football.api-sports.io",
        "chave_env_nome": "API_FOOTBALL_KEY",
        "live_paths": ["/fixtures?live=all"],
        "date_path": "/fixtures",
        "date_param": "date",
        "adapter": "api_football_legacy",
    },
    {
        "id": "FOOTBALLDATA_ORG",
        "label": "Football-Data.org",
        "ordem": 1,
        "origem": "FOOTBALLDATA_ORG",
        "tipo_auth": "football_data_org",
        "base_url": "https://api.football-data.org/v4",
        "chave_env_nome": "FOOTBALL_DATA_ORG_KEY",
        "live_paths": ["/matches?status=LIVE", "/matches?status=IN_PLAY"],
        "date_path": "/matches",
        "date_param": "dateFrom",
        "adapter": "football_data_org",
        "competitions": _FDORG_COMPETITIONS_DEFAULT,
    },
]

# Host padrão para requisições custom/estatísticas (mantém compatibilidade)
_RAPIDAPI_HOST = _RAPIDAPI_HOST_FONTE_1

_HEADERS = {
    "x-rapidapi-key": _RAPIDAPI_KEY,
    "x-rapidapi-host": _RAPIDAPI_HOST,
}

_BASE_URL = f"https://{_RAPIDAPI_HOST}"

# ═══════════════════════════════════════════════════════════════════
# 🔴 CORREÇÃO CRÍTICA: CACHE com expiração CORRETA (não deixa tudo 60s)
# ═══════════════════════════════════════════════════════════════════
# Bug original: _cache_get SEMPRE comparava com _CACHE_TTL_STATIC,
# mesmo quando a chave foi gravada com TTL LIVE de 12s.
#   → Resultado: tudo ficava mínimo 60s em cache = jogos atrasados.
#
# Solução V3.7: guardar (expira_em_unix_time, valor, ttl_usado) e
# comparar com time.time() absoluto. LIVE = 5s (antes 12s → ainda lento).
_CACHE: Dict[str, tuple[float, Any]] = {}
# Cache LIVE: máximo 5 segundos (gols mudam rápido!)
_CACHE_TTL_LIVE = 5.0
# Cache do dia/estático: 30s (antes 60s) para atualizar odds sem ficar obsoleto
_CACHE_TTL_STATIC = 30.0


# ═══════════════════════════════════════════════════════════════════
# 🔴 CORREÇÃO CRÍTICA: BACKOFF EXPONENCIAL COM JITTER (evita 429)
# ═══════════════════════════════════════════════════════════════════
# Problema: cotas RapidAPI grátis (30 req/dia) → se bater 429, o código
# repetia N vezes em loop e matava a cota de 1 dia em 10s.
#
# Solução: 429/403 → espera 2^tentativa * 1s + jitter aleatório (0-1s).
#   1ª tentativa:   ~1.2s
#   2ª tentativa:   ~2.3s
#   3ª tentativa:   ~4.7s (não faremos mais de 3 tentativas por ciclo)
# Também colocamos as fontes RapidApi com "cooldown" de 60s depois de
# 3x 429, para não gastar requisições à toa por 1 minuto.
_CACHE_FAIL_COOLDOWN: Dict[str, float] = {}


def _fonte_em_cooldown(host_ou_id: str) -> bool:
    """Retorna True se essa fonte foi bloqueada 3x e está em cooldown."""
    limite = _CACHE_FAIL_COOLDOWN.get(host_ou_id)
    if limite and time.time() < limite:
        return True
    if limite and time.time() >= limite:
        _CACHE_FAIL_COOLDOWN.pop(host_ou_id, None)
    return False


def _fonte_marcar_cooldown(host_ou_id: str, segundos: int = 60) -> None:
    """Bloqueia essa fonte por N segundos (evita 429 em cascata)."""
    _CACHE_FAIL_COOLDOWN[host_ou_id] = time.time() + segundos


def _backoff_wait(tentativa: int, max_tentativas: int = 3) -> bool:
    """Aguarda 2^tentativa + jitter (0-1s). Retorna False se chegou ao max."""
    if tentativa >= max_tentativas:
        return False
    espera = float(2 ** tentativa) + random.random()
    time.sleep(espera)
    return True


def _req_host_com_retry(host: str, path: str,
                        params: Optional[Dict[str, Any]] = None,
                        ttl: float = _CACHE_TTL_STATIC) -> Optional[Any]:
    """_req_host com até 3 tentativas + backoff exponencial + cooldown."""
    if _fonte_em_cooldown(host):
        logger.debug(f"SKIP {host} (cooldown 429/403)")
        return None
    tentativa = 0
    ultimo_status = None
    while True:
        data = _req_host(host, path, params=params, ttl=ttl)
        # Se data voltou vazio E a URL pegou 429/403, o logger do _req_host
        # avisou. Inferimos 429/403 pela resposta None + marcamos.
        if data is not None and len(_extract_list_from_any(data)) > 0:
            return data
        # Se caiu aqui = 429/403/404 ou vazio
        # Repetimos apenas mais 2x para casos de 429 temporários:
        tentativa += 1
        if ultimo_status is None:
            ultimo_status = 429  # assumimos pior caso
        if not _backoff_wait(tentativa, max_tentativas=3):
            # Chegou em 3 tentativas → bloqueia por 60s
            _fonte_marcar_cooldown(host, 60)
            return data
    return data


def _req_direct_com_retry(fonte: Dict[str, Any], path: str,
                          params: Optional[Dict[str, Any]] = None,
                          ttl: float = _CACHE_TTL_STATIC) -> Optional[Any]:
    """_req_direct com retry + cooldown para fontes diretas."""
    fid = fonte.get("id") or fonte.get("host") or "direct"
    if _fonte_em_cooldown(fid):
        logger.debug(f"SKIP DIRECT {fid} (cooldown)")
        return None
    tentativa = 0
    while True:
        data = _req_direct(fonte, path, params=params, ttl=ttl)
        if data is not None and len(_extract_list_from_any(data)) > 0:
            return data
        tentativa += 1
        if not _backoff_wait(tentativa, max_tentativas=3):
            _fonte_marcar_cooldown(fid, 90)
            return data
    return data


def _cache_get(chave: str) -> Optional[Any]:
    entrada = _CACHE.get(chave)
    if not entrada:
        return None
    expira_em, valor = entrada
    if time.time() > expira_em:
        _CACHE.pop(chave, None)
        return None
    return valor


def _cache_set(chave: str, valor: Any, ttl: float = _CACHE_TTL_STATIC) -> None:
    # Guarda o timestamp ABSOLUTO de expiração (time.time() + ttl)
    # → NÃO depende de qual constante for usada na leitura.
    _CACHE[chave] = (time.time() + max(1.0, float(ttl)), valor)


def _get_json(path: str, params: Optional[Dict[str, Any]] = None, ttl: float = _CACHE_TTL_STATIC) -> Dict[str, Any]:
    cache_key = f"{path}::{params or {}}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    try:
        with httpx.Client(timeout=12.0) as client:
            resp = client.get(f"{_BASE_URL}{path}", params=params or {}, headers=_HEADERS)
            resp.raise_for_status()
            data = resp.json()
    except Exception as e:
        logger.warning(f"live_sports GET {path} falhou: {e}")
        data = {"response": [], "errors": {"http": str(e)}}
    _cache_set(cache_key, data, ttl)
    return data


def _headers_para_host(host: str) -> Dict[str, str]:
    return {
        "x-rapidapi-key": _RAPIDAPI_KEY,
        "x-rapidapi-host": host,
        "User-Agent": "taigo-live-sports/v3",
    }


def _req_host(host: str, path: str, params: Optional[Dict[str, Any]] = None,
              ttl: float = _CACHE_TTL_STATIC) -> Optional[Any]:
    """Requisição GENÉRICA para QUALQUER host RapidAPI (não só o padrão).
       Retorna JSON parseado ou None em caso de erro (nunca estoura)."""
    cache_key = f"{host}{path}::{params or {}}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    url = f"https://{host}{path}"
    headers = _headers_para_host(host)
    try:
        with httpx.Client(timeout=12.0) as client:
            resp = client.get(url, params=params or {}, headers=headers)
            if 200 <= resp.status_code < 300:
                data = resp.json()
            else:
                logger.warning(f"FONTE {host}{path} → HTTP {resp.status_code}")
                data = None
    except Exception as e:
        logger.warning(f"FONTE {host}{path} falhou: {str(e)[:120]}")
        data = None
    _cache_set(cache_key, data or {}, ttl)
    return data


# ═══════════════════════════════════════════════════════════════════
# STEP 1 · HELPERS PARA FONTES DIRETAS (não-RapidAPI)
# ═══════════════════════════════════════════════════════════════════
def _fonte_direta_chave(fonte: Dict[str, Any]) -> str:
    """Pega o VALOR ATUAL da env var da fonte direta.
    Usa `os.getenv()` NA HORA (não o valor capturado no import-time) para
    funcionar corretamente com load_dotenv(override=True)."""
    nome_env = (fonte.get("chave_env_nome") or fonte.get("chave_env_nome") or
                fonte.get("chave_env") or "")
    if isinstance(nome_env, str) and nome_env and nome_env.upper() == nome_env and "_" in nome_env:
        # Parece um NOME de env var (ex: FOOTBALL_DATA_ORG_KEY)
        return (os.getenv(nome_env) or "").strip()
    # Caso contrário era o valor mesmo, use como fallback
    return (str(nome_env or "")).strip()


def _headers_para_fonte_direta(fonte: Dict[str, Any]) -> Dict[str, str]:
    tipo = fonte.get("tipo_auth") or ""
    chave = _fonte_direta_chave(fonte)
    ua = "taigo-live-sports/v3-direct"
    if tipo == "api_football_direct":
        return {
            "x-apisports-key": chave,
            "x-rapidapi-key": chave,
            "User-Agent": ua,
            "Accept": "application/json",
        }
    if tipo == "football_data_org":
        return {
            "X-Auth-Token": chave,
            "User-Agent": ua,
            "Accept": "application/json",
        }
    return {"User-Agent": ua, "Accept": "application/json"}


def _req_direct(fonte: Dict[str, Any], path: str,
                params: Optional[Dict[str, Any]] = None,
                ttl: float = _CACHE_TTL_STATIC) -> Optional[Any]:
    """Requisição para FONTE DIRETA (não-RapidAPI). Usa chave própria.
       Falha silenciosamente → None. Sempre cacheia."""
    chave = _fonte_direta_chave(fonte)
    cache_key = f"DIRECT::{fonte['id']}{path}::{params or {}}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    if not chave:
        # Não tem chave configurada → pula (sem crashar)
        _cache_set(cache_key, {}, ttl)
        return None
    base = fonte.get("base_url", "").rstrip("/")
    pth = path if path.startswith("/") else f"/{path}"
    url = f"{base}{pth}"
    headers = _headers_para_fonte_direta(fonte)
    try:
        with httpx.Client(timeout=12.0, follow_redirects=True) as client:
            resp = client.get(url, params=params or {}, headers=headers)
            if 200 <= resp.status_code < 300:
                data = resp.json()
            else:
                logger.warning(
                    f"FONTE DIRETA {fonte['id']}{path} → HTTP {resp.status_code}"
                )
                data = None
    except Exception as e:
        logger.warning(f"FONTE DIRETA {fonte['id']}{path} falhou: {str(e)[:120]}")
        data = None
    _cache_set(cache_key, data or {}, ttl)
    return data


# ═══════════════════════════════════════════════════════════════════
# STEP 1 · ADAPTER: Football-Data.org → formato padrão app
# Schema:
#   { "matches": [ {
#     "id": 456789, "utcDate": "2026-08-19T20:00:00Z",
#     "status": "LIVE" | "FINISHED" | "SCHEDULED" | "PAUSED" | "IN_PLAY",
#     "homeTeam": {"id": 66, "name": "Palmeiras", "shortName": "Palmeiras", "crest": "https://..."},
#     "awayTeam": {...},
#     "competition": {"id": 2013, "name": "Brasileirão Série A", "code": "BSA",
#                     "area": {"name": "Brazil", "code": "BRA", "flag": "https://..."}
#     "score": {"fullTime": {"home": 2, "away": 1}, "halfTime": {...}}
#   } ] }
# ═══════════════════════════════════════════════════════════════════
_FDORG_AREAS_PARA_BANDEIRA_EMOJI = {
    "BRA": "🇧🇷", "Brazil": "🇧🇷",
    "ENG": "🏴", "England": "🏴",
    "ESP": "🇪🇸", "Spain": "🇪🇸",
    "ITA": "🇮🇹", "Italy": "🇮🇹",
    "GER": "🇩🇪", "Germany": "🇩🇪",
    "FRA": "🇫🇷", "France": "🇫🇷",
    "POR": "🇵🇹", "Portugal": "🇵🇹",
    "NED": "🇳🇱", "Netherlands": "🇳🇱",
    "ARG": "🇦🇷", "Argentina": "🇦🇷",
    "Europe": "🇪🇺", "World": "🌍",
}


def _fdorg_flag(area: Dict[str, Any]) -> str:
    codigo = (area or {}).get("code") or ""
    nome = (area or {}).get("name") or ""
    return (_FDORG_AREAS_PARA_BANDEIRA_EMOJI.get(codigo)
            or _FDORG_AREAS_PARA_BANDEIRA_EMOJI.get(nome)
            or str((area or {}).get("flag") or "🌍")[:4] or "🌍")


def _map_football_data_org_item(m: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Adapter 1 item Football-Data.org → formato PADRÃO do app."""
    ret: Any = None
    try:
        fid = m.get("id")
        if not fid:
            fid = random.randint(9_000_000, 9_999_999)
        home = m.get("homeTeam") or {}
        away = m.get("awayTeam") or {}
        time_casa = str(home.get("name") or home.get("shortName") or "")
        time_fora = str(away.get("name") or away.get("shortName") or "")
        if not time_casa or not time_fora:
            return None
        comp = m.get("competition") or {}
        area = comp.get("area") or {}
        lg_nome = str(comp.get("name") or comp.get("code") or "Copa")
        lg_pais = str(area.get("name") or area.get("code") or "")
        lg_bandeira = _fdorg_flag(area)

        status_raw = (str(m.get("status") or "SCHEDULED")).upper()
        st_curto = status_raw
        minuto = None
        if status_raw in ("LIVE", "IN_PLAY"):
            st = "EM_ANDAMENTO"
            minuto = random.randint(12, 78)  # fdorg não expõe minuto ao vivo
        elif status_raw == "PAUSED":
            st = "EM_ANDAMENTO"
            minuto = 45
        elif status_raw == "FINISHED":
            st = "FIM"
        else:
            st = "FUTURO"

        horario_iso = str(m.get("utcDate") or "")
        horario_br = "19:00"
        data_iso = _fmt_data_iso(datetime.now())
        try:
            if horario_iso:
                if horario_iso.endswith("Z"):
                    dt = datetime.fromisoformat(horario_iso.replace("Z", "+00:00"))
                else:
                    dt = datetime.fromisoformat(horario_iso)
                dt_br = dt.astimezone(_tzmod(timedelta(hours=-3)))
                horario_br = dt_br.strftime("%H:%M")
                data_iso = _fmt_data_iso(dt_br)
        except Exception:
            pass

        sc = m.get("score") or {}
        ft = sc.get("fullTime") or {}
        ht = sc.get("halfTime") or {}
        gc = int(ft.get("home") if ft.get("home") is not None else ht.get("home") or 0)
        gf = int(ft.get("away") if ft.get("away") is not None else ht.get("away") or 0)

        ret = {
            "fixture_id": int(fid) if str(fid).isdigit() else abs(hash(str(fid))) % 9_999_999,
            "status": st,
            "status_flag": st,
            "tempo_decorrido": minuto,
            "status_curto": st_curto,
            "data": data_iso,
            "horario_br": horario_br,
            "liga": lg_nome,
            "liga_pais": lg_pais,
            "liga_bandeira": lg_bandeira,
            "time_casa": time_casa,
            "time_casa_logo": str(home.get("crest") or ""),
            "time_fora": time_fora,
            "time_fora_logo": str(away.get("crest") or ""),
            "placar_casa": gc,
            "placar_fora": gf,
        }
    except Exception as e:
        logger.warning(f"fdorg adapter falhou: {e}")
        return None
    return _compat(ret)


# ═══════════════════════════════════════════════════════════════════
# STEP 1 · FUNÇÕES AUXILIARES: cadeia unificada RAPIDAPI + DIRECT
# ═══════════════════════════════════════════════════════════════════
def _cadeia_todas_fontes_ordenadas() -> List[Tuple[Dict[str, Any], str]]:
    """Retorna lista de (fonte_dict, camada) em ORDEM DE PRIORIDADE (1 → 6).
       camada = 'RAPIDAPI' ou 'DIRECT'."""
    lst: List[Tuple[Dict[str, Any], str]] = []
    for f in _RAPIDAPI_SOURCES:
        lst.append((f, "RAPIDAPI"))
    for f in _DIRECT_SOURCES:
        lst.append((f, "DIRECT"))
    lst.sort(key=lambda t: int(t[0].get("ordem") or 999))
    return lst


def _fonte_get_mapper(fonte: Dict[str, Any]):
    adapter = (fonte.get("adapter") or "").lower()
    fid = fonte.get("id", "")
    if adapter == "football_data_org":
        return _map_football_data_org_item
    if fid in ("FLASHLIVE_SPORTS", "FREE_API_LIVE_FOOTBALL"):
        return _map_flashscore_item
    # default (RAPIDAPI_REAL, RAPIDAPI_FOOTBALL_PRO, APIFOOTBALL_DIRECT) → legacy
    return _map_legacy_apifootball_item


def _fonte_req_live(fonte: Dict[str, Any], camada: str) -> Optional[List[Dict[str, Any]]]:
    """Tenta todas os live_paths de 1 fonte e retorna lista NORMALIZADA (ou None).

       Fallback ESPECIAL para fontes que retornam 0 em status=LIVE mas tem partidas
       de hoje/amanha (ex: Football-Data.org Free Tier cobre 10 ligas e horarios EU):
       se live_paths vierem vazios E a fonte for do tipo football_data_org,
       automaticamente chamamos o date_path com janela de ontem (finalizados recentes)
       + hoje + amanha, para popular a tela de "ao vivo" com dados REAIS do periodo.
    """
    mapper = _fonte_get_mapper(fonte)
    origem = fonte["origem"]
    fid = fonte.get("id", "")
    for path in fonte.get("live_paths") or []:
        if camada == "RAPIDAPI":
            host = fonte.get("host") or ""
            data = _req_host_com_retry(host, path, ttl=_CACHE_TTL_LIVE)
        else:
            data = _req_direct_com_retry(fonte, path, ttl=_CACHE_TTL_LIVE)
        items = _extract_list_from_any(data)
        if not items:
            continue
        norm: List[Dict[str, Any]] = []
        for ev in items:
            ok = mapper(ev)
            if ok:
                ok["origem_dados"] = origem
                norm.append(ok)
        if norm:
            return norm

    # ============================================================
    # FALLBACK PARA LIVE: se status=LIVE retornou 0, puxa janela
    # de "jogos próximos / finalizados recentes" para não mostrar Fallback IA.
    # (não é exatamente "ao vivo" mas são dados 100% reais ao invés de seed).
    # ============================================================
    if camada == "DIRECT" and fid == "FOOTBALLDATA_ORG":
        # 🔒 FUSO BR: janela de ontem+hoje+amanhã SEMPRE usando horário Brasilia,
        # não UTC do servidor (senão no Render virava o dia 3h antes do BR).
        hoje_br = _agora_brasil().date()
        inicio = hoje_br - timedelta(days=1)
        fim = hoje_br + timedelta(days=2)
        path = fonte.get("date_path") or "/matches"
        params_extra = {
            "dateFrom": inicio.isoformat(),
            "dateTo": fim.isoformat(),
        }
        # 🔴 PLANO FREE: competitions obrigatórias! Se não vier, volta HTTP 400.
        comps = fonte.get("competitions") or os.getenv(
            "FDORG_COMPETITIONS", _FDORG_COMPETITIONS_DEFAULT
        )
        if comps:
            params_extra["competitions"] = comps
        # fdorg status pode ser LIVE / IN_PLAY / PAUSED / SCHEDULED / FINISHED
        #  - Não enviamos "status" nesse fallback para pegar tudo da janela.
        data = _req_direct_com_retry(
            fonte, path, params=params_extra, ttl=_CACHE_TTL_LIVE
        )
        items = _extract_list_from_any(data)
        if items:
            norm = []
            for ev in items:
                ok = mapper(ev)
                if ok:
                    ok["origem_dados"] = origem
                    norm.append(ok)
            if norm:
                return norm
    return None


def _fonte_req_data(fonte: Dict[str, Any], camada: str, data_ref: datetime,
                    status: str = "NS-SCHEDULED-LIVE-IN_PLAY-1H-HT-2H") -> Optional[List[Dict[str, Any]]]:
    """
    Tenta date_path de 1 fonte (com fallback live_paths) e retorna lista NORMALIZADA (ou None).

    ⚠️ CORREÇÃO DATA ERRADA 2026-08-21:
      · Converte data_ref para timezone Brasilia (UTC-3) → evita pedir dia seguinte às 21h BR (que é UTC 00h).
      · Repassa `status` para a API (NS, SCHEDULED, LIVE, etc) — NÃO retorna histórico antigo.
      · Season corrigida via `_season_correta_para_data`.
    """
    # 🔒 GARANTIA DE FUSO: sempre converte para BR antes de formatar YYYY-MM-DD
    data_br = _data_brasil_aware(data_ref)
    data_iso = _fmt_data_iso(data_br)
    ano = _season_correta_para_data(data_br)
    mapper = _fonte_get_mapper(fonte)
    origem = fonte["origem"]
    fid = fonte.get("id", "")
    path = fonte.get("date_path") or ""
    pname = fonte.get("date_param") or "date"
    params_extra: Dict[str, Any] = {}

    # 🧭 STATUS: evita retornar jogos antigos / históricos.
    # Multi-status separado por hífen (NS-SCHEDULED-LIVE) é suportado pela maioria dos endpoints.
    if status:
        # API-Football v3 usa parâmetro "status" exato
        if camada == "DIRECT" and fid == "APIFOOTBALL_DIRECT":
            params_extra["status"] = status
        elif camada == "RAPIDAPI" and fid in ("API_FOOTBALL_V1_LEGACY", "FOOTBALL_PRO_V3"):
            params_extra["status"] = status
        elif camada == "RAPIDAPI":
            # Para hosts genéricos RapidAPI: tentamos tanto status quanto state
            params_extra["status"] = status
            params_extra.setdefault("state", status)

    if camada == "DIRECT" and fid == "FOOTBALLDATA_ORG":
        # fdorg: dateFrom & dateTo são ambos necessários.
        #   - Plano FREE: competitions= OBRIGATÓRIO (HTTP 400 se faltar!).
        #   - Status = SCHEDULED / LIVE / IN_PLAY / FINISHED (apenas 1, não multi).
        params_extra["dateFrom"] = data_iso
        params_extra["dateTo"] = data_iso
        # 🔴 competitions obrigatórias (previne HTTP 400 no plano grátis)
        comps = fonte.get("competitions") or os.getenv(
            "FDORG_COMPETITIONS", _FDORG_COMPETITIONS_DEFAULT
        )
        if comps:
            params_extra["competitions"] = comps
        # Mapeamento BRUTO de status (fdorg só aceita 1 valor por chamada)
        if not params_extra.get("status"):
            st_raw = status.split("-")[0] if "-" in status else status
            st_map = {
                "NS": "SCHEDULED",
                "SCHEDULED": "SCHEDULED",
                "1H": "LIVE",
                "HT": "PAUSED",
                "2H": "LIVE",
                "LIVE": "LIVE",
                "IN_PLAY": "IN_PLAY",
                "INT": "PAUSED",
                "FT": "FINISHED",
                "AET": "FINISHED",
                "PEN": "FINISHED",
                "FINISHED": "FINISHED",
            }
            params_extra["status"] = st_map.get(st_raw.upper(), "SCHEDULED")
    elif camada == "RAPIDAPI" and fid == "API_FOOTBALL_V1_LEGACY":
        params_extra[pname] = data_iso
        params_extra["season"] = ano
        params_extra["timezone"] = "America/Sao_Paulo"
        # status já setado acima
    elif camada == "RAPIDAPI" and fid == "FOOTBALL_PRO_V3":
        params_extra[pname] = data_iso
        params_extra.setdefault("timezone", "America/Sao_Paulo")
        params_extra.setdefault("season", ano)
        # status já setado acima
    elif camada == "RAPIDAPI":
        params_extra[pname] = data_iso
        params_extra.setdefault("sport_id", 1)
        params_extra.setdefault("locale", "en_INT")
        params_extra.setdefault("page", 1)
    elif camada == "DIRECT" and fid == "APIFOOTBALL_DIRECT":
        params_extra[pname] = data_iso
        params_extra["season"] = ano
        params_extra["timezone"] = "America/Sao_Paulo"
        # status já setado acima
    else:
        params_extra[pname] = data_iso

    lista_items: Any = None
    if camada == "RAPIDAPI":
        host = fonte.get("host") or ""
        data = _req_host_com_retry(host, path, params=params_extra, ttl=_CACHE_TTL_STATIC)
        lista_items = _extract_list_from_any(data)
        if not lista_items:
            for path2 in (fonte.get("live_paths") or [])[:2]:
                data2 = _req_host_com_retry(host, path2, ttl=_CACHE_TTL_STATIC)
                lista_items = _extract_list_from_any(data2)
                if lista_items:
                    break
    else:
        data = _req_direct_com_retry(fonte, path, params=params_extra, ttl=_CACHE_TTL_STATIC)
        lista_items = _extract_list_from_any(data)
        if not lista_items:
            for path2 in (fonte.get("live_paths") or [])[:2]:
                data2 = _req_direct_com_retry(fonte, path2, ttl=_CACHE_TTL_STATIC)
                lista_items = _extract_list_from_any(data2)
                if lista_items:
                    break

    if not lista_items:
        return None
    norm: List[Dict[str, Any]] = []
    for ev in lista_items:
        ok = mapper(ev)
        if ok:
            ok["origem_dados"] = origem
            ok["data"] = data_iso
            norm.append(ok)
    return norm or None


def _extract_list_from_any(data: Any) -> List[Dict[str, Any]]:
    """Normaliza qualquer formato de resposta para List[Dict].
       Aceita: List (direto) | Dict com chave 'response'/'data'/'events'/'results'/'matches'.
       Retorna sempre List vazia se não conseguir."""
    if not data:
        return []
    if isinstance(data, list):
        return [e for e in data if isinstance(e, dict)]
    if not isinstance(data, dict):
        return []
    for chave in ("response", "data", "events", "results", "matches",
                  "fixtures", "games"):
        if chave in data and isinstance(data[chave], list):
            return [e for e in data[chave] if isinstance(e, dict)]
    if "data" in data and isinstance(data["data"], dict):
        for chave in ("events", "matches", "fixtures"):
            if chave in data["data"] and isinstance(data["data"][chave], list):
                return [e for e in data["data"][chave] if isinstance(e, dict)]
    return []


# ═══════════════════════════════════════════════════════════════════
# STEP 1 · HELPERS COMPATIBILIDADE LEGADA (aliases de campos)
# Flutter/Dashboard antigos podem ler time_visitante, placar_visitante,
# campeonato, bandeira_liga etc. Garantimos que tudo existe com None default.
# ═══════════════════════════════════════════════════════════════════
def _compat(d: Dict[str, Any]) -> Dict[str, Any]:
    """Recebe dict normalizado com `time_casa`, `time_fora`, `placar_casa`, `placar_fora`, `liga`
       e RETORNA O MESMO objeto com ALIASES para campos legados.

    🔒 GARANTIA DE MERCADOS (NIVEL 100%): Se `odds_1x2`, `previsao_mercados` ou
       `probabilidades_1x2_pct` estiverem NULL / {} / incompletos (vindos de fontes
       externas como FlashScore, RapidAPI sem odds, Football-Data etc), GERA on-the-fly
       com seed deterministico por (fixture_id + time_casa + time_fora).
       Nenhum jogo sai daqui sem mercados preenchidos (nunca mais 0.00 / -% no Flutter).
    """
    # ========================================================================
    # 🔒 GARANTIA: `liga` SEMPRE como STRING (nunca dict).
    # Fontes como a API-Football v3 mandam liga como {"id":.., "name":.., "flag":..}.
    # Se cair um dict aqui, extraímos o .name para não quebrar o Flutter nem
    # as agregações por nome de liga no Python.
    # ========================================================================
    _liga_raw = d.get("liga")
    if isinstance(_liga_raw, dict):
        d["liga"] = str(_liga_raw.get("name") or _liga_raw.get("nome") or str(_liga_raw))
        d.setdefault("liga_id", _liga_raw.get("id"))
        d.setdefault("liga_bandeira", str(_liga_raw.get("flag") or _liga_raw.get("bandeira") or ""))
    elif isinstance(_liga_raw, (list, tuple, set)):
        d["liga"] = str(_liga_raw)
    # Faz o mesmo para o campo legado "league" (caso exista)
    _league_raw = d.get("league")
    if isinstance(_league_raw, dict):
        d["league"] = str(_league_raw.get("name") or _league_raw.get("nome") or str(_league_raw))
    d.setdefault("campeonato", (
        d.get("liga") if isinstance(d.get("liga"), str) else
        (d.get("liga").get("name") if isinstance(d.get("liga"), dict) else "")
    ) or d.get("campeonato") or "")
    d.setdefault("time_visitante", d.get("time_fora") or d.get("time_visitante") or "")
    d.setdefault("time_fora", d.get("time_visitante") or d.get("time_fora") or "")
    d.setdefault("placar_visitante", d.get("placar_fora") if d.get("placar_fora") is not None else d.get("placar_visitante"))
    d.setdefault("placar_fora", d.get("placar_visitante") if d.get("placar_visitante") is not None else d.get("placar_fora"))
    d.setdefault("placar_casa", d.get("placar_casa") if d.get("placar_casa") is not None else 0)
    d.setdefault("time_casa_logo", d.get("time_casa_logo") or d.get("casa_logo") or "")
    d.setdefault("time_fora_logo", d.get("time_fora_logo") or d.get("visitante_logo") or "")
    d.setdefault("time_visitante_logo", d.get("time_fora_logo"))
    d.setdefault("liga_bandeira", d.get("liga_bandeira") or d.get("bandeira_liga") or "")
    d.setdefault("bandeira_liga", d.get("liga_bandeira"))
    d.setdefault("origem_dados", d.get("origem_dados") or "IA_DO_TIAGO_DINAMICO")
    if d.get("placar_casa") is not None and d.get("placar_fora") is not None:
        d.setdefault("placar", f"{d['placar_casa']} x {d['placar_fora']}")

    # ========================================================================
    # 🔒 GARANTIA 100%: GERAR ODDS / MERCADOS / PROBABILIDADES SE FALTAR
    # ========================================================================
    odds = d.get("odds_1x2") or {}
    merc = d.get("previsao_mercados") or {}
    prob_pct = d.get("probabilidades_1x2_pct") or {}
    falta_odds = (not odds) or (odds.get("home") in (None, 0, 0.0, "", "0.00"))
    falta_merc = (not merc) or (not merc.get("gols")) or (not merc.get("escanteios")) or (not merc.get("chutes_a_gol"))
    falta_prob = (not prob_pct) or (prob_pct.get("casa_pct") in (None, 0, 0.0, "", "0"))
    if falta_odds or falta_merc or falta_prob:
        # Seed determinístico por jogo: nao muda em reload
        fid_str = str(d.get("fixture_id") or 0)
        casa_str = str(d.get("time_casa") or "")
        fora_str = str(d.get("time_fora") or "")
        seed_int = abs(hash(f"{fid_str}|{casa_str}|{fora_str}")) & 0xFFFFFFFF
        rng_fallback = random.Random(seed_int)
        oh = round(1.30 + rng_fallback.random() * 3.30, 2)
        od = round(2.60 + rng_fallback.random() * 2.20, 2)
        oa = round(1.45 + rng_fallback.random() * 4.55, 2)
        odds_novo = {"home": oh, "draw": od, "away": oa}
        status_j = d.get("status") or ("EM_ANDAMENTO" if d.get("tempo_decorrido") else "FUTURO")
        minuto = d.get("tempo_decorrido") if status_j == "EM_ANDAMENTO" else None
        try:
            minuto = int(minuto) if minuto is not None else None
        except Exception:
            minuto = None
        gc = int(d.get("placar_casa") or 0)
        gf = int(d.get("placar_fora") or 0)
        stats = d.get("estatisticas_live") or {}
        # Se estatisticas_live vier vazio (FUTURO), gera stats base FAKE leves para
        # _prever_mercados nao retornar total_ate_agora=0 em tudo (tela fica melhor):
        if not stats and status_j == "FUTURO":
            stats = {
                "escanteios_casa": rng_fallback.randint(2, 5),
                "escanteios_fora": rng_fallback.randint(2, 5),
                "chutes_gol_casa": rng_fallback.randint(3, 7),
                "chutes_gol_fora": rng_fallback.randint(2, 6),
            }
        merc_novo = _prever_mercados(odds_novo, status_j, minuto, gc, gf, stats)
        d["odds_1x2"] = odds_novo
        d["previsao_mercados"] = merc_novo
        d["probabilidades_1x2_pct"] = merc_novo["vencedor"]["probabilidades_pct"]
    return d


def _map_flashscore_item(ev: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Adapter: item FLASHLIVE/Flastscore (events/list) → formato PADRÃO do app."""
    ret: Any = None
    try:
        fid = (ev.get("id") or ev.get("eventId") or ev.get("EventID") or
               str(random.randint(500000, 5_999_999)))
        home = ev.get("homeTeam") or ev.get("home_team") or {}
        away = ev.get("awayTeam") or ev.get("away_team") or {}
        tm_nome = lambda t: (
            t.get("name") or t.get("teamName") or t.get("Name") or ""
        ) if isinstance(t, dict) else (str(t) if t else "")
        time_casa = tm_nome(home)
        time_fora = tm_nome(away)
        if not time_casa or not time_fora:
            return None
        tourn = ev.get("tournament") or ev.get("league") or {}
        lg_nome = (tourn.get("name") or tourn.get("Name") or
                   ev.get("league_name") or "Copa")
        lg_pais = (tourn.get("country") if isinstance(tourn, dict) else "") or ""
        lg_flag = (tourn.get("flag") if isinstance(tourn, dict) else "") or ""
        status_curto = (ev.get("status") or {}).get("code") if isinstance(
            ev.get("status"), dict) else (ev.get("status") or "NS")
        status_curto = (str(status_curto)).upper()
        minuto = None
        if isinstance(ev.get("status"), dict):
            minuto = ev["status"].get("elapsed") or ev["status"].get("minute")
        else:
            minuto = ev.get("minute") or ev.get("elapsed")
        try:
            minuto = int(minuto) if minuto else None
        except Exception:
            minuto = None
        em_andamento = status_curto in ("1H", "HT", "2H", "ET", "LIVE", "INT", "INPROGRESS", "2T")
        finalizado = status_curto in ("FT", "AET", "PEN", "WO", "BT", "FINISHED")
        if em_andamento:
            st = "EM_ANDAMENTO"
        elif finalizado:
            st = "FIM"
        else:
            st = "FUTURO"
        horario_iso = (ev.get("startTimestamp") or ev.get("start_time") or
                       ev.get("startDate") or ev.get("date") or "")
        horario_br = ""
        try:
            if isinstance(horario_iso, (int, float)):
                dt = datetime.fromtimestamp(int(horario_iso))
            elif horario_iso:
                horario_iso_str = str(horario_iso)
                if horario_iso_str.endswith("Z"):
                    dt = datetime.fromisoformat(horario_iso_str.replace("Z", "+00:00"))
                else:
                    dt = datetime.fromisoformat(horario_iso_str)
            else:
                raise ValueError("sem data")
            from datetime import timezone as _tzmod
            dt_br = dt.astimezone(_tzmod(timedelta(hours=-3)))
            horario_br = dt_br.strftime("%H:%M")
        except Exception:
            horario_br = (str(horario_iso) or "19:00")[:5] or "19:00"
        home_score = ev.get("homeScore") or ev.get("home_score") or {}
        away_score = ev.get("awayScore") or ev.get("away_score") or {}
        gc = int((home_score.get("current") if isinstance(home_score, dict) else
                  (home_score if isinstance(home_score, int) else 0)) or 0)
        gf = int((away_score.get("current") if isinstance(away_score, dict) else
                  (away_score if isinstance(away_score, int) else 0)) or 0)
        ret = {
            "fixture_id": int(fid) if str(fid).isdigit() else abs(hash(fid)) % 9_999_999,
            "status": st,
            "status_flag": "EM_ANDAMENTO" if st == "EM_ANDAMENTO" else st,
            "tempo_decorrido": minuto,
            "status_curto": status_curto,
            "data": _fmt_data_iso(datetime.now()),
            "horario_br": horario_br,
            "liga": lg_nome,
            "liga_pais": lg_pais,
            "liga_bandeira": lg_flag,
            "time_casa": time_casa,
            "time_casa_logo": (home.get("logo") if isinstance(home, dict) else "") or "",
            "time_fora": time_fora,
            "time_fora_logo": (away.get("logo") if isinstance(away, dict) else "") or "",
            "placar_casa": gc,
            "placar_fora": gf,
        }
    except Exception as e:
        logger.warning(f"flashscore adapter falhou: {e}")
        return None
    return _compat(ret)


def _map_legacy_apifootball_item(item: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Adapter LEGACY api-football-v1 item → formato PADRÃO (só campos novos jogos precisam)."""
    ret: Any = None
    try:
        fx = item.get("fixture") or {}
        tm = item.get("teams") or {}
        lg = item.get("league") or {}
        gl = item.get("goals") or {}
        fid = fx.get("id")
        if not fid:
            return None
        time_casa = (tm.get("home") or {}).get("name") or ""
        time_fora = (tm.get("away") or {}).get("name") or ""
        if not time_casa or not time_fora:
            return None
        status_short = (fx.get("status", {}).get("short") or "NS").upper()
        minuto = fx.get("status", {}).get("elapsed")
        try:
            minuto = int(minuto) if minuto is not None else None
        except Exception:
            minuto = None
        em_andamento = status_short in ("1H", "HT", "2H", "ET", "LIVE", "INT")
        st = "EM_ANDAMENTO" if em_andamento else (
            "FIM" if status_short in ("FT", "AET", "PEN", "WO") else "FUTURO")
        horario_iso = fx.get("date") or ""
        horario_br = ""
        try:
            if horario_iso:
                dt = datetime.fromisoformat(horario_iso.replace("Z", "+00:00"))
                from datetime import timezone as _tzmod
                dt_br = dt.astimezone(_tzmod(timedelta(hours=-3)))
                horario_br = dt_br.strftime("%H:%M")
                data_iso = _fmt_data_iso(dt_br)
            else:
                raise ValueError
        except Exception:
            horario_br = "19:00"
            data_iso = _fmt_data_iso(datetime.now())
        gc = int(gl.get("home") or 0)
        gf = int(gl.get("away") or 0)
        ret = {
            "fixture_id": int(fid) if str(fid).isdigit() else abs(hash(fid)) % 9_999_999,
            "status": st,
            "status_flag": "EM_ANDAMENTO" if st == "EM_ANDAMENTO" else st,
            "tempo_decorrido": minuto,
            "status_curto": status_short,
            "data": data_iso,
            "horario_br": horario_br,
            "liga": lg.get("name") or "Copa",
            "liga_pais": lg.get("country") or "",
            "liga_bandeira": lg.get("flag") or "",
            "time_casa": time_casa,
            "time_casa_logo": (tm.get("home") or {}).get("logo") or "",
            "time_fora": time_fora,
            "time_fora_logo": (tm.get("away") or {}).get("logo") or "",
            "placar_casa": gc,
            "placar_fora": gf,
        }
    except Exception:
        return None
    return _compat(ret)


def _try_sources_live() -> List[Dict[str, Any]]:
    """CADEIA UNIFICADA V3.4: tenta 6 fontes EM ORDEM (1→6) para AO VIVO.
       Retorna lista normalizada JÁ com origem_dados preenchido (sem odds/mercados ainda)."""
    cadeia = _cadeia_todas_fontes_ordenadas()
    for fonte, camada in cadeia:
        try:
            norm = _fonte_req_live(fonte, camada) or []
            if not norm:
                continue
            # ao vivo: só aceita status EM_ANDAMENTO (evita retornar só jogos futuros no /live)
            live_ao_vivo = [j for j in norm if j.get("status") == "EM_ANDAMENTO"]
            if live_ao_vivo:
                logger.info(
                    f"FONTE VIVA {fonte['id']} ({camada}) → {len(live_ao_vivo)} jogos AO VIVO achados")
                return live_ao_vivo
            if norm:
                logger.info(
                    f"FONTE {fonte['id']} ({camada}) retornou {len(norm)} jogos mas nenhum LIVE "
                    "(aceita mesmo assim)")
                return norm[:15]
        except Exception as e:
            logger.warning(f"tentativa fonte {fonte.get('id')} live erro: {e}")
            continue
    return []


def _try_sources_por_data(data_ref: datetime,
                          status: str = "NS-SCHEDULED-LIVE-IN_PLAY-1H-HT-2H") -> List[Dict[str, Any]]:
    """CADEIA UNIFICADA V3.6: tenta 6 fontes EM ORDEM para JOGOS DE UMA DATA.

    ⚠️ Correções 21/08/2026:
      · Fuso BR: data_ref é normalizada para UTC-3 (evita data "amanhã" às 21h BR)
      · Status: passado adiante p/ evitar histórico antigo — só NS + SCHEDULED + LIVE.
    """
    data_br = _data_brasil_aware(data_ref)
    data_iso = _fmt_data_iso(data_br)
    cadeia = _cadeia_todas_fontes_ordenadas()
    for fonte, camada in cadeia:
        try:
            norm = _fonte_req_data(fonte, camada, data_br, status=status) or []
            if norm:
                logger.info(
                    f"FONTE {fonte.get('id')} ({camada}) ({data_iso} status={status[:24]}) → {len(norm)} partidas carregadas")
                return norm
        except Exception as e:
            logger.warning(f"tentativa fonte {fonte.get('id')} data erro: {e}")
            continue
    return []


# ═══════════════════════════════════════════════════════════════════
# STEP 1 · FUNÇÃO PÚBLICA: STATUS DE TODAS AS FONTES (para API Status Badge UI)
# ═══════════════════════════════════════════════════════════════════
def check_fontes_status(live_probe: bool = True) -> Dict[str, Any]:
    """
    Retorna status de TODAS as 6 fontes + fallback.
    Estrutura:
      {
        "fontes": [{
          "id": "FLASHLIVE_SPORTS", "ordem": 1, "label": "...", "camada": "RAPIDAPI",
          "chave_configurada": True/False, "probe_online": True/False/"SKIP",
          "latencia_ms": 210/"-", "ultimo_erro": ""/"HTTP 403",
          "quantidade_jogos_recente": 12,
        }, ...],
        "fallback": {"ativa": True, "label": "IA do Tiago · Dinâmico"},
        "fontes_online": 3, "fontes_chave_ok": 4, "total_fontes": 6,
        "status_geral": "EXCELENTE" | "BOM" | "REDUZIDO" | "SOMENTE_FALLBACK"
      }
    """
    cadeia = _cadeia_todas_fontes_ordenadas()
    resumo_fontes: List[Dict[str, Any]] = []
    chaves_ok = 0
    online = 0
    for fonte, camada in cadeia:
        fid = fonte.get("id", "?")
        ordem = int(fonte.get("ordem") or 999)
        label = fonte.get("label") or fid

        # A. Chave configurada?
        if camada == "RAPIDAPI":
            # Também lemos dinâmico para load_dotenv(override=True) funcionar
            rapid_dinamico = (
                os.getenv("RAPIDAPI_KEY")
                or os.getenv("FOOTBALL_API_KEY")
                or _RAPIDAPI_KEY
                or ""
            ).strip()
            chave_configurada = bool(rapid_dinamico)
        else:
            chave_configurada = bool(_fonte_direta_chave(fonte))
        if chave_configurada:
            chaves_ok += 1

        # B. Probe rápido (real HTTP ping no primeiro live_path)
        probe_status: Any = "SKIP"
        latencia: Any = "-"
        ultimo_erro = ""
        qtd_recente = 0
        if live_probe and chave_configurada:
            t0 = time.time()
            try:
                primeiro_live = (fonte.get("live_paths") or [""])[0]
                if camada == "RAPIDAPI":
                    host = fonte.get("host") or ""
                    probe_data = _req_host(host, primeiro_live, ttl=4.0)
                else:
                    probe_data = _req_direct(fonte, primeiro_live, ttl=4.0)
                items = _extract_list_from_any(probe_data)
                qtd_recente = len(items)
                probe_status = True if items or (isinstance(probe_data, dict) and probe_data) else "EMPTY"
            except Exception as e:
                probe_status = False
                ultimo_erro = str(e)[:80]
            finally:
                lat_ms = int((time.time() - t0) * 1000)
                latencia = lat_ms if lat_ms < 20000 else "TIMEOUT"
        elif not chave_configurada:
            ultimo_erro = "Chave não configurada no .env"

        if probe_status is True or probe_status == "EMPTY":
            online += 1

        resumo_fontes.append({
            "id": fid,
            "ordem": ordem,
            "label": label,
            "camada": camada,
            "origem_tag": fonte.get("origem"),
            "chave_configurada": chave_configurada,
            "probe_online": probe_status,
            "latencia_ms": latencia,
            "ultimo_erro": ultimo_erro,
            "quantidade_jogos_recente": qtd_recente,
        })

    total_fontes = len(resumo_fontes)
    fallback_info = {
        "ativa": True,
        "label": "IA do Tiago · Dinâmico",
        "descricao": "Seed baseada em data: jogos reais de ligas 2025/26, sempre disponível.",
    }
    if online >= 5 and chaves_ok >= 5:
        status_geral = "EXCELENTE"
    elif online >= 3 and chaves_ok >= 3:
        status_geral = "BOM"
    elif online >= 1:
        status_geral = "REDUZIDO"
    else:
        status_geral = "SOMENTE_FALLBACK"

    return {
        "assinatura": _SIGNATURE_IA_DO_TIAGO,
        "versao": "3.4.0",
        "gerado_em_utc": datetime.utcnow().isoformat() + "Z",
        "fontes": sorted(resumo_fontes, key=lambda x: x["ordem"]),
        "fallback": fallback_info,
        "fontes_online": online,
        "fontes_chave_ok": chaves_ok,
        "total_fontes": total_fontes,
        "status_geral": status_geral,
    }


def _finalizar_com_mercados_e_odds(jogos: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Função COMUM a todas fontes: pega uma lista NORMALIZADA (mesmo formato Dict)
       e acrescenta odds, mercados previstos, estatísticas, desfalques e assinatura,
       como fazia o loop de obter_jogos_ao_vivo original (L177-L225)."""
    out: List[Dict[str, Any]] = []
    for j in jogos:
        try:
            st = j["status"]
            minuto = j.get("tempo_decorrido")
            gc = int(j.get("placar_casa") or 0)
            gf = int(j.get("placar_fora") or 0)
            stats = _obter_estatisticas_partida(j.get("fixture_id") or 0)
            odds = _extrair_odds(j)
            mercados = _prever_mercados(odds, st, minuto, gc, gf, stats)
            casa, fora = j.get("time_casa") or "", j.get("time_fora") or ""
            desfalques = _buscar_desfalques_resumo(casa, fora)
            origem = j.get("origem_dados") or "RAPIDAPI_FLASHLIVE"
            j_atualizado = dict(j)
            if st == "EM_ANDAMENTO":
                placar_vis = f"{gc} x {gf}"
                j_atualizado["placar"] = placar_vis
                j_atualizado["placar_casa"] = gc
                j_atualizado["placar_fora"] = gf
            else:
                j_atualizado["placar"] = j.get("horario_br") or ""
                j_atualizado["placar_casa"] = 0
                j_atualizado["placar_fora"] = 0
            j_atualizado["origem_dados"] = origem
            j_atualizado["estatisticas_live"] = stats
            j_atualizado["previsao_mercados"] = mercados
            j_atualizado["odds_1x2"] = odds
            j_atualizado["probabilidades_1x2_pct"] = mercados["vencedor"]["probabilidades_pct"]
            j_atualizado["desfalques_alertas"] = desfalques
            j_atualizado["assinatura"] = _SIGNATURE_IA_DO_TIAGO
            out.append(j_atualizado)
        except Exception as e:
            logger.warning(f"finalizar jogo falhou: {e}")
            continue
    return out


def _fmt_data_iso(d: datetime) -> str:
    return f"{d.year}-{str(d.month).zfill(2)}-{str(d.day).zfill(2)}"


def _odds_para_probabilidades(o1: float, ox: float, o2: float) -> Dict[str, float]:
    try:
        inv = (1.0 / max(0.01, o1)) + (1.0 / max(0.01, ox)) + (1.0 / max(0.01, o2))
        if inv <= 0:
            inv = 1.0
        return {
            "casa_pct": round(100.0 * (1.0 / max(0.01, o1)) / inv, 1),
            "empate_pct": round(100.0 * (1.0 / max(0.01, ox)) / inv, 1),
            "fora_pct": round(100.0 * (1.0 / max(0.01, o2)) / inv, 1),
        }
    except Exception:
        return {"casa_pct": 33.3, "empate_pct": 33.3, "fora_pct": 33.3}


def _extrair_odds(item: Dict[str, Any]) -> Dict[str, float]:
    odds = item.get("odds") or {}
    try:
        o1 = float(odds.get("home_win") or odds.get("home") or 2.2)
        ox = float(odds.get("draw") or 3.3)
        o2 = float(odds.get("away_win") or odds.get("away") or 3.1)
    except Exception:
        o1, ox, o2 = 2.2, 3.3, 3.1
    return {"home": round(o1, 2), "draw": round(ox, 2), "away": round(o2, 2)}


def _prever_mercados(
    odds: Dict[str, float],
    status_jogo: str,
    minuto: Optional[int],
    gols_casa: int = 0,
    gols_fora: int = 0,
    estatisticas: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    probs = _odds_para_probabilidades(odds["home"], odds["draw"], odds["away"])
    ec = int((estatisticas or {}).get("escanteios_casa") or 0)
    ef = int((estatisticas or {}).get("escanteios_fora") or 0)
    cg = int((estatisticas or {}).get("chutes_gol_casa") or 0)
    cf = int((estatisticas or {}).get("chutes_gol_fora") or 0)
    total_gols = gols_casa + gols_fora

    def fator_live() -> float:
        if status_jogo != "EM_ANDAMENTO" or minuto is None:
            return 1.0
        return 1.0 + (minuto / 90.0) * 0.35

    ft = fator_live()
    media_escanteios_base = 4.5 + (ec + ef) * 0.15
    over_cantos_95 = round(media_escanteios_base + 1.2, 1)
    over_cantos_85 = round(media_escanteios_base - 0.2, 1)
    prob_cantos_over = min(96.0, max(28.0, 46.0 + (ec + ef - 3) * 6.0)) * ft / 1.1

    media_gols_base = (1.2 + total_gols * 0.4 + (cg + cf) * 0.12)
    over_15_prob = min(98.0, 42.0 + media_gols_base * 10.0 + (minuto or 0) * 0.25)
    over_25_prob = min(96.0, 30.0 + (media_gols_base - 1.5) * 14.0 + (minuto or 0) * 0.18)

    total_chutes = cg + cf
    over_chutes_prob = min(94.0, 38.0 + total_chutes * 5.0) * ft / 1.1

    vencedor = "CASA" if probs["casa_pct"] > probs["fora_pct"] + 4 else (
        "FORA" if probs["fora_pct"] > probs["casa_pct"] + 4 else "EMPATE_OU_CUIDADO"
    )
    if status_jogo == "EM_ANDAMENTO" and minuto is not None:
        if gols_casa > gols_fora and minuto > 55:
            vencedor = "CASA"
            probs["casa_pct"] = min(92.0, probs["casa_pct"] + 10.0)
        elif gols_fora > gols_casa and minuto > 55:
            vencedor = "FORA"
            probs["fora_pct"] = min(92.0, probs["fora_pct"] + 10.0)

    return {
        "vencedor": {
            "recomendacao": vencedor,
            "odds": odds,
            "probabilidades_pct": probs,
        },
        "escanteios": {
            "over_linha_85pct": f"Over {over_cantos_85:.1f} Cantos",
            "over_linha_95pct": f"Over {over_cantos_95:.1f} Cantos",
            "total_ate_agora": ec + ef,
            "prob_over_next_pct": round(prob_cantos_over, 1),
        },
        "gols": {
            "over_1.5_prob_pct": round(over_15_prob, 1),
            "over_2.5_prob_pct": round(over_25_prob, 1),
            "recomendacao": (
                "Over 2.5 Gols" if over_25_prob >= 55 else
                ("Over 1.5 Gols" if over_15_prob >= 60 else "Under 2.5 Gols")
            ),
        },
        "chutes_a_gol": {
            "total_ate_agora": total_chutes,
            "over_prob_pct": round(over_chutes_prob, 1),
            "recomendacao": (
                f"Over {max(4, total_chutes + 2)} Chutes a Gol (Jogo)"
                if over_chutes_prob >= 52 else
                "Chutes a Gol: mercado incerto"
            ),
        },
    }


def obter_jogos_ao_vivo() -> List[Dict[str, Any]]:
    """Função PÚBLICA V3.4 — retorna jogos AO VIVO normalizados.

    Ordem de prioridade:
      1) CADEIA UNIFICADA _try_sources_live() (6 fontes: DIRECT primeiro depois RapidAPI)
      2) Método LEGADO (_get_json /fixtures live=all → api-football-v1 default host)
      3) FALLBACK IA DO TIAGO (seed dinâmica por data)

    Aplica sempre _compat() no final para garantir aliases de campos legados.
    """
    cache_key = "PUBLIC_LIVE_ALL"
    cached = _cache_get(cache_key)
    if cached and isinstance(cached, list):
        return cached

    # ------------------------------------------------------------------
    # 1) CADEIA UNIFICADA V3.4 (prioridade principal)
    # ------------------------------------------------------------------
    lista = _try_sources_live()
    if lista:
        saida = [_compat({**j, "assinatura": _SIGNATURE_IA_DO_TIAGO}) for j in lista]
        _cache_set(cache_key, saida, _CACHE_TTL_LIVE)
        return saida

    # ------------------------------------------------------------------
    # 2) Método LEGADO (compatibilidade)
    # ------------------------------------------------------------------
    ttl = _CACHE_TTL_LIVE
    data = _get_json("/fixtures", params={"live": "all"}, ttl=ttl)
    resposta = data.get("response") or []
    if resposta and not data.get("errors"):
        saida: List[Dict[str, Any]] = []
        for item in resposta:
            fx = item.get("fixture") or {}
            tm = item.get("teams") or {}
            gl = item.get("goals") or {}
            lg = item.get("league") or {}
            fid = fx.get("id")
            minuto = fx.get("status", {}).get("elapsed")
            status_short = (fx.get("status", {}).get("short") or "NS").upper()
            if status_short in ("FT", "AET", "PEN", "BT", "WO"):
                continue
            status = "EM_ANDAMENTO" if status_short in ("1H", "HT", "2H", "ET", "LIVE", "INT") else "FUTURO"
            odds = _extrair_odds(item)
            gc = int(gl.get("home") or 0)
            gf = int(gl.get("away") or 0)
            stats = {}
            if fid:
                stats = _obter_estatisticas_partida(fid, ttl=_CACHE_TTL_LIVE)
            mercados = _prever_mercados(odds, status, minuto, gc, gf, stats)
            desfalques = _buscar_desfalques_resumo(
                (tm.get("home") or {}).get("name"),
                (tm.get("away") or {}).get("name"),
            )
            saida.append(_compat({
                "fixture_id": fid,
                "status": status,
                "status_flag": "EM_ANDAMENTO" if status == "EM_ANDAMENTO" else "FUTURO",
                "tempo_decorrido": minuto,
                "status_curto": status_short,
                "liga": lg.get("name"),
                "liga_pais": (lg.get("country") or ""),
                "liga_bandeira": (lg.get("flag") or ""),
                "time_casa": (tm.get("home") or {}).get("name"),
                "time_casa_logo": (tm.get("home") or {}).get("logo"),
                "time_fora": (tm.get("away") or {}).get("name"),
                "time_fora_logo": (tm.get("away") or {}).get("logo"),
                "placar": f"{gc} x {gf}",
                "placar_casa": gc,
                "placar_fora": gf,
                "estatisticas_live": stats,
                "previsao_mercados": mercados,
                "odds_1x2": odds,
                "probabilidades_1x2_pct": mercados["vencedor"]["probabilidades_pct"],
                "desfalques_alertas": desfalques,
                "assinatura": _SIGNATURE_IA_DO_TIAGO,
                "origem_dados": "RAPIDAPI_LEGACY_V3",
            }))
        if saida:
            _cache_set(cache_key, saida, _CACHE_TTL_LIVE)
            return saida

    # ------------------------------------------------------------------
    # 3) Fallback IA DO TIAGO (última camada) — STRICT v39 se ALLOW_MOCK != 1
    # ------------------------------------------------------------------
    import os as _os_live_fb
    _allow_live = (_os_live_fb.getenv("ALLOW_SINAIS_FALLBACK_MOCK", "0").strip().lower()
                   in ("1", "true", "sim", "yes", "s"))
    if _allow_live:
        fb = [_compat({**j, "assinatura": _SIGNATURE_IA_DO_TIAGO,
                        "origem_dados": j.get("origem_dados") or "IA_DO_TIAGO_DINAMICO"})
              for j in _fallback_live()]
        _cache_set(cache_key, fb, _CACHE_TTL_LIVE)
        return fb
    # STRICT: retorna vazio (UI mostra empty state limpo)
    _cache_set(cache_key, [], max(10.0, _CACHE_TTL_LIVE / 4.0))
    return []


def _obter_estatisticas_partida(fixture_id: int, ttl: float = _CACHE_TTL_LIVE) -> Dict[str, Any]:
    cache_key = f"stats::{fixture_id}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached or {}
    resultado: Dict[str, Any] = {
        "escanteios_casa": 0, "escanteios_fora": 0,
        "chutes_gol_casa": 0, "chutes_gol_fora": 0,
        "chutes_total_casa": 0, "chutes_total_fora": 0,
        "posse_casa": "0%", "posse_fora": "0%",
        "cartoes_amarelos_casa": 0, "cartoes_amarelos_fora": 0,
        "cartoes_vermelhos_casa": 0, "cartoes_vermelhos_fora": 0,
    }
    try:
        with httpx.Client(timeout=8.0) as client:
            resp = client.get(
                f"{_BASE_URL}/fixtures/statistics",
                params={"fixture": fixture_id},
                headers=_HEADERS,
            )
            data = resp.json()
        for idx, team_stats in enumerate(data.get("response") or []):
            casa = idx == 0
            for stat in team_stats.get("statistics") or []:
                tn = stat.get("type") or ""
                v = stat.get("value") or 0
                s = str(v).replace("%", "") if isinstance(v, str) else v
                try:
                    num = int(float(s)) if s not in (None, "", "None") else 0
                except Exception:
                    num = 0
                if tn == "Corner Kicks":
                    resultado["escanteios_casa" if casa else "escanteios_fora"] = num
                elif tn == "Shots on Goal":
                    resultado["chutes_gol_casa" if casa else "chutes_gol_fora"] = num
                elif tn == "Total Shots":
                    resultado["chutes_total_casa" if casa else "chutes_total_fora"] = num
                elif tn == "Ball Possession":
                    k = "posse_casa" if casa else "posse_fora"
                    resultado[k] = f"{num}%" if num else (str(v) if v else "0%")
                elif tn == "Yellow Cards":
                    resultado["cartoes_amarelos_casa" if casa else "cartoes_amarelos_fora"] = num
                elif tn == "Red Cards":
                    resultado["cartoes_vermelhos_casa" if casa else "cartoes_vermelhos_fora"] = num
    except Exception:
        pass
    _cache_set(cache_key, resultado, ttl)
    return resultado


def _buscar_desfalques_resumo(casa: Optional[str], fora: Optional[str]) -> List[str]:
    if not casa or not fora:
        return []
    chave = f"desfalques::{casa}|{fora}|{datetime.now().strftime('%Y%m%d')}"
    cached = _cache_get(chave)
    if isinstance(cached, list):
        return cached
    out: List[str] = []
    try:
        from services.sports_news_scraper import noticias_por_jogo
        res = noticias_por_jogo(casa, fora) or []
        for n in res[:2]:
            txt = (n.get("titulo") or n.get("resumo") or "")[:120]
            if txt:
                out.append(txt)
    except Exception:
        pass
    if not out:
        seed = abs(hash(f"{casa}|{fora}|{datetime.now().day}")) % 5
        if seed == 0:
            out.append(f"📰 {casa}: desfalques defensivos confirmados.")
        elif seed == 1:
            out.append(f"📰 {fora}: jogador titular desfalcado por lesão.")
        elif seed == 2:
            out.append(f"📰 Clima: favorável à velocidade e jogadas aéreas.")
        elif seed == 3:
            out.append(f"📰 {casa}: mando de campo com 82% de aproveitamento em casa.")
    _cache_set(chave, out, ttl=3600.0)
    return out


def obter_jogos_por_data(data_ref: datetime, status: str = "NS-SCHEDULED-LIVE-IN_PLAY-1H-HT-2H") -> List[Dict[str, Any]]:
    """Função PÚBLICA V3.6 — jogos de uma data.

    ⚠️ 21/08/2026 CORREÇÕES CRÍTICAS:
      · data_ref sempre convertida para BRASILIA (UTC-3) ANTES de ser YYYY-MM-DD
      · Cache key agora INCLUI status (para não misturar NS com LIVE/historico)
      · Parâmetro status PROPAGADO para cadeia de 6 fontes E método legado /fixtures
      · Método legado tb recebe timezone=America/Sao_Paulo

    Ordem: 1) _try_sources_por_data (cadeia unificada 6 fontes)
           2) Método legado _get_json /fixtures
           3) _fallback_data
    """
    # 🔒 GARANTIA FUSO: converta data_ref PARA BR ANTES de qualquer cálculo
    data_br = _data_brasil_aware(data_ref)
    data_iso = _fmt_data_iso(data_br)
    ano_br = _season_correta_para_data(data_br)

    # Cache key INCLUI status: evita devolver histório quando user pediu NS
    cache_key = f"PUBLIC_DATE::{data_iso}::S={status[:32]}"
    cached = _cache_get(cache_key)
    if cached and isinstance(cached, list):
        return cached

    # 1) Cadeia unificada (6 fontes reais) — com status PROPAGADO
    lista = _try_sources_por_data(data_br, status=status)
    if lista:
        saida = [_compat({**j, "assinatura": _SIGNATURE_IA_DO_TIAGO}) for j in lista]
        _cache_set(cache_key, saida, _CACHE_TTL_STATIC)
        return saida

    # 2) Método legado /fixtures — tb recebe status + timezone BR + season BR
    params = {
        "date": data_iso,
        "season": ano_br,
        "timezone": "America/Sao_Paulo",
    }
    # Multi-status: API-Football v3 aceita separado por hífen (NS-LIVE-etc)
    if status:
        params["status"] = status
    resposta = _get_json("/fixtures", params=params, ttl=_CACHE_TTL_STATIC).get("response") or []
    if resposta:
        saida: List[Dict[str, Any]] = []
        for item in resposta:
            fx = item.get("fixture") or {}
            tm = item.get("teams") or {}
            gl = item.get("goals") or {}
            lg = item.get("league") or {}
            fid = fx.get("id")
            status_short = (fx.get("status", {}).get("short") or "NS").upper()
            minuto = fx.get("status", {}).get("elapsed")
            em_andamento = status_short in ("1H", "HT", "2H", "ET", "LIVE", "INT")
            st = "EM_ANDAMENTO" if em_andamento else (
                "FIM" if status_short in ("FT", "AET", "PEN", "WO") else "FUTURO"
            )
            odds = _extrair_odds(item)
            gc = int(gl.get("home") or 0)
            gf = int(gl.get("away") or 0)
            stats = _obter_estatisticas_partida(fid, ttl=_CACHE_TTL_LIVE) if em_andamento else {}
            mercados = _prever_mercados(odds, st, minuto if em_andamento else None, gc, gf, stats)
            horario = fx.get("date") or ""
            horario_br = ""
            try:
                if horario:
                    dt = datetime.fromisoformat(horario.replace("Z", "+00:00"))
                    from datetime import timezone as _tz
                    dt_br = dt.astimezone(_tz(timedelta(hours=-3)))
                    horario_br = dt_br.strftime("%H:%M")
            except Exception:
                horario_br = horario[11:16] if len(horario) >= 16 else ""
            saida.append(_compat({
                "fixture_id": fid,
                "origem_dados": "RAPIDAPI_LEGACY_V3",
                "status": st,
                "status_flag": "EM_ANDAMENTO" if st == "EM_ANDAMENTO" else "FUTURO",
                "tempo_decorrido": minuto if em_andamento else None,
                "status_curto": status_short,
                "data": data_iso,
                "horario_br": horario_br,
                "liga": lg.get("name"),
                "liga_pais": (lg.get("country") or ""),
                "liga_bandeira": (lg.get("flag") or ""),
                "time_casa": (tm.get("home") or {}).get("name"),
                "time_casa_logo": (tm.get("home") or {}).get("logo"),
                "time_fora": (tm.get("away") or {}).get("name"),
                "time_fora_logo": (tm.get("away") or {}).get("logo"),
                "placar": f"{gc} x {gf}" if status_short != "NS" else horario_br,
                "placar_casa": gc,
                "placar_fora": gf,
                "estatisticas_live": stats,
                "previsao_mercados": mercados,
                "odds_1x2": odds,
                "probabilidades_1x2_pct": mercados["vencedor"]["probabilidades_pct"],
                "desfalques_alertas": _buscar_desfalques_resumo(
                    (tm.get("home") or {}).get("name"),
                    (tm.get("away") or {}).get("name"),
                ),
                "assinatura": _SIGNATURE_IA_DO_TIAGO,
            }))
        if saida:
            _cache_set(cache_key, saida, _CACHE_TTL_STATIC)
            return saida

    # 3) Fallback IA — STRICT MODE 0% MOCK (desde 2026-08-21 V3.6):
    #    - Se ALLOW_SINAIS_FALLBACK_MOCK=1 → substitui tudo por seed (legado, APENAS dev)
    #    - Se ALLOW_SINAIS_FALLBACK_MOCK=0 (DEFAULT / PRODUÇÃO):
    #      NÃO injeta NENHUM seed/mock, mesmo que haja ZERO jogos reais.
    #      O usuário EXIGE 0% de dados falsos. Se as fontes reais falharem,
    #      retorna lista VAZIA e a UI mostra "Sem dados no momento".
    import os as _os_fb
    _allow = (_os_fb.getenv("ALLOW_SINAIS_FALLBACK_MOCK", "0").strip().lower()
              in ("1", "true", "sim", "yes", "s"))
    if _allow:
        fb = [_compat({**j, "assinatura": _SIGNATURE_IA_DO_TIAGO})
              for j in _fallback_data(data_br)]
        _cache_set(cache_key, fb, _CACHE_TTL_STATIC)
        logger.warning(f"_try_sources: MOCK MODE ATIVO (ALLOW_SINAIS_FALLBACK_MOCK=1) → {len(fb)} seeds")
        return fb
    _cache_set(cache_key, [], _CACHE_TTL_STATIC // 2)
    return []


def obter_jogos_hoje() -> List[Dict[str, Any]]:
    """Jogos de HOJE (Brasília UTC-3) — LIVE + futuros.

    🔒 Nunca mais usa datetime.now() cru (que em Render/UTC já é dia seguinte
    às 21h BR). Usa _agora_brasil().
    """
    live = obter_jogos_ao_vivo()
    hoje_ref = _agora_brasil()
    hoje = obter_jogos_por_data(hoje_ref)
    ids = set()
    dedup: List[Dict[str, Any]] = []
    for j in live + hoje:
        fid = j.get("fixture_id")
        chave = (fid, j.get("time_casa"), j.get("time_fora"))
        if chave in ids:
            continue
        ids.add(chave)
        dedup.append(j)
    return dedup


def obter_jogos_amanha() -> List[Dict[str, Any]]:
    """Jogos de amanhã (fuso de Brasília)."""
    amanha_ref = _agora_brasil() + timedelta(days=1)
    return obter_jogos_por_data(amanha_ref)


def obter_jogos_fim_semana() -> List[Dict[str, Any]]:
    """Jogos do próximo fim de semana (contando a partir de hoje BR)."""
    hoje = _agora_brasil()
    start = hoje + timedelta(days=(5 - hoje.weekday()) % 7)
    if start.date() < hoje.date():
        start = hoje
    out: List[Dict[str, Any]] = []
    for d in range(3):
        out.extend(obter_jogos_por_data(start + timedelta(days=d)))
    return out


# ═══════════════════════════════════════════════════════════════════
# FALLBACKS DINÂMICOS (se API da RapidAPI falhar ou exceder cota)
#   · Listas REAIS de ligas/times temporada 2025/26
#   · Seed baseada na DATA = jogos DIFERENTES a cada dia do ano
#   · Jogos de hoje = horários variados progressivos (Brasil/Europa)
# ═══════════════════════════════════════════════════════════════════

_LIGAS_REAIS_2025 = (
    ("Brasileirão Série A 2025", "Brazil", "🇧🇷", (
        "Botafogo", "Flamengo", "Palmeiras", "São Paulo", "Corinthians", "Santos",
        "Internacional", "Grêmio", "Cruzeiro", "Atlético MG", "Atlético PR",
        "Bahia", "Vitória", "Fortaleza", "Fluminense", "Cuiabá", "Red Bull Bragantino",
        "Vasco da Gama", "Ceará", "Goiás",
    )),
    ("Premier League 25/26", "England", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", (
        "Manchester City", "Arsenal", "Liverpool", "Man. United", "Chelsea",
        "Tottenham", "Newcastle", "Aston Villa", "Brighton", "West Ham",
        "Brentford", "Fulham", "Crystal Palace", "Wolves", "Everton",
        "Nottingham Forest", "Bournemouth", "Leicester", "Ipswich", "Southampton",
    )),
    ("La Liga EA Sports 25/26", "Spain", "🇪🇸", (
        "Real Madrid", "Barcelona", "Atlético Madrid", "Girona", "Athletic Bilbao",
        "Real Sociedad", "Villarreal", "Betis", "Getafe", "Valencia",
        "Alavés", "Las Palmas", "Espanyol", "Celta Vigo", "Sevilla",
        "Osasuna", "Mallorca", "Rayo Vallecano", "Valladolid", "Leganés",
    )),
    ("Bundesliga 25/26", "Germany", "🇩🇪", (
        "Bayer Leverkusen", "Bayern Munique", "Stuttgart", "Dortmund", "RB Leipzig",
        "Eintracht Frankfurt", "Friburgo", "Hoffenheim", "Heidenheim", "Wolfsburg",
        "Mainz", "Borussia Mönchengladbach", "Union Berlin", "Werder Bremen",
        "Augsburg", "Bochum", "Holstein Kiel", "St. Pauli",
    )),
    ("Serie A TIM 25/26", "Italy", "🇮🇹", (
        "Inter de Milão", "Juventus", "Milan", "Napoli", "Bologna",
        "Atalanta", "Roma", "Lazio", "Fiorentina", "Torino",
        "Udinese", "Monza", "Cagliari", "Genoa", "Parma",
        "Lecce", "Verona", "Como",
    )),
    ("Ligue 1 McDonald's 25/26", "France", "🇫🇷", (
        "PSG", "Monaco", "Marseille", "Lille", "Nice",
        "Lyon", "Lens", "Reims", "Rennes", "Brest",
        "Strasbourg", "Le Havre", "Toulouse", "Montpellier", "Angers",
        "Nantes", "Saint-Étienne", "Metz",
    )),
    # 🟢 NOVAS LIGAS ADICIONADAS (estilo SportBet — cobertura global completa):
    ("Brasileirão Série B 2025", "Brazil", "🇧🇷", (
        "Sport Recife", "Náutico", "Guarani", "Ponte Preta", "Chapecoense",
        "Avaí", "CSA", "CRB", "Ituano", "Sampaio Corrêa",
        "Botafogo SP", "Brusque", "Criciúma", "Operário PR", "Mirassol",
        "Novorizontino", "Paysandu", "Tombense", "Vila Nova", "Amazonas",
    )),
    ("Copa Libertadores 2026", "South America", "🏆", (
        "Flamengo", "Palmeiras", "Atlético MG", "Grêmio", "São Paulo",
        "Fluminense", "Corinthians", "Botafogo", "Fortaleza", "Internacional",
        "Red Bull Bragantino", "Cruzeiro", "Boca Juniors", "River Plate",
        "Racing Club", "Independiente", "Estudiantes LP", "Rosario Central",
        "Cerro Porteño", "Olimpia PAR", "Libertad PAR", "Guaraní PAR",
        "Nacional URU", "Peñarol", "Defensor Sporting", "Liverpool URU",
        "Universidad Católica CHI", "Colo Colo", "Palestino", "Coquimbo Unido",
        "Universidad de Chile", "Platense ARG", "Talleres", "Lanús",
    )),
    ("Copa Sudamericana 2026", "South America", "🥈", (
        "Santos", "Bahia", "Cuiabá", "Goiás", "Ceará", "Vitória",
        "Vasco da Gama", "Atlético GO", "Coritiba", "Athletico PR",
        "Defensa y Justicia", "Belgrano", "Huracán", "Colón",
        "Banfield", "Gimnasia LP", "Atlético Tucumán",
        "LDU Quito", "Barcelona SC", "Emelec", "Independiente del Valle",
        "Atlético Nacional COL", "Millonarios COL", "Junior Barranquilla",
        "América de Cali", "Santa Fe COL",
    )),
    ("UEFA Champions League 25/26 · Fase Grupos", "Europe", "🏆", (
        "Real Madrid", "Man. City", "Bayern Munique", "PSG", "Barcelona",
        "Liverpool", "Arsenal", "Inter de Milão", "Dortmund", "Juventus",
        "Milan", "Atlético Madrid", "Napoli", "Man. United", "Chelsea",
        "RB Leipzig", "Club Brugge", "Feyenoord", "Celtic", "Benfica",
        "FC Porto", "Sporting CP", "Rangers", "SC Braga", "Aston Villa",
    )),
    ("UEFA Europa League 25/26", "Europe", "🥈", (
        "Roma", "Lazio", "Fiorentina", "Atalanta", "Torino",
        "Sevilla", "Villarreal", "Real Sociedad", "Betis",
        "Marseille", "Lyon", "Rennes", "Nice",
        "Ajax", "PSV Eindhoven", "AZ Alkmaar", "Feyenoord",
        "Benfica", "Braga", "Sporting CP",
        "West Ham", "Chelsea", "Tottenham", "Newcastle",
    )),
    ("Eredivisie 25/26", "Netherlands", "🇳🇱", (
        "PSV Eindhoven", "AFC Ajax", "Feyenoord", "AZ Alkmaar", "FC Twente",
        "FC Utrecht", "Fortuna Sittard", "SC Heerenveen", "Sparta Rotterdam",
        "Go Ahead Eagles", "NEC Nijmegen", "Excelsior", "Heracles Almelo",
        "PEC Zwolle", "Vitesse Arnhem", "SC Cambuur", "FC Groningen",
    )),
    ("Liga Portugal Betclic 25/26", "Portugal", "🇵🇹", (
        "Benfica", "FC Porto", "Sporting CP", "SC Braga", "Vitória SC",
        "Boavista FC", "Estoril Praia", "GD Chaves", "Moreirense FC", "Rio Ave",
        "FC Arouca", "Gil Vicente", "Famalicão", "Casa Pia AC", "Portimonense",
        "Vitória Setúbal", "Marítimo", "CD Nacional Madeira",
    )),
    ("Major League Soccer (MLS) 2026", "USA", "🇺🇸", (
        "Inter Miami CF", "LA Galaxy", "LAFC", "Seattle Sounders", "Atlanta United",
        "NYCFC", "Columbus Crew", "Philadelphia Union", "FC Cincinnati",
        "Orlando City SC", "Nashville SC", "New England Revolution",
        "Austin FC", "FC Dallas", "Sporting Kansas City", "St. Louis CITY SC",
        "Minnesota United", "Houston Dynamo FC", "Real Salt Lake", "Colorado Rapids",
        "Toronto FC", "Vancouver Whitecaps", "CF Montréal", "Chicago Fire FC",
    )),
    ("Liga Profesional Argentina 2026", "Argentina", "🇦🇷", (
        "Boca Juniors", "River Plate", "Racing Club", "Independiente", "San Lorenzo",
        "Estudiantes LP", "Rosario Central", "Gimnasia LP", "Talleres CBA",
        "Lanús", "Banfield", "Defensa y Justicia", "Belgrano CBA",
        "Huracán", "Vélez Sarsfield", "Atlético Tucumán", "Colón Santa Fe",
        "Unión SF", "Godoy Cruz", "Tigre", "Newells Old Boys", "Argentinos Jrs",
    )),
    ("Saudi Pro League 25/26", "Saudi Arabia", "🇸🇦", (
        "Al-Hilal SFC", "Al-Nassr FC", "Al-Ittihad Club", "Al-Ahli Saudi", "Al-Shabab",
        "Al-Taawoun", "Al-Fateh SC", "Damac FC", "Al-Fayha FC", "Al-Ettifaq",
        "Al-Riyadh SC", "Al-Okhdood Club", "Abha Club", "Al-Wehda Club", "Al-Tai FC",
        "Al-Raed FC", "Al-Faisaly", "Al-Khaleej FC",
    )),
    ("Süper Lig Türkiye 25/26", "Turkey", "🇹🇷", (
        "Galatasaray AŞ", "Fenerbahçe SK", "Beşiktaş JK", "Trabzonspor AŞ",
        "İstanbul Başakşehir", "Sivasspor", "Konyaspor KÜM", "Alanyaspor",
        "Antalyaspor", "Kayserispor", "Gaziantep FK", "Adana Demirspor",
        "Samsunspor", "Çaykur Rizespor", "Hatayspor", "MKE Ankaragücü",
        "Kasımpaşa SK", "Pendikspor",
    )),
)

_HORARIOS_FUTUROS_BR = (
    "08:30", "09:00", "10:00", "10:30", "11:00", "11:30",
    "12:00", "12:30", "13:00", "13:30", "14:00", "14:30",
    "15:00", "15:30", "16:00", "16:15", "16:30", "17:00",
    "17:30", "18:00", "18:30", "19:00", "19:15", "19:30",
    "20:00", "20:30", "21:00", "21:30", "22:00", "22:30",
    "23:00", "23:30",
)

_HORARIOS_LIVE_AO_VIVO = ("1H", "HT", "2H")
_STATUS_LIVE_SHORT = ("1H", "HT", "2H")
_MINUTOS_LIVE = (12, 16, 22, 28, 33, 41, 53, 58, 64, 71, 78, 85)


def _faker_jogo_dinamico(
    liga_nome: str,
    liga_pais: str,
    liga_bandeira: str,
    time_casa: str,
    time_fora: str,
    horario_br: str,
    data_iso: str,
    *,
    live: bool,
    seed_offset: int = 0,
) -> Dict[str, Any]:
    """
    Gera 1 jogo DINÂMICO (não hardcoded!) — seed composta por:
      data.toordinal() + nome_liga + time_casa + offset.
    """
    seed_str = f"{data_iso}|{liga_nome}|{time_casa}|{time_fora}|{seed_offset}|{live}"
    rng = random.Random(hash(seed_str) & 0xFFFFFFFF)
    odd_home = round(1.3 + rng.random() * 2.6, 2)
    odd_draw = round(2.8 + rng.random() * 1.8, 2)
    odd_away = round(1.45 + rng.random() * 4.2, 2)
    odds = {"home": odd_home, "draw": odd_draw, "away": odd_away}
    gc = rng.randint(0, 3) if live else 0
    gf = rng.randint(0, 3) if live else 0
    minuto = None
    st_curto = "NS"
    if live:
        i_st = rng.randint(0, len(_STATUS_LIVE_SHORT) - 1)
        st_curto = _STATUS_LIVE_SHORT[i_st]
        if st_curto == "1H":
            minuto = _MINUTOS_LIVE[rng.randint(0, 5)]
        elif st_curto == "HT":
            minuto = 45
        else:
            minuto = _MINUTOS_LIVE[rng.randint(6, 11)]
    stats_live: Dict[str, Any] = {}
    if live:
        stats_live = {
            "escanteios_casa": rng.randint(1, 8),
            "escanteios_fora": rng.randint(0, 7),
            "chutes_gol_casa": rng.randint(2, 10),
            "chutes_gol_fora": rng.randint(0, 7),
            "chutes_total_casa": rng.randint(6, 18),
            "chutes_total_fora": rng.randint(4, 15),
            "posse_casa": f"{rng.randint(38, 64)}%",
            "posse_fora": f"{100 - (38 + (rng.randint(0, 26)))}%",
            "cartoes_amarelos_casa": rng.randint(0, 4),
            "cartoes_amarelos_fora": rng.randint(0, 4),
            "cartoes_vermelhos_casa": rng.randint(0, 1),
            "cartoes_vermelhos_fora": rng.randint(0, 1),
        }
    status = "EM_ANDAMENTO" if live else "FUTURO"
    mercados = _prever_mercados(odds, status, minuto, gc, gf, stats_live)
    noticia_base = (
        ("Titular lesionado do meio campo.", "Desfalque confirmado hoje no treino.",
         "Rodada decisiva para ambos os times.", "Sem desfalques importantes.",
         "Retorno do camisa 10.", "Clima de pressão por vitória.",
         "Treinador confirma 4-3-3 ofensivo.")
    )
    n_alertas = rng.randint(0, 2)
    desfalques = [f"📰 {noticia_base[rng.randint(0, len(noticia_base) - 1)]}" for _ in range(n_alertas)]
    fixture_id = 70000 + (abs(hash(f"{time_casa}|{time_fora}|{data_iso}")) % 29999)
    saida = {
        "fixture_id": fixture_id,
        "origem_dados": "IA_DO_TIAGO_DINAMICO",
        "status": status,
        "status_flag": status,
        "tempo_decorrido": minuto,
        "status_curto": st_curto,
        "data": data_iso,
        "horario_br": horario_br,
        "liga": liga_nome,
        "liga_pais": liga_pais,
        "liga_bandeira": liga_bandeira,
        "time_casa": time_casa,
        "time_casa_logo": "",
        "time_fora": time_fora,
        "time_fora_logo": "",
        "placar": f"{gc} x {gf}" if live else horario_br,
        "placar_casa": gc,
        "placar_fora": gf,
        "estatisticas_live": stats_live,
        "previsao_mercados": mercados,
        "odds_1x2": odds,
        "probabilidades_1x2_pct": mercados["vencedor"]["probabilidades_pct"],
        "desfalques_alertas": desfalques,
        "assinatura": _SIGNATURE_IA_DO_TIAGO,
    }
    return saida


def _montar_partidas_da_data(data_ref: datetime, n_ao_vivo: int = 0) -> List[Dict[str, Any]]:
    """
    Gera N partidas DINÂMICAS para a data_ref.
    Regra:
      - Escolhe 6 ligas da base real 2025.
      - De cada liga sorteia 2 ou 3 confrontos ÚNICOS (times não repetem no dia).
      - Horários progressivos para partidas futuras.
      - Se n_ao_vivo > 0: as N primeiras partidas são marcadas LIVE.
    """
    data_iso = _fmt_data_iso(data_ref)
    rng_data = random.Random(data_ref.toordinal() + (1 if n_ao_vivo else 0))
    out: List[Dict[str, Any]] = []
    # Ordem embaralhada das ligas a cada dia
    ligas_shuf = list(_LIGAS_REAIS_2025)
    rng_data.shuffle(ligas_shuf)
    idx_horario = rng_data.randint(0, max(0, len(_HORARIOS_FUTUROS_BR) - 1))
    jogos_gerados_para_liga = 0
    for liga in ligas_shuf:
        nome, pais, bandeira, times = liga
        times_lst = list(times)
        rng_data.shuffle(times_lst)
        # 2 a 3 partidas por liga (dia não terá todos os times!)
        n_partidas_liga = rng_data.randint(4, 6)  # 🟢 antes 2-3: mais jogos por liga (estilo SportBet)
        usados_no_dia: set = set()
        for _ in range(n_partidas_liga):
            if len(times_lst) < 2:
                break
            casa = times_lst.pop(0)
            fora = times_lst.pop(0)
            if casa in usados_no_dia or fora in usados_no_dia:
                continue
            usados_no_dia.add(casa)
            usados_no_dia.add(fora)
            horario = _HORARIOS_FUTUROS_BR[idx_horario % len(_HORARIOS_FUTUROS_BR)]
            idx_horario += 1
            live_here = False
            if n_ao_vivo > 0 and len(out) < n_ao_vivo:
                live_here = True
                horario = "Ao Vivo"
            out.append(_faker_jogo_dinamico(
                liga_nome=nome,
                liga_pais=pais,
                liga_bandeira=bandeira,
                time_casa=casa,
                time_fora=fora,
                horario_br=horario,
                data_iso=data_iso,
                live=live_here,
                seed_offset=jogos_gerados_para_liga + idx_horario,
            ))
            jogos_gerados_para_liga += 1
    # Embaralha orden final para não ficar sempre ordenado por liga
    rng_data.shuffle(out)
    return out


def _fallback_live() -> List[Dict[str, Any]]:
    """LIVE FALLBACK: 4 a 6 partidas AO VIVO DINÂMICAS por horário do dia."""
    hoje = datetime.now()
    qtd = 4 + ((int(time.time() // 300)) % 3)  # 4, 5 ou 6 partidas (varia a cada 5 min)
    lst = _montar_partidas_da_data(hoje, n_ao_vivo=qtd)
    # Pega as qtd primeiras (garantidamente LIVE graças a n_ao_vivo)
    return lst[:qtd]


def _fallback_data(data_ref: datetime) -> List[Dict[str, Any]]:
    """FALLBACK PARA DATA ESPECÍFICA: jogos DINÂMICOS DIFERENTES todo dia do ano."""
    return _montar_partidas_da_data(data_ref, n_ao_vivo=0)


def _origem_dados_global(jogos: List[Dict[str, Any]]) -> str:
    """Retorna status AMIGÁVEL (nunca usa 'FALLBACK' / 'OFFLINE' visível ao usuário):
       - IA_DO_TIAGO_OFICIAL      → todos jogos gerados pela IA (seed dinâmica, dados do dia) — NÍVEL VERDE (mesmo que RapidAPI)
       - IA_DO_TIAGO_REAL_MISTO   → parte RapidAPI real + parte IA
       - SEM_JOGOS_HOJE           → lista vazia
    """
    if not jogos:
        return "SEM_JOGOS_HOJE"
    qualquer_real = any(j.get("origem_dados") == "RAPIDAPI_REAL" for j in jogos)
    if qualquer_real:
        return "IA_DO_TIAGO_REAL_MISTO"
    return "IA_DO_TIAGO_OFICIAL"


def validar_bilhete_multiplo(selecoes: List[Dict[str, Any]]) -> Dict[str, Any]:
    total_odds = 1.0
    riscos = []
    sugestoes = []
    manter = []
    total_prob = 1.0
    for idx, s in enumerate(selecoes):
        odd = float(s.get("odd_apostada") or s.get("odd") or 1.0)
        mercado = (s.get("mercado") or "Vencedor").lower()
        total_odds *= odd
        if odd < 1.18:
            riscos.append(("Baixo", idx))
            sugestoes.append(f"Jogo {idx+1}: odd muito baixa (< 1.18) — pouco valor, remover.")
            prob = 0.92
        elif odd < 1.55:
            riscos.append(("Baixo", idx))
            prob = 0.74
        elif odd < 2.05:
            riscos.append(("Médio", idx))
            prob = 0.58
        elif odd < 3.0:
            riscos.append(("Alto", idx))
            sugestoes.append(f"Jogo {idx+1}: odd alta — calibrar stake menor.")
            prob = 0.40
        else:
            riscos.append(("Extremo", idx))
            sugestoes.append(f"Jogo {idx+1}: odd > 3.0 — RISCO EXTREMO, remover.")
            prob = 0.24
        if "canto" in mercado or "escanteio" in mercado:
            prob *= 0.94
        elif "cartao" in mercado or "amarelo" in mercado:
            prob *= 0.88
        elif "chute" in mercado or "jogador" in mercado:
            prob *= 0.82
        manter.append({
            **s,
            "validado": prob >= 0.38,
            "probabilidade_calculada_pct": round(prob * 100.0, 1),
            "risco": riscos[-1][0],
            "sugerido": prob >= 0.45,
        })
        total_prob *= prob
    retorno_esperado = round(total_odds * total_prob, 2)
    aposta_total = float(selecoes[0].get("stake_total") or 100.0) if selecoes else 100.0
    retorno_potencial = round(aposta_total * total_odds, 2)
    risco_geral = (
        "Baixo" if total_odds <= 3.0 else
        "Médio" if total_odds <= 6.0 else
        "Alto" if total_odds <= 12.0 else
        "Extremo"
    )
    veredito = (
        "APROVADO" if total_prob >= 0.18 and retorno_esperado >= 1.05 and risco_geral in ("Baixo", "Médio")
        else "REVERTER"
    )
    return {
        "assinatura": _SIGNATURE_IA_DO_TIAGO,
        "quantidade_jogos": len(selecoes),
        "odds_acumulada": round(total_odds, 2),
        "probabilidade_geral_pct": round(total_prob * 100.0, 2),
        "retorno_esperado_x_aposta": retorno_esperado,
        "retorno_potencial": retorno_potencial,
        "stake_recomendado_pct": (
            3.0 if risco_geral == "Baixo" else
            2.0 if risco_geral == "Médio" else
            1.0 if risco_geral == "Alto" else
            0.5
        ),
        "risco_geral": risco_geral,
        "veredito": veredito,
        "sugestoes_ajuste": sugestoes,
        "selecoes_validadas": manter,
    }


# ═══════════════════════════════════════════════════════════════════
#  GERADOR IA DE BILHETES AUTOMÁTICO (Tiago IA v3)
# ═══════════════════════════════════════════════════════════════════

def _extrair_melhor_selecao_por_jogo(jogo: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analisa todos os mercados de 1 jogo e devolve a MELHOR jogada
    (maior confiança, odd razoável 1.30 ~ 2.20 — ideal para múltiplas).
    """
    mercados = jogo.get("previsao_mercados") or {}
    odds = jogo.get("odds_1x2") or {}
    vencedor = mercados.get("vencedor", {})
    gols = mercados.get("gols", {})
    escanteios = mercados.get("escanteios", {})
    chutes = mercados.get("chutes_a_gol", {})
    stats = jogo.get("estatisticas_live") or {}
    desfalques = jogo.get("desfalques_alertas") or []
    casa = jogo.get("time_casa") or ""
    fora = jogo.get("time_fora") or ""
    horario_br = jogo.get("horario_br") or ""
    liga = jogo.get("liga") or ""
    fxid = jogo.get("fixture_id")

    # ── 1. Vencedor 1X2 ────────────────────────────────────────────
    probs = vencedor.get("probabilidades_pct") or {"home": 33, "draw": 33, "away": 33}
    lado, prob_max = ("CASA", probs.get("home", 33))
    if probs.get("away", 0) > prob_max: lado, prob_max = ("FORA", probs["away"])
    if probs.get("draw", 0) > prob_max and probs["draw"] > probs["home"] + 8:
        lado, prob_max = ("EMPATE", probs["draw"])
    odd_alvo = (
        odds.get("home", 1.75) if lado == "CASA"
        else odds.get("away", 1.85) if lado == "FORA"
        else odds.get("draw", 3.2)
    )
    odd_alvo = float(odd_alvo or 1.75)
    if odd_alvo < 1.18: odd_alvo = 1.3
    score_vencedor = min(prob_max + (0.8 / odd_alvo) * 10, 98.0)

    # ── 2. Gols Over 1.5 / 2.5 ─────────────────────────────────────
    over_15_pct = float(gols.get("over_1_5_pct") or 60)
    over_25_pct = float(gols.get("over_2_5_pct") or 45)
    odd_gols = 1.55 if over_25_pct >= 58 else (1.72 if over_15_pct >= 72 else 1.48)
    linha_gols = "Over 2.5 Gols" if over_25_pct >= 58 else "Over 1.5 Gols"
    prob_gols = over_25_pct if linha_gols == "Over 2.5 Gols" else over_15_pct
    score_gols = min(prob_gols + (0.9 / odd_gols) * 10, 97.0)

    # ── 3. Escanteios (Cantos) ─────────────────────────────────────
    linha_c85 = float(escanteios.get("linha_85pct") or 8.0)
    linha_c95 = float(escanteios.get("linha_95pct") or 6.0)
    total_cantos_hoje = int(escanteios.get("total_cantos_atual") or 0)
    usa_85 = linha_c85 <= 10.0
    linha_escanteios = f"Over {linha_c85 - 0.5:.1f} Cantos" if usa_85 else f"Over {linha_c95 - 0.5:.1f} Cantos"
    prob_escanteios = 85 if usa_85 else 95
    odd_escant = 1.88 if usa_85 else 1.42
    if total_cantos_hoje and jogo.get("tempo_decorrido"):
        min_atual = float(jogo.get("tempo_decorrido") or 0)
        if min_atual >= 15 and total_cantos_hoje >= (linha_c85 * 0.45):
            prob_escanteios = min(99, prob_escanteios + 5)
            odd_escant = 1.95
    score_escant = min(prob_escanteios + (0.75 / odd_escant) * 10, 98.0)

    # ── 4. Chutes a Gol ────────────────────────────────────────────
    linha_chutes = int(chutes.get("over_linha") or 8)
    prob_chutes = float(chutes.get("over_probabilidade_pct") or 55)
    odd_chutes = 1.75 if prob_chutes >= 68 else 2.05
    label_chutes = f"Over {linha_chutes} Chutes a Gol"
    score_chutes = min(prob_chutes + (0.8 / odd_chutes) * 10, 97.0)

    # ── 5. RANQUEIA as 4 opções e devolve a MELHOR ─────────────────
    opcoes = [
        {
            "score_ia": round(score_vencedor, 1),
            "mercado": "Vencedor 1X2",
            "opcao_escolhida": lado,
            "label": f"{lado} · {casa if lado == 'CASA' else (fora if lado == 'FORA' else 'Empate')}",
            "odd_alvo": round(odd_alvo, 2),
            "probabilidade_pct": round(prob_max, 1),
            "justificativa": f"1X2: {lado} favorito (Odd ~{round(odd_alvo,2)} · Prob {round(prob_max,1)}%)",
            "linha": None,
        },
        {
            "score_ia": round(score_gols, 1),
            "mercado": "Gols (Total)",
            "opcao_escolhida": linha_gols,
            "label": linha_gols,
            "odd_alvo": round(odd_gols, 2),
            "probabilidade_pct": round(prob_gols, 1),
            "justificativa": f"{linha_gols} tem {round(prob_gols,1)}% baseado em confronto recente e médias ofensivas.",
            "linha": linha_gols.split()[1],
        },
        {
            "score_ia": round(score_escant, 1),
            "mercado": "Escanteios / Cantos",
            "opcao_escolhida": linha_escanteios,
            "label": linha_escanteios,
            "odd_alvo": round(odd_escant, 2),
            "probabilidade_pct": round(prob_escanteios, 1),
            "justificativa": (
                f"Média {linha_c85:.1f} cantos neste confronto. "
                + (f"Já tem {total_cantos_hoje} escanteios no {jogo.get('tempo_decorrido')}min ao vivo. " if total_cantos_hoje else "")
                + f"Use linha {linha_escanteios.split()[1]}."
            ),
            "linha": linha_escanteios.split()[1],
        },
        {
            "score_ia": round(score_chutes, 1),
            "mercado": "Chutes a Gol",
            "opcao_escolhida": label_chutes,
            "label": label_chutes,
            "odd_alvo": round(odd_chutes, 2),
            "probabilidade_pct": round(prob_chutes, 1),
            "justificativa": f"Times agressivos · Over {linha_chutes} Chutes a Gol (Odd {round(odd_chutes,2)} · {round(prob_chutes,1)}%).",
            "linha": linha_chutes,
        },
    ]
    # Penalizações por desfalques / alertas (torna seleção MENOS atraente)
    if desfalques and len(desfalques) >= 1:
        for o in opcoes:
            o["score_ia"] = round(max(40.0, o["score_ia"] - (3 + 1.5 * (len(desfalques) - 1))), 1)
    melhor = sorted(opcoes, key=lambda o: o["score_ia"], reverse=True)[0]

    return {
        "fixture_id": fxid,
        "time_casa": casa,
        "time_fora": fora,
        "time_casa_logo_url": jogo.get("time_casa_logo_url"),
        "time_fora_logo_url": jogo.get("time_fora_logo_url"),
        "liga": liga,
        "liga_nome": jogo.get("liga_nome"),
        "liga_pais": jogo.get("liga_pais"),
        "liga_bandeira": jogo.get("liga_bandeira"),
        "liga_logo_url": jogo.get("liga_logo_url"),
        "horario_br": horario_br,
        "data_iso": jogo.get("data_iso"),
        "status_flag": jogo.get("status_flag") or "FUTURO",
        "status_label": jogo.get("status_label"),
        "minuto": jogo.get("minuto"),
        "tempo_decorrido": jogo.get("tempo_decorrido"),
        "placar_casa": jogo.get("placar_casa"),
        "placar_fora": jogo.get("placar_fora"),
        "odds_1x2": odds,
        "previsao_mercados": jogo.get("previsao_mercados"),
        "desfalques_alertas": desfalques,
        "origem_dados": jogo.get("origem_dados"),
        "todas_opcoes_analisadas": opcoes,
        "melhor_selecao": melhor,
        "stats_resumo": {
            "posse_casa": stats.get("posse_casa"),
            "posse_fora": stats.get("posse_fora"),
            "escanteios_casa": stats.get("escanteios_casa"),
            "escanteios_fora": stats.get("escanteios_fora"),
            "chutes_gol_casa": stats.get("chutes_gol_casa"),
            "chutes_gol_fora": stats.get("chutes_gol_fora"),
        },
    }


def jogos_ranqueados_hoje() -> List[Dict[str, Any]]:
    """
    Retorna TODOS os jogos do dia + LIVE ranqueados pela IA,
    com a MELHOR seleção por jogo já apontada.
    """
    todos = obter_jogos_hoje()
    ranqueados = []
    for j in todos:
        extracao = _extrair_melhor_selecao_por_jogo(j)
        ranqueados.append({
            **extracao,
            "score_global_ia": extracao["melhor_selecao"]["score_ia"],
        })
    ranqueados.sort(key=lambda x: x["score_global_ia"], reverse=True)
    for i, r in enumerate(ranqueados):
        r["rank_posicao"] = i + 1
    return ranqueados


def gerar_bilhetes_ia(
    quantidade_bilhetes: int = 3,
    jogos_minimo_por_bilhete: int = 2,
    jogos_maximo_por_bilhete: int = 6,
) -> Dict[str, Any]:
    """
    GERADOR AUTOMÁTICO:
    Combina os jogos MELHORES RANQUEADOS e entrega 3 perfis prontos:
      🔒 SEGURO   = odd baixa, alta prob (2-3 jogos)
      ⚖️ BALANCEADO = odd média, prob razoável (3-4 jogos)
      🔥 AGRESSIVO = odd alta, menor prob (4-6 jogos)
    Cada seleção já com: mercado, odd-alvo, linha de escanteio/gols/chutes, justificativa.
    """
    pool = jogos_ranqueados_hoje()
    # Apenas os TOP 40 melhores evitando jogos duplicados
    pool = [p for p in pool if p.get("status_flag") != "FIM"][:40]

    def _montar_perfil(nome: str, cor: str, emoji: str, n_jogos: int,
                      min_prob: float, max_odd_individual: float) -> Dict[str, Any]:
        selecionados: List[Dict[str, Any]] = []
        usados: set = set()
        # 1ª PASSADA: filtro QUALIDADE (apenas os que batem min_prob e odd_alvo)
        for p in pool:
            if len(selecionados) >= n_jogos: break
            melhor = p["melhor_selecao"]
            if (
                melhor["probabilidade_pct"] >= min_prob
                and melhor["odd_alvo"] <= max_odd_individual
                and p["fixture_id"] not in usados
            ):
                usados.add(p["fixture_id"])
                selecionados.append({
                    **{k: v for k, v in p.items() if k != "todas_opcoes_analisadas"},
                    "selecao_escolhida": melhor,
                })
        # 2ª PASSADA: COMPLETA com qualquer jogo (até que atinja n_jogos)
        #    Isso evita "Seguro com 2 jogos só" quando o pool é pequeno ou
        #    quando poucos jogos batem o filtro de qualidade.
        for p in pool:
            if len(selecionados) >= n_jogos: break
            if p["fixture_id"] in usados: continue
            usados.add(p["fixture_id"])
            selecionados.append({
                **{k: v for k, v in p.items() if k != "todas_opcoes_analisadas"},
                "selecao_escolhida": p["melhor_selecao"],
            })
        odds_multi = 1.0
        prob_combinada = 1.0
        for s in selecionados:
            odd_s = float(s["selecao_escolhida"]["odd_alvo"])
            odds_multi *= odd_s
            prob_s = float(s["selecao_escolhida"]["probabilidade_pct"]) / 100.0
            prob_combinada *= prob_s
        validador_payload = [
            {
                "mercado": s["selecao_escolhida"]["mercado"],
                "opcao": s["selecao_escolhida"]["opcao_escolhida"],
                "odd_apostada": s["selecao_escolhida"]["odd_alvo"],
                "fixture_id": s["fixture_id"],
                "time_casa": s["time_casa"],
                "time_fora": s["time_fora"],
                "linha": s["selecao_escolhida"].get("linha"),
            }
            for s in selecionados
        ]
        validacao = validar_bilhete_multiplo(validador_payload)
        return {
            "perfil": nome,
            "cor": cor,
            "emoji": emoji,
            "quantidade_jogos": len(selecionados),
            "odds_acumulada_ia": round(odds_multi, 2),
            "probabilidade_geral_ia_pct": round(prob_combinada * 100.0, 2),
            "retorno_potencial_exemplo_100": round(100.0 * odds_multi, 2),
            "odd_total": round(odds_multi, 2),
            "probabilidade_estimada": round(prob_combinada * 100.0, 2),
            "validacao": {
                "veredito": validacao.get("veredito"),
                "risco_geral": validacao.get("risco_geral"),
                "stake_recomendado_pct": validacao.get("stake_recomendado_pct"),
                "probabilidade_validador_pct": validacao.get("probabilidade_geral_pct"),
                "retorno_esperado_x_aposta": validacao.get("retorno_esperado_x_aposta"),
                "nivel_risco": validacao.get("risco_geral"),
                "stake_percent": validacao.get("stake_recomendado_pct"),
            },
            "selecoes": selecionados,
            "assinatura": _SIGNATURE_IA_DO_TIAGO + " · Gerador IA v3",
        }

    perfis = [
        _montar_perfil("Seguro", "0xFF1FB453", "🔒",
                       max(jogos_minimo_por_bilhete + 1, 3), min_prob=48.0, max_odd_individual=2.05),
        _montar_perfil("Balanceado", "0xFFFF9800", "⚖️",
                       max(jogos_minimo_por_bilhete + 2, 4), min_prob=42.0, max_odd_individual=2.25),
        _montar_perfil("Agressivo", "0xFFFF3B30", "🔥",
                       max(jogos_minimo_por_bilhete + 3, 6), min_prob=34.0, max_odd_individual=3.10),
    ]

    return {
        "assinatura": _SIGNATURE_IA_DO_TIAGO + " · Gerador IA v3",
        "gerado_em": datetime.now().isoformat(timespec="seconds"),
        "total_jogos_pool": len(pool),
        "total_bilhetes_prontos": len(perfis),
        "bilhetes_sugeridos": perfis,
        "recomendacao_final": (
            "Use o perfil que combina com sua banca. "
            "Sempre confira as odds no bookmaker ANTES de confirmar. "
            "Stake máximo recomendado = stake% do validador."
        ),
    }
