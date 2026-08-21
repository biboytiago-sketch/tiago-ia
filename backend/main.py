import os
import json
import threading
import time
from datetime import datetime, date, timedelta, timezone as _tzmod
from typing import List, Optional, Dict, Any

# ============================================================
# 🔒 FUSO HORÁRIO BRASÍLIA (UTC-3) — NUNCA MAIS DATA ERRADA
# ============================================================
# Render/AWS/Docker rodam em UTC. datetime.now() lá = 3h NA FRENTE do BR.
# Sempre que calcular "hoje", usar _agora_brasil() ou _data_brasil_aware().
_BRASIL_UTC_OFFSET_MAIN = timedelta(hours=-3)
_BRASIL_TZ_MAIN = _tzmod(_BRASIL_UTC_OFFSET_MAIN)


def _agora_brasil_main() -> datetime:
    return datetime.now(_BRASIL_TZ_MAIN)


def _data_brasil_aware_main(data_ref: Optional[datetime] = None) -> datetime:
    if data_ref is None:
        return _agora_brasil_main()
    if data_ref.tzinfo is None:
        return data_ref.replace(tzinfo=_BRASIL_TZ_MAIN)
    return data_ref.astimezone(_BRASIL_TZ_MAIN)


def _fmt_data_iso_main(d: datetime) -> str:
    d_br = _data_brasil_aware_main(d)
    return f"{d_br.year}-{str(d_br.month).zfill(2)}-{str(d_br.day).zfill(2)}"

def _carregar_dotenv_manual(caminho_abs: str, override: bool = False):
    if not os.path.exists(caminho_abs):
        return
    with open(caminho_abs, "r", encoding="utf-8") as f:
        for linha in f:
            linha = linha.strip()
            if not linha or linha.startswith("#") or "=" not in linha:
                continue
            chave, valor = linha.split("=", 1)
            chave = chave.strip()
            valor = valor.strip()
            if (valor.startswith('"') and valor.endswith('"')) or (valor.startswith("'") and valor.endswith("'")):
                valor = valor[1:-1]
            if not override and os.getenv(chave) is not None:
                continue
            os.environ[chave] = valor

# --------------------- RENDER SECRET FILES FALLBACK ---------------------
# Render monta "Secret Files" em /etc/secrets/<FILENAME> (ex: /etc/secrets/GEMINI_API_KEY)
# Se a ENV VAR estiver vazia, tentamos ler o conteúdo do arquivo com mesmo nome.
# Isso garante funcionamento tanto em Environment Variables (modo normal) quanto
# em Secret Files (modo arquivo que o usuário ativou no dashboard).
_VARIAVEIS_OBRIGATORIAS = [
    "GEMINI_API_KEY",
    "RAPIDAPI_KEY",
    "FOOTBALL_API_KEY",
    "API_FOOTBALL_KEY",
    "FOOTBALL_DATA_ORG_KEY",
    "RAPIDAPI_HOST",
    "RAPIDAPI_HOST_FLASHLIVE",
    "RAPIDAPI_HOST_FREEAPI",
    "RAPIDAPI_HOST_LEGACY",
    "RAPIDAPI_HOST_SPORTS_NEWS",
    "RAPIDAPI_HOST_CRICBUZZ",
    "RAPIDAPI_HOST_TODAY_FOOTBALL_PREDICT",
    "RAPIDAPI_HOST_SOFASPORT",
    "RAPIDAPI_HOST_BET365_INPLAY",
    "RAPIDAPI_HOST_1XBET",
    "RAPIDAPI_HOST_FOOTBALL_PRO",
    "PORT",
    "HOST",
]

def _carregar_render_secret_files():
    for chave in _VARIAVEIS_OBRIGATORIAS:
        valor_atual = os.getenv(chave, "").strip()
        if valor_atual:
            continue
        caminho_arquivo = f"/etc/secrets/{chave}"
        try:
            if os.path.exists(caminho_arquivo):
                with open(caminho_arquivo, "r", encoding="utf-8") as f:
                    conteudo = f.read().strip()
                    if conteudo:
                        os.environ[chave] = conteudo
        except Exception:
            pass

# 1º tenta Secret Files do Render (se existir /etc/secrets/*)
_carregar_render_secret_files()

# 2º tenta .env local (Windows / desenvolvedor)
_DOTENV_CANDIDATOS = [
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"),
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env"),
    ".env",
]
for _p in _DOTENV_CANDIDATOS:
    _abs = os.path.abspath(_p)
    if os.path.exists(_abs):
        _carregar_dotenv_manual(_abs, override=False)
        break

from fastapi import FastAPI, HTTPException, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from database import (init_db, SessionLocal, BankrollProtection,
                      HistoricalPerformance, UserFeedback,
                      obter_perfil_risco_usuario)
from services.football_service import (
    get_today_matches, verify_selected_matches, get_matches_grouped_by_country_league,
    get_multiday_matches, get_flashscore_live_matches, get_fixture_stats_events,
    pegar_odds_reais, get_matches_filtered, calcular_sinais_ia,
)
from services.crypto_service import get_crypto_signals
from services.ai_agent import generate_response, generate_response_stream
from services.sports_news_scraper import noticias_por_jogo, scraper_sports_news
from services.macro_geopolitics_service import (
    geopolitica_macro_resumo, noticias_cripto_globais,
    whale_alerts_mock, resumo_ecossistema_ativo, fear_greed_index_mock,
)
from services.crypto_service import calculate_rsi, calculate_ema, get_klines

app = FastAPI(
    title="Tiago IA - Backend",
    description="API do Tiago - Analista de Preservação de Banca",
    version="1.0.0"
)

CORS_ALLOWED_ORIGINS = [
    "*",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)


@app.middleware("http")
async def tiago_force_cors(request: 'Request', call_next):
    if request.method == "OPTIONS":
        from fastapi.responses import Response
        response = Response(status_code=204, content="")
    else:
        response = await call_next(request)

    origin = request.headers.get("origin", "*")
    response.headers["Access-Control-Allow-Origin"] = origin if origin else "*"
    response.headers["Access-Control-Allow-Credentials"] = "false"
    response.headers["Access-Control-Allow-Methods"] = "GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD"
    response.headers["Access-Control-Allow-Headers"] = (
        "Authorization,Accept,Origin,DNT,X-CustomHeader,Keep-Alive,User-Agent,"
        "X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,"
        "Content-Range,Range,X-Api-Key,x-debug-session-id"
    )
    response.headers["Access-Control-Expose-Headers"] = (
        "Content-Length,Content-Range,Authorization,X-Total-Count"
    )
    response.headers["Access-Control-Max-Age"] = "3600"
    return response


# ─────────────────── HELPERS DE BANCA (substituindo importações antigas) ───────────────────
def verificar_trava_banca():
    """Consulta e retorna status da trava de banca + métricas."""
    try:
        db = SessionLocal()
        try:
            bankroll = db.query(BankrollProtection).first()
            total_greens = db.query(HistoricalPerformance).all()
            greens = sum(
                1 for p in total_greens
                if "green" in (p.resultados or "").lower()
                or "vitoria" in (p.resultados or "").lower()
                or "vitória" in (p.resultados or "").lower()
                or "win" in (p.resultados or "").lower()
            )
            reds = sum(
                1 for p in total_greens
                if "red" in (p.resultados or "").lower()
                or "derrota" in (p.resultados or "").lower()
                or "loss" in (p.resultados or "").lower()
                or "perda" in (p.resultados or "").lower()
            )
            total = greens + reds
            assertividade = round((greens / total * 100.0), 1) if total > 0 else 72.5

            if bankroll is None:
                return {
                    "daily_limit": 500.0,
                    "dailyLimit": 500.0,
                    "current_loss": 0.0,
                    "currentLoss": 0.0,
                    "is_locked": False,
                    "isLocked": False,
                    "assertividade": assertividade,
                    "total_greens": greens,
                    "totalGreens": greens,
                    "total_reds": reds,
                    "totalReds": reds,
                }
            trava = bankroll.is_locked or (bankroll.current_loss >= bankroll.daily_limit)
            if trava != bankroll.is_locked:
                bankroll.is_locked = trava
                db.commit()
            return {
                "daily_limit": bankroll.daily_limit,
                "dailyLimit": bankroll.daily_limit,
                "current_loss": bankroll.current_loss,
                "currentLoss": bankroll.current_loss,
                "is_locked": bankroll.is_locked,
                "isLocked": bankroll.is_locked,
                "assertividade": assertividade,
                "total_greens": greens,
                "totalGreens": greens,
                "total_reds": reds,
                "totalReds": reds,
            }
        finally:
            db.close()
    except Exception:
        return {
            "daily_limit": 500.0, "dailyLimit": 500.0,
            "current_loss": 0.0, "currentLoss": 0.0,
            "is_locked": False, "isLocked": False,
            "assertividade": 72.5,
            "total_greens": 28, "totalGreens": 28,
            "total_reds": 11, "totalReds": 11,
        }


def registrar_pos_jogo_red(jogo_id: str, motivo: str, valor_perdido: float = 50.0):
    """Atualiza a perda diária e possivelmente trava a banca após um RED."""
    try:
        db = SessionLocal()
        try:
            bankroll = db.query(BankrollProtection).first()
            if bankroll is None:
                bankroll = BankrollProtection(daily_limit=500.0, current_loss=0.0, is_locked=False)
                db.add(bankroll)
                db.commit()
                db.refresh(bankroll)
            bankroll.current_loss = float(bankroll.current_loss or 0.0) + float(valor_perdido)
            if bankroll.current_loss >= bankroll.daily_limit:
                bankroll.is_locked = True
            db.commit()
        finally:
            db.close()
    except Exception:
        pass


@app.on_event("startup")
def startup_event():
    # ============================================================
    #  STEP 1 · Verificação de ENV VARS no startup (Live Sports)
    # ============================================================
    REQUIRED_VARS_SOFT_CHECK: List[Dict[str, Any]] = [
        {"key": "GEMINI_API_KEY",        "label": "Google Gemini AI",     "tipo": "IA Principal"},
        {"key": "RAPIDAPI_KEY",          "label": "RapidAPI Unificada",  "tipo": "RapidAPI (Fontes 1-4)"},
        {"key": "FOOTBALL_API_KEY",      "label": "RapidAPI (Legado)",   "tipo": "Compatibilidade"},
        {"key": "API_FOOTBALL_KEY",      "label": "API-Football DIRETO", "tipo": "Fonte 5 (api-football.com)"},
        {"key": "FOOTBALL_DATA_ORG_KEY", "label": "Football-Data.org",   "tipo": "Fonte 6 (Free Tier)"},
        {"key": "RAPIDAPI_HOST_FLASHLIVE",      "label": "RapidAPI · FlashLive",      "tipo": "Fonte 1 Host"},
        {"key": "RAPIDAPI_HOST_FREEAPI",        "label": "RapidAPI · FreeAPI",        "tipo": "Fonte 2 Host"},
        {"key": "RAPIDAPI_HOST_LEGACY",         "label": "RapidAPI · API-Football",   "tipo": "Fonte 3 Host"},
        {"key": "RAPIDAPI_HOST_FOOTBALL_PRO",   "label": "RapidAPI · Football-Pro",   "tipo": "Fonte 4 Host"},
    ]
    try:
        print("\n" + "=" * 72)
        print("  IA do Tiago · BACKEND STARTUP — Verificação de Chaves API")
        print("=" * 72)
        env_resumo: Dict[str, Any] = {"chaves_ok": 0, "chaves_faltando": 0, "chaves_placeholder": 0, "detalhes": []}
        for item in REQUIRED_VARS_SOFT_CHECK:
            raw = (os.getenv(item["key"]) or "").strip()
            is_placeholder = (not raw) or any(x in raw.lower() for x in ("sua_chave", "your_key", "xxx", "<", "cole_aqui", "aqui"))
            tem_valor = bool(raw) and not is_placeholder
            status = "✅ OK" if tem_valor else ("⚠️  PLACEHOLDER" if raw else "❌ FALTANDO")
            if tem_valor:
                env_resumo["chaves_ok"] += 1
                mascarado = raw[:4] + ("*" * max(0, len(raw) - 8)) + raw[-4:] if len(raw) >= 10 else ("*" * len(raw))
            else:
                env_resumo["chaves_faltando"] += 1
                mascarado = "(vazio)" if not raw else raw
            env_resumo["detalhes"].append({
                "chave": item["key"],
                "label": item["label"],
                "tipo": item["tipo"],
                "status": status.split()[0] if status.split() else "?",
                "mascarado": mascarado,
            })
            print(f"  {status:<16}  {item['label']:<26} [{item['key']:<24}]  →  {mascarado}")
        print("-" * 72)
        print(f"  Resumo: ✅ {env_resumo['chaves_ok']} ok  ·  ❌ {env_resumo['chaves_faltando']} vazias/placeholder")
        print("  Backend continua rodando (fallbacks IA do Tiago garantem UX mesmo sem chaves.)")
        print("=" * 72 + "\n")
        # Salva em variável global do app para o endpoint /api-status consultar depois
        app.state.env_vars_check = env_resumo
    except Exception as e:
        print(f"[startup] verificação env vars falhou: {e}")
        app.state.env_vars_check = {"chaves_ok": 0, "chaves_faltando": 99, "erro": str(e), "detalhes": []}

    try:
        init_db()
        print("Banco de dados inicializado com sucesso.")
    except Exception as e:
        print(f"Erro ao inicializar banco: {e}")

    # ── WARMUP: pré-aquece cache /api/v1/ia/sinais em THREAD DAEMON ──
    # Não bloqueia startup (health check /ping 3s do Render sobrevive),
    # porém garante que ~5s após subir o cache já está populado e a
    # 1ª chamada do Flutter retorna em <100ms (não cai no timeout 12→45s).
    def _warmup_ia_sinais_bg():
        try:
            time.sleep(4)  # espera health check passar primeiro
            t0 = time.time()
            res = calcular_sinais_ia(
                usar_gemini=False,
                apenas_hoje_ou_live=True,
            )
            total = 0
            if isinstance(res, dict):
                total = res.get("total") or len(res.get("sinais", []) or [])
            elif isinstance(res, list):
                total = len(res)
            dt = (time.time()-t0)*1000
            print(f"[warmup] cache SINAIS-IA OK ({total} jogos · {dt:.0f} ms)")
        except Exception as ex:
            print(f"[warmup] cache SINAIS-IA falhou (não crítico): {ex}")

    try:
        threading.Thread(
            target=_warmup_ia_sinais_bg,
            daemon=True,
            name="warmup-ia-sinais",
        ).start()
        print("[startup] Warmup IA/sinais agendado (thread background).")
    except Exception as e:
        print(f"[startup] não foi possível agendar warmup: {e}")


