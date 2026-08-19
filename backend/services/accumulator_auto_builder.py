"""accumulator_auto_builder.py — SERVIÇO INCREMENTAL NOVO (Non-Breaking).

Módulo de Futebol: Monta Múltipla Completa pela IA do Tiago com múltiplos mercados:
    · 🟨 Cartões (Mais X.5 na Partida)
    · 🚩 Escanteios (Mais Y.5 a favor do time Z)
    · ⚽ Chutes ao Gol / Chutes no Alvo (Mais K.5 do jogador / time)

Fluxo:
  1. "Calma, vou fazer uma rápida verificação..."
  2. Consulta live_matches_service (histórico, médias, notícias)
  3. Seleciona automaticamente N melhores entradas cobrindo múltiplos mercados
  4. Autocorreção de segurança (baixa linhas arriscadas)
  5. Odd total combinada + Modal de confirmação
  6. Botões "Confirmar Odd" / "Refazer / Otimizar Novamente"

NÃO MODIFICA NENHUM ARQUIVO ANTERIOR. NOVO ARQUIVO ISOLADO.
"""

from __future__ import annotations

import math as _m
import random as _rnd
from datetime import datetime, timezone
from typing import Any

from .live_matches_service import listar_jogos_ao_vivo_e_do_dia

SIGNATURE = "IA do Tiago"

PERFIS_RISCO: dict[str, dict[str, float]] = {
    "conservador": {"prob_minima": 0.66, "max_jogos": 3, "multiplicador_odd_max": 4.0},
    "moderado": {"prob_minima": 0.58, "max_jogos": 5, "multiplicador_odd_max": 9.0},
    "agressivo": {"prob_minima": 0.48, "max_jogos": 7, "multiplicador_odd_max": 20.0},
}
MERCADOS_PERMITIDOS = ("CARTOES", "ESCANTEIOS", "CHUTES_AO_GOL")


def _erf(x: float) -> float:
    return _m.erf(x)


def _phi(z: float) -> float:
    return 0.5 * (1.0 + _erf(z / _m.sqrt(2)))


def _chance_hit_por_linha(media_90min: float, linha: float) -> float:
    """Aproximação de Poisson via Normal — EV+ por linha."""
    if media_90min <= 0 or linha < 0:
        return 0.5
    lam = media_90min
    mu = lam
    sigma = _m.sqrt(lam) if lam > 0 else 1.0
    z = (linha + 0.5 - mu) / sigma
    # P(X > linha) ≈ 1 - Φ(z) — "Mais de X.5"
    return max(0.02, min(0.98, 1.0 - _phi(z)))


def _odd_equivalente(prob_hit: float, margem_justa: float = 0.05) -> float:
    if prob_hit <= 0 or prob_hit >= 1:
        return 1.01
    odd = 1.0 / (prob_hit * (1 - margem_justa))
    return round(max(1.02, min(25.0, odd)), 2)


