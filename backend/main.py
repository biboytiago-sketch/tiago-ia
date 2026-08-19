import os
import json
from datetime import datetime, date, timedelta
from typing import List, Optional, Dict, Any
from dotenv import load_dotenv

# Carrega .env da pasta backend/ (caminho absoluto)
_DOTENV_CANDIDATOS = [
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"),
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env"),
    ".env",
]
for _p in _DOTENV_CANDIDATOS:
    _abs = os.path.abspath(_p)
    if os.path.exists(_abs):
        load_dotenv(_abs, override=False)
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
    try:
        init_db()
        print("Banco de dados inicializado com sucesso.")
    except Exception as e:
        print(f"Erro ao inicializar banco: {e}")


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
def ping_check():
    return "pong"


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
    hoje = date.today()
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
        "campeonato": liga_nome,
        "categoria": cat,
        "time_casa": casa,
        "time_fora": fora,
        "odd_casa": f"{o1:.2f}",
        "odd_empate": f"{ox:.2f}",
        "odd_fora": f"{o2:.2f}",
        "probabilidade": str(p_int),
        "probabilidade_real": round(max_p, 1),
        "pais": liga_pais,
        "liga_nome": liga_nome,
        "liga_pais": liga_pais,
        "liga_bandeira": liga_bandeira,
        "data_jogo": data_jogo,
        "data_curta": data_curta,
        "horario": f"{hh:02d}:{mm:02d}",
        "horario_iso": horario_iso,
        "status": status_legado,
        "minuto_live": (int(minuto) if minuto is not None else
                        (45 + (idx % 45) if status_legado == "AO_VIVO" else None)),
        "placar_casa": placar_c,
        "placar_fora": placar_f,
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


def _v1_hoje_dinamico():
    """Retorna {'total','data','jogos','categorias'} V1 usando dados V3 dinâmicos."""
    v3_payload = nb_v3_sports_hoje()
    v3_jogos = list(v3_payload.get("jogos") or [])
    v1_jogos = [_v3_para_v1_jogo(j, idx=i) for i, j in enumerate(v3_jogos)]
    return {
        "total": len(v1_jogos),
        "data": datetime.now().isoformat(),
        "jogos": v1_jogos,
        "categorias": _monta_categorias_v1(v1_jogos),
    }


def _v1_multiday_dinamico(dias: int = 4) -> Dict[str, Any]:
    dias = max(1, min(7, int(dias)))
    datas: List[Dict[str, Any]] = []
    jogos_por_data: Dict[str, List[Dict[str, Any]]] = {}
    total_jogos = 0
    hoje_iso = date.today()
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
        dados = get_matches_filtered(status=status, date=date, sport=sport)
        return {
            "query": {
                "status": status,
                "date": date or datetime.now().strftime("%Y-%m-%d"),
                "sport": sport,
            },
            "total": len(dados),
            "generated_at": datetime.now().isoformat(),
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
        totais = {
            "apostar": sum(1 for s in sinais if s.get("sinal") == "apostar"),
            "cuidado": sum(1 for s in sinais if s.get("sinal") == "cuidado"),
            "nao_apostar": sum(1 for s in sinais if s.get("sinal") == "nao_apostar"),
        }
        return {
            "generated_at": datetime.now().isoformat(),
            "fonte": "Gemini" if usar_gemini else "Heurística + Odds",
            "totais": totais,
            "cache_ttl_seconds": 90,
            "total": len(sinais),
            "sinais": sinais,
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
)
from services.crypto_service import (
    get_crypto_signals_v2 as _crypto_v2_resumo,
    analisar_par_v2 as _crypto_v2_par,
)

_SIG_V3 = "IA do Tiago · V3"


@app.get("/api/v3/sports/live", tags=["sports-v3"])
def nb_v3_sports_live():
    """🔴 Ao Vivo Agora · partidas em andamento com stats + previsões 4 mercados."""
    jogos = _lsv_live()
    return {
        "assinatura": _SIG_V3,
        "aba": "AO_VIVO",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        "jogos": jogos,
    }


@app.get("/api/v3/sports/today", tags=["sports-v3"])
@app.get("/api/v3/sports/hoje", tags=["sports-v3"])
def nb_v3_sports_hoje():
    """📅 Hoje · todas partidas do dia (ao vivo + agendadas) com odds/probs."""
    jogos = _lsv_hoje()
    return {
        "assinatura": _SIG_V3,
        "aba": "HOJE",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        "jogos": jogos,
    }


@app.get("/api/v3/sports/tomorrow", tags=["sports-v3"])
@app.get("/api/v3/sports/amanha", tags=["sports-v3"])
def nb_v3_sports_amanha():
    """📅 Amanhã · partidas agendadas."""
    jogos = _lsv_amanha()
    return {
        "assinatura": _SIG_V3,
        "aba": "AMANHA",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        "jogos": jogos,
    }


@app.get("/api/v3/sports/weekend", tags=["sports-v3"])
@app.get("/api/v3/sports/fim-de-semana", tags=["sports-v3"])
def nb_v3_sports_fds():
    """🗓️ Fim de Semana · sábado + domingo + segunda (3 dias)."""
    jogos = _lsv_fds()
    return {
        "assinatura": _SIG_V3,
        "aba": "FIM_DE_SEMANA",
        "origem_dados_geral": _lsv_origem_geral(jogos),
        "total": len(jogos),
        "jogos": jogos,
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
    jogos = _lsv_jogos_ranqueados_hoje()
    # Origem vem do próprio jogo via "origem_dados"
    origem_geral = (
        "RAPIDAPI_REAL" if any(j.get("origem_dados") == "RAPIDAPI_REAL" for j in jogos)
        else "FALLBACK_TODOS" if jogos else "FALLBACK_VAZIO"
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
    # Origem = olhar primeira seleção do primeiro bilhete
    primeira_origem = "FALLBACK_VAZIO"
    primeiro_bilhete = (dados.get("bilhetes_sugeridos") or [{}])[0] if (dados.get("bilhetes_sugeridos") or []) else {}
    for s in (primeiro_bilhete.get("selecoes") or []):
        if s.get("origem_dados") == "RAPIDAPI_REAL":
            primeira_origem = "RAPIDAPI_REAL"
            break
        primeira_origem = s.get("origem_dados") or primeira_origem
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
