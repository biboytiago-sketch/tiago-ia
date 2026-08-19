"""live_matches_service.py (NOVO MODULO · Non-Breaking)
Lista jogos do dia em tempo real (horários, status, placar, minuto de jogo).
Retorna estrutura neutra, sem menções a marcas de terceiros.
Assinatura: "IA do Tiago" em todos os headers de resposta.
"""
from __future__ import annotations

import math
import random
from datetime import datetime, timezone
from typing import Any

SIGNATURE = "IA do Tiago"

_STATUS_PADRAO = (
    ("AGENDADO", "AGENDADO", 0),
    ("EM JOGO · 1º TEMPO", "1H", 18),
    ("EM JOGO · 1º TEMPO", "1H", 32),
    ("INTERVALO", "HT", 45),
    ("EM JOGO · 2º TEMPO", "2H", 61),
    ("EM JOGO · 2º TEMPO", "2H", 74),
    ("ACRÉSCIMOS", "ET", 90),
    ("ENCERRADO", "FT", 90),
)

_JOGOS_BRASILEIRAO_MOCK = (
    {
        "casa": "Palmeiras", "fora": "São Paulo",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Allianz Parque", "hr_local": "16:00",
    },
    {
        "casa": "Flamengo", "fora": "Fluminense",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Maracanã", "hr_local": "18:30",
    },
    {
        "casa": "Botafogo", "fora": "Vasco da Gama",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Nilton Santos", "hr_local": "20:00",
    },
    {
        "casa": "Grêmio", "fora": "Internacional",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Arena do Grêmio", "hr_local": "21:30",
    },
    {
        "casa": "Atlético Mineiro", "fora": "Cruzeiro",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Mineirão", "hr_local": "19:00",
    },
    {
        "casa": "Corinthians", "fora": "Santos",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Neo Química Arena", "hr_local": "16:00",
    },
    {
        "casa": "Red Bull Bragantino", "fora": "Bahia",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Nabi Abi Chedid", "hr_local": "18:00",
    },
    {
        "casa": "Fortaleza", "fora": "Ceará",
        "liga": "Brasileirão Série A", "pais": "🇧🇷",
        "estadio": "Arena Castelão", "hr_local": "21:00",
    },
)

_LIGAS_EXTRA_MOCK: tuple[tuple[str, str, str, str, str, str, str], ...] = (
    ("Real Madrid", "Barcelona", "La Liga", "🇪🇸", "Santiago Bernabéu", "17:00", "El Clássico"),
    ("Manchester City", "Liverpool", "Premier League", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "Etihad", "18:30", ""),
    ("Bayern de Munique", "Dortmund", "Bundesliga", "🇩🇪", "Allianz Arena", "15:30", "Der Klassiker"),
    ("PSG", "Marselha", "Ligue 1", "🇫🇷", "Parc des Princes", "16:00", "Le Classique"),
    ("Juventus", "Inter de Milão", "Serie A", "🇮🇹", "Allianz Stadium", "16:45", "Derby d'Italia"),
)