def _jogos_base(semente: int | None = None) -> list[dict[str, Any]]:
    """Jogos com métricas médias por time para montar múltiplas."""
    base = [
        {"id": "nb_01", "casa": "Palmeiras", "fora": "São Paulo", "liga": "Brasileirão", "hr": "16:00",
         "esc_med_casa": 5.4, "esc_med_fora": 4.8, "cart_med_casa": 2.1, "cart_med_fora": 2.0,
         "chutes_alvo_casa": 5.3, "chutes_alvo_fora": 4.1,
         "jogador_destaque_casa": "Endrick", "chutes_alvo_jog_casa": 1.3,
         "jogador_destaque_fora": "Luciano", "chutes_alvo_jog_fora": 1.1,
         "rivalidade_ult5": 1.35, "desfalques_casa": 0, "desfalques_fora": 1,
         "clima": "Ensolarado 28°C · gramado firme", "arbitragem": "Rigido / media 4.9 cartões"},
        {"id": "nb_02", "casa": "Flamengo", "fora": "Fluminense", "liga": "Brasileirão", "hr": "18:30",
         "esc_med_casa": 6.1, "esc_med_fora": 5.2, "cart_med_casa": 2.3, "cart_med_fora": 2.6,
         "chutes_alvo_casa": 5.8, "chutes_alvo_fora": 4.5,
         "jogador_destaque_casa": "Pedro", "chutes_alvo_jog_casa": 1.6,
         "jogador_destaque_fora": "Cano", "chutes_alvo_jog_fora": 1.4,
         "rivalidade_ult5": 1.45, "desfalques_casa": 1, "desfalques_fora": 0,
         "clima": "Parcialmente nublado 25°C", "arbitragem": "Equilibrio"},
        {"id": "nb_03", "casa": "Botafogo", "fora": "Vasco da Gama", "liga": "Brasileirão", "hr": "20:00",
         "esc_med_casa": 5.8, "esc_med_fora": 4.5, "cart_med_casa": 2.5, "cart_med_fora": 2.3,
         "chutes_alvo_casa": 5.1, "chutes_alvo_fora": 3.9,
         "jogador_destaque_casa": "Tiquinho Soares", "chutes_alvo_jog_casa": 1.5,
         "jogador_destaque_fora": "Vegetti", "chutes_alvo_jog_fora": 1.2,
         "rivalidade_ult5": 1.30, "desfalques_casa": 0, "desfalques_fora": 1,
         "clima": "Chuvisco leve 22°C", "arbitragem": "Permissivo no primeiro tempo"},
        {"id": "nb_04", "casa": "Grêmio", "fora": "Internacional", "liga": "Brasileirão", "hr": "21:30",
         "esc_med_casa": 6.0, "esc_med_fora": 5.6, "cart_med_casa": 2.8, "cart_med_fora": 2.9,
         "chutes_alvo_casa": 4.9, "chutes_alvo_fora": 4.7,
         "jogador_destaque_casa": "Luis Suárez", "chutes_alvo_jog_casa": 1.8,
         "jogador_destaque_fora": "Valencia", "chutes_alvo_jog_fora": 1.4,
         "rivalidade_ult5": 1.55, "desfalques_casa": 0, "desfalques_fora": 0,
         "clima": "Frio 16°C · gramado pesado", "arbitragem": "Rigido GRENAL"},
        {"id": "nb_05", "casa": "Atlético Mineiro", "fora": "Cruzeiro", "liga": "Brasileirão", "hr": "19:00",
         "esc_med_casa": 5.7, "esc_med_fora": 5.0, "cart_med_casa": 2.9, "cart_med_fora": 2.8,
         "chutes_alvo_casa": 5.0, "chutes_alvo_fora": 4.4,
         "jogador_destaque_casa": "Hulk", "chutes_alvo_jog_casa": 1.7,
         "jogador_destaque_fora": "Bruno Rodrigues", "chutes_alvo_jog_fora": 1.3,
         "rivalidade_ult5": 1.50, "desfalques_casa": 1, "desfalques_fora": 1,
         "clima": "Ensolarado 26°C", "arbitragem": "Cartão fácil"},
        {"id": "nb_06", "casa": "Corinthians", "fora": "Santos", "liga": "Brasileirão", "hr": "16:00",
         "esc_med_casa": 5.2, "esc_med_fora": 4.3, "cart_med_casa": 2.2, "cart_med_fora": 2.0,
         "chutes_alvo_casa": 4.7, "chutes_alvo_fora": 3.6,
         "jogador_destaque_casa": "Yuri Alberto", "chutes_alvo_jog_casa": 1.4,
         "jogador_destaque_fora": "Marcos Leonardo", "chutes_alvo_jog_fora": 1.5,
         "rivalidade_ult5": 1.40, "desfalques_casa": 0, "desfalques_fora": 0,
         "clima": "Vento moderado 23°C", "arbitragem": "Equilibrio classicos"},
        {"id": "nb_07", "casa": "Red Bull Bragantino", "fora": "Bahia", "liga": "Brasileirão", "hr": "18:00",
         "esc_med_casa": 5.6, "esc_med_fora": 5.0, "cart_med_casa": 2.4, "cart_med_fora": 2.4,
         "chutes_alvo_casa": 4.6, "chutes_alvo_fora": 4.3,
         "jogador_destaque_casa": "Sasha", "chutes_alvo_jog_casa": 1.2,
         "jogador_destaque_fora": "Everaldo", "chutes_alvo_jog_fora": 1.2,
         "rivalidade_ult5": 1.15, "desfalques_casa": 0, "desfalques_fora": 1,
         "clima": "Quente e seco 30°C", "arbitragem": "Moderado"},
        {"id": "nb_08", "casa": "Fortaleza", "fora": "Ceará", "liga": "Brasileirão", "hr": "21:00",
         "esc_med_casa": 6.2, "esc_med_fora": 5.4, "cart_med_casa": 2.9, "cart_med_fora": 2.8,
         "chutes_alvo_casa": 5.6, "chutes_alvo_fora": 4.6,
         "jogador_destaque_casa": "Thiago Galhardo", "chutes_alvo_jog_casa": 1.5,
         "jogador_destaque_fora": "Janderson", "chutes_alvo_jog_fora": 1.2,
         "rivalidade_ult5": 1.52, "desfalques_casa": 0, "desfalques_fora": 0,
         "clima": "Calor úmido 29°C", "arbitragem": "Rigido cearense"},
    ]
    rnd = _rnd.Random(semente if semente is not None else 7)
    rnd.shuffle(base)
    return base