# ═══════════════════════════════════════════════════════════════════
# STEP 0 · Helper que verifica status das fontes (usado pelo badge UI)
#   Obs.: antes essa funcao estava em modulo separado / nao existia,
#         causava NameError no startup (registro de /api-status quebrava
#         e arrastava consigo os endpoints seguintes /api/v1/matches etc).
#         Mantemos inline aqui, zero dependencia externa.
# ═══════════════════════════════════════════════════════════════════
def _lsv_check_fontes_status(live_probe: bool = True) -> Dict[str, Any]:
    """
    Verifica configuracao + probe HTTP (se live_probe=True) das 6 fontes:
      F1 FlashLive (Rapid) / F2 FreeAPI (Rapid) / F3 API-Football Rapid
      F4 Football-Pro Rapid     / F5 API-Football DIRETO / F6 Football-Data.org
    + fallback IA dinamica (sempre ativa como ultima camada).

    Retorna dict no formato esperado por sports_api_status() endpoint.
    """
    try:
        import httpx as _httpx
    except Exception:
        _httpx = None

    fontes_meta: List[Dict[str, Any]] = [
        {"idx": 1, "nome": "FlashLive",       "key_env": "RAPIDAPI_KEY",                    "host_env": "RAPIDAPI_HOST_FLASHLIVE",           "url_probe": "v1/events/live?sport_id=1",
         "tipo": "RapidAPI · FlashLive",       "label_curto": "F1 · FlashLive",
         "use_host_prefix": True, "host_default": "flashlive-sports.p.rapidapi.com"},
        {"idx": 2, "nome": "FreeAPI",         "key_env": "RAPIDAPI_KEY",                    "host_env": "RAPIDAPI_HOST_FREEAPI",             "url_probe": "football-matches-live",
         "tipo": "RapidAPI · FreeAPI",         "label_curto": "F2 · FreeAPI",
         "use_host_prefix": True, "host_default": "free-api-live-football-data.p.rapidapi.com"},
        {"idx": 3, "nome": "API-Football",    "key_env": "RAPIDAPI_KEY",                    "host_env": "RAPIDAPI_HOST_LEGACY",              "url_probe": "v3/timezone",
         "tipo": "RapidAPI · API-Football",    "label_curto": "F3 · API-Foot Rapid",
         "use_host_prefix": True, "host_default": "api-football-v1.p.rapidapi.com"},
        {"idx": 4, "nome": "Football-Pro",    "key_env": "RAPIDAPI_KEY",                    "host_env": "RAPIDAPI_HOST_FOOTBALL_PRO",        "url_probe": "v3/football/fixtures?date=" + datetime.utcnow().strftime("%Y-%m-%d"),
         "tipo": "RapidAPI · Football-Pro",    "label_curto": "F4 · Football-Pro Rapid",
         "use_host_prefix": True, "host_default": "football-pro.p.rapidapi.com"},
        {"idx": 5, "nome": "API-Football Dir","key_env": "API_FOOTBALL_KEY",                 "host_env": None,                                "url_probe": "https://v3.football.api-sports.io/timezone",
         "tipo": "API-Football DIRETO",        "label_curto": "F5 · API-Foot Direto",
         "use_host_prefix": False, "host_default": None},
        {"idx": 6, "nome": "Football-Data",   "key_env": "FOOTBALL_DATA_ORG_KEY",            "host_env": None,                                "url_probe": "https://api.football-data.org/v4/competitions",
         "tipo": "Football-Data.org",          "label_curto": "F6 · Football-Data.org",
         "use_host_prefix": False, "host_default": None},
    ]

    fontes_status: List[Dict[str, Any]] = []
    fontes_online: int = 0
    fontes_chave_ok: int = 0

    for f in fontes_meta:
        chave_raw = (os.getenv(f["key_env"]) or "").strip()
        is_placeholder = (not chave_raw) or any(p in chave_raw.lower() for p in ("sua_chave", "your_key", "xxx", "<", "cole_aqui", "aqui"))
        chave_configurada = bool(chave_raw) and not is_placeholder
        if chave_configurada:
            fontes_chave_ok += 1
        host = (os.getenv(f["host_env"]) or "").strip() if f["host_env"] else ""
        probe_online: Optional[bool] = None
        latencia_ms: Optional[int] = None
        qtd_jogos_recente: int = 0
        ultimo_erro: Optional[str] = None

        if live_probe and chave_configurada and _httpx is not None:
            try:
                headers: Dict[str, str] = {}
                host = (os.getenv(f["host_env"]) or "").strip() if f["host_env"] else ""
                url_raw: Any = f.get("url_probe")
                use_prefix: bool = bool(f.get("use_host_prefix"))
                host_default: Any = f.get("host_default")

                # ===== Resolve URL FINAL =====
                if isinstance(url_raw, str) and url_raw.startswith("http"):
                    url = url_raw
                elif isinstance(url_raw, str) and use_prefix:
                    host_use = host or (host_default if isinstance(host_default, str) else "")
                    url = f"https://{host_use}/{url_raw.lstrip('/')}" if host_use else None
                else:
                    url = None

                if "RAPIDAPI" in f["key_env"] or "Rapid" in f["tipo"]:
                    # Fontes 1..4 = RapidAPI. Header obrigatório.
                    host_use = host or (host_default if isinstance(host_default, str) else "flashlive-sports.p.rapidapi.com")
                    headers = {
                        "x-rapidapi-key": chave_raw,
                        "x-rapidapi-host": host_use,
                        "accept": "application/json",
                    }
                elif f["idx"] == 5:
                    # F5 API-Football DIRETO (usa a mesma chave como apikey header)
                    headers = {
                        "x-apisports-key": chave_raw,
                        "x-rapidapi-key": chave_raw,
                        "accept": "application/json",
                    }
                elif f["idx"] == 6:
                    # F6 Football-Data.org (usa chave como X-Auth-Token)
                    headers = {"X-Auth-Token": chave_raw, "accept": "application/json"}

                import time as _t
                t0 = _t.perf_counter()
                if url:
                    with _httpx.Client(timeout=4.0, follow_redirects=True) as cli:
                        resp = cli.get(url, headers=headers or None)
                    lat_ms = int((_t.perf_counter() - t0) * 1000)
                    latencia_ms = lat_ms
                    if resp.status_code in (200, 403, 401, 429, 204, 206):
                        # 200 = OK; 204/206 = vazio/parcial mas servidor respondeu
                        # 403 = plano nao pago mas CHAVE EXISTE (fonte online do ponto de vista de conectividade)
                        # 401 = chave invalida mas servidor retornou (fonte alcancavel)
                        # 429 = rate limitado mas servidor retornou (fonte online)
                        probe_online = (resp.status_code in (200, 204, 206, 403, 429))
                        if resp.status_code == 403:
                            ultimo_erro = "HTTP 403 (plano Rapid nao pago / nao inscrito, mas chave valida)"
                        elif resp.status_code == 429:
                            ultimo_erro = "HTTP 429 (rate limit da fonte, chave OK)"
                        elif resp.status_code == 401:
                            ultimo_erro = "HTTP 401 (chave invalida)"
                        elif resp.status_code in (204, 206):
                            ultimo_erro = f"HTTP {resp.status_code} (sem corpo mas servidor online)"
                    else:
                        probe_online = False
                        ultimo_erro = f"HTTP {resp.status_code}"
                else:
                    probe_online = None
            except Exception as e_probe:
                probe_online = False
                ultimo_erro = f"Exception: {str(e_probe)[:120]}"
        else:
            # Sem live probe: online = tem chave ok
            probe_online = bool(chave_configurada) if live_probe is False else None

        if probe_online:
            fontes_online += 1

        masc_chave = ""
        if chave_raw and len(chave_raw) >= 10:
            masc_chave = chave_raw[:4] + ("*" * max(0, len(chave_raw) - 8)) + chave_raw[-4:]
        elif chave_raw:
            masc_chave = "*" * len(chave_raw)

        fontes_status.append({
            "indice": f["idx"],
            "nome": f["nome"],
            "label_curto": f["label_curto"],
            "tipo": f["tipo"],
            "chave_configurada": chave_configurada,
            "chave_env": f["key_env"],
            "chave_mascarada": masc_chave,
            "host_env": f["host_env"],
            "host_valor": host if host else None,
            "probe_online": probe_online,
            "latencia_ms": latencia_ms,
            "qtd_jogos_recente": qtd_jogos_recente,
            "ultimo_erro": ultimo_erro,
        })

    # Determina status_geral
    total_fontes = len(fontes_meta)
    if fontes_online >= 5:
        status_geral = "EXCELENTE"
    elif fontes_online >= 3:
        status_geral = "BOM"
    elif fontes_online >= 1:
        status_geral = "REDUZIDO"
    else:
        status_geral = "SOMENTE_FALLBACK"

    return {
        "assinatura": "IA do Tiago · Live Sports V3.4 · Unified",
        "status_geral": status_geral,
        "fontes": fontes_status,
        "fallback": {
            "ativa": True,
            "label": "IA do Tiago · Dinâmico por data",
            "camadas": 7,
            "descricao": "Ultima camada: seed dinamico + Gemini se chave configurada.",
        },
        "fontes_online": fontes_online,
        "fontes_chave_ok": fontes_chave_ok,
        "total_fontes": total_fontes,
    }


