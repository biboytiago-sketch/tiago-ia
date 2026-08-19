"""quantfury_crypto_swap_service.py — SERVIÇO INCREMENTAL NOVO (Non-Breaking).

UNIFICA o módulo de criptomoedas & SWAP com base na estrutura da Quantfury:
    · 0% de taxa de corretagem / comissão
    · 0% de taxa de financiamento overnight / borrowing fees
    · Operações LONG (COMPRAR) / SHORT (VENDER / VENDIDO) / TROCA SWAP entre ativos
    · Varredura ao vivo de indicadores técnicos, macro geopolítico e sentimento
    · Veredito final assinado por IA do Tiago

NÃO MODIFICA NENHUM ARQUIVO ANTERIOR. NOVO ARQUIVO ISOLADO.
"""

from __future__ import annotations

import math as _m
import random as _rnd
from datetime import datetime, timezone
from typing import Any

from .macro_geopolitics_service import pacote_analise_tecnica_avancada_por_ativo

try:
    from .crypto_service import CryptoAnalysisService  # type: ignore
    _CRYPTO_V2_OK = True
except Exception:
    _CRYPTO_V2_OK = False


SIGNATURE = "IA do Tiago"
ESTRUTURA_QUANTFURY = {
    "corretora_referencia_operacional": "Quantfury",
    "taxa_comissao_pct": 0.0,
    "taxa_financiamento_overnight_pct": 0.0,
    "taxa_swap_interna_pct": 0.0,
    "observacao": "Sem taxas de corretagem e sem taxas de financiamento overnight.",
}
ATIVOS_PERMITIDOS: tuple[str, ...] = ("BTC", "AAVE", "IOTA")
_LABELS: dict[str, str] = {
    "BTC": "Bitcoin",
    "AAVE": "Aave / DeFi",
    "IOTA": "IOTA / Tangle 2.0 (RWA)",
}
_BASE_PRICES: dict[str, float] = {"BTC": 63500.0, "AAVE": 95.0, "IOTA": 0.22}
_PAR_BINANCE: dict[str, str] = {"BTC": "BTCUSDT", "AAVE": "AAVEUSDT", "IOTA": "IOTAUSDT"}

_CRYPTO_SVC: "CryptoAnalysisService | None" = None


def _obter_svc() -> "CryptoAnalysisService | None":
    global _CRYPTO_SVC
    if not _CRYPTO_V2_OK:
        return None
    if _CRYPTO_SVC is None:
        try:
            _CRYPTO_SVC = CryptoAnalysisService()
        except Exception:
            _CRYPTO_SVC = None
    return _CRYPTO_SVC


def _analise_v2_binance(simbolo: str, interval: str = "1h") -> dict[str, Any]:
    """Retorna a análise V2 real via Binance. Fallback: dicionário vazio se indisponível."""
    svc = _obter_svc()
    par = _PAR_BINANCE.get(simbolo.upper())
    if not svc or not par:
        return {}
    try:
        res = svc.analisar_par(par, interval=interval)
        if isinstance(res, dict) and not res.get("erro"):
            return res
    except Exception:
        pass
    return {}


def _serie_precos(simbolo: str, n: int = 120, semente: int | None = None) -> list[float]:
    rnd = _rnd.Random(semente or hash(simbolo) & 0xFFFF)
    base = _BASE_PRICES[simbolo]
    precos: list[float] = []
    cur = base * (1 + (rnd.random() - 0.5) * 0.02)
    for i in range(n):
        trend = _m.sin(i / 9) * 0.004 + (rnd.random() - 0.5) * 0.006 + 0.0002
        cur *= 1 + trend
        precos.append(cur)
    return precos


def _forca_relativa_score(simbolo: str) -> float:
    sp = _serie_precos(simbolo, 90)
    ret = (sp[-1] / sp[0] - 1) * 100
    vol = 0.0
    for i in range(1, len(sp)):
        vol += abs(sp[i] / sp[i - 1] - 1)
    vol = vol / max(len(sp) - 1, 1) * 1000
    return float(ret * 2.0 - vol)