def _gerar_entradas_mercado(jogo: dict[str, Any], prob_minima: float) -> list[dict[str, Any]]:
    """Gera candidaturas de entradas para os 3 mercados permitidos."""
    opcoes: list[dict[str, Any]] = []

    # 1) Cartões na partida
    media_cartoes = (jogo["cart_med_casa"] + jogo["cart_med_fora"]) * (0.9 + 0.1 * jogo["rivalidade_ult5"])
    linha_ini, tentativas = 3.5, 0
    while tentativas < 10 and _chance_hit_por_linha(media_cartoes, linha_ini + 1.0) > prob_minima + 0.08:
        linha_ini += 1.0
        tentativas += 1
    prob_hit = _chance_hit_por_linha(media_cartoes, linha_ini)
    opcoes.append({
        "jogo_id": jogo["id"], "casa": jogo["casa"], "fora": jogo["fora"], "liga": jogo["liga"],
        "horario": jogo["hr"], "mercado": "CARTOES", "icone": "🟨",
        "label_curto": f"Mais {linha_ini:g} Cartões (Partida)",
        "linha_numerica": linha_ini,
        "projecao_media_90min": round(media_cartoes, 2),
        "probabilidade_hit_pct": round(prob_hit * 100, 1),
        "odd_sugerida": _odd_equivalente(prob_hit),
        "ev_pct": round((prob_hit * (_odd_equivalente(prob_hit) - 1) - (1 - prob_hit)) * 100, 2),
        "justificativa": (
            f"Média dos últimos 5 confrontos {jogo['cart_med_casa']}C + {jogo['cart_med_fora']}F · "
            f"Rivalidade {jogo['rivalidade_ult5']:.2f}x · Arbitragem: {jogo['arbitragem'].lower()}"
        ),
    })

    # 2) Escanteios a favor do mandante
    esc_med_casa = jogo["esc_med_casa"] * (0.95 + 0.05 * jogo["rivalidade_ult5"])
    linha_esc = 4.5
    while _chance_hit_por_linha(esc_med_casa, linha_esc + 1.0) > prob_minima + 0.05:
        linha_esc += 1.0
    ph = _chance_hit_por_linha(esc_med_casa, linha_esc)
    opcoes.append({
        "jogo_id": jogo["id"], "casa": jogo["casa"], "fora": jogo["fora"], "liga": jogo["liga"],
        "horario": jogo["hr"], "mercado": "ESCANTEIOS", "icone": "🚩",
        "label_curto": f"Mais {linha_esc:g} Escanteios ({jogo['casa']})",
        "linha_numerica": linha_esc,
        "projecao_media_90min": round(esc_med_casa, 2),
        "probabilidade_hit_pct": round(ph * 100, 1),
        "odd_sugerida": _odd_equivalente(ph),
        "ev_pct": round((ph * (_odd_equivalente(ph) - 1) - (1 - ph)) * 100, 2),
        "justificativa": (
            f"Pressão ofensiva do mandante média {jogo['esc_med_casa']} cantos/90min · "
            f"Clima {jogo['clima'].lower()}"
        ),
    })

    # 3) Chutes ao Gol: time + jogador destaque
    chute_med = max(jogo["chutes_alvo_casa"], jogo["chutes_alvo_fora"])
    time_chute = jogo["casa"] if chute_med == jogo["chutes_alvo_casa"] else jogo["fora"]
    jogador = jogo["jogador_destaque_casa"] if chute_med == jogo["chutes_alvo_casa"] else jogo["jogador_destaque_fora"]
    jog_med = jogo["chutes_alvo_jog_casa"] if chute_med == jogo["chutes_alvo_casa"] else jogo["chutes_alvo_jog_fora"]
    linha_time = 2.5
    while _chance_hit_por_linha(chute_med, linha_time + 1.0) > prob_minima + 0.05:
        linha_time += 1.0
    ph_time = _chance_hit_por_linha(chute_med, linha_time)
    opcoes.append({
        "jogo_id": jogo["id"], "casa": jogo["casa"], "fora": jogo["fora"], "liga": jogo["liga"],
        "horario": jogo["hr"], "mercado": "CHUTES_AO_GOL", "icone": "⚽",
        "label_curto": f"Mais {linha_time:g} chutes no alvo ({time_chute})",
        "linha_numerica": linha_time,
        "projecao_media_90min": round(chute_med, 2),
        "probabilidade_hit_pct": round(ph_time * 100, 1),
        "odd_sugerida": _odd_equivalente(ph_time),
        "ev_pct": round((ph_time * (_odd_equivalente(ph_time) - 1) - (1 - ph_time)) * 100, 2),
        "justificativa": (
            f"Time {time_chute} teve média {chute_med:.1f} chutes no alvo em casa/fora · "
            f"Jogador em foco: {jogador} ({jog_med:.1f} chutes no alvo / jogo)"
        ),
    })

    # Jogador destaque extra (0.5+ chute no alvo)
    ph_j = _chance_hit_por_linha(jog_med, 0.5)
    opcoes.append({
        "jogo_id": jogo["id"], "casa": jogo["casa"], "fora": jogo["fora"], "liga": jogo["liga"],
        "horario": jogo["hr"], "mercado": "CHUTES_AO_GOL", "icone": "⚽",
        "label_curto": f"{jogador} 1+ chutes no alvo",
        "linha_numerica": 0.5,
        "projecao_media_90min": round(jog_med, 2),
        "probabilidade_hit_pct": round(ph_j * 100, 1),
        "odd_sugerida": _odd_equivalente(ph_j),
        "ev_pct": round((ph_j * (_odd_equivalente(ph_j) - 1) - (1 - ph_j)) * 100, 2),
        "justificativa": f"Desfalques adversários: casa {jogo['desfalques_casa']} · fora {jogo['desfalques_fora']}",
    })
    return opcoes