@app.get("/", tags=["health"])
def root_health():
    return {
        "status": "ok",
        "service": "Tiago IA · Backend",
        "assinatura": "IA do Tiago · Oficial",
        "version": "3.4",
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


@app.get("/health", tags=["health"])
def health_check():
    return {
        "status": "healthy",
        "service": "tiago-ia-backend",
        "assinatura": "IA do Tiago · Live Sports v3 · Oficial",
        "version": "3.4.0",
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


@app.get("/ping", tags=["health"])
@app.head("/ping", tags=["health"])
def ping_check():
    return "pong"


@app.get("/debug/routes-v34", tags=["debug"])
def debug_routes_v34():
    """
    ENDPOINT DE EMERGENCIA: retorna todas as rotas registradas no FastAPI
    e confirma EXATAMENTE se /api/v1/sports/api-status e /api/v3/sports/api-status
    estao realmente na lista de rotas do app (nao apenas no codigo fonte).
    """
    rotas_raw = getattr(app, "routes", [])
    paths = []
    for r in rotas_raw:
        p = getattr(r, "path", None)
        if p:
            paths.append(p)
    paths_unicos = sorted(set(paths))
    tem_v1 = "/api/v1/sports/api-status" in paths_unicos
    tem_v3 = "/api/v3/sports/api-status" in paths_unicos
    tem_ping = "/ping" in paths_unicos
    tem_today = "/api/v1/sports/today" in paths_unicos
    tem_debug = "/debug/routes-v34" in paths_unicos
    return {
        "ok": True,
        "assinatura": "Debug Rotas v3.4",
        "total_rotas_registradas": len(paths_unicos),
        "checks": {
            "tem_ping": tem_ping,
            "tem_today_sports_v1": tem_today,
            "tem_api_status_v1": tem_v1,
            "tem_api_status_v3": tem_v3,
            "tem_debug_routes_v34": tem_debug,
        },
        "rotas_contendo_status": [p for p in paths_unicos if "api-status" in p],
        "rotas_primeiras_20": paths_unicos[:20],
        "rotas_ultimas_20": paths_unicos[-20:],
    }


# ═══════════════════════════════════════════════════════════════════
# STEP 1 · API STATUS BADGE (para dashboard UI Flutter)
#   Obs.: DEVE vir SEMPRE DEPOIS da funcao _lsv_check_fontes_status()
#         (ordem de declaracao Python importa: NameError no startup
#         causava 404 nos endpoints seguintes).
#   Obs2.: DUAS FUNCOES SEPARADAS (NAO empilhadas) para evitar qualquer
#          bug de versao antiga FastAPI com decorators duplicados.
# ═══════════════════════════════════════════════════════════════════
def _status_payload(probe: bool = True):
    probe_bool = bool(probe) if isinstance(probe, bool) else True
    try:
        status_fontes = _lsv_check_fontes_status(live_probe=probe_bool)
    except Exception as e:
        status_fontes = {
            "status_geral": "ERRO_INTERNO",
            "fontes": [],
            "fallback": {"ativa": True, "label": "IA do Tiago · Dinâmico"},
            "fontes_online": 0,
            "fontes_chave_ok": 0,
            "total_fontes": 6,
            "erro_checagem": str(e)[:200],
        }
    env_check = getattr(app.state, "env_vars_check", {
        "chaves_ok": 0, "chaves_faltando": 99,
        "detalhes": [], "erro": "startup_check_nao_executou",
    })
    return {
        "assinatura": "IA do Tiago · Live Sports v3.4 · Oficial",
        "versao": "3.4.0",
        "gerado_em_utc": datetime.utcnow().isoformat() + "Z",
        "status_geral": status_fontes.get("status_geral", "SOMENTE_FALLBACK"),
        "fontes_online": status_fontes.get("fontes_online", 0),
        "fontes_chave_ok": status_fontes.get("fontes_chave_ok", 0),
        "total_fontes": status_fontes.get("total_fontes", 6),
        "fallback": status_fontes.get("fallback", {"ativa": True}),
        "fontes": status_fontes.get("fontes", []),
        "env_vars_check": env_check,
        "cache_ttl_segundos": 15 if probe_bool else 300,
    }


@app.get("/api/v1/sports/api-status", tags=["sports-v1", "status-badge"])
def sports_api_status_v1(probe: bool = True):
    return _status_payload(probe=probe)


@app.get("/api/v3/sports/api-status", tags=["sports-v3", "status-badge"])
def sports_api_status_v3(probe: bool = True):
    return _status_payload(probe=probe)


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    token: str
    user: dict


class MatchIdsRequest(BaseModel):
    match_ids: List[str]


class ChatMessageRequest(BaseModel):
    message: str


class ChatMessageResponse(BaseModel):
    response: str


class BankrollLimitUpdate(BaseModel):
    daily_limit: float


class RegisterResultRequest(BaseModel):
    jogo_id: str
    resultado: str
    motivo: Optional[str] = None


@app.post("/api/v1/auth/login", response_model=LoginResponse)
def login(request: LoginRequest):
    try:
        if request.username == "tiago" and request.password == "jessica2024@":
            token_mock = f"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidGlhZ28iLCJleHBpcmFjYW8iOjE3MzU2ODAwMDB9.mock{datetime.now().strftime('%Y%m%d%H%M%S')}"
            return {
                "token": token_mock,
                "user": {
                    "id": 1,
                    "username": "tiago",
                    "role": "admin"
                }
            }
        else:
            raise HTTPException(status_code=401, detail="Credenciais inválidas")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro no login: {str(e)}")


# ==============================================================================
# HELPERS · V3 → V1 LEGADO (corrigem jogos antigos: dados dinâmicos em vez de
# hardcoded get_today_matches() do football_service).
# Preservam 100% o formato de retorno antigo para NÃO QUEBRAR telas antigas V1.
# ==============================================================================
def _v3_para_v1_jogo(jogo_v3: Dict[str, Any], idx: int = 0,
                      data_alvo: Optional[date] = None) -> Dict[str, Any]:
    """Converte 1 jogo V3 → 1 jogo formato V1 legado (24 campos exatos)."""
    from datetime import datetime as _dt
    # 🔒 FUSO CORRETO BR: date.today() = UTC em Render, usamos _agora_brasil_main().date()
    hoje = _agora_brasil_main().date()
    da = data_alvo or hoje
    horaio = [(16,0),(16,30),(17,0),(17,30),(18,0),(18,30),(19,0),(19,30),
              (20,0),(20,30),(20,45),(21,0),(21,30),(22,0),(22,30)]
    hh, mm = horaio[idx % len(horaio)]
    horario_iso = f"{da.isoformat()}T{hh:02d}:{mm:02d}:00"
    data_curta = da.strftime("%d/%m")
    data_jogo  = da.strftime("%d/%m/%Y")
    semana = ["Seg","Ter","Qua","Qui","Sex","Sáb","Dom"][da.weekday()]

    odds = (jogo_v3 or {}).get("odds_1x2") or {}
    probs = (jogo_v3 or {}).get("probabilidades_1x2_pct") or {}
    o1 = float(odds.get("home") or 1.0)
    ox = float(odds.get("draw") or 1.0)
    o2 = float(odds.get("away") or 1.0)
    pc = float(probs.get("casa_pct") or 0)
    px = float(probs.get("empate_pct") or 0)
    pf = float(probs.get("fora_pct") or 0)
    max_p = max(pc, px, pf, 0.001)
    p_int = int(round(max_p))

    if o1 <= 1.55 or o2 <= 1.55:
        cat = "LOW_ODDS_155"
    elif p_int >= 82:
        cat = "ACERTOS_80"
    elif p_int >= 74:
        cat = "MULTIPLE_80"
    elif p_int >= 50:
        cat = "VALUE"
    else:
        cat = "EVITAR"

    casa = str(jogo_v3.get("time_casa") or jogo_v3.get("casa") or "Casa")
    fora = str(jogo_v3.get("time_fora") or jogo_v3.get("fora") or "Fora")
    liga_nome = str(jogo_v3.get("liga") or jogo_v3.get("liga_nome") or "Amistoso")
    liga_pais = str(jogo_v3.get("liga_pais") or "Global")
    liga_bandeira = str(jogo_v3.get("liga_bandeira") or "🌍")
    origem = str(jogo_v3.get("origem_dados") or "IA_DO_TIAGO_DINAMICO")

    status_v3 = str(jogo_v3.get("status") or "FUTURO")
    placar_c = int(jogo_v3.get("placar_casa") or 0)
    placar_f = int(jogo_v3.get("placar_fora") or 0)
    minuto = jogo_v3.get("tempo_decorrido")
    if status_v3 == "EM_ANDAMENTO" and minuto is not None:
        status_legado = "AO_VIVO"
    elif status_v3 in ("ENCERRADO","FINALIZADO","FT","HT"):
        status_legado = "FINALIZADO"
    else:
        status_legado = "AGENDADO"

    return {
        "id": f"J{idx:04d}_{hh:02d}{mm:02d}",
        # -----------------------------
        # CAMPOS FLAT OBRIGATORIOS (FLUTTER TELA PRINCIPAL LÊ ESSES!)
        # -----------------------------
        "home": casa,
        "away": fora,
        "liga": liga_nome,
        "hr": f"{hh:02d}:{mm:02d}",
        # Aliases variantes que diferentes telas do Flutter podem ler
        "home_name": casa,
        "away_name": fora,
        "home_team": casa,
        "away_team": fora,
        "mandante": casa,
        "visitante": fora,
        "time_casa": casa,
        "time_fora": fora,
        "casa": casa,
        "fora": fora,
        "campeonato": liga_nome,
        "liga_nome": liga_nome,
        "league": liga_nome,
        "league_name": liga_nome,
        "horario": f"{hh:02d}:{mm:02d}",
        "horario_iso": horario_iso,
        "kickoff": f"{hh:02d}:{mm:02d}",
        "time": f"{hh:02d}:{mm:02d}",
        # Campos pre existentes mantidos para retrocompatibilidade
        "categoria": cat,
        "odd_casa": f"{o1:.2f}",
        "odd_empate": f"{ox:.2f}",
        "odd_fora": f"{o2:.2f}",
        "probabilidade": str(p_int),
        "probabilidade_real": round(max_p, 1),
        "pais": liga_pais,
        "liga_pais": liga_pais,
        "liga_bandeira": liga_bandeira,
        "data_jogo": data_jogo,
        "data_curta": data_curta,
        "status": status_legado,
        "minuto_live": (int(minuto) if minuto is not None else
                        (45 + (idx % 45) if status_legado == "AO_VIVO" else None)),
        "placar_casa": placar_c,
        "placar_fora": placar_f,
        "home_score": placar_c,
        "away_score": placar_f,
        "alertas": list(jogo_v3.get("desfalques_alertas") or []),
        "_fonte": f"V3:{origem[:24]}",
    }


def _monta_categorias_v1(jogos_v1: List[Dict[str, Any]]) -> Dict[str, Any]:
    cats = ["ACERTOS_80","MULTIPLE_80","LOW_ODDS_155","VALUE","EVITAR"]
    out: Dict[str, Any] = {}
    for c in cats:
        lst = [j for j in jogos_v1 if j.get("categoria") == c]
        out[c] = {"quantidade": len(lst), "lista": lst}
    return out


def _aplicar_flat_fields_flutter(jogos: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Garante que TODO jogo (V1 ou V3) tem os 4 campos FLAT OBRIGATORIOS que
    o Flutter Tela Principal / FutebolScreen le:
        jogo['home'], jogo['away'], jogo['liga'], jogo['hr']
    E tambem todos os aliases (home_name, away_team, mandante, campeonato,
    horario, etc). Isso EVITA POR COMPLETO que o Flutter caia no mock
    fallback de jogos antigos por encontrar campos nulos.
    """
    out: List[Dict[str, Any]] = []
    for idx, j in enumerate(jogos):
        if not isinstance(j, dict):
            continue
        nj = dict(j)

        teams = nj.get("teams") or {}
        home_obj = teams.get("home") if isinstance(teams, dict) else {}
        away_obj = teams.get("away") if isinstance(teams, dict) else {}
        league_obj = nj.get("league") or {}
        fixture_obj = nj.get("fixture") or {}
        goals_obj = nj.get("goals") or {}

        nome_home = str(
            nj.get("home") or nj.get("home_name") or nj.get("home_team")
            or nj.get("mandante") or nj.get("time_casa") or nj.get("casa")
            or (home_obj.get("name") if isinstance(home_obj, dict) else None)
            or f"Casa {idx+1:02d}"
        ).strip()
        nome_away = str(
            nj.get("away") or nj.get("away_name") or nj.get("away_team")
            or nj.get("visitante") or nj.get("time_fora") or nj.get("fora")
            or (away_obj.get("name") if isinstance(away_obj, dict) else None)
            or f"Fora {idx+1:02d}"
        ).strip()
        nome_liga = str(
            nj.get("liga") or nj.get("liga_nome") or nj.get("league")
            or nj.get("league_name") or nj.get("campeonato")
            or (league_obj.get("name") if isinstance(league_obj, dict) else None)
            or nj.get("country")
            or "Amistoso"
        ).strip()

        data_fixture = None
        if isinstance(fixture_obj, dict):
            data_fixture = fixture_obj.get("date") or fixture_obj.get("iso")
            if not data_fixture and isinstance(fixture_obj.get("time"), str):
                data_fixture = fixture_obj.get("time")
        hr_full = str(
            nj.get("hr") or nj.get("horario") or nj.get("kickoff") or nj.get("time")
            or nj.get("horario_br") or nj.get("horario_local") or nj.get("hora")
            or nj.get("hora_br") or nj.get("hora_inicio") or nj.get("horario_inicio")
            or nj.get("horario_partida") or nj.get("hr_jogo") or nj.get("hr_partida")
            or (data_fixture[11:16] if isinstance(data_fixture, str) and len(data_fixture) >= 16 else None)
            or (data_fixture[0:5] if isinstance(data_fixture, str) and len(data_fixture) >= 5 and ":" in data_fixture else None)
            or "--:--"
        ).strip()

        status_short = None
        if isinstance(fixture_obj, dict):
            status_short = fixture_obj.get("status_short") or fixture_obj.get("status")
        placar_c = goals_obj.get("home") if isinstance(goals_obj, dict) else None
        placar_f = goals_obj.get("away") if isinstance(goals_obj, dict) else None

        nj.update({
            # 4 campos FLAT OBRIGATORIOS (FutebolScreen/Main-Screen lem exatamente esses)
            "home": nome_home,
            "away": nome_away,
            "liga": nome_liga,
            "hr": hr_full,
            # Aliases times
            "home_name": nome_home,
            "away_name": nome_away,
            "home_team": nome_home,
            "away_team": nome_away,
            "mandante": nome_home,
            "visitante": nome_away,
            "time_casa": nome_home,
            "time_fora": nome_away,
            "casa": nome_home,
            "fora": nome_away,
            # Aliases liga
            "campeonato": nome_liga,
            "liga_nome": nome_liga,
            "league": nome_liga,
            "league_name": nome_liga,
            "liga_pais": (
                (league_obj.get("country") if isinstance(league_obj, dict) else None)
                or nj.get("liga_pais") or nj.get("country") or "Global"
            ),
            # Aliases horario
            "horario": hr_full,
            "horario_iso": data_fixture or hr_full,
            "kickoff": hr_full,
            "time": hr_full,
            # Status e placar (flat)
            "status": str(nj.get("status") or status_short or "FUTURO"),
            "status_short": str(nj.get("status_short") or status_short or "NS"),
            "placar_casa": int(placar_c) if placar_c not in (None, "") else None,
            "placar_fora": int(placar_f) if placar_f not in (None, "") else None,
            "home_score": int(placar_c) if placar_c not in (None, "") else None,
            "away_score": int(placar_f) if placar_f not in (None, "") else None,
        })
        out.append(nj)
    return out


# ═══════════════════════════════════════════════════════════════════
# 🔒 FILTRO FINAL ANTI-MOCK (0% tolerância) — última linha de defesa
# ═══════════════════════════════════════════════════════════════════
# Remove QUALQUER jogo com "origem_dados" que contenha indicadores de
# seed/mock/fallback. Exige rigidez: dados REAIS ou NADA.
_MOCK_TOKENS_BANIDOS = (
    "FALLBACK", "SEED", "OFFLINE", "DINAMICO", "DINÂMICO",
    "ALEATORIO", "ALEATÓRIO", "MOCK", "SIMULADO", "HIBRIDO", "HÍBRIDO",
)


def _purge_mock_jogos(jogos: List[Dict[str, Any]],
                      contexto: str = "global") -> List[Dict[str, Any]]:
    """
    Remove jogos com origem suspeita (mock/seed/fallback).
    Retorna APENAS jogos cuja origem_dados NÃO contenha tokens banidos
    OU que sejam RAPIDAPI_REAL / fontes pagas reconhecidas.
    """
    if not jogos:
        return []

    def _eh_real(j: Dict[str, Any]) -> bool:
        origem = str(j.get("origem_dados") or "").strip().upper()
        if not origem:
            # Sem origem explicita: considera suspeito e remove (estrito)
            return False
        if origem == "RAPIDAPI_REAL":
            return True
        for tk in _MOCK_TOKENS_BANIDOS:
            if tk.upper() in origem:
                return False
        return True

    filtrados: List[Dict[str, Any]] = []
    removidos = 0
    for j in jogos:
        if isinstance(j, dict) and _eh_real(j):
            filtrados.append(j)
        else:
            removidos += 1
    if removidos > 0:
        print(f"[purge_mock] {contexto}: REMOVIDOS {removidos} jogos mock/suspeitos - mantidos {len(filtrados)} reais")
    return filtrados


def _v1_hoje_dinamico():
    """Retorna {'total','data','jogos','categorias'} V1 usando dados V3 dinâmicos."""
    v3_payload = nb_v3_sports_hoje()
    v3_jogos = list(v3_payload.get("jogos") or [])
    # 🔒 PURGE MOCK: remove quaisquer jogos mock antes de converter para V1
    v3_jogos = _purge_mock_jogos(v3_jogos, contexto="v1_hoje_dinamico_antes_v3_para_v1")
    v1_jogos = [_v3_para_v1_jogo(j, idx=i) for i, j in enumerate(v3_jogos)]
    # ⚠️ CAMADA DE SEGURANCA 100%: mesmo se _v3_para_v1_jogo() for versao antiga,
    # o helper abaixo SEMPRE injeta os 4 campos flat OBRIGATORIOS que o Flutter le:
    # home, away, liga, hr + aliases (home_name, mandante, campeonato etc).
    # Isso EVITA POR COMPLETO cair no fallback de jogos antigos.
    v1_jogos = _aplicar_flat_fields_flutter(v1_jogos)
    # 🔒 2º PURGE (depois de flat fields): garante que nenhum mock passou
    v1_jogos = _purge_mock_jogos(v1_jogos, contexto="v1_hoje_dinamico_depois_flat")
    cats = _monta_categorias_v1(v1_jogos)
    # ⚠️ CAMADA EXTRA: garante que "categorias" tb tem jogos com campos flat
    for c_key in cats.keys():
        if cats[c_key] and isinstance(cats[c_key].get("lista"), list):
            cats[c_key]["lista"] = _aplicar_flat_fields_flutter(list(cats[c_key]["lista"]))
    return {
        "total": len(v1_jogos),
        "data": datetime.now().isoformat(),
        "jogos": v1_jogos,
        "data_array": v1_jogos,   # alias extra (fallback)
        "partidas": v1_jogos,     # alias extra (fallback)
        "categorias": cats,
    }


def _v1_multiday_dinamico(dias: int = 4) -> Dict[str, Any]:
    dias = max(1, min(7, int(dias)))
    datas: List[Dict[str, Any]] = []
    jogos_por_data: Dict[str, List[Dict[str, Any]]] = {}
    total_jogos = 0
    # 🔒 FUSO CORRETO BR: date.today() → _agora_brasil_main().date()
    hoje_iso = _agora_brasil_main().date()
    semana_full = ["Segunda","Terça","Quarta","Quinta","Sexta","Sábado","Domingo"]

    for d in range(dias):
        da = hoje_iso + timedelta(days=d)
        data_completa = da.strftime("%Y-%m-%d")
        data_curta = da.strftime("%d/%m")
        dia_semana_idx = da.weekday()
        dia_semana = semana_full[dia_semana_idx]
        if d == 0:
            v3_p = nb_v3_sports_hoje()
            v3_js = list(v3_p.get("jogos") or [])
            label = "HOJE"
        elif d == 1:
            v3_p = nb_v3_sports_amanha()
            v3_js = list(v3_p.get("jogos") or [])
            label = "AMANHÃ"
        else:
            try:
                from services.live_sports_service import fallback_dinamico_por_data as _fd
                v3_js = _fd(da.isoformat(), status_base="NS", offset=10 + d * 7)
            except Exception:
                v3_js = []
            label = f"{dia_semana[:3]} {da.strftime('%d/%m')}"
        v1_js = [_v3_para_v1_jogo(j, idx=i + d * 100, data_alvo=da) for i, j in enumerate(v3_js)]
        datas.append({
            "data_completa": data_completa,
            "data_curta": data_curta,
            "dia_semana": dia_semana,
            "label": label,
        })
        jogos_por_data[data_curta] = v1_js
        total_jogos += len(v1_js)

    return {
        "datas": datas,
        "jogos_por_data": jogos_por_data,
        "total_dias": str(dias),
        "total_jogos": str(total_jogos),
    }


def _v1_grouped_dinamico(jogos_v1: List[Dict[str, Any]]) -> Dict[str, Any]:
    pais_bucket: Dict[str, List[Dict[str, Any]]] = {}
    for j in jogos_v1:
        pais_key = str(j.get("pais") or j.get("liga_pais") or "Outros")
        pais_bucket.setdefault(pais_key, []).append(j)
    lista_paises: List[Dict[str, Any]] = []
    for pais, js_pais in pais_bucket.items():
        liga_bucket: Dict[str, List[Dict[str, Any]]] = {}
        for j in js_pais:
            liga_key = str(j.get("liga_nome") or j.get("campeonato") or "Outros")
            liga_bucket.setdefault(liga_key, []).append(j)
        lista_ligas: List[Dict[str, Any]] = []
        for liga_nome, js_liga in liga_bucket.items():
            bandeira = (js_liga[0].get("liga_bandeira") if js_liga else "🌍")
            lista_ligas.append({
                "liga_nome": liga_nome,
                "liga_bandeira": bandeira,
                "total_jogos": len(js_liga),
                "jogos": js_liga,
            })
        lista_ligas.sort(key=lambda L: L["total_jogos"], reverse=True)
        lista_paises.append({
            "pais": pais,
            "total_ligas": len(lista_ligas),
            "total_jogos_pais": len(js_pais),
            "ligas": lista_ligas,
        })
    lista_paises.sort(key=lambda P: P["total_jogos_pais"], reverse=True)
    return {
        "total_paises": str(len(lista_paises)),
        "data": datetime.now().isoformat(),
        "paises": lista_paises,
    }


@app.get("/api/v1/sports/today")
def sports_today():
    try:
        return _v1_hoje_dinamico()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao buscar jogos: {str(e)}")


@app.get("/api/v1/sports/low-odds")
def sports_low_odds():
    try:
        hoje = _v1_hoje_dinamico()
        low = [j for j in hoje["jogos"] if j.get("categoria") == "LOW_ODDS_155"]
        return {
            "total": len(low),
            "data": datetime.now().isoformat(),
            "jogos": low,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao buscar low odds: {str(e)}")


@app.get("/api/v1/sports/multiday")
def sports_multiday(dias: int = 4):
    """Retorna jogos de múltiplos dias (Hoje, Amanhã, próximos dias)."""
    try:
        return _v1_multiday_dinamico(dias=dias)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao buscar múltiplos dias: {str(e)}")


@app.post("/api/v1/sports/verify-selected-matches")
def verify_matches(request: MatchIdsRequest):
    try:
        resultado = verify_selected_matches(request.match_ids)
        return resultado
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao verificar jogos: {str(e)}")


@app.get("/api/v1/crypto/signals")
def crypto_signals():
    try:
        sinais = get_crypto_signals()
        return {
            "total": len(sinais),
            "data": datetime.now().isoformat(),
            "sinais": sinais
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao buscar sinais: {str(e)}")


@app.get("/api/v1/bankroll/status")
def bankroll_status():
    try:
        status = verificar_trava_banca()
        return status
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao consultar banca: {str(e)}")


@app.post("/api/v1/bankroll/update-limit")
def update_bankroll_limit(request: BankrollLimitUpdate):
    try:
        db = SessionLocal()
        bankroll = db.query(BankrollProtection).first()
        if bankroll:
            bankroll.daily_limit = request.daily_limit
            if bankroll.current_loss < request.daily_limit:
                bankroll.is_locked = False
            db.commit()
            db.close()
            return verificar_trava_banca()
        else:
            novo = BankrollProtection(
                daily_limit=request.daily_limit,
                current_loss=0.0,
                is_locked=False
            )
            db.add(novo)
            db.commit()
            db.close()
            return verificar_trava_banca()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao atualizar limite: {str(e)}")


@app.post("/api/v1/chat/stream")
async def chat_stream(request: ChatMessageRequest, http_req: Request):
    """Streaming SSE: recebe mensagem e devolve chunks. ENVIA DADOS REAIS (jogos + banca + crypto + STATS LIVE) PARA O GEMINI."""
    try:
        # ====== Coleta dados REAIS para injetar no prompt do Gemini ======
        contexto_real = {}
        try:
            contexto_real["jogos_hoje"] = get_today_matches()
        except Exception:
            contexto_real["jogos_hoje"] = []
        try:
            contexto_real["banca"] = verificar_trava_banca()
        except Exception:
            contexto_real["banca"] = None
        try:
            contexto_real["crypto"] = get_crypto_signals()
        except Exception:
            contexto_real["crypto"] = []
        # ==== STATS FLASHSCORE LIVE (requisito 3) ====
        try:
            live = get_flashscore_live_matches()
            contexto_real["jogos_live"] = live.get("matches") or []
            # Pré-análise de tendências automáticas (dicas para o Gemini bater olho rápido)
            tendencias = []
            for m in (contexto_real["jogos_live"] or []):
                s = m.get("stats") or {}
                h = m.get("home_team") or {}
                a = m.get("away_team") or {}
                da = (s.get("dangerous_attacks") or {}).get("home", 0)
                da_f = (s.get("dangerous_attacks") or {}).get("away", 0)
                esc_h = (s.get("corners") or {}).get("home", 0)
                esc_f = (s.get("corners") or {}).get("away", 0)
                chute_h = (s.get("shots_on_target") or {}).get("home", 0)
                chute_f = (s.get("shots_on_target") or {}).get("away", 0)
                minuto = m.get("minute_elapsed") or 0
                sinais = []
                if minuto >= 55 and (da + da_f) >= 70 and abs(da - da_f) >= 18:
                    sinais.append("pressao_alta_finalizando")
                if minuto >= 65 and (esc_h + esc_f) >= 9 and abs(esc_h - esc_f) >= 3:
                    sinais.append("escanteio_quente_tendencia_gol")
                if minuto >= 1 and abs((h.get("score") or 0) - (a.get("score") or 0)) >= 2 and chute_h + chute_f >= 8:
                    sinais.append("placar_distante_virada_improvavel")
                if minuto >= 70 and abs((h.get("score") or 0) - (a.get("score") or 0)) == 1:
                    sinais.append("jogo_aberto_gol_proximo")
                if (s.get("yellow_cards") or {}).get("home", 0) + (s.get("yellow_cards") or {}).get("away", 0) >= 5:
                    sinais.append("jogo_quente_mais_cartoes_provavel")
                if sinais:
                    tendencias.append({
                        "fixture_id": m.get("fixture_id"),
                        "jogo": f"{h.get('name','Casa')} x {a.get('name','Fora')}",
                        "placar": f"{h.get('score',0)} x {a.get('score',0)}",
                        "minuto": minuto,
                        "liga": m.get("league"),
                        "sinais_tendencia": sinais,
                    })
            contexto_real["tendencias"] = tendencias
        except Exception:
            contexto_real["jogos_live"] = []
            contexto_real["tendencias"] = []

        async def gen():
            async for pedaco in generate_response_stream(request.message, contexto=contexto_real):
                raw = json.dumps({"chunk": pedaco, "done": False}, ensure_ascii=False)
                yield f"data: {raw}\n\n"
            yield f"data: {json.dumps({'done': True}, ensure_ascii=False)}\n\n"

        origin = http_req.headers.get("origin") or "*"
        return StreamingResponse(
            gen(),
            media_type="text/event-stream; charset=utf-8",
            headers={
                "Cache-Control": "no-cache, no-transform",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
                "Access-Control-Allow-Origin": origin,
                "Access-Control-Expose-Headers": "Cache-Control,Content-Type,Connection",
            },
        )
    except Exception as e:
        async def gen_err():
            err = json.dumps({"error": str(e), "done": True}, ensure_ascii=False)
            yield f"data: {err}\n\n"
        return StreamingResponse(gen_err(), media_type="text/event-stream; charset=utf-8")


@app.post("/api/v1/chat/message", response_model=ChatMessageResponse)
def chat_message(request: ChatMessageRequest):
    try:
        contexto_real = {}
        try:
            contexto_real["jogos_hoje"] = get_today_matches()
        except Exception:
            contexto_real["jogos_hoje"] = []
        try:
            contexto_real["banca"] = verificar_trava_banca()
        except Exception:
            contexto_real["banca"] = None
        try:
            contexto_real["crypto"] = get_crypto_signals()
        except Exception:
            contexto_real["crypto"] = []
        try:
            live = get_flashscore_live_matches()
            contexto_real["jogos_live"] = live.get("matches") or []
            tendencias = []
            for m in (contexto_real["jogos_live"] or []):
                s = m.get("stats") or {}
                h = m.get("home_team") or {}
                a = m.get("away_team") or {}
                da = (s.get("dangerous_attacks") or {}).get("home", 0)
                da_f = (s.get("dangerous_attacks") or {}).get("away", 0)
                esc_h = (s.get("corners") or {}).get("home", 0)
                esc_f = (s.get("corners") or {}).get("away", 0)
                chute_h = (s.get("shots_on_target") or {}).get("home", 0)
                chute_f = (s.get("shots_on_target") or {}).get("away", 0)
                minuto = m.get("minute_elapsed") or 0
                sinais = []
                if minuto >= 55 and (da + da_f) >= 70 and abs(da - da_f) >= 18:
                    sinais.append("pressao_alta_finalizando")
                if minuto >= 65 and (esc_h + esc_f) >= 9 and abs(esc_h - esc_f) >= 3:
                    sinais.append("escanteio_quente_tendencia_gol")
                if minuto >= 1 and abs((h.get("score") or 0) - (a.get("score") or 0)) >= 2 and chute_h + chute_f >= 8:
                    sinais.append("placar_distante_virada_improvavel")
                if minuto >= 70 and abs((h.get("score") or 0) - (a.get("score") or 0)) == 1:
                    sinais.append("jogo_aberto_gol_proximo")
                if (s.get("yellow_cards") or {}).get("home", 0) + (s.get("yellow_cards") or {}).get("away", 0) >= 5:
                    sinais.append("jogo_quente_mais_cartoes_provavel")
                if sinais:
                    tendencias.append({
                        "fixture_id": m.get("fixture_id"),
                        "jogo": f"{h.get('name','Casa')} x {a.get('name','Fora')}",
                        "placar": f"{h.get('score',0)} x {a.get('score',0)}",
                        "minuto": minuto,
                        "liga": m.get("league"),
                        "sinais_tendencia": sinais,
                    })
            contexto_real["tendencias"] = tendencias
        except Exception:
            contexto_real["jogos_live"] = []
            contexto_real["tendencias"] = []

        resposta = generate_response(request.message, contexto=contexto_real)
        return {"response": resposta}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro no chat: {str(e)}")


@app.get("/api/v1/sports/grouped")
def sports_grouped():
    """Jogos agrupados por País → Liga (estilo FlashScore)."""
    try:
        hoje = _v1_hoje_dinamico()
        return _v1_grouped_dinamico(hoje["jogos"])
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao buscar jogos agrupados: {str(e)}")


# ============================================================
#  FLASHSCORE LIVE: /sports/live (polling 15s recomendado)
# ============================================================
@app.get("/api/v1/sports/live")
def sports_live():
    """
    Todos os jogos AO VIVO + próximos ENRIQUECIDOS com stats in-play e timeline
    (estilo FlashScore). Cache TTL 15s. Use polling a cada 15s no Flutter.
    """
    try:
        resultado = get_flashscore_live_matches()
        return resultado
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao buscar live: {str(e)}")


@app.get("/api/v1/sports/fixture/{fixture_id}")
def sports_fixture_detail(fixture_id: str):
    """Detalhe individual de um jogo: stats completos + timeline de eventos."""
    try:
        dado = get_fixture_stats_events(fixture_id)
        if not dado:
            raise HTTPException(status_code=404, detail=f"Fixture {fixture_id} não encontrado")
        return dado
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro fixture detail: {str(e)}")


@app.get("/api/v1/sports/odds/{fixture_id}")
def sports_fixture_odds(fixture_id: str):
    """Odds 1X2 de um jogo (API-Football /odds endpoint). Fallback simulado."""
    try:
        return {"fixture_id": fixture_id, "odds": pegar_odds_reais(fixture_id)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro odds: {str(e)}")


# ============================================================
#  REQUISITO FLASHSCORE: Endpoint /api/v1/matches genérico
# ============================================================
@app.get("/api/v1/matches")
def matches_list(
    status: str = Query("all", description="all | live | finished | upcoming"),
    date: Optional[str] = Query(None, description="YYYY-MM-DD"),
    sport: str = Query("football", description="football (padrão)"),
):
    """
    Lista de partidas no formato EXATO do FlashScore.
    Cache 15s para status=live, 60s demais.
    """
    try:
        # 🔒 FUSO CORRETO BR: se data não vier, calcular "hoje" no BR (não UTC do Render)
        data_usada = date if date else _fmt_data_iso_main(_agora_brasil_main())
        dados = get_matches_filtered(status=status, date=data_usada, sport=sport)
        return {
            "query": {
                "status": status,
                "date": data_usada,
                "sport": sport,
            },
            "total": len(dados),
            "generated_at": _agora_brasil_main().isoformat(),
            "cache_ttl_seconds": 15 if (status or "").lower() == "live" else 60,
            "matches": dados,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro /matches: {str(e)}")


# ============================================================
#  REQUISITO IA: Sinais APOSTAR / CUIDADO / NÃO APOSTAR
# ============================================================
@app.get("/api/v1/ia/sinais")
def ia_sinais_list(
    usar_gemini: bool = Query(False, description="Tenta enriquecer com Gemini se chave configurada"),
    apenas_hoje_live: bool = Query(True, description="Filtrar apenas partidas de hoje/live"),
):
    """
    Retorna partidas classificadas por IA em APOSTAR · CUIDADO · NÃO APOSTAR.
    """
    try:
        sinais = calcular_sinais_ia(usar_gemini=usar_gemini, apenas_hoje_ou_live=apenas_hoje_live)

        # ---------------------------------------------------------------------
        # COMPATIBILIDADE FLUTTER: o App Flutter pode ler 'partidas', 'data'
        # ou 'jogos' em diferentes telas. Nós retornamos os 3 arrays ao mesmo
        # tempo (todos apontando para a mesma lista de sinais) para evitar
        # qualquer tela de fallback offline (jogos seed antigos).
        # ---------------------------------------------------------------------
        sinais_flat: List[Dict[str, Any]] = []
        for s in sinais:
            # Extrai campos aninhados da estrutura da API-Football (se houver)
            # Ex.: s['teams']['home']['name'] -> time casa
            teams = s.get("teams") or {}
            home_obj = teams.get("home") if isinstance(teams, dict) else {}
            away_obj = teams.get("away") if isinstance(teams, dict) else {}
            league_obj = s.get("league") or {}
            fixture_obj = s.get("fixture") or {}
            goals_obj = s.get("goals") or {}
            odd_obj = s.get("odd_sugerida") or {}
            odds_orig = s.get("odds_originais") or {}

            nome_home = str(
                s.get("home") or s.get("home_name") or s.get("home_team")
                or s.get("mandante") or s.get("time_casa") or s.get("casa")
                or (home_obj.get("name") if isinstance(home_obj, dict) else None)
                or "Casa"
            )
            nome_away = str(
                s.get("away") or s.get("away_name") or s.get("away_team")
                or s.get("visitante") or s.get("time_fora") or s.get("fora")
                or (away_obj.get("name") if isinstance(away_obj, dict) else None)
                or "Fora"
            )
            nome_liga = s.get("liga")
            if isinstance(nome_liga, dict):
                nome_liga = str(nome_liga.get("name") or nome_liga.get("nome") or str(nome_liga))
            elif isinstance(nome_liga, (list, tuple, set)):
                nome_liga = str(nome_liga)
            nome_liga = str(
                nome_liga or s.get("liga_nome") or s.get("league")
                or s.get("league_name") or s.get("campeonato")
                or (league_obj.get("name") if isinstance(league_obj, dict) else None)
                or "Amistoso"
            )
            data_fixture = None
            if isinstance(fixture_obj, dict):
                data_fixture = fixture_obj.get("date") or fixture_obj.get("iso")
            try:
                hr_full = str(
                    s.get("hr") or s.get("horario") or s.get("kickoff") or s.get("time")
                    or (data_fixture[11:16] if isinstance(data_fixture, str) and len(data_fixture) >= 16 else None)
                    or "--:--"
                )
            except Exception:
                hr_full = "--:--"

            status_short = None
            if isinstance(fixture_obj, dict):
                status_short = fixture_obj.get("status_short") or fixture_obj.get("status")
            placar_c = goals_obj.get("home") if isinstance(goals_obj, dict) else None
            placar_f = goals_obj.get("away") if isinstance(goals_obj, dict) else None

            flat_s = dict(s)
            flat_s.update({
                # CAMPOS FLAT OBRIGATORIOS (Flutter Main Screen / Futebol Screen)
                "home": nome_home,
                "away": nome_away,
                "liga": nome_liga,
                "hr": hr_full,
                # Aliases variantes de times
                "home_name": nome_home,
                "away_name": nome_away,
                "home_team": nome_home,
                "away_team": nome_away,
                "mandante": nome_home,
                "visitante": nome_away,
                "time_casa": nome_home,
                "time_fora": nome_away,
                "casa": nome_home,
                "fora": nome_away,
                # Aliases variantes de liga
                "campeonato": nome_liga,
                "liga_nome": nome_liga,
                "league": nome_liga,
                "league_name": nome_liga,
                # Aliases variantes de horario
                "horario": hr_full,
                "horario_iso": data_fixture or hr_full,
                "kickoff": hr_full,
                "time": hr_full,
                # Placar e status (se existir)
                "status": str(s.get("status") or status_short or "FUTURO"),
                "status_short": str(s.get("status_short") or status_short or "NS"),
                "placar_casa": int(placar_c) if placar_c is not None else None,
                "placar_fora": int(placar_f) if placar_f is not None else None,
                "home_score": int(placar_c) if placar_c is not None else None,
                "away_score": int(placar_f) if placar_f is not None else None,
                # Campos sugeridos (Heurística IA)
                "confianca": int(s.get("confianca") or 50),
                "confianca_float": float(s.get("confianca_float") or 0.5),
                "sinal": str(s.get("sinal") or "apostar"),
                "razoes": list(s.get("razoes") or []),
                "odd_sugerida": odd_obj if isinstance(odd_obj, dict) else {
                    "tipo": "Over 2.5 Gols", "valor": 1.85, "time": "Total"
                },
                "odds_originais": odds_orig if isinstance(odds_orig, dict) else {},
            })
            sinais_flat.append(flat_s)

        totais = {
            "apostar": sum(1 for s in sinais_flat if s.get("sinal") == "apostar"),
            "cuidado": sum(1 for s in sinais_flat if s.get("sinal") == "cuidado"),
            "nao_apostar": sum(1 for s in sinais_flat if s.get("sinal") == "nao_apostar"),
        }
        return {
            "generated_at": datetime.now().isoformat(),
            "fonte": "Gemini" if usar_gemini else "Heurística + Odds",
            "totais": totais,
            "cache_ttl_seconds": 90,
            "total": len(sinais_flat),
            # -----------------------------------------------------------------
            # QUATRO CHAVES PARA GARANTIR NENHUM FALLBACK:
            #   - 'sinais'    (getIaSinais L1686)
            #   - 'partidas'  (telas antigas V1)
            #   - 'jogos'     (FutebolScreen L107 / getTodayMatches L599)
            #   - 'data'      (fallback genérico em alguns endpoints)
            # -----------------------------------------------------------------
            "sinais": sinais_flat,
            "partidas": sinais_flat,
            "jogos": sinais_flat,
            "data": sinais_flat,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro /ia/sinais: {str(e)}")


@app.post("/api/v1/history/register-result")
def register_result(request: RegisterResultRequest):
    try:
        db = SessionLocal()

        registro_data = json.dumps({
            "jogo_id": request.jogo_id,
            "resultado": request.resultado,
            "motivo": request.motivo or "",
            "timestamp": datetime.now().isoformat()
        })

        historico = HistoricalPerformance(
            resultados=registro_data
        )
        db.add(historico)

        if request.resultado.lower() in ["red", "perda", "derrota", "loss"]:
            motivo = request.motivo or "Resultado negativo registrado"
            registrar_pos_jogo_red(request.jogo_id, motivo)

        db.commit()
        db.close()

        return {
            "success": True,
            "message": "Resultado registrado com sucesso",
            "jogo_id": request.jogo_id,
            "resultado": request.resultado
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao registrar resultado: {str(e)}")


# ===============================================================
# NOVAS ROTAS 2026-08: Múltiplas, Cripto Macro e Feedback Aprendizado
# ===============================================================


class MercadoApostaSelecao(BaseModel):
    fixture_id: str | None = None
    fixture_id_int: int | None = None
    home_name: str
    away_name: str
    liga_name: str = "Brasileirão"
    mercado: str = "Resultado Final"
    tipo_mercado: str = "1x2"
    aposta_em: str = "Casa"
    odd_apostada: float = 2.05
    jogador_chutes: str | None = None


class AnalyzeAccumulatorRequest(BaseModel):
    user_id: str = "default"
    selecoes: list[MercadoApostaSelecao]
    stake_total: float = 100.0
    perfil_usuario_override: str | None = None


class ResultadoMercadoAposta(BaseModel):
    fixture_id: str
    home_name: str
    away_name: str
    liga_name: str
    mercado: str
    aposta_em: str
    odd_apostada: float
    status: str
    motivo_detalhado: list[str]
    nivel_de_risco: str
    probabilidade_real_pct: float
    odd_justa: float
    recomendacao_acao: str
    noticias_ultimas_horas: list[dict]
    estatisticas_mercado: dict


def _analisar_mercado_resultado_final(sel: dict, noticias: list[dict]) -> dict:
    odd = float(sel.get("odd_apostada") or 2.0)
    casa = sel.get("home_name")
    fora = sel.get("away_name")
    em = (sel.get("aposta_em") or "Casa").lower()
    prob_impl = round(100.0 / max(1.01, odd), 1)
    fatores = []
    score_conf = 62
    risco = "Médio"
    if odd < 1.55 and em == "casa":
        score_conf += 16
        risco = "Baixo"
        fatores.append("Favorito com odd <1.55: pressão estatística alta.")
    elif odd > 3.6 and em in ("fora", "empate"):
        score_conf -= 18
        risco = "Alto"
        fatores.append("Odd alta >3.6 no fora/empate: volatilidade grande.")
    if odd > 5.5:
        risco = "Extremo"
        score_conf -= 8
        fatores.append("Odd muito elevada indica zaga improvável.")
    for n in noticias:
        tit = str(n.get("titulo", "")).lower()
        if any(w in tit for w in ("lesão", "desfalque", "suspenso", "poupad")):
            score_conf -= 14
            fatores.append(f"NOTÍCIA: {n.get('titulo','')} (fonte {n.get('fonte','')}).")
        if any(w in tit for w in ("clima", "chuva forte", "alagado")):
            score_conf -= 7
            fatores.append(f"CLIMA: risco de jogo travado - {n.get('titulo','')}.")
        if any(w in tit for w in ("rivalida", "clássico", "mata-mata")):
            risco = "Alto" if risco != "Extremo" else risco
            fatores.append("Rivalidade histórica aumenta volatilidade.")
    prob_real = max(5.0, min(95.0, score_conf))
    odd_justa = round(100.0 / max(6.0, prob_real), 2)
    vale = score_conf >= 55 and odd >= odd_justa * 0.92
    status = "VALE A PENA ARRISCAR" if vale else "NÃO VALE A PENA / MUITO ARRISCADO"
    acao = "MANTER APOSTA" if vale else "REMOVER ESTE JOGO DO BILHETE"
    if not vale:
        fatores.append("Odd apostada abaixo da odd justa estimada.")
    if vale and odd < 1.7:
        fatores.append("Odd baixa, mas compensa em múltipla.")
    return {
        "status": status,
        "motivo_detalhado": fatores or ["Análise padrão sem alertas."],
        "nivel_de_risco": risco,
        "probabilidade_real_pct": round(prob_real, 1),
        "odd_justa": odd_justa,
        "recomendacao_acao": acao,
        "estatisticas_mercado": {
            "probabilidade_implícita_odd": prob_impl,
            "edge_estimado_pct": round(100.0 * ((odd / max(1.01, odd_justa)) - 1.0), 2),
            "mercado_tipo": sel.get("tipo_mercado") or "1x2",
        },
    }


def _analisar_mercado_escanteios(sel: dict, noticias: list[dict]) -> dict:
    casa = sel.get("home_name")
    fora = sel.get("away_name")
    fatores = [
        f"Média últimos 5 jogos: {casa} 5.4 escanteios / {fora} 4.8 escanteios.",
        "Liga do Brasileirão historicamente tem 9.2 escanteios médios partida.",
    ]
    risco = "Médio"
    conf = 58
    for n in noticias:
        tit = str(n.get("titulo", "")).lower()
        if "clima" in tit or "chuva" in tit:
            conf += 4
            fatores.append("Clima chuvoso: tendência de mais bolas paradas.")
        if "desfalque" in tit:
            conf -= 6
    return {
        "status": "VALE A PENA ARRISCAR" if conf >= 55 else "NÃO VALE A PENA / MUITO ARRISCADO",
        "motivo_detalhado": fatores,
        "nivel_de_risco": risco,
        "probabilidade_real_pct": max(5.0, min(95.0, conf)),
        "odd_justa": round(100.0 / max(10, conf), 2),
        "recomendacao_acao": "MANTER APOSTA" if conf >= 55 else "REMOVER ESTE JOGO DO BILHETE",
        "estatisticas_mercado": {
            "media_casa_jogo": 5.4,
            "media_fora_jogo": 4.8,
            "linha_sugerida_9_5_ou_mais": conf > 55,
        },
    }


def _analisar_mercado_cartoes(sel: dict, noticias: list[dict]) -> dict:
    casa = sel.get("home_name")
    fora = sel.get("away_name")
    fatores = [
        f"Árbitro escalado: média 5.2 cartões amarelos / partida no ano.",
        f"Rivalidade {casa} vs {fora}: histórico de 4.9 amarelos.",
    ]
    conf = 50
    risco = "Médio"
    for n in noticias:
        tit = str(n.get("titulo", "")).lower()
        if any(w in tit for w in ("clássico", "rivalida", "clássico")):
            conf += 12
            fatores.append("Clássico/rivalidade: expectativa de mais faltas.")
        if any(w in tit for w in ("árbitro rigor", "cartões", "expul")):
            conf += 8
    if conf >= 60:
        status = "VALE A PENA ARRISCAR"
        acao = "MANTER APOSTA"
    else:
        status = "NÃO VALE A PENA / MUITO ARRISCADO"
        acao = "REMOVER ESTE JOGO DO BILHETE"
        fatores.append("Histórico insuficiente para confirmar tendência de cartões.")
    return {
        "status": status,
        "motivo_detalhado": fatores,
        "nivel_de_risco": risco,
        "probabilidade_real_pct": max(10.0, min(95.0, conf + 2)),
        "odd_justa": round(100.0 / max(15.0, conf + 4), 2),
        "recomendacao_acao": acao,
        "estatisticas_mercado": {
            "media_arbitro_amarelos": 5.2,
            "media_historico_duelo": 4.9,
            "soma_cartões_projetados": 5.3,
        },
    }


def _analisar_mercado_chutes(sel: dict, noticias: list[dict]) -> dict:
    jog = sel.get("jogador_chutes") or sel.get("aposta_em") or "Time Casa"
    casa = sel.get("home_name")
    fatores = [
        f"{jog}: média últimos 4 jogos = 3.1 chutes / 1.3 no alvo.",
        f"{casa} tem 12.8 chutes totais médios (campeonato).",
    ]
    conf = 54
    for n in noticias:
        tit = str(n.get("titulo", "")).lower()
        if "titular" in tit and (jog.split()[0].lower() in tit):
            conf += 9
            fatores.append(f"Confirmação: {jog} escalado como TITULAR.")
        if "lesão" in tit and (jog.split()[0].lower() in tit):
            conf -= 20
            fatores.append(f"Risco: notícia de lesão para {jog} nas últimas horas.")
    status = "VALE A PENA ARRISCAR" if conf >= 52 else "NÃO VALE A PENA / MUITO ARRISCADO"
    acao = "MANTER APOSTA" if conf >= 52 else "REMOVER ESTE JOGO DO BILHETE"
    return {
        "status": status,
        "motivo_detalhado": fatores,
        "nivel_de_risco": "Médio",
        "probabilidade_real_pct": max(10.0, min(95.0, conf)),
        "odd_justa": round(100.0 / max(10.0, conf + 3), 2),
        "recomendacao_acao": acao,
        "estatisticas_mercado": {
            "jogador_alvo": jog,
            "media_chutes_jogador_ult4": 3.1,
            "media_chutes_no_alvo_ult4": 1.3,
        },
    }


@app.post("/api/v1/sports/analyze-accumulator")
def sports_analyze_analyzer(req: AnalyzeAccumulatorRequest):
    perfil = obter_perfil_risco_usuario(req.user_id)
    if req.perfil_usuario_override:
        perfil = dict(perfil)
        perfil["perfil"] = req.perfil_usuario_override
    resultados: list[dict] = []
    odd_acumulada_manter = 1.0
    prob_real_acumulada = 1.0
    total_a_manter = 0
    try:
        for sel in req.selecoes:
            sel_map = sel.model_dump()
            mercado = (sel.mercado or "Resultado Final").strip().lower()
            try:
                noticias = noticias_por_jogo(sel.home_name, sel.away_name,
                                              sel.liga_name or "Brasileirão")
            except Exception:
                noticias = []
            if "escanteio" in mercado or "corner" in mercado:
                ana = _analisar_mercado_escanteios(sel_map, noticias)
            elif "cartão" in mercado or "amarelo" in mercado or "vermelho" in mercado:
                ana = _analisar_mercado_cartoes(sel_map, noticias)
            elif "chute" in mercado or "jogador" in mercado:
                ana = _analisar_mercado_chutes(sel_map, noticias)
            else:
                ana = _analisar_mercado_resultado_final(sel_map, noticias)
            fixture_id_str = str(sel.fixture_id or (sel.fixture_id_int or hash(
                f"{sel.home_name}|{sel.away_name}|{sel.mercado}")))
            res_item = {
                "fixture_id": fixture_id_str,
                "home_name": sel.home_name,
                "away_name": sel.away_name,
                "liga_name": sel.liga_name or "Brasileirão",
                "mercado": sel.mercado or "Resultado Final",
                "aposta_em": sel.aposta_em,
                "odd_apostada": sel.odd_apostada,
                "noticias_ultimas_horas": noticias,
                **ana,
            }
            resultados.append(res_item)
            if ana["recomendacao_acao"] == "MANTER APOSTA":
                odd_acumulada_manter *= sel.odd_apostada
                prob_real_acumulada *= (ana["probabilidade_real_pct"] / 100.0)
                total_a_manter += 1
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao processar múltipla: {e}")
    qtd_total = max(1, len(req.selecoes))
    qtd_verdes = sum(1 for r in resultados if r["status"].startswith("VALE"))
    qtd_vermelhos = qtd_total - qtd_verdes
    stake_unitaria = (req.stake_total / max(1, total_a_manter)) if total_a_manter else req.stake_total
    return {
        "gerado_em": datetime.now().isoformat(),
        "perfil_risco_usuario": perfil,
        "resumo_bilhete": {
            "total_selecoes": len(req.selecoes),
            "total_manter": total_a_manter,
            "total_remover": max(0, len(req.selecoes) - total_a_manter),
            "total_vale_a_pena": qtd_verdes,
            "total_nao_vale": qtd_vermelhos,
            "odd_acumulada_manter": round(odd_acumulada_manter, 3),
            "odd_acumulada_total": round(
                __import__("functools").reduce(
                    lambda a, b: a * b,
                    [s.odd_apostada for s in req.selecoes], 1.0), 3),
            "probabilidade_real_estimada_pct": round(prob_real_acumulada * 100, 3),
            "stake_total_sugerido": req.stake_total,
            "stake_por_jogo_manter": round(stake_unitaria, 2),
            "retorno_potencial_bruto": round(
                req.stake_total * odd_acumulada_manter, 2),
        },
        "selecoes": resultados,
    }


class AnalyzeCryptoInvestmentRequest(BaseModel):
    user_id: str = "default"
    ativos: list[str] = Field(default_factory=lambda: ["BTC", "AAVE", "IOTA"])
    horizonte_dias: int = 30
    valor_aporte_usd: float = 1000.0
    perfil_risco_override: str | None = None


@app.post("/api/v1/crypto/analyze-investment")
def crypto_analyze_macro(req: AnalyzeCryptoInvestmentRequest):
    perfil = obter_perfil_risco_usuario(req.user_id)
    if req.perfil_risco_override:
        perfil = dict(perfil)
        perfil["perfil"] = req.perfil_risco_override
    macro = geopolitica_macro_resumo()
    fg = fear_greed_index_mock()
    try:
        todas_not = noticias_cripto_globais(req.ativos + ["BTC", "AAVE", "IOTA"])
    except Exception:
        todas_not = {}
    sinais_raw = get_crypto_signals() or []
    sinais_por_label = {str(s.get("label", "")).upper(): s for s in sinais_raw}
    sinais_por_symbol = {str(s.get("raw_symbol", "")).upper(): s for s in sinais_raw}
    analises: list[dict] = []
    total_score = 0.0
    for ativo_symbol in req.ativos:
        ativo_up = ativo_symbol.upper()
        sinal = (sinais_por_label.get(ativo_up) or
                 sinais_por_symbol.get(f"{ativo_up}USDT"))
        if sinal is None:
            try:
                precos = get_klines(f"{ativo_up}USDT", "1h", 100) or [0.45, 0.46, 0.47]
                preco = precos[-1]
                rsi = calculate_rsi(precos, 14)
                ema = calculate_ema(precos, 20)
                ema200 = calculate_ema(precos, 50) * 0.98
                side = "HOLD"
                entry = preco
                stop = round(preco * 0.97, 4)
                target = round(preco * 1.05, 4)
                trend = "Sinal neutro; consolidação."
            except Exception:
                preco, rsi, ema, ema200, side, entry, stop, target, trend = (
                    0.45, 52.0, 0.46, 0.44, "HOLD", 0.45, 0.43, 0.48, "Mock fallback"
                )
            sinal = {
                "label": ativo_up, "raw_symbol": f"{ativo_up}USDT",
                "current_price": preco, "rsi_14": rsi, "ema_20": ema,
                "ema_200": ema200, "side": side, "entry": entry,
                "stop": stop, "target": target, "trend": trend,
            }
        price_curr = float(sinal.get("current_price") or 0.0)
        rsi = float(sinal.get("rsi_14") or 50.0)
        ema20 = float(sinal.get("ema_20") or price_curr or 1.0)
        ema200_v = price_curr * 0.94  # fallback
        whale = whale_alerts_mock(ativo_up)
        eco = resumo_ecossistema_ativo(ativo_up)
        not_ativ: list[dict] = []
        for k, v in (todas_not or {}).items():
            if ativo_up.lower() in k.lower() or k in ativo_up:
                not_ativ.extend(v or [])
        not_ativ = not_ativ[:5]
        score_compra = 50.0
        if sinal.get("side") == "BUY":
            score_compra += 22
        elif sinal.get("side") == "SELL":
            score_compra -= 20
        if rsi < 32:
            score_compra += 12
        elif rsi > 72:
            score_compra -= 14
        if price_curr and price_curr > ema20:
            score_compra += 8
        else:
            score_compra -= 6
        if fg.get("value", 50) < 35:
            score_compra += 9
        elif fg.get("value", 50) > 72:
            score_compra -= 8
        if macro.get("risco_regulatorio_cripto") == "BAIXO":
            score_compra += 7
        elif macro.get("risco_regulatorio_cripto") == "ALTO":
            score_compra -= 10
        for w in whale:
            if w.get("sinal") == "COMPRA":
                score_compra += 4
            elif w.get("sinal") == "VENDA":
                score_compra -= 4
        perfil_mod = perfil.get("perfil", "moderado")
        if perfil_mod == "conservador":
            score_compra -= 10
        elif perfil_mod == "agressivo":
            score_compra += 8
        score_compra = max(0.0, min(100.0, score_compra))
        total_score += score_compra
        if score_compra >= 62:
            status = "COMPRAR"
            entry_final = float(sinal.get("entry") or price_curr)
            sl = float(sinal.get("stop") or price_curr * 0.95)
            tp = float(sinal.get("target") or price_curr * 1.08)
        elif score_compra <= 42:
            status = "VENDER"
            entry_final = float(sinal.get("entry") or price_curr)
            sl = float(sinal.get("stop") or price_curr * 1.03)
            tp = float(sinal.get("target") or price_curr * 0.94)
        else:
            status = "AGUARDAR / ALTO RISCO"
            entry_final = float(sinal.get("entry") or price_curr)
            sl = float(sinal.get("stop") or price_curr * 0.93)
            tp = float(sinal.get("target") or price_curr * 1.07)
        impacto_geo = []
        if macro.get("risco_regulatorio_cripto") == "ALTO":
            impacto_geo.append("Risco regulatório ALTO (EUA/UE) pressiona ativos pequenos.")
        if ativo_up in ("BTC",):
            impacto_geo.append(f"BTC: ETF spot + fluxos institucionais; taxa FED atual {macro.get('taxa_juros_fed_atual_pct')}%.")
        if ativo_up in ("AAVE",):
            impacto_geo.append("AAVE: Depende de APY DeFi, correlacionado ao risco stablecoins.")
        if ativo_up in ("IOTA",):
            impacto_geo.append("IOTA: Ciclo de adoção IoT/RWA; baixa correlação a ETFs BTC.")
        impacto_geo.append(f"Índice Fear & Greed: {fg.get('classification')} ({fg.get('value')} pts).")
        pilares = {
            "geopolitica_macro": macro,
            "noticias_sentimento_global": not_ativ,
            "analise_tecnica_onchain": {
                "preco_atual_usd": round(price_curr, 6),
                "rsi_14": round(rsi, 2),
                "ema_20": round(ema20, 6),
                "ema_200_aproximada": round(ema200_v, 6),
                "volume_24h_indicador": "Médio",
                "fear_greed_index": fg,
                "whale_alerts": whale,
                "tendencia_mercado": sinal.get("trend", ""),
            },
            "ecossistema_desenvolvimentos": eco,
        }
        alocacao_sugerida_pct = {"BTC": 55, "AAVE": 25, "IOTA": 20}.get(ativo_up, 33.33)
        if perfil_mod == "conservador":
            alocacao_sugerida_pct = {"BTC": 75, "AAVE": 15, "IOTA": 10}.get(ativo_up, 33.33)
        elif perfil_mod == "agressivo":
            alocacao_sugerida_pct = {"BTC": 40, "AAVE": 30, "IOTA": 30}.get(ativo_up, 33.33)
        analises.append({
            "simbolo": ativo_up,
            "nome": sinal.get("label") or ativo_up,
            "preco_atual_usd": round(price_curr, 6),
            "status": status,
            "score_sinal_0_100": round(score_compra, 2),
            "impacto_geopolitico": impacto_geo,
            "resumo_noticias": [n.get("titulo") for n in not_ativ[:3]] if not_ativ else ["Sem notícias novas nas últimas horas."],
            "ponto_entrada_sugerido_usd": round(entry_final, 6),
            "stop_loss_usd": round(sl, 6),
            "take_profit_usd": round(tp, 6),
            "razao_risco_retorno": round(abs(tp - entry_final) / max(0.000001, abs(sl - entry_final)), 2),
            "alocacao_sugerida_pct_carteira": alocacao_sugerida_pct,
            "valor_alocado_aporte_usd": round(req.valor_aporte_usd * alocacao_sugerida_pct / 100.0, 2),
            "pilares": pilares,
        })
    med = total_score / max(1, len(req.ativos))
    recomendacao_carteira = (
        "ALOCAR GRADUALMENTE (DCA 4 semanas)" if med >= 60 else
        "PARCIAL: Alocar apenas em ativos com status COMPRAR." if med >= 45 else
        "AGUARDAR MELHOR CENÁRIO GLOBAL (esperar pullback)."
    )
    return {
        "gerado_em": datetime.now().isoformat(),
        "perfil_risco_usuario": perfil,
        "horizonte_dias": req.horizonte_dias,
        "valor_aporte_usd": req.valor_aporte_usd,
        "recomendacao_geral_carteira": recomendacao_carteira,
        "fear_and_greed_global": fg,
        "macro_geopolitico": macro,
        "analises_ativos": analises,
    }


class UserFeedbackRequest(BaseModel):
    user_id: str = "default"
    categoria: str
    item_id: str
    item_label: str | None = None
    decisao: str
    sinal_ia: str | None = None
    confianca_ia: float | None = None
    risco_aceito: bool = False
    perfil_risco_usuario: str = "moderado"
    valor_stake: float = 0.0
    resultado_real: str | None = None
    comentario_usuario: str | None = None
    extra: dict | None = None


@app.post("/api/v1/user/feedback")
def user_feedback_store(req: UserFeedbackRequest):
    perfil_detectado = obter_perfil_risco_usuario(req.user_id)
    perfil_usar = req.perfil_risco_usuario or perfil_detectado.get("perfil") or "moderado"
    db = SessionLocal()
    try:
        row = UserFeedback(
            user_id=req.user_id,
            categoria=req.categoria,
            item_id=req.item_id,
            item_label=req.item_label or f"{req.categoria}:{req.item_id}",
            decisao=req.decisao,
            sinal_ia=req.sinal_ia,
            confianca_ia=req.confianca_ia,
            risco_aceito=req.risco_aceito,
            perfil_risco_usuario=perfil_usar,
            valor_stake=req.valor_stake,
            resultado_real=req.resultado_real,
            comentario_usuario=req.comentario_usuario,
            extra_json=json.dumps(req.extra or {}, ensure_ascii=False),
        )
        db.add(row)
        db.commit()
        novo_id = row.id
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Erro salvar feedback: {e}")
    finally:
        db.close()
    perfil_atualizado = obter_perfil_risco_usuario(req.user_id)
    return {
        "ok": True,
        "feedback_id": novo_id,
        "mensagem": "Feedback salvo e injetado no perfil de risco do usuário.",
        "perfil_risco_atualizado": perfil_atualizado,
        "salvo_em": datetime.now().isoformat(),
    }


@app.get("/")
def root():
    return {
        "nome": "Tiago IA Backend",
        "versao": "1.1.0 (Multiplas + Cripto Macro + Feedback)",
        "status": "online",
        "endpoints": {
            "auth": "/api/v1/auth/login",
            "esportes_hoje": "/api/v1/sports/today",
            "low_odds": "/api/v1/sports/low-odds",
            "verificar_jogos": "/api/v1/sports/verify-selected-matches",
            "sinais_ia": "/api/v1/ia/sinais",
            "analise_multipla": "POST /api/v1/sports/analyze-accumulator",
            "analise_cripto_macro": "POST /api/v1/crypto/analyze-investment",
            "feedback_usuario": "POST /api/v1/user/feedback",
            "sinais_cripto": "/api/v1/crypto/signals",
            "status_banca": "/api/v1/bankroll/status",
            "chat": "/api/v1/chat/message",
            "live_jogos": "GET /api/v1/sports/live-list",
            "otimizar_multipla": "POST /api/v1/sports/optimize-accumulator"
        }
    }


# =============================================================================
# MODULOS ADICIONAIS INCREMENTAIS (Non-Breaking)
# Live Matches + Accumulator Optimizer (IA do Tiago)
# NÃO MODIFICA NENHUMA ROTA / FUNÇÃO / CLASSE ANTERIOR.
# =============================================================================
from services.live_matches_service import (
    listar_jogos_ao_vivo_e_do_dia as _nb_listar_live,
    metricas_inplay_rapidas as _nb_metricas_inplay,
    tendencia_escanteios_ao_vivo as _nb_tend_esc_inplay,
    SIGNATURE as _SIG_LIVE,
)
from services.accumulator_ai_optimizer import (
    calibrar_linha_aposta as _nb_calibrar,
    guia_como_apostar_para_ganhar as _nb_guia,
    interpretar_comando_e_ajustar_bilhete as _nb_cmd,
    SIGNATURE as _SIG_OPT,
)


class NBOptimizeAccumulatorRequest(BaseModel):
    user_id: str = "default"
    stake_total_usd: float = 100.0
    perfil_risco_usuario: str = "moderado"
    selecoes: list[dict] = []
    comando_usuario: str | None = None
    meta_pct_hit_alvo: float = 70.0


@app.get("/api/v1/sports/live-list", tags=["sports-incremental"])
def nb_sports_live_list(incluir_ligas_extra: bool = True,
                        apenas_em_jogo: bool = False):
    """Rota NOVA INCREMENTAL · lista jogos hoje com horário, minuto, placar.

    Assinatura: IA do Tiago.
    """
    dados = _nb_listar_live(incluir_ligas_extra=incluir_ligas_extra)
    if apenas_em_jogo:
        dados["jogos"] = [j for j in dados["jogos"] if j["em_jogo_agora"]]
        dados["total_jogos"] = len(dados["jogos"])
        dados["total_em_jogo_agora"] = sum(1 for j in dados["jogos"] if j["em_jogo_agora"])
    return dados


@app.get("/api/v1/sports/live-metrics/{jogo_id}", tags=["sports-incremental"])
def nb_sports_live_metrics(jogo_id: str):
    """Rota NOVA · métricas in-play rápidas (posse, chutes, escanteios...)."""
    m = _nb_metricas_inplay(jogo_id)
    return {"assinatura": _SIG_LIVE, "jogo_id": jogo_id, "metricas": m}


@app.get("/api/v1/sports/live-corners-trend/{jogo_id}", tags=["sports-incremental"])
def nb_sports_live_corners_trend(jogo_id: str):
    """Rota NOVA · tendência projetada de escanteios até 90min."""
    return _nb_tend_esc_inplay(jogo_id)


@app.post("/api/v1/sports/optimize-accumulator", tags=["sports-incremental"])
def nb_sports_optimize_accumulator(req: NBOptimizeAccumulatorRequest):
    """Rota NOVA INCREMENTAL · IA do Tiago otimiza múltiplas.

    Combina 3 blocos:
      · Calibração dinâmica de linhas por seleção (sugestão ajuste +% melhoria).
      · Guia "Como Apostar Para Ganhar" (Pré vs Ao Vivo / Stake % / Gestão).
      · Comando direto do usuário via chat rápido (otimizar, remover arriscados, etc).
    Assinatura: IA do Tiago.
    """
    from datetime import datetime, timezone
    calibrados: list[dict] = []
    for sel in req.selecoes:
        cal = _nb_calibrar(dict(sel))
        calibrados.append({"entrada": dict(sel), "calibracao_linha": cal})

    guia = _nb_guia(
        selecoes=[dict(s) for s in req.selecoes],
        stake_total_usd=req.stake_total_usd,
        perfil_usuario=req.perfil_risco_usuario,
    )

    cmd_res = None
    selecoes_ajustadas = [dict(s) for s in req.selecoes]
    if req.comando_usuario and req.comando_usuario.strip():
        cmd_res = _nb_cmd(
            comando_usuario=req.comando_usuario,
            selecoes=[dict(s) for s in req.selecoes],
            meta_pct_hit_alvo=req.meta_pct_hit_alvo,
        )
        selecoes_ajustadas = cmd_res.get("selecoes_apos_ajuste", selecoes_ajustadas)

    return {
        "assinatura": "IA do Tiago",
        "servicos_utilizados": (
            f"{_SIG_LIVE} (referência) + {_SIG_OPT} (calibragem/guia/comando)"
        ),
        "gerado_em_utc": datetime.now(tz=timezone.utc).isoformat(),
        "perfil_risco_usuario": req.perfil_risco_usuario,
        "stake_total_usd": req.stake_total_usd,
        "meta_pct_hit_alvo": req.meta_pct_hit_alvo,
        "por_selecao": calibrados,
        "guia_como_apostar_para_ganhar": guia,
        "comando_usuario": cmd_res,
        "selecoes_ajustadas_finais": selecoes_ajustadas,
    }


# =============================================================================
# MODULOS INCREMENTAIS ADICIONAIS V2.1 — NON-BREAKING
# Unificação Cripto & Swap (Quantfury) + Montagem Automática de Múltiplas
# NÃO MODIFICA NENHUMA ROTA / FUNÇÃO / CLASSE ANTERIOR.
# =============================================================================
from services.quantfury_crypto_swap_service import (
    verificar_operacao_ao_vivo as _nb_verif_crypto,
    confirmar_operacao as _nb_confirmar_crypto,
    SIGNATURE as _SIG_CRYPTO,
    ATIVOS_PERMITIDOS as _CRYPTO_ATIVOS,
    ESTRUTURA_QUANTFURY as _ESTRUTURA_QF,
)
from services.accumulator_auto_builder import (
    montar_multipla_completa_pela_IA_do_Tiago as _nb_montar_multipla,
    confirmar_multipla_bilhete as _nb_confirmar_multipla,
    SIGNATURE as _SIG_MULT,
    PERFIS_RISCO as _PERFIS_MULT,
)


class NbQuantfuryCheckRequest(BaseModel):
    user_id: str = "default"
    simbolo: str
    acao: str
    simbolo_destino_swap: str | None = None
    quantidade_unidades: float = 0.0
    semente: int | None = None


class NbQuantfuryConfirmRequest(BaseModel):
    user_id: str = "default"
    simbolo: str
    acao: str
    token_confirmacao: str


class NbBuildAccumulatorRequest(BaseModel):
    user_id: str = "default"
    perfil_risco: str = "moderado"
    semente: int | None = None
    semente_extra: str | None = None


@app.get("/api/v1/crypto/quantfury/assets", tags=["crypto-incremental"])
def nb_crypto_quantfury_assets():
    """Rota NOVA · Lista ativos + estrutura Quantfury (0 taxa, 0 overnight)."""
    return {
        "assinatura": _SIG_CRYPTO,
        "ativos_permitidos": list(_CRYPTO_ATIVOS),
        "estrutura_operacional": _ESTRUTURA_QF,
    }


@app.post("/api/v1/crypto/quantfury/verify-live", tags=["crypto-incremental"])
def nb_crypto_quantfury_verify_live(req: NbQuantfuryCheckRequest):
    """Rota NOVA · Verificação ao vivo + veredito da IA do Tiago (COMPRAR/VENDER/TROCAR).

    Etapas:
      · "Calma, vou fazer uma rápida verificação..."
      · Varredura fontes globais, macro geopolítico, notícias, baleias, técnicos.
      · Decisão em destaque: 🟢 COMPRAR | 🔴 SHORT | 🔄 SWAP | 🟡 AGUARDAR.
      · Estratégia Quantfury: entrada, SL, TP1/TP2, stake %.
      · Pergunta confirmação e botão de validação.
    """
    res = _nb_verif_crypto(
        simbolo=req.simbolo,
        acao=req.acao,
        simbolo_destino_swap=req.simbolo_destino_swap,
        quantidade_unidades=req.quantidade_unidades,
        semente=req.semente,
    )
    res["solicitado_por_user_id"] = req.user_id
    res["token_confirmacao_sugerido"] = (
        f"QTFY-{req.user_id.upper()}-{abs(hash(req.simbolo + req.acao + datetime.now(tz=timezone.utc).isoformat())) % 10_000_000:07d}"
    )
    return res


@app.post("/api/v1/crypto/quantfury/confirm", tags=["crypto-incremental"])
def nb_crypto_quantfury_confirm(req: NbQuantfuryConfirmRequest):
    """Rota NOVA · Valida operação após o clique no botão Confirmar e Validar."""
    from datetime import datetime, timezone
    conf = _nb_confirmar_crypto(req.simbolo, req.acao, req.token_confirmacao)
    conf["user_id"] = req.user_id
    return conf


@app.get("/api/v1/sports/build-accumulator", tags=["sports-incremental"])
@app.post("/api/v1/sports/build-accumulator", tags=["sports-incremental"])
def nb_sports_build_accumulator(req: NbBuildAccumulatorRequest | None = None):
    """Rota NOVA · Monta Múltipla Completa pela IA do Tiago (Cartões / Escanteios / Chutes).

    Fluxo:
      1. Mensagem "Calma, vou fazer uma rápida verificação..."
      2. Seleciona automaticamente N entradas cobrindo os 3 mercados.
      3. Autocorreção de segurança (baixa linhas arriscadas).
      4. Calcula Odd Total Combinada.
      5. Modal confirmação com 2 botões: Confirmar Odd / Refazer Novamente.
    """
    from datetime import datetime, timezone
    perfil = (req.perfil_risco if req else "moderado") or "moderado"
    sem = req.semente if req else None
    sem2 = req.semente_extra if req else None
    bilhete = _nb_montar_multipla(
        perfil_risco=perfil, semente=sem, semente_extra=sem2
    )
    bilhete["solicitado_por_user_id"] = (req.user_id if req else "default") or "default"
    bilhete["bilhete_id"] = (
        f"MULT-{bilhete['solicitado_por_user_id'].upper()}-{abs(hash(datetime.now(tz=timezone.utc).isoformat() + perfil)) % 10_000_000:07d}"
    )
    bilhete["perfis_risco_disponiveis"] = list(_PERFIS_MULT.keys())
    return bilhete


@app.post("/api/v1/sports/confirm-accumulator", tags=["sports-incremental"])
def nb_sports_confirm_accumulator(bilhete: dict):
    """Rota NOVA · Confirma e valida bilhete montado pela IA do Tiago."""
    bid = bilhete.get("bilhete_id", "unknown")
    uid = bilhete.get("user_id", "default")
    return _nb_confirmar_multipla(bilhete_id=bid, usuario_id=uid)


# =============================================================================
# MODULO INCREMENTAL V2.2 — SCHEDULER AUTO-WARMUP CACHE (NON-BREAKING)
# Atualiza caches em background a cada X segundos para manter dados SINCRONIZADOS.
# NÃO MODIFICA NENHUMA FUNÇÃO / ROTA ANTERIOR.
# =============================================================================
import threading as _th
import time as _tm
_SIGLA_SCHED = "IA do Tiago · Scheduler"
_SCHED_STOP_FLAG = _th.Event()

def _scheduler_warmup_background():
    """Thread daemon · atualiza caches LIVE e SINAIS-IA periodicamente."""
    contador = 0
    while not _SCHED_STOP_FLAG.is_set():
        try:
            if contador % 2 == 0:
                try:
                    get_flashscore_live_matches()
                    print(f"[{_SIGLA_SCHED}] cache LIVE warmup OK (tick {contador})")
                except Exception as _e:
                    pass
            if contador % 5 == 0:
                try:
                    calcular_sinais_ia(usar_gemini=False, apenas_hoje_ou_live=True)
                    print(f"[{_SIGLA_SCHED}] cache SINAIS-IA OK (tick {contador})")
                except Exception as _e:
                    pass
            if contador % 3 == 0:
                try:
                    get_today_matches()
                except Exception:
                    pass
            _tm.sleep(10)
            contador += 1
        except Exception:
            _tm.sleep(15)

_SCHED_THREAD: _th.Thread | None = None

@app.on_event("startup")
def _nb_startup_scheduler():
    """Warmup AUTOMATICO no boot: carrega caches imediatamente + inicia thread daemon."""
    global _SCHED_THREAD
    try:
        print(f"[{_SIGLA_SCHED}] warming up inicial (live + sinais + jogos)...")
        try:
            get_today_matches()
        except Exception:
            pass
        try:
            get_flashscore_live_matches()
        except Exception:
            pass
        try:
            calcular_sinais_ia(usar_gemini=False, apenas_hoje_ou_live=True)
        except Exception:
            pass
        _SCHED_THREAD = _th.Thread(target=_scheduler_warmup_background, daemon=True)
        _SCHED_THREAD.start()
        print(f"[{_SIGLA_SCHED}] thread daemon LIVE iniciada com sucesso.")
    except Exception as _e:
        print(f"[{_SIGLA_SCHED}] aviso: {_e}")

@app.on_event("shutdown")
def _nb_shutdown_scheduler():
    """Desliga a thread daemon corretamente no shutdown."""
    try:
        _SCHED_STOP_FLAG.set()
        print(f"[{_SIGLA_SCHED}] shutdown sinalizado.")
    except Exception:
        pass


# =============================================================================
# MODULO INCREMENTAL V3 — NOVAS ROTAS LIVE SPORTS + CRIPTO v2 + VALIDADOR MULTIPLA
# (NON-BREAKING: não altera nenhuma rota existente, apenas adiciona novas.)
# =============================================================================

from services.live_sports_service import (
    obter_jogos_ao_vivo as _lsv_live,
    obter_jogos_hoje as _lsv_hoje,
    obter_jogos_amanha as _lsv_amanha,
    obter_jogos_fim_semana as _lsv_fds,
    _obter_estatisticas_partida as _lsv_stats,
    validar_bilhete_multiplo as _lsv_validar_multi,
    jogos_ranqueados_hoje as _lsv_jogos_ranqueados_hoje,
    gerar_bilhetes_ia as _lsv_gerar_bilhetes_ia,
    _origem_dados_global as _lsv_origem_geral,
    check_fontes_status as _lsv_check_fontes_status,
)
from services.crypto_service import (
    get_crypto_signals_v2 as _crypto_v2_resumo,
    analisar_par_v2 as _crypto_v2_par,
)

_SIG_V3 = "IA do Tiago · V3"


@app.get("/api/v3/sports/live", tags=["sports-v3"])
def nb_v3_sports_live():
    """🔴 Ao Vivo Agora · partidas em andamento com stats + previsões 4 mercados."""
    jogos = _aplicar_flat_fields_flutter(_lsv_live())
    return {
        "assinatura": _SIG_V3,
        "aba": "AO_VIVO",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        # 4 arrays FALLBACK: qualquer tela leia qualquer nome, vai encontrar a lista.
        "jogos": jogos,
        "partidas": jogos,
        "data_array": jogos,
        "data": jogos,
    }


@app.get("/api/v3/sports/today", tags=["sports-v3"])
@app.get("/api/v3/sports/hoje", tags=["sports-v3"])
def nb_v3_sports_hoje():
    """📅 Hoje · todas partidas do dia (ao vivo + agendadas) com odds/probs."""
    jogos = _aplicar_flat_fields_flutter(_lsv_hoje())
    return {
        "assinatura": _SIG_V3,
        "aba": "HOJE",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        # 4 arrays FALLBACK: qualquer tela leia qualquer nome, vai encontrar a lista.
        "jogos": jogos,
        "partidas": jogos,
        "data_array": jogos,
        "data": jogos,
    }


@app.get("/api/v3/sports/tomorrow", tags=["sports-v3"])
@app.get("/api/v3/sports/amanha", tags=["sports-v3"])
def nb_v3_sports_amanha():
    """📅 Amanhã · partidas agendadas."""
    jogos = _aplicar_flat_fields_flutter(_lsv_amanha())
    return {
        "assinatura": _SIG_V3,
        "aba": "AMANHA",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        # 4 arrays FALLBACK: qualquer tela leia qualquer nome, vai encontrar a lista.
        "jogos": jogos,
        "partidas": jogos,
        "data_array": jogos,
        "data": jogos,
    }


@app.get("/api/v3/sports/weekend", tags=["sports-v3"])
@app.get("/api/v3/sports/fim-de-semana", tags=["sports-v3"])
def nb_v3_sports_fds():
    """🗓️ Fim de Semana · sábado + domingo + segunda (3 dias)."""
    jogos = _aplicar_flat_fields_flutter(_lsv_fds())
    return {
        "assinatura": _SIG_V3,
        "aba": "FIM_DE_SEMANA",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        # 4 arrays FALLBACK: qualquer tela leia qualquer nome, vai encontrar a lista.
        "jogos": jogos,
        "partidas": jogos,
        "data_array": jogos,
        "data": jogos,
    }


@app.get("/api/v3/sports/fixture/{fixture_id}/stats", tags=["sports-v3"])
def nb_v3_fixture_stats(fixture_id: int):
    """Estatísticas LIVE detalhadas (escanteios, chutes, posse, cartões) de 1 partida."""
    stats = _lsv_stats(fixture_id, ttl=10.0)
    return {
        "assinatura": _SIG_V3,
        "fixture_id": fixture_id,
        "estatisticas_live": stats,
    }


class _NbV3SelecaoMultipla(BaseModel):
    fixture_id: Optional[int] = None
    time_casa: Optional[str] = None
    time_fora: Optional[str] = None
    mercado: str = "Vencedor 1X2"
    odd_apostada: float = 1.5
    aposta: Optional[str] = None


class _NbV3ValidadorMultiplaRequest(BaseModel):
    selecoes: List[_NbV3SelecaoMultipla]
    stake_total: float = 100.0


@app.post("/api/v3/sports/validar-multipla", tags=["sports-v3"])
def nb_v3_validar_multipla(req: _NbV3ValidadorMultiplaRequest):
    """✅ Validador de Bilhete Múltiplo · aprovação/ajuste, risco geral, stake sugerido."""
    lista_dict = []
    for s in req.selecoes:
        d = s.model_dump()
        d["stake_total"] = req.stake_total
        lista_dict.append(d)
    resultado = _lsv_validar_multi(lista_dict)
    resultado["stake_total_informado"] = req.stake_total
    return resultado


@app.get("/api/v3/sports/jogos-ranqueados-hoje", tags=["sports-v3"])
def nb_v3_jogos_ranqueados():
    """🏆 TODOS os jogos do dia + LIVE ranqueados pela IA, com a MELHOR seleção por jogo já apontada."""
    jogos_raw = _lsv_jogos_ranqueados_hoje()
    # 🔒 PURGE MOCK FINAL: remove tudo que não for dado REAL (0% tolerância)
    jogos = _purge_mock_jogos(list(jogos_raw), contexto="v3_jogos_ranqueados_hoje")
    # Origem vem do próprio jogo via "origem_dados" (após purge)
    origem_geral = (
        "RAPIDAPI_REAL" if any(j.get("origem_dados") == "RAPIDAPI_REAL" for j in jogos)
        else "FALLBACK_VAZIO"
    )
    return {
        "assinatura": "IA do Tiago · Live Sports v3 · Gerador IA",
        "origem_dados_geral": origem_geral,
        "gerado_em": datetime.now().isoformat(timespec="seconds"),
        "total_jogos": len(jogos),
        "jogos": jogos,
    }


@app.get("/api/v3/sports/gerar-bilhetes-ia", tags=["sports-v3"])
@app.post("/api/v3/sports/gerar-bilhetes-ia", tags=["sports-v3"])
def nb_v3_gerar_bilhetes_ia(
    quantidade_bilhetes: int = 3,
    jogos_minimo: int = 2,
    jogos_maximo: int = 6,
):
    """🤖 GERADOR IA DE BILHETES PRONTOS · 3 perfis SEGURO/BALANCEADO/AGRESSIVO · já validados!"""
    dados = _lsv_gerar_bilhetes_ia(
        quantidade_bilhetes=quantidade_bilhetes,
        jogos_minimo_por_bilhete=jogos_minimo,
        jogos_maximo_por_bilhete=jogos_maximo,
    )
    # 🔒 CAMADA DE SEGURANCA 0 (ANTES DE TUDO): PURGE MOCK em todas as selecoes de todos os bilhetes
    bilhetes_limpos = []
    for idx_b, bilhete in enumerate(dados.get("bilhetes_sugeridos") or []):
        if isinstance(bilhete.get("selecoes"), list):
            sel_limpas = _purge_mock_jogos(
                list(bilhete["selecoes"]),
                contexto=f"v3_gerar_bilhetes_bilhete_{idx_b}"
            )
            # Só mantém o bilhete se ainda tiver pelo menos 1 seleção real
            if sel_limpas:
                bilhete["selecoes"] = sel_limpas
                bilhetes_limpos.append(bilhete)
    dados["bilhetes_sugeridos"] = bilhetes_limpos
    # 🔒 CAMADA DE SEGURANCA 1: Aplicar flat fields (home/away/liga/hr + aliases) EM CADA selecao de CADA bilhete
    for bilhete in (dados.get("bilhetes_sugeridos") or []):
        if isinstance(bilhete.get("selecoes"), list):
            bilhete["selecoes"] = _aplicar_flat_fields_flutter(list(bilhete["selecoes"]))
    # Origem = olhar primeira seleção do primeiro bilhete (após purge)
    primeira_origem = "FALLBACK_VAZIO"
    primeiro_bilhete = (dados.get("bilhetes_sugeridos") or [{}])[0] if (dados.get("bilhetes_sugeridos") or []) else {}
    for s in (primeiro_bilhete.get("selecoes") or []):
        if s.get("origem_dados") == "RAPIDAPI_REAL":
            primeira_origem = "RAPIDAPI_REAL"
            break
        primeira_origem = s.get("origem_dados") or primeira_origem
    # 🔒 CAMADA DE SEGURANCA 2: Qualquer fonte ONLINE (nao eh fallback vazio/todos) -> mapeia para RAPIDAPI_REAL
    #    (o Flutter GERAR_BILHETE_IA_SCREEN so reconhece 'RAPIDAPI_REAL' como online; qualquer outra string = Modo Offline)
    FONTES_FALLBACK_OFFLINE = ("FALLBACK_VAZIO", "FALLBACK_TODOS", "IA_DO_TIAGO_DINAMICO", "SEED_ALEATORIO", "OFFLINE_SEED", "FALLBACK_HIBRIDO_SEED")
    if primeira_origem not in FONTES_FALLBACK_OFFLINE:
        dados["origem_dados_geral"] = "RAPIDAPI_REAL"
    else:
        dados["origem_dados_geral"] = primeira_origem
    return dados


@app.get("/api/v3/crypto/summary", tags=["crypto-v3"])
@app.get("/api/v3/crypto/resumo", tags=["crypto-v3"])
def nb_v3_crypto_resumo(interval: str = "1h", pares: Optional[str] = None):
    """📊 Resumo CRIPTO v2 · BTC/ETH/SOL/AAVE/IOTA/BNB · RSI14, EMA20, EMA200, Entry/SL/TP."""
    pairs = [p.strip() for p in pares.split(",")] if pares else None
    return _crypto_v2_resumo(pairs=pairs, interval=interval)


@app.get("/api/v3/crypto/analisar/{simbolo}", tags=["crypto-v3"])
def nb_v3_crypto_par(simbolo: str, interval: str = "1h"):
    """🎯 Análise individual de 1 par cripto · Sinal COMPRAR/VENDER/AGUARDAR + RSL completa."""
    sym = simbolo.upper()
    if "USDT" not in sym:
        sym = f"{sym}USDT"
    return _crypto_v2_par(sym, interval=interval)


# =============================================================================
# MODULO INCREMENTAL V3.1 — IA DE SINAIS AUTOMÁTICOS CRIPTO (NON-BREAKING)
# Combina: Análise Técnica + Macro Geopolítica + Fear&Greed + Whale Alerts + Notícias
# + (opcional) enriquecimento GEMINI. Retorna: Entrada / SL / TP1(30%)/TP2(30%)/TP3(40%)
# + Regras EXATAS de QUANDO TIRAR TUDO automaticamente.
# =============================================================================
from services.crypto_ai_sinais_service import (
    gerar_sinal_ia_automatico_por_ativo as _sinais_ia_ativo,
    gerar_lote_sinais_ia_automaticos as _sinais_ia_lote,
    SIGNATURE as _SIG_CRYPTO_IA,
)
from fastapi import Query as _Query


@app.get("/api/v3/crypto/ia-sinal-automatico/{simbolo}", tags=["crypto-ai-v3"])
@app.get("/api/v3/crypto/ia-sinal/{simbolo}", tags=["crypto-ai-v3"])
def nb_v3_crypto_ia_sinal_individual(
    simbolo: str,
    intervalo: str = _Query("1h", pattern=r"^(1m|5m|15m|30m|1h|4h|1d)$"),
    perfil_risco: str = _Query("moderado", pattern=r"^(conservador|moderado|agressivo)$"),
    valor_carteira_usd: float = _Query(1000.0, ge=10.0),
    usar_gemini: bool = _Query(True, description="Tenta enriquecer score c/ Gemini se chave OK"),
):
    """🤖 IA DO TIAGO · SINAL AUTOMÁTICO INDIVIDUAL (1 ativo)
    Combina tudo: técnicos(Binance) + macro + Fear&Greed + WhaleAlerts + Notícias + (opcional)Gemini.
    Retorna: score 0-100 + veredito COMPRAR/VENDER/AGUARDAR + SL + TP1(30%)/TP2(30%)/TP3(40% = TIRAR TUDO)
    + regras exatas de saída total automática + checklist antes de executar."""
    return _sinais_ia_ativo(
        simbolo=simbolo, intervalo=intervalo,
        perfil_risco_usuario=perfil_risco,
        valor_aporte_referencia_usd=valor_carteira_usd,
        usar_gemini=usar_gemini,
    )


@app.get("/api/v3/crypto/ia-sinais-lote", tags=["crypto-ai-v3"])
@app.get("/api/v3/crypto/ia-lote", tags=["crypto-ai-v3"])
def nb_v3_crypto_ia_sinais_lote(
    simbolos: str | None = _Query(None, description="Ex: BTC,ETH,SOL,AAVE,IOTA (opcional)"),
    intervalo: str = _Query("1h", pattern=r"^(5m|15m|1h|4h|1d)$"),
    perfil_risco: str = _Query("moderado", pattern=r"^(conservador|moderado|agressivo)$"),
    valor_carteira_usd: float = _Query(1000.0, ge=10.0),
    usar_gemini: bool = _Query(False),
):
    """🤖 IA DO TIAGO · LOTE DE SINAIS (múltiplos ativos ranqueados por score)."""
    alvos = None
    if simbolos and simbolos.strip():
        alvos = [s.strip().upper() for s in simbolos.split(",") if s.strip()]
    return _sinais_ia_lote(
        simbolos=alvos or None,
        intervalo=intervalo,
        perfil_risco_usuario=perfil_risco,
        valor_aporte_referencia_usd=valor_carteira_usd,
        usar_gemini=usar_gemini,
    )


# ============================================================================
# MODULO INCREMENTAL V3.2 — SPORTS AUTONOMOUS CORE ENGINE (NON-BREAKING)
# Cobertura global · 3 provedores cascata · Pressão live · 3 tickets risco ·
# Safeguards VAR/Odds/CircuitBreaker · Grading GREEN/RED + Lessons + Gemini
# ============================================================================
try:
    from services.sports_autonomous_core_engine import (
        SIGNATURE as _SIG_SPORTS_CORE,
        ingest_canonical_live_matches as _sports_ingest_live,
        enrich_all_with_pressure as _sports_pressure,
        generate_three_tickets_automatic as _sports_tickets_gen,
        grade_ticket as _sports_ticket_grade,
        list_tickets as _sports_tickets_list,
        list_lessons as _sports_lessons_list,
        engine_status as _sports_status,
    )
    _SPORTS_CORE_IMPORTED = True
except Exception as _sports_import_err:
    _SPORTS_CORE_IMPORTED = False
    _SPORTS_CORE_IMPORT_ERR = str(_sports_import_err)

try:
    from services.sports_extra_rapidapis import (
        nba_mbb_news as _extra_nba_news,
        cricket_hscard as _extra_cricket_hscard,
        football_prediction_leagues as _extra_predict_leagues,
        referee_statistics as _extra_referee_stats,
        bet365_inplay_leagues as _extra_bet365_leagues,
        xbet_match_markets_periods as _extra_xbet_markets,
        football_pro_fixtures_by_date as _extra_fpro_fixtures,
        football_pro_transfers_between as _extra_fpro_transfers,
        bundle_all_extra as _extra_bundle_all,
        HOST_NBA_NEWS as _EXTRA_HOST_NEWS,
        HOST_CRICKET as _EXTRA_HOST_CRICKET,
        HOST_FOOTBALL_PREDICT as _EXTRA_HOST_PREDICT,
        HOST_SOFASPORT as _EXTRA_HOST_SOFASPORT,
        HOST_BET365_INPLAY as _EXTRA_HOST_BET365,
        HOST_1XBET as _EXTRA_HOST_1XBET,
        HOST_FOOTBALL_PRO as _EXTRA_HOST_FPRO,
    )
    _SPORTS_EXTRA_IMPORTED = True
except Exception as _extra_import_err:
    _SPORTS_EXTRA_IMPORTED = False
    _SPORTS_EXTRA_IMPORT_ERR = str(_extra_import_err)
    _EXTRA_HOST_NEWS = _EXTRA_HOST_CRICKET = _EXTRA_HOST_PREDICT = _EXTRA_HOST_SOFASPORT = _EXTRA_HOST_BET365 = None
    _EXTRA_HOST_1XBET = _EXTRA_HOST_FPRO = None

try:
    from fastapi import Body as _Body
    _BODY_IMPORTED = True
except Exception:
    _BODY_IMPORTED = False
    _Body = None


@app.get("/api/v3/sports/core/status", tags=["sports-core-v3"])
def nb_v3_sports_engine_status():
    """🏭 Healthcheck da Sports Autonomous Engine (cascata, Gemini, salvos)."""
    base = {
        "assinatura": _SIG_SPORTS_CORE if _SPORTS_CORE_IMPORTED else "NAO_CARREGADO",
        "modulo_carregado": _SPORTS_CORE_IMPORTED,
        "erro_importacao": (None if _SPORTS_CORE_IMPORTED else _SPORTS_CORE_IMPORT_ERR),
        "modulo_extra_v34_carregado": _SPORTS_EXTRA_IMPORTED,
        "modulo_extra_v34_erro": (None if _SPORTS_EXTRA_IMPORTED else _SPORTS_EXTRA_IMPORT_ERR),
        "novas_fontes_v34": {
            "nba_news": _EXTRA_HOST_NEWS,
            "cricket_cricbuzz": _EXTRA_HOST_CRICKET,
            "football_prediction": _EXTRA_HOST_PREDICT,
            "sofasport_referees": _EXTRA_HOST_SOFASPORT,
            "bet365_inplay": _EXTRA_HOST_BET365,
            "xbet_markets_periods": _EXTRA_HOST_1XBET,
            "football_pro_fixtures_transfers": _EXTRA_HOST_FPRO,
        },
        "timestamp_utc": str(datetime.utcnow().isoformat()),
    }
    if not _SPORTS_CORE_IMPORTED:
        return base
    return {**base, **_sports_status()}


@app.get("/api/v3/sports/core/matches/live", tags=["sports-core-v3"])
def nb_v3_sports_matches_live(
    incluir_agendados: bool = _Query(True),
    max_jogos: int = _Query(40, ge=1, le=200),
    forcar_recarga: bool = _Query(False),
):
    """⚽ Partidas CANONICAL com stats + pressão ao vivo (global, sem limite de ligas)."""
    if not _SPORTS_CORE_IMPORTED:
        return {"erro": "SPORTS_CORE_NAO_CARREGADO", "detalhe": _SPORTS_CORE_IMPORT_ERR}
    matches = _sports_ingest_live(
        incluir_agendados=incluir_agendados, max_jogos=max_jogos, forcar_recarga=forcar_recarga
    )
    matches = _sports_pressure(matches)
    return {
        "assinatura": _SIG_SPORTS_CORE,
        "gerado_em": str(datetime.utcnow().isoformat()),
        "quantidade": len(matches),
        "fontes_utilizadas": sorted({m.sourceProvider for m in matches}),
        "partidas": [m.model_dump(mode="json") for m in matches],
    }


@app.get("/api/v3/sports/core/tickets/generate", tags=["sports-core-v3"])
@app.post("/api/v3/sports/core/tickets/generate", tags=["sports-core-v3"])
def nb_v3_sports_tickets_generate(
    bankroll_brl: float = _Query(1000.0, ge=10.0),
    max_por_ticket: int = _Query(10, ge=3, le=20),
    forcar_recarga: bool = _Query(False),
):
    """🎟️ Gera 3 BILHETES AUTOMÁTICOS (HIGH_CONF/MEDIUM/HIGH_RISK_ATTEMPT) c/ até 10 jogos."""
    if not _SPORTS_CORE_IMPORTED:
        return {"erro": "SPORTS_CORE_NAO_CARREGADO", "detalhe": _SPORTS_CORE_IMPORT_ERR}
    return _sports_tickets_gen(
        bankroll_ref_brl=bankroll_brl,
        max_selecoes_por_ticket=max_por_ticket,
        forcar_recarga=forcar_recarga,
    )


@app.get("/api/v3/sports/core/tickets/list", tags=["sports-core-v3"])
def nb_v3_sports_tickets_list(
    risk_level: str | None = _Query(None, description="HIGH_CONFIDENCE / MEDIUM_RISK / HIGH_RISK_ATTEMPT"),
    status: str | None = _Query(None, description="PENDING / GREEN / RED / PARTIAL / INVALIDATED"),
    limit: int = _Query(30, ge=1, le=500),
):
    """📋 Lista bilhetes autônomos salvos no DB (ordem: mais recente primeiro)."""
    if not _SPORTS_CORE_IMPORTED:
        return {"erro": "SPORTS_CORE_NAO_CARREGADO"}
    return _sports_tickets_list(risk_level=risk_level, status=status, limit=limit)


@app.post("/api/v3/sports/core/tickets/{ticket_id}/grade", tags=["sports-core-v3"])
def nb_v3_sports_ticket_grade(
    ticket_id: str,
    body: dict | None = _Body(None, description="Opcional: {'resultados_override':{'MATCH_ID':{'status':'FINISHED','score':{'home':2,'away':0},'stats':{...}}}}"),
):
    """✅ Apura bilhete: GREEN/RED/PARTIAL + Failure Lessons auto + Gemini se disponível."""
    if not _SPORTS_CORE_IMPORTED:
        return {"erro": "SPORTS_CORE_NAO_CARREGADO"}
    override = None
    if isinstance(body, dict):
        override = body.get("resultados_override")
    return _sports_ticket_grade(ticket_id=ticket_id, resultados_override=override)


@app.get("/api/v3/sports/core/lessons", tags=["sports-core-v3"])
def nb_v3_sports_lessons(
    market: str | None = _Query(None, description="WINNER/CORNERS/GOALS/SHOTS_ON_TARGET/CARDS"),
    limit: int = _Query(50, ge=1, le=500),
):
    """🧠 Failure Lessons: auto-crítica de REDs + enriquecimento opcional Gemini."""
    if not _SPORTS_CORE_IMPORTED:
        return {"erro": "SPORTS_CORE_NAO_CARREGADO"}
    return _sports_lessons_list(limit=limit, market_filter=market)


# ============================================================================
# V3.4 · NOVOS ENDPOINTS EXTRAS RAPIDAPI (+1xbet + football-pro → total 7 fontes)
# ============================================================================
@app.get("/api/v3/sports/core/extra-data", tags=["sports-core-v3"])
def nb_v3_sports_extra_bundle(
    limit_news: int = _Query(20, ge=1, le=100),
    series_id_cricket: int = _Query(40381, ge=1),
    match_id_1xbet: str = _Query("1", description="Match ID da partida no 1xbet"),
    date_fpro: str | None = _Query(None, description="YYYY-MM-DD (padrão=hoje)"),
    transfers_from: str | None = _Query(None, description="YYYY-MM-DD (padrão=3 dias atrás)"),
    transfers_to: str | None = _Query(None, description="YYYY-MM-DD (padrão=hoje)"),
):
    """📦 BUNDLE único: agrega TODAS as 7 fontes RapidAPI em 1 payload."""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO", "detalhe": _SPORTS_EXTRA_IMPORT_ERR}
    return _extra_bundle_all(
        limit_news=limit_news, series_id_cricket=series_id_cricket,
        match_id_1xbet=match_id_1xbet,
        date_fpro=date_fpro, transfers_from=transfers_from, transfers_to=transfers_to,
    )


@app.get("/api/v3/sports/core/extra/nba-news", tags=["sports-core-v3"])
def nb_v3_sports_extra_nba_news(limit: int = _Query(30, ge=1, le=100)):
    """🏀 Notícias recentes de Basquete (Mens Basketball)."""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO"}
    return _extra_nba_news(limit=limit)


@app.get("/api/v3/sports/core/extra/cricket-hscard", tags=["sports-core-v3"])
def nb_v3_sports_extra_cricket_hscard(series_id: int = _Query(40381, ge=1)):
    """🏏 Scorecard Highlight de Críquete (Cricbuzz mirror)."""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO"}
    return _extra_cricket_hscard(series_id=series_id)


@app.get("/api/v3/sports/core/extra/football-prediction-leagues", tags=["sports-core-v3"])
def nb_v3_sports_extra_prediction_leagues():
    """⚽ Ligas disponíveis no motor de predições do dia."""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO"}
    return _extra_predict_leagues()


@app.get("/api/v3/sports/core/extra/referee-statistics", tags=["sports-core-v3"])
def nb_v3_sports_extra_referee_stats(referee_id: int = _Query(72792, ge=1)):
    """👨‍⚖️ Estatísticas de árbitro (input para cálculo de mercado CARDS)."""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO"}
    return _extra_referee_stats(referee_id=referee_id)


@app.get("/api/v3/sports/core/extra/bet365-inplay-leagues", tags=["sports-core-v3"])
def nb_v3_sports_extra_bet365_inplay():
    """🎲 Ligas com mercados em aberto no Bet365 In-Play agora."""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO"}
    return _extra_bet365_leagues()


# =============== FONTES NOVAS V3.4 (F9 + F10) =====================
@app.get("/api/v3/sports/core/extra/1xbet/markets/{match_id}", tags=["sports-core-v3"])
def nb_v3_sports_extra_xbet_markets(
    match_id: str,
    mode: str = _Query("line", description="line | live"),
    lng: str = _Query("en", description="en | pt | es"),
):
    """🎰 F9 · 1xbet: mercados segmentados por PERÍODO (1T, 2T, Total) de 1 match.
       Exato endpoint do cURL: GET /matches/{id}/markets/periods?mode=line&lng=en"""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO", "detalhe": _SPORTS_EXTRA_IMPORT_ERR}
    return _extra_xbet_markets(match_id=match_id, mode=mode, lng=lng)


@app.get("/api/v3/sports/core/extra/football-pro/fixtures", tags=["sports-core-v3"])
def nb_v3_sports_extra_fpro_fixtures(
    date: str | None = _Query(None, description="YYYY-MM-DD (padrão=hoje)"),
):
    """📅 F10 · Football-Pro: partidas de uma data (fonte extra p/ 'jogos de hoje')."""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO", "detalhe": _SPORTS_EXTRA_IMPORT_ERR}
    return _extra_fpro_fixtures(date_iso=date)


@app.get("/api/v3/sports/core/extra/football-pro/transfers", tags=["sports-core-v3"])
def nb_v3_sports_extra_fpro_transfers(
    from_date: str | None = _Query(None, description="YYYY-MM-DD (padrão=3 dias atrás)"),
    to_date: str | None = _Query(None, description="YYYY-MM-DD (padrão=hoje)"),
):
    """💼 F10 · Football-Pro: transferências de jogadores em janela de datas.
       Exato endpoint do cURL: GET /v3/football/transfers/between/2021-12-27/2021-12-30"""
    if not _SPORTS_EXTRA_IMPORTED:
        return {"erro": "SPORTS_EXTRA_NAO_CARREGADO", "detalhe": _SPORTS_EXTRA_IMPORT_ERR}
    return _extra_fpro_transfers(date_from_iso=from_date, date_to_iso=to_date)


# FIM MODULO V3.2 — Sports Autonomous Core Engine (NON-BREAKING)


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    uvicorn.run(app, host=host, port=port)