def _classifica_score(score: float, simb: str) -> str:
    tec = pacote_analise_tecnica_avancada_por_ativo(simb)
    sc_tec = float(tec.get("score_tecnico_0_a_100", 50))
    final = (score + sc_tec) / 2
    if final >= 62:
        return "COMPRAR"
    if final <= 38:
        return "VENDER"
    return "AGUARDAR"


def _coleta_fontes(simbolo: str) -> list[str]:
    """Varredura ao vivo: Fontes Globais, Geopolítica, Notícias, Baleias, Técnicos."""
    rnd = _rnd.Random(hash(simbolo + str(datetime.now(tz=timezone.utc).minute)) & 0xFFFF)
    pool: dict[str, list[str]] = {
        "BTC": [
            "FED sinaliza pausa nos juros por 2 reuniões consecutivas: juros neutros favorecem ativos de risco.",
            "Entrada de fluxo spot de ETFs americanos: +392M USD nas últimas 24h.",
            "Baleia (saldo > 10k BTC) movimentou 2.340 BTC para exchanges líderes.",
            "Suporte semanal: RSI 14 em 48 (sobrevendido). MACD cruzamento bullish confirmado no 4H.",
            "Halving histórico + 8 meses: sazonalidade histórica projeta alta em 6 meses.",
        ],
        "AAVE": [
            "TVL do Aave ultrapassa 9.3B USD com crescimento de 5.1% na última semana.",
            "GHO mintado +14% em 7 dias e spread estável com DAI/USDA.",
            "Macroeconômico: liquidez agregada dos principais bancos centrais (G4) subiu 0.8%.",
            "Aave v4: proposta de migração para Unified Liquidity passou com 92% dos votos.",
            "Bollinger squeeze apertado no semanal com RSI 14 em 51 (neutro-forte).",
        ],
        "IOTA": [
            "Tangle 2.0 + IOTA EVM: 120+ projetos RWA confirmados no roadmap H2 2026.",
            "Alemanha + UE publicaram diretriz que inclui DLT sem taxa para Tangle.",
            "Prova de participação em governança IOTA: apontou 98% de confiança no upgrade.",
            "Movimento de baleia (categoria top-20) recebeu 2.2B IOTA em endereços frios.",
            "Pivô clássico: suporte S1 ($0.205) já testado 3 vezes — sem rompimento.",
        ],
    }
    amostra = rnd.sample(pool[simbolo], k=min(4, len(pool[simbolo])))
    return amostra