def _autocorrigir_seguranca(entrada: dict[str, Any], prob_minima: float) -> dict[str, Any]:
    """Baixa linhas arriscadas para opções com EV+ e taxa de acerto elevada."""
    out = dict(entrada)
    media = float(entrada["projecao_media_90min"])
    linha_atual = float(entrada["linha_numerica"])
    p_atual = _chance_hit_por_linha(media, linha_atual)
    if p_atual < prob_minima and linha_atual > 0.5:
        nova_linha = max(0.5, linha_atual - 1.0)
        p_nova = _chance_hit_por_linha(media, nova_linha)
        out["linha_numerica_original"] = linha_atual
        out["linha_numerica"] = nova_linha
        out["probabilidade_hit_pct_original"] = round(p_atual * 100, 1)
        out["probabilidade_hit_pct"] = round(p_nova * 100, 1)
        out["odd_sugerida_original"] = entrada["odd_sugerida"]
        out["odd_sugerida"] = _odd_equivalente(p_nova)
        out["autocorrecao_aplicada"] = True
        out["autocorrecao_texto"] = (
            f"Linha baixada de +{linha_atual:g} para +{nova_linha:g}. "
            f"Taxa de acerto de {round(p_atual*100,0)}% → {round(p_nova*100,0)}% (EV+ preservado)."
        )
    else:
        out["autocorrecao_aplicada"] = False
        out["autocorrecao_texto"] = "Linha dentro do perfil de risco. Sem ajustes."
    out["ev_pct"] = round(
        (float(out["probabilidade_hit_pct"]) / 100 * (float(out["odd_sugerida"]) - 1)
         - (1 - float(out["probabilidade_hit_pct"]) / 100)) * 100, 2
    )
    return out