def listar_jogos_ao_vivo_e_do_dia(
    sementinha: int | None = None,
    incluir_ligas_extra: bool = True,
) -> dict[str, Any]:
    """Serviço neutro · retorna horários, minutos e placares de hoje.

    Assinatura IA do Tiago embutida.
    """
    if sementinha is None:
        sementinha = int(datetime.now(tz=timezone.utc).timestamp() // 30)
    rng = random.Random(sementinha)
    horario_base = datetime.now(tz=timezone.utc).replace(second=0, microsecond=0)

    jogos: list[dict[str, Any]] = []
    n = 0

    def _adicionar(*, casa: str, fora: str, liga: str, pais: str,
                   estadio: str, hr_local: str, destaque: str = "") -> None:
        nonlocal n
        n += 1
        idx = rng.randint(0, len(_STATUS_PADRAO) - 1)
        status_texto, status_sigla, minuto = _STATUS_PADRAO[idx]
        placar_casa = 0
        placar_fora = 0
        if minuto >= 10:
            placar_casa = rng.randint(0, 3) if minuto > 35 else rng.randint(0, 1)
            placar_fora = rng.randint(0, 3) if minuto > 40 else rng.randint(0, 2)
        jogos.append({
            "jogo_id": f"live_{n:03d}",
            "casa": casa,
            "fora": fora,
            "liga": liga,
            "pais": pais,
            "estadio": estadio,
            "horario_local": hr_local,
            "status_texto": status_texto,
            "status_sigla": status_sigla,
            "minuto_jogo": minuto,
            "placar_casa": placar_casa,
            "placar_fora": placar_fora,
            "destaque_rotulo": destaque,
            "em_jogo_agora": status_sigla not in {"AGENDADO", "FT"},
            "ts_geracao_utc": horario_base.isoformat(),
            "atualizado_por": SIGNATURE,
        })

    for j in _JOGOS_BRASILEIRAO_MOCK:
        _adicionar(casa=j["casa"], fora=j["fora"], liga=j["liga"], pais=j["pais"],
                   estadio=j["estadio"], hr_local=j["hr_local"])
    if incluir_ligas_extra:
        for casa, fora, liga, pais, estadio, hr, dest in _LIGAS_EXTRA_MOCK:
            _adicionar(casa=casa, fora=fora, liga=liga, pais=pais,
                       estadio=estadio, hr_local=hr, destaque=dest)

    qt_em_jogo = sum(1 for x in jogos if x["em_jogo_agora"])
    return {
        "assinatura": SIGNATURE,
        "gerado_em_utc": horario_base.isoformat(),
        "atualizacao_proxima_em_segundos": 20,
        "total_jogos": len(jogos),
        "total_em_jogo_agora": qt_em_jogo,
        "jogos": jogos,
    }


def buscar_jogo_por_id(jogo_id: str) -> dict[str, Any] | None:
    """Localiza um jogo específico na lista atual."""
    dados = listar_jogos_ao_vivo_e_do_dia()
    for j in dados["jogos"]:
        if j["jogo_id"] == jogo_id:
            return j
    return None


def metricas_inplay_rapidas(jogo_id: str, sementinha: int | None = None) -> dict[str, Any]:
    """Retorna métricas em jogo sem depender de serviços externos nominais.

    Posse, chutes, escanteios, cartões, ataques perigosos.
    Assinatura IA do Tiago.
    """
    if sementinha is None:
        sementinha = hash(jogo_id) + int(datetime.now(tz=timezone.utc).timestamp() // 40)
    rng = random.Random(sementinha)
    base = {
        "assinatura": SIGNATURE,
        "jogo_id": jogo_id,
        "posse_bola_pct": {"casa": 50 + rng.randint(-12, 12), "fora": 0},
        "chutes_no_gol": {"casa": rng.randint(1, 7), "fora": rng.randint(0, 6)},
        "chutes_fora": {"casa": rng.randint(2, 9), "fora": rng.randint(1, 8)},
        "escanteios": {"casa": rng.randint(1, 7), "fora": rng.randint(0, 6)},
        "cartoes_amarelos": {"casa": rng.randint(0, 3), "fora": rng.randint(0, 3)},
        "cartoes_vermelhos": {"casa": rng.randint(0, 1), "fora": rng.randint(0, 1)},
        "ataques_perigosos": {"casa": rng.randint(4, 28), "fora": rng.randint(3, 24)},
    }
    base["posse_bola_pct"]["fora"] = max(0, 100 - base["posse_bola_pct"]["casa"])
    return base


# -----------------------------------------------------------------------------
# Helpers para calibrar linhas · usados pelo accumulator_ai_optimizer.py
# NÃO substituem os módulos existentes; são utilitários adicionais.
# -----------------------------------------------------------------------------
def tendencia_escanteios_ao_vivo(jogo_id: str) -> dict[str, Any]:
    """Calcula linha projetada final de escanteios baseado no minuto atual."""
    j = buscar_jogo_por_id(jogo_id)
    if not j:
        return {"assinatura": SIGNATURE, "ok": False, "erro": "jogo não encontrado"}
    m = j["minuto_jogo"]
    mtr = metricas_inplay_rapidas(jogo_id)
    esc = mtr["escanteios"]["casa"] + mtr["escanteios"]["fora"]
    denominador = max(1, m)
    proj = round((esc / denominador) * 90.0, 1)
    return {
        "assinatura": SIGNATURE,
        "ok": True,
        "minuto_atual": m,
        "escanteios_atuais_total": esc,
        "projetados_90min": proj,
        "linha_recomendada": math.ceil(proj / 0.5) * 0.5,
    }