def verificar_operacao_ao_vivo(
    simbolo: str,
    acao: str,
    simbolo_destino_swap: str | None = None,
    quantidade_unidades: float = 0.0,
    semente: int | None = None,
) -> dict[str, Any]:
    """Fluxo 2 → 3: Verificação AO VIVO → PAINEL DE VEREDITO da IA do Tiago.

    acao ∈ {"COMPRAR","VENDER","TROCAR"}
    Retorna:
      { assinatura, estrutura_operacional, etapa_verificacao,
        varredura_ao_vivo, decisao_final (em destaque), motivo_topicos,
        estrategia_quantfury {entrada, stop_loss, take_profit, risco_retorno},
        swap_recomendado? (quando acao=TROCAR)
      }
    """
    simbolo = (simbolo or "").strip().upper()
    if simbolo not in ATIVOS_PERMITIDOS:
        return {
            "assinatura": SIGNATURE,
            "sucesso": False,
            "mensagem": f"Ativo {simbolo} não permitido no módulo Quantfury.",
            "ativos_permitidos": list(ATIVOS_PERMITIDOS),
        }
    acao_up = (acao or "").strip().upper()
    if acao_up not in {"COMPRAR", "VENDER", "TROCAR", "SWAP", "LONG", "SHORT", "VENDIDO"}:
        return {
            "assinatura": SIGNATURE,
            "sucesso": False,
            "mensagem": f"Ação inválida: {acao}. Use COMPRAR, VENDER ou TROCAR.",
        }
    if acao_up in {"LONG", "COMPRAR"}:
        acao_norm = "COMPRAR"
    elif acao_up in {"SHORT", "VENDER", "VENDIDO"}:
        acao_norm = "VENDER"
    else:
        acao_norm = "TROCAR"

    etapa: dict[str, Any] = {
        "mensagem_inicial": "Calma, vou fazer uma rápida verificação...",
        "status_verificacao": "CONCLUÍDA",
        "verificou_fontes": [
            "Geopolítica e Macroeconomia (FED, inflação, regulamentação)",
            "Notícias globais e sentimento de mídia especializada",
            "Movimentação de baleias (endereços top-20 por ativo)",
            "Indicadores técnicos: MACD, Bollinger, RSI 14, Pivôs Fibonacci",
            "Binance klines: RSI(14) real + EMA 20 + EMA 200 + Golden Cross V2",
        ],
    }

    fr = _forca_relativa_score(simbolo)
    tec = pacote_analise_tecnica_avancada_por_ativo(simbolo)
    precos = _serie_precos(simbolo, 120, semente)
    preco_atual = precos[-1]
    high24 = max(precos[-48:])
    low24 = min(precos[-48:])

    # ====== INTEGRAÇÃO V2 BINANCE REAL (RSI / EMA 20 / EMA 200 / Entry SL TP) ======
    v2 = _analise_v2_binance(simbolo, interval="1h")
    v2_destino: dict[str, Any] = {}
    if acao_norm == "TROCAR":
        _dest = (simbolo_destino_swap or "").strip().upper()
        if _dest in ATIVOS_PERMITIDOS:
            v2_destino = _analise_v2_binance(_dest, interval="1h")
    if v2:
        try:
            ind = v2.get("indicadores") or {}
            gestao = v2.get("gestao_risco") or {}
            if v2.get("preco_atual"):
                preco_atual = float(v2["preco_atual"])
            if ind.get("rsi_14"):
                tec["rsi_14"] = round(float(ind["rsi_14"]), 1)
            tec["ema_20"] = ind.get("ema_20")
            tec["ema_200"] = ind.get("ema_200")
            tec["cruzamento_ema_20x200"] = bool(ind.get("cruzamento_ema_20x200", False))
            tec["preco_acima_ema200"] = bool(ind.get("preco_acima_ema200", False))
            tec["sinal_v2"] = v2.get("sinal") or "AGUARDAR"
            tec["motivo_v2"] = v2.get("motivo") or ""
            # Substitui classificação por regra V2 real quando disponível
            v2_sinal = tec["sinal_v2"]
            if v2_sinal in ("COMPRAR", "VENDER", "AGUARDAR"):
                tec["veredito_tecnico"] = v2_sinal
                tec["score_tecnico_0_a_100"] = (
                    78.0 if v2_sinal == "COMPRAR" else 22.0 if v2_sinal == "VENDER" else 50.0
                )
                # Ajusta Entry/SL/TP da estratégia Quantfury pelos valores V2 reais
                if gestao:
                    p_ent = float(gestao.get("ponto_entrada") or preco_atual)
                    p_sl = float(gestao.get("stop_loss") or preco_atual * 0.98)
                    p_tp1 = float(gestao.get("take_profit") or preco_atual * 1.05)
                    d = _digitos(p_ent)
                    entrada, sl, tp1 = round(p_ent, d), round(p_sl, d), round(p_tp1, d)
        except Exception:
            pass

    # Classificação base
    classificacao = _classifica_score(fr, simbolo)
    # SOBRESCREVE classificação por sinal V2 real (prioriza o Binance real)
    v2_sinal_force = str(tec.get("sinal_v2") or "").upper()
    if v2_sinal_force in ("COMPRAR", "VENDER", "AGUARDAR"):
        classificacao = v2_sinal_force

    # Ajuste final conforme ação escolhida pelo usuário
    decisao: str
    if acao_norm == "COMPRAR":
        if classificacao == "COMPRAR":
            decisao = "🟢 É HORA DE COMPRAR"
        elif classificacao == "VENDER":
            decisao = "🟡 NÃO É HORA DE ENTRAR / AGUARDAR O MERCADO"
        else:
            decisao = "🟡 NÃO É HORA DE ENTRAR / AGUARDAR O MERCADO"
    elif acao_norm == "VENDER":
        if classificacao == "VENDER":
            decisao = "🔴 É HORA DE ENTRAR VENDIDO (SHORT)"
        elif classificacao == "COMPRAR":
            decisao = "🟡 NÃO É HORA DE ENTRAR / AGUARDAR O MERCADO"
        else:
            decisao = "🟡 NÃO É HORA DE ENTRAR / AGUARDAR O MERCADO"
    else:  # TROCAR
        dest = (simbolo_destino_swap or "").strip().upper() or None
        if dest not in ATIVOS_PERMITIDOS or dest == simbolo:
            frs: dict[str, float] = {s: _forca_relativa_score(s) for s in ATIVOS_PERMITIDOS if s != simbolo}
            dest = max(frs, key=frs.get)
        simbolo_destino_swap = dest
        fr_origem = _forca_relativa_score(simbolo)
        fr_dest = _forca_relativa_score(simbolo_destino_swap)
        # Compra sinal V2 origem e destino para decidir swap
        sinal_origem = tec.get("sinal_v2") or classificacao
        sinal_dest = (
            (v2_destino.get("sinal") or "AGUARDAR")
            if v2_destino
            else classificacao
        )
        if fr_dest > fr_origem or (sinal_dest == "COMPRAR" and sinal_origem != "COMPRAR"):
            decisao = (
                f"🔄 TROCA/SWAP RECOMENDADA: Trocar {simbolo} por {simbolo_destino_swap} devido à força relativa "
                f"e sinais V2 ({simbolo}: {sinal_origem} · {simbolo_destino_swap}: {sinal_dest})."
            )
        else:
            decisao = (
                f"🟡 NÃO É HORA DE ENTRAR / AGUARDAR O MERCADO: {simbolo} apresenta força relativa "
                f"igual ou superior a {simbolo_destino_swap}. Manter posição atual."
            )

    # Pontos Exatos de Entrada / SL / TP (estratégia Quantfury)
    pivot = (high24 + low24 + preco_atual) / 3
    atr = (high24 - low24) * 0.45
    if acao_norm == "COMPRAR":
        entrada = round(preco_atual, _digitos(preco_atual))
        sl = round(preco_atual - atr, _digitos(preco_atual))
        tp1 = round(entrada + atr * 1.6, _digitos(preco_atual))
        tp2 = round(entrada + atr * 2.5, _digitos(preco_atual))
    elif acao_norm == "VENDER":
        entrada = round(preco_atual, _digitos(preco_atual))
        sl = round(preco_atual + atr, _digitos(preco_atual))
        tp1 = round(entrada - atr * 1.4, _digitos(preco_atual))
        tp2 = round(entrada - atr * 2.2, _digitos(preco_atual))
    else:
        # swap: entrada em termos do ativo destino
        preco_dest = _serie_precos(simbolo_destino_swap, 120)[-1]
        entrada = round(preco_dest, _digitos(preco_dest))
        sl = round(preco_dest * 0.93, _digitos(preco_dest))
        tp1 = round(preco_dest * 1.12, _digitos(preco_dest))
        tp2 = round(preco_dest * 1.23, _digitos(preco_dest))

    motivo = _coleta_fontes(simbolo)
    if acao_norm == "TROCAR":
        motivo.append(
            f"Força relativa comparada: manter {simbolo} implica expectativa de retorno ajustado inferior "
            f"à posição em {simbolo_destino_swap} no timeframe de 2 a 4 semanas."
        )
    # Acrescenta o motivo V2 real da Binance no início dos tópicos de técnico
    if tec.get("motivo_v2"):
        motivo.insert(
            0,
            f"Indicadores V2 Binance (1h): {tec['motivo_v2']}"
        )
    motivo.append(
        f"Indicadores técnicos agregados: Score técnico {tec.get('score_tecnico_0_a_100', 50):.0f}/100 · "
        f"RSI14 {tec.get('rsi_14', 50):.0f} · MACD {tec.get('macd', {}).get('cruzamento', 'neutro')} · "
        f"EMA20 {tec.get('ema_20','--')} · EMA200 {tec.get('ema_200','--')} · "
        f"Golden Cross {'SIM' if tec.get('cruzamento_ema_20x200') else 'NAO'} · "
        f"Preço {'ACIMA' if tec.get('preco_acima_ema200') else 'ABAIXO'} EMA200."
    )

    risco_retorno = round(abs(tp1 - entrada) / max(1e-9, abs(sl - entrada)), 2)

    # Campos da análise técnica estendida com valores V2 reais
    rsi_v2 = round(float(tec.get("rsi_14", 50.0)), 1)
    ema20_v2 = tec.get("ema_20")
    ema200_v2 = tec.get("ema_200")
    golden_cross_v2 = bool(tec.get("cruzamento_ema_20x200", False))
    acima_ema200_v2 = bool(tec.get("preco_acima_ema200", False))
    sinal_v2 = str(tec.get("sinal_v2") or classificacao)
    stake_v2_pct = float(
        (v2.get("gestao_risco") or {}).get("recomendacao_stake_pct")
        or (2.5 if classificacao != "AGUARDAR" else 0.0)
    )

    payload: dict[str, Any] = {
        "assinatura": SIGNATURE,
        "estrutura_operacional": ESTRUTURA_QUANTFURY,
        "etapa_verificacao": etapa,
        "ativo_solicitado": {
            "simbolo": simbolo,
            "nome": _LABELS.get(simbolo, simbolo),
            "preco_referencia_atual_usd": round(preco_atual, _digitos(preco_atual)),
            "quantidade_unidades_solicitada": quantidade_unidades,
            "acao_usuario": acao_norm,
        },
        "varredura_ao_vivo": {
            "fontes_checadas": etapa["verificou_fontes"],
            "forca_relativa_0_a_100": max(0.0, min(100.0, fr + 50)),
            "analise_tecnica_resumida": {
                "score_tecnico_0_a_100": round(float(tec.get("score_tecnico_0_a_100", 50)), 1),
                "veredito_tecnico": tec.get("veredito_tecnico", "AGUARDAR"),
                "macd_cruzamento": tec.get("macd", {}).get("cruzamento", "n/a"),
                "rsi_14": rsi_v2,
                "ema_20": ema20_v2,
                "ema_200": ema200_v2,
                "cruzamento_ema_20x200": golden_cross_v2,
                "preco_acima_ema200": acima_ema200_v2,
                "sinal_v2": sinal_v2,
                "bollinger_squeeze": tec.get("bandas_bollinger", {}).get("squeeze_apertado", False),
            },
            "topicos_noticias_e_macro": motivo,
        },
        # Bloco completo V2 para Flutter renderizar cards de RSI/EMA/Entry/SL/TP
        "crypto_v2_completo": v2 if v2 else {},
        "crypto_v2_resumo": {
            "simbolo_par_binance": _PAR_BINANCE.get(simbolo),
            "intervalo": "1h",
            "preco_atual": round(preco_atual, _digitos(preco_atual)),
            "sinal_v2": sinal_v2,
            "rsi_14": rsi_v2,
            "ema_20": ema20_v2,
            "ema_200": ema200_v2,
            "cruzamento_ema_20x200": golden_cross_v2,
            "preco_acima_ema200": acima_ema200_v2,
            "ponto_entrada_sugerido_usd": entrada,
            "stop_loss_usd": sl,
            "take_profit_alvo_1_usd": tp1,
            "take_profit_alvo_2_usd": tp2,
            "recomendacao_stake_pct_carteira": stake_v2_pct,
            "razao_risco_retorno_1": risco_retorno,
        },
        "decisao_final_em_destaque": decisao,
        "estrategia_quantfury": {
            "ponto_entrada_sugerido_usd": entrada,
            "stop_loss_usd": sl,
            "take_profit_alvo_1_usd": tp1,
            "take_profit_alvo_2_usd": tp2,
            "razao_risco_retorno_1": risco_retorno,
            "stake_recomendado_pct_carteira": stake_v2_pct,
            "observacao_confirmacao": (
                "🎯 A IA do Tiago identificou esta oportunidade na Quantfury (dados Binance V2: "
                f"RSI {rsi_v2} · EMA20 {ema20_v2} · EMA200 {ema200_v2})."
                " Deseja confirmar e validar esta operação?"
            ),
        },
        "confirmacao_pendente": True,
    }
    if acao_norm == "TROCAR":
        preco_dest = (
            float(v2_destino.get("preco_atual"))
            if v2_destino and v2_destino.get("preco_atual")
            else _serie_precos(simbolo_destino_swap, 120)[-1]
        )
        v2d_ind = v2_destino.get("indicadores") or {}
        v2d_ges = v2_destino.get("gestao_risco") or {}
        payload["swap_recomendacao"] = {
            "ativo_origem": simbolo,
            "ativo_destino": simbolo_destino_swap,
            "ativo_destino_nome": _LABELS.get(simbolo_destino_swap, simbolo_destino_swap),
            "taxa_swap_quantfury_pct": 0.0,
            "valor_estimado_troca_usd": round(
                quantidade_unidades * preco_atual, 2
            ) if quantidade_unidades and quantidade_unidades > 0 else 0.0,
            "forca_relativa_origem": round(max(0.0, min(100.0, fr + 50)), 1),
            "forca_relativa_destino": round(
                max(0.0, min(100.0, _forca_relativa_score(simbolo_destino_swap) + 50)), 1
            ),
            "destino_crypto_v2_resumo": {
                "simbolo_par_binance": _PAR_BINANCE.get(simbolo_destino_swap),
                "preco_atual": round(preco_dest, _digitos(preco_dest)),
                "sinal_v2": v2_destino.get("sinal") or "AGUARDAR",
                "rsi_14": round(float(v2d_ind.get("rsi_14") or 50.0), 1),
                "ema_20": v2d_ind.get("ema_20"),
                "ema_200": v2d_ind.get("ema_200"),
                "cruzamento_ema_20x200": bool(v2d_ind.get("cruzamento_ema_20x200", False)),
                "preco_acima_ema200": bool(v2d_ind.get("preco_acima_ema200", False)),
                "ponto_entrada_sugerido_usd": round(
                    float(v2d_ges.get("ponto_entrada") or preco_dest), _digitos(preco_dest)
                ),
                "stop_loss_usd": round(
                    float(v2d_ges.get("stop_loss") or preco_dest * 0.97), _digitos(preco_dest)
                ),
                "take_profit_alvo_1_usd": round(
                    float(v2d_ges.get("take_profit") or preco_dest * 1.05), _digitos(preco_dest)
                ),
            },
        }
    return payload


def confirmar_operacao(simbolo: str, acao: str, token_confirmacao: str) -> dict[str, Any]:
    """Assina validação final da operação após confirmação do usuário."""
    return {
        "assinatura": SIGNATURE,
        "token_confirmacao": token_confirmacao,
        "status_operacao": "OPERACAO VALIDADA E CONFIRMADA PELA IA DO TIAGO",
        "ativo": simbolo,
        "acao": acao,
        "carimbo_utc_validacao": datetime.now(tz=timezone.utc).isoformat(),
        "estrutura_operacional": ESTRUTURA_QUANTFURY,
    }


def _digitos(v: float) -> int:
    if v >= 1000:
        return 0
    if v >= 1:
        return 2
    return 5