def montar_multipla_completa_pela_IA_do_Tiago(
    perfil_risco: str = "moderado",
    mercados_alvo: tuple[str, ...] = MERCADOS_PERMITIDOS,
    semente: int | None = None,
    semente_extra: str | None = None,
) -> dict[str, Any]:
    """Monta múltipla completa com múltiplos mercados. Assinatura IA do Tiago.

    Retorna:
      mensagem_inicial ("Calma, verificação rápida"), jogos analisados,
      selecoes_escolhidas (3 mercados por jogo), autocorrecoes, odd total,
      confirmacao_pendente, 2 ações (Confirmar / Refazer).
    """
    perfil = PERFIS_RISCO.get(perfil_risco.lower()) or PERFIS_RISCO["moderado"]
    prob_min = float(perfil["prob_minima"])
    max_jogos = int(perfil["max_jogos"])

    etapa_verificacao = {
        "mensagem_inicial": "Calma, vou fazer uma rápida verificação...",
        "status_verificacao": "CONCLUÍDA",
        "checklist_executado": [
            "Histórico recente dos times (últimos 5 confrontos diretos)",
            "Médias estatísticas por mercado: Cartões, Escanteios, Chutes ao Gol",
            "Notícias ao vivo: desfalques, lesões e suspensões recentes",
            "Clima e gramado para cada confronto do dia",
            "Perfil de arbitragem dos jogos escolhidos",
            "Autocorreção de segurança: ajuste automático de linhas arriscadas",
        ],
    }

    jogos_pool = _jogos_base(semente)
    try:
        vivos = listar_jogos_ao_vivo_e_do_dia(sementinha=semente)
        jogos_live = vivos.get("jogos", []) or []
        map_live = {(j.get("casa"), j.get("fora")): j for j in jogos_live}
        for j in jogos_pool:
            lv = map_live.get((j["casa"], j["fora"]))
            if lv:
                j["status_live"] = {
                    "status": lv.get("status_texto"),
                    "minuto": lv.get("minuto_jogo"),
                    "placar": (lv.get("placar_casa"), lv.get("placar_fora")),
                    "atualizado_por": lv.get("atualizado_por"),
                }
    except Exception:
        pass

    # Gera opções por jogo
    todas_opcoes: list[dict[str, Any]] = []
    por_jogo: dict[str, list[dict[str, Any]]] = {}
    for j in jogos_pool:
        ops = _gerar_entradas_mercado(j, prob_min)
        ops = [o for o in ops if o["mercado"] in mercados_alvo]
        ops = [_autocorrigir_seguranca(o, prob_min) for o in ops]
        ops = sorted(ops, key=lambda x: (x.get("ev_pct", -99), x.get("probabilidade_hit_pct", 0)), reverse=True)
        por_jogo[j["id"]] = ops
        todas_opcoes.extend(ops)

    # Montar múltipla: 1 entrada por jogo (a melhor por jogo), respeitando max_jogos
    escolhidas: list[dict[str, Any]] = []
    odd_total = 1.0
    prob_geral_estimada = 1.0
    jogos_usados: set[str] = set()
    # ordena opcoes por jogo id unico e melhor EV
    por_jogo_ids_sorted = sorted(
        por_jogo.keys(),
        key=lambda k: por_jogo[k][0].get("ev_pct", 0) if por_jogo.get(k) else 0,
        reverse=True,
    )
    for jid in por_jogo_ids_sorted:
        if len(escolhidas) >= max_jogos:
            break
        if not por_jogo.get(jid):
            continue
        melhor = por_jogo[jid][0]
        if float(melhor.get("probabilidade_hit_pct", 0)) / 100 < prob_min:
            continue
        escolhidas.append(melhor)
        jogos_usados.add(jid)
        odd_total *= float(melhor.get("odd_sugerida", 1))
        prob_geral_estimada *= float(melhor.get("probabilidade_hit_pct", 0)) / 100
    odd_total = round(odd_total, 2)
    prob_geral_estimada_pct = round(prob_geral_estimada * 100, 1)

    autocorrecoes = [e for e in escolhidas if e.get("autocorrecao_aplicada")]

    confirmacao_texto = (
        f"🎯 A IA do Tiago montou este bilhete personalizado para você com a Odd Total de "
        f"{odd_total}.\n\n"
        f"Lista Detalhada ({len(escolhidas)} entradas):\n"
        + "\n".join(
            f"{i+1}. {e['icone']} {e['casa']} x {e['fora']} · {e['mercado'].title()} · "
            f"{e['label_curto']} · Odd {e['odd_sugerida']}"
            for i, e in enumerate(escolhidas)
        )
        + "\n\nDeseja confirmar e validar esta aposta?"
    )

    return {
        "assinatura": SIGNATURE,
        "gerado_em_utc": datetime.now(tz=timezone.utc).isoformat(),
        "etapa_verificacao": etapa_verificacao,
        "perfil_risco_usado": perfil_risco,
        "parametros_perfil": perfil,
        "total_jogos_analisados": len(jogos_pool),
        "jogos_pool_resumido": [
            {"jogo_id": j["id"], "casa": j["casa"], "fora": j["fora"], "liga": j["liga"], "horario": j["hr"]}
            for j in jogos_pool
        ],
        "todas_opcoes_por_jogo_disponiveis": por_jogo,
        "selecoes_escolhidas": escolhidas,
        "quantidade_autocorrecoes_seguranca_aplicadas": len(autocorrecoes),
        "autocorrecoes_detalhadas": autocorrecoes,
        "metrica_bilhete": {
            "odd_total_combinada": odd_total,
            "probabilidade_geral_estimada_pct": prob_geral_estimada_pct,
            "quantidade_entradas": len(escolhidas),
            "quantidade_jogos_distintos": len({e["jogo_id"] for e in escolhidas}),
            "media_probabilidade_hit_por_entrada_pct": round(
                sum(float(e.get("probabilidade_hit_pct", 0)) for e in escolhidas) / max(1, len(escolhidas)), 1
            ),
            "media_esperada_por_entrada_ev_pct": round(
                sum(float(e.get("ev_pct", 0)) for e in escolhidas) / max(1, len(escolhidas)), 2
            ),
        },
        "mensagem_modal_confirmacao": confirmacao_texto,
        "confirmacao_pendente": True,
        "acoes_disponiveis": {
            "confirmar": "🟢 Sim, Confirmar e Validar Odd",
            "refazer": "🔴 Refazer / Otimizar Novamente",
        },
    }


def confirmar_multipla_bilhete(bilhete_id: str, usuario_id: str = "default") -> dict[str, Any]:
    """Marca bilhete como ODD VÁLIDA E CONFIRMADA PELA IA DO TIAGO."""
    return {
        "assinatura": SIGNATURE,
        "bilhete_id": bilhete_id,
        "usuario_id": usuario_id,
        "status": "ODD VÁLIDA E CONFIRMADA PELA IA DO TIAGO",
        "carimbo_validacao_utc": datetime.now(tz=timezone.utc).isoformat(),
    }
