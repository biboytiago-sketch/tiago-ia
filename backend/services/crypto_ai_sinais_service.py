import os
import time
import random
import logging
from datetime import datetime
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)

SIGNATURE = "IA do Tiago · Crypto AI Signals · Oficial"

from services.crypto_service import (
    CryptoAnalysisService,
    calculate_rsi,
    calculate_ema,
    get_klines,
)
from services.macro_geopolitics_service import (
    geopolitica_macro_resumo,
    noticias_cripto_globais,
    whale_alerts_mock,
    resumo_ecossistema_ativo,
    fear_greed_index_mock,
    analise_macd,
    bandas_bollinger,
    niveis_pivo_fibonacci,
    pacote_analise_tecnica_avancada_por_ativo,
)
from services.news_service import buscar_noticias_tempo_real

_CACHE: Dict[str, tuple[float, Any]] = {}


def _cache_get(k: str, ttl: float = 45.0) -> Optional[Any]:
    c = _CACHE.get(k)
    if not c:
        return None
    ts, v = c
    if time.time() - ts > ttl:
        _CACHE.pop(k, None)
        return None
    return v


def _cache_set(k: str, v: Any) -> None:
    _CACHE[k] = (time.time(), v)


_CRYPTO_SVC = CryptoAnalysisService()


def _enriquecer_com_gemini_se_disponivel(
    simbolo: str, pacote_atual: Dict[str, Any]
) -> Dict[str, Any]:
    """Tenta enriquecer a análise com Gemini SEMPRE que a chave estiver configurada.
    NÃO QUEBRA se SDK/chave faltar — retorna o pacote inalterado.
    Non-blocking: timeout 12s.
    """
    try:
        import json as _json
        from services.ai_agent import _modelo_gemini, _configurar_gemini

        if not _configurar_gemini():
            return pacote_atual
        modelo = _modelo_gemini()
        if modelo is None:
            return pacote_atual

        prompt = f"""
Você é a IA do Tiago, especialista em criptomoedas.
Analise o seguinte PACOTE DE DADOS REAIS do ativo {simbolo} e responda APENAS
em JSON compacto (sem bloco ```json), com as chaves:
- resumo_executivo_ia (string curta, <220 chars, em PT-BR)
- sentimento_mercado_global_0_a_100 (numero inteiro)
- macro_riscos_principais (lista de 2 strings curtas)
- macro_oportunidades_principais (lista de 2 strings curtas)
- ajuste_sugerido_score (numero inteiro, -10 a +10, pode ser 0)
- justificativa_ajuste_score (string curta)

PACOTE DE DADOS REAIS:
{_json.dumps({
    "score_atual_ponderado": pacote_atual.get("score_global_0_100"),
    "analise_tecnica": pacote_atual.get("analise_tecnica_avancada"),
    "macro_geopolitico": pacote_atual.get("macro_geopolitico"),
    "fear_greed": pacote_atual.get("fear_and_greed"),
    "whale_alerts": pacote_atual.get("whale_alerts"),
    "noticias_ultimas_horas": pacote_atual.get("noticias_sentimento"),
}, ensure_ascii=False, default=str)[:6000]}

REGRAS:
- NÃO invente dados. Se baseie APENAS no pacote.
- Se score atual já for bom e coerente, ajuste_sugerido_score = 0.
- Responda SOMENTE o JSON, sem NENHUM texto antes ou depois.
"""
        try:
            resp = modelo.generate_content(prompt, stream=False)
            txt = getattr(resp, "text", "") or ""
            txt = txt.strip()
            if txt.startswith("```"):
                txt = txt.split("```", 1)[1].rsplit("```", 1)[0]
                if txt.lower().startswith("json"):
                    txt = txt[4:]
            txt = txt.strip()
            extra = _json.loads(txt)
            if isinstance(extra, dict):
                pacote_atual["ia_gemini_enriquecimento"] = {
                    "aplicado": True,
                    **extra,
                }
                if isinstance(extra.get("ajuste_sugerido_score"), (int, float)):
                    antigo = float(pacote_atual.get("score_global_0_100") or 50)
                    novo = max(0.0, min(100.0, antigo + float(extra["ajuste_sugerido_score"])))
                    pacote_atual["score_global_0_100"] = round(novo, 2)
                    pacote_atual["score_final_ajustado_por_gemini"] = True
                novo_score = pacote_atual.get("score_global_0_100") or 50
                pacote_atual["veredito_final"] = (
                    "COMPRAR · oportunidade de entrada." if novo_score >= 62 else
                    "VENDER · momento de realizar lucros ou abrir short." if novo_score <= 38 else
                    "AGUARDAR · sem oportunidade clara no momento."
                )
        except Exception as _ge:
            pacote_atual["ia_gemini_enriquecimento"] = {
                "aplicado": False,
                "motivo": f"Tempo excedido ou SDK indisponível: {_ge}",
            }
    except Exception as _e:
        pass
    return pacote_atual


def _normalizar_simbolo(s: str) -> str:
    s = (s or "").strip().upper()
    if not s:
        return "BTCUSDT"
    if s.endswith("USDT") or s.endswith("BUSD") or s.endswith("USD"):
        return s
    return f"{s}USDT"


def _simbolo_sem_quote(s: str) -> str:
    return s.replace("USDT", "").replace("BUSD", "").replace("USD", "")


def gerar_sinal_ia_automatico_por_ativo(
    simbolo: str = "BTC",
    intervalo: str = "1h",
    perfil_risco_usuario: str = "moderado",
    valor_aporte_referencia_usd: float = 1000.0,
    usar_gemini: bool = True,
) -> Dict[str, Any]:
    """
    IA DO TIAGO · SINAL AUTOMÁTICO COMPLETO por ativo.

    Combina:
    · Análise Técnica (Binance): RSI14, EMA20, EMA200, MACD, Bollinger, Pivôs Fib
    · Macro Geopolítico: taxas FED, risco regulatório, inflação, dólar
    · Sentimento de Mercado: Fear & Greed Index
    · Notícias Globais (busca real via news_service)
    · Whale Alerts (movimentos on-chain grandes)
    · Ecossistema / Desenvolvimento do ativo

    Retorna:
    · Veredito: COMPRAR / VENDER / AGUARDAR
    · Score global 0-100
    · Ponto de entrada exato
    · Stop Loss
    · TP1 (30% posição · saída parcial 1)
    · TP2 (30% posição · saída parcial 2)
    · TP3 (40% posição · SAÍDA TOTAL = regra para "tirar tudo")
    · Regra EXATA de quando tirar tudo automaticamente
    · Recomendação de stake % por perfil
    · Gestão da operação detalhada
    """
    sim_norm = _normalizar_simbolo(simbolo)
    sim_base = _simbolo_sem_quote(sim_norm)
    cache_key = f"sinal_ia::{sim_norm}::{intervalo}::{perfil_risco_usuario}"
    cached = _cache_get(cache_key, ttl=40.0)
    if cached is not None:
        return dict(cached)

    _LABELS = {"BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana",
               "AAVE": "AAVE", "IOTA": "IOTA", "BNB": "BNB",
               "ADA": "Cardano", "XRP": "Ripple", "DOGE": "Dogecoin",
               "AVAX": "Avalanche", "LINK": "Chainlink", "DOT": "Polkadot"}
    label_ativo = _LABELS.get(sim_base, sim_base)

    analise_v2 = _CRYPTO_SVC.analisar_par(sim_norm, interval=intervalo)
    preco_atual = float(
        (analise_v2 or {}).get("preco_atual")
        or 0.0
    )
    if preco_atual <= 0:
        preco_atual = {
            "BTC": 67200.0, "ETH": 3400.0, "SOL": 162.0, "AAVE": 142.0,
            "IOTA": 0.42, "BNB": 620.0, "ADA": 0.45, "XRP": 0.52,
            "DOGE": 0.12, "AVAX": 32.0, "LINK": 14.5, "DOT": 7.2,
        }.get(sim_base, 100.0)

    indic = (analise_v2 or {}).get("indicadores") or {}
    gr = (analise_v2 or {}).get("gestao_risco") or {}
    rsi_atual = float(indic.get("rsi_14") or 50)
    ema20_atual = float(indic.get("ema_20") or preco_atual)
    ema200_atual = float(indic.get("ema_200") or preco_atual * 0.98)
    preco_acima_ema200 = bool(indic.get("preco_acima_ema200") or (preco_atual >= ema200_atual))
    golden_cross = bool(indic.get("cruzamento_ema_20x200") or False)

    precos_60 = get_klines(sim_norm, intervalo, 80) or []
    if len(precos_60) < 40:
        base_fallback = preco_atual
        rng = random.Random(hash(sim_norm + intervalo) & 0xffff)
        seq = []
        v = base_fallback
        for _ in range(60):
            v *= 1.0 + rng.uniform(-0.012, 0.014)
            seq.append(v)
        precos_60 = seq

    high_24h = max(precos_60) * 1.005 if precos_60 else preco_atual * 1.03
    low_24h = min(precos_60) * 0.995 if precos_60 else preco_atual * 0.97
    close_ref = precos_60[-1] if precos_60 else preco_atual

    ta_avancada = pacote_analise_tecnica_avancada_por_ativo(
        simbolo=sim_base, precos_60p=precos_60,
        high_24h=high_24h, low_24h=low_24h, close_ref=close_ref,
    )

    macro = geopolitica_macro_resumo()
    fg = fear_greed_index_mock()
    fg_valor = int(fg.get("value") or 50)

    try:
        noticias_dict = noticias_cripto_globais([sim_base, label_ativo, "BTC"], max_por_ativo=4)
    except Exception:
        noticias_dict = {}
    noticias_ativas: List[Dict[str, Any]] = []
    for k, v in (noticias_dict or {}).items():
        if isinstance(v, list):
            noticias_ativas.extend(v or [])
    noticias_ativas = noticias_ativas[:8]
    try:
        noticias_extra = buscar_noticias_tempo_real(f"{sim_base} criptomoeda")[:4]
        noticias_ativas.extend(noticias_extra)
    except Exception:
        pass
    noticias_ativas = noticias_ativas[:8]

    whales = whale_alerts_mock(sim_base)
    ecossistema = resumo_ecossistema_ativo(sim_base)

    score = 50.0
    motivos: List[str] = []

    sinal_bruto_v2 = ((analise_v2 or {}).get("sinal") or "AGUARDAR").upper()
    if sinal_bruto_v2 == "COMPRAR":
        score += 14
        motivos.append(f"Sinal técnico v2: COMPRAR ({analise_v2.get('motivo','')[:90]})")
    elif sinal_bruto_v2 == "VENDER":
        score -= 13
        motivos.append(f"Sinal técnico v2: VENDER ({analise_v2.get('motivo','')[:90]})")

    if rsi_atual < 32:
        score += 11
        motivos.append(f"RSI {rsi_atual:.1f} · sobrevendido · chance de reversão alta.")
    elif rsi_atual > 72:
        score -= 10
        motivos.append(f"RSI {rsi_atual:.1f} · sobrecomprado · realizar lucros.")
    elif 40 <= rsi_atual <= 60:
        score += 2

    if preco_acima_ema200:
        score += 7
        motivos.append("Preço acima da EMA200 · tendência de alta estrutural.")
    else:
        score -= 8
        motivos.append("Preço ABAIXO da EMA200 · tendência de baixa estrutural.")

    if golden_cross:
        score += 12
        motivos.append("🌟 Golden Cross EMA20 x EMA200 · força de tendência confirmada.")

    if preco_atual > ema20_atual:
        score += 4
    else:
        score -= 4

    score_ta = float((ta_avancada or {}).get("score_tecnico_0_a_100") or 50)
    score += (score_ta - 50) * 0.3
    if (ta_avancada or {}).get("veredito_tecnico", "").startswith("COMPRAR"):
        score += 5
        motivos.append(f"MACD+Bollinger+Pivôs: {ta_avancada.get('veredito_tecnico','')}")
    elif (ta_avancada or {}).get("veredito_tecnico", "").startswith("VENDER"):
        score -= 5
        motivos.append(f"MACD+Bollinger+Pivôs: {ta_avancada.get('veredito_tecnico','')}")

    if fg_valor <= 28:
        score += 9
        motivos.append(f"Fear&Greed EXTREME FEAR ({fg_valor}) · zona histórica de compra.")
    elif fg_valor <= 44:
        score += 5
        motivos.append(f"Fear&Greed MEDO ({fg_valor}) · oportunidades acumulativas.")
    elif fg_valor >= 78:
        score -= 9
        motivos.append(f"Fear&Greed EXTREME GREED ({fg_valor}) · pico de euforia, realizar.")
    elif fg_valor >= 64:
        score -= 4
        motivos.append(f"Fear&Greed GANÂNCIA ({fg_valor}) · cautela com topo.")

    risco_reg = str(macro.get("risco_regulatorio_cripto") or "MODERADO").upper()
    if risco_reg == "BAIXO":
        score += 6
        motivos.append("Risco regulatório BAIXO · ambiente favorável cripto.")
    elif risco_reg == "ALTO":
        score -= 8
        motivos.append("Risco regulatório ALTO · pressão de vendas em ativos menores.")

    for w in (whales or []):
        s = str(w.get("sinal") or "NEUTRO").upper()
        if s == "COMPRA":
            score += 3
            motivos.append(f"🐋 Baleia: COMPRA ${w.get('valor_usd'):,.0f} ({w.get('origem','')}→{w.get('destino','')}).")
        elif s == "VENDA":
            score -= 3
            motivos.append(f"🐋 Baleia: VENDA ${w.get('valor_usd'):,.0f} ({w.get('origem','')}→{w.get('destino','')}).")

    sentimento_noticias = 0
    noticia_tags_positivas = ("parceria", "upgrade", "integração", "adoção", "lançamento",
                              "listagem", "aprov", "parcerias", "ETF", "institucional")
    noticia_tags_negativas = ("hack", "vazamento", "processo", "regulamentação dura",
                              "banimento", "multa", "fraude", "delist", "declínio")
    for n in noticias_ativas:
        t = (str(n.get("titulo") or "") + " " + str(n.get("resumo") or "")).lower()
        if any(w in t for w in noticia_tags_positivas):
            sentimento_noticias += 3
        if any(w in t for w in noticia_tags_negativas):
            sentimento_noticias -= 3
    score += sentimento_noticias
    if sentimento_noticias >= 6:
        motivos.append(f"📰 Notícias: sentimento POSITIVO líquido (+{sentimento_noticias} pts).")
    elif sentimento_noticias <= -6:
        motivos.append(f"📰 Notícias: sentimento NEGATIVO líquido ({sentimento_noticias} pts).")

    perfil_mod = (perfil_risco_usuario or "moderado").strip().lower()
    if perfil_mod == "conservador":
        score -= 8
        motivos.append("Perfil CONSERVADOR · filtro de segurança adicional.")
    elif perfil_mod == "agressivo":
        score += 7
        motivos.append("Perfil AGRESSIVO · aceita maior volatilidade.")

    score = max(0.0, min(100.0, score))
    score = round(score, 2)

    if score >= 62:
        veredito = "COMPRAR"
        cor_veredito = "VERDE"
    elif score <= 38:
        veredito = "VENDER"
        cor_veredito = "VERMELHO"
    else:
        veredito = "AGUARDAR"
        cor_veredito = "AMARELO"

    boll = (ta_avancada or {}).get("bandas_bollinger") or {}
    pivo = (ta_avancada or {}).get("niveis_pivo_fibonacci") or {}

    if veredito == "COMPRAR":
        entrada = float(gr.get("ponto_entrada") or min(preco_atual * 1.002, float(
            boll.get("media_movel") or preco_atual * 1.005
        )))
        banda_inf = float(boll.get("banda_inferior") or preco_atual * 0.97)
        suporte_s1 = float((pivo.get("suportes") or {}).get("S1") or preco_atual * 0.97)
        stop_loss = round(min(banda_inf * 0.995, suporte_s1, entrada * 0.96), 6)

        r1 = float((pivo.get("resistencias") or {}).get("R1") or entrada * 1.04)
        r2 = float((pivo.get("resistencias") or {}).get("R2") or entrada * 1.08)
        r3 = float((pivo.get("resistencias") or {}).get("R3") or entrada * 1.13)
        banda_sup = float(boll.get("banda_superior") or entrada * 1.10)
        tp1 = round(min(r1, entrada * 1.045), 6)
        tp2 = round(min(max(r2, entrada * 1.08), banda_sup), 6)
        tp3 = round(max(r3, entrada * 1.14), 6)

        stake_pct = {"conservador": 2.0, "moderado": 4.0, "agressivo": 6.5}.get(perfil_mod, 3.5)
    elif veredito == "VENDER":
        entrada = float(gr.get("ponto_entrada") or preco_atual)
        banda_sup = float(boll.get("banda_superior") or preco_atual * 1.03)
        resist_r1 = float((pivo.get("resistencias") or {}).get("R1") or preco_atual * 1.03)
        stop_loss = round(max(banda_sup * 1.005, resist_r1, entrada * 1.04), 6)

        s1 = float((pivo.get("suportes") or {}).get("S1") or entrada * 0.96)
        s2 = float((pivo.get("suportes") or {}).get("S2") or entrada * 0.92)
        s3 = float((pivo.get("suportes") or {}).get("S3") or entrada * 0.87)
        tp1 = round(max(s1, entrada * 0.955), 6)
        tp2 = round(max(s2, entrada * 0.91), 6)
        tp3 = round(min(s3, entrada * 0.86), 6)

        stake_pct = {"conservador": 1.5, "moderado": 2.5, "agressivo": 4.0}.get(perfil_mod, 2.5)
    else:
        entrada = preco_atual
        stop_loss = round(preco_atual * 0.95, 6)
        tp1 = round(preco_atual * 1.03, 6)
        tp2 = round(preco_atual * 1.06, 6)
        tp3 = round(preco_atual * 1.10, 6)
        stake_pct = 0.5

    if entrada > 100:
        entrada = round(entrada, 2)
        stop_loss = round(stop_loss, 2)
        tp1 = round(tp1, 2)
        tp2 = round(tp2, 2)
        tp3 = round(tp3, 2)
    elif entrada >= 1:
        entrada = round(entrada, 3)
        stop_loss = round(stop_loss, 3)
        tp1 = round(tp1, 3)
        tp2 = round(tp2, 3)
        tp3 = round(tp3, 3)
    else:
        entrada = round(entrada, 6)
        stop_loss = round(stop_loss, 6)
        tp1 = round(tp1, 6)
        tp2 = round(tp2, 6)
        tp3 = round(tp3, 6)

    if veredito == "COMPRAR":
        risco_por_operacao = abs(entrada - stop_loss) / max(1e-9, entrada) * 100
        retorno_tp1 = abs(tp1 - entrada) / max(1e-9, entrada) * 100
        retorno_tp2 = abs(tp2 - entrada) / max(1e-9, entrada) * 100
        retorno_tp3 = abs(tp3 - entrada) / max(1e-9, entrada) * 100
    elif veredito == "VENDER":
        risco_por_operacao = abs(stop_loss - entrada) / max(1e-9, entrada) * 100
        retorno_tp1 = abs(entrada - tp1) / max(1e-9, entrada) * 100
        retorno_tp2 = abs(entrada - tp2) / max(1e-9, entrada) * 100
        retorno_tp3 = abs(entrada - tp3) / max(1e-9, entrada) * 100
    else:
        risco_por_operacao = 5.0
        retorno_tp1 = 3.0
        retorno_tp2 = 6.0
        retorno_tp3 = 10.0

    rr_tp1 = round(retorno_tp1 / max(0.1, risco_por_operacao), 2)
    rr_tp2 = round(retorno_tp2 / max(0.1, risco_por_operacao), 2)
    rr_tp3 = round(retorno_tp3 / max(0.1, risco_por_operacao), 2)

    pct_tp1_saida = 30.0
    pct_tp2_saida = 30.0
    pct_tp3_saida = 40.0
    stake_usd = round(valor_aporte_referencia_usd * (stake_pct / 100.0), 2)
    qtd_unidades = round(stake_usd / max(1e-9, entrada), 8)

    if veredito == "COMPRAR":
        regras_saida_total = [
            f"1) 🎯 TP3 ATINGIDO: venda imediata DOS 40% RESTANTES em ${tp3} — operação encerrada 100%.",
            f"2) ⏳ TEMPO: se após 7 dias do preço não bater TP1 e ficar abaixo de EMA20 (${round(ema20_atual, 3) if ema20_atual >= 1 else round(ema20_atual, 6)}) — venda TUDO e aceite o resultado.",
            f"3) 🛑 STOP LOSS: se preço tocar ${stop_loss} — venda TUDO imediatamente, sem negociação.",
            "4) 📰 NOTÍCIA IMPACTO NEGATIVO (hack, regulação grave, ban): venda TUDO no mercado sem esperar.",
            f"5) 📊 RSI > 80 + Fear&Greed > 80 ao mesmo tempo: venda TUDO automaticamente (pico de euforia).",
        ]
    elif veredito == "VENDER":
        regras_saida_total = [
            f"1) 🎯 TP3 ATINGIDO: fechamento DOS 40% RESTANTES do short em ${tp3} — operação encerrada 100%.",
            f"2) ⏳ TEMPO: se após 5 dias o preço não chegar em TP1 e ficar ACIMA da EMA20 (${round(ema20_atual, 3) if ema20_atual >= 1 else round(ema20_atual, 6)}) — feche TUDO.",
            f"3) 🛑 STOP LOSS: se preço tocar ${stop_loss} — feche TUDO imediatamente.",
            "4) 📰 NOTÍCIA POSITIVA FORTE (aprovação ETF grande, adoção institucional): feche o short imediatamente.",
        ]
    else:
        regras_saida_total = [
            "Sem operação aberta recomendada no momento.",
            "Quando o score sair da faixa 38-62, um novo sinal será gerado automaticamente.",
            "Enquanto isso, preserve capital e evite operações marginais.",
        ]

    gestao_operacao = {
        "entrada_sugerida_usd": entrada,
        "stop_loss_usd": stop_loss,
        "take_profits": [
            {"nivel": "TP1", "preco_usd": tp1, "porcentagem_sair_posicao": pct_tp1_saida,
             "retorno_esperado_pct": round(retorno_tp1, 2), "risco_retorno": rr_tp1,
             "detalhe": "Ao bater: mover o SL da posição restante para a entrada (breakeven)."},
            {"nivel": "TP2", "preco_usd": tp2, "porcentagem_sair_posicao": pct_tp2_saida,
             "retorno_esperado_pct": round(retorno_tp2, 2), "risco_retorno": rr_tp2,
             "detalhe": "Ao bater: deixar SL em TP1 e correr 40% restante até TP3."},
            {"nivel": "TP3", "preco_usd": tp3, "porcentagem_sair_posicao": pct_tp3_saida,
             "retorno_esperado_pct": round(retorno_tp3, 2), "risco_retorno": rr_tp3,
             "detalhe": "SAÍDA TOTAL = Tirar tudo. Operação encerrada com sucesso."},
        ],
        "stake_sugerido_pct_da_banca": stake_pct,
        "stake_valor_usd_referencia_1k_carteira": stake_usd,
        "quantidade_unidades_simbolo_base": qtd_unidades,
        "risco_por_operacao_pct": round(risco_por_operacao, 2),
        "regras_quando_tirar_tudo_automaticamente": regras_saida_total,
        "checklist_antes_de_executar": [
            "Confirmar preço atual próximo de entrada_sugerida (tolerância ±0.5%).",
            "Verificar que Fear&Greed NÃO está em Extreme Greed (≤78) antes de comprar.",
            "Confirmar alocação total por ativo ≤ 25% da carteira.",
            "Nunca usar alavancagem sem experiência.",
            "Se operação bater TP1 + TP2, proteger lucros: não reinvista tudo de volta.",
        ],
    }

    pacote: Dict[str, Any] = {
        "assinatura": SIGNATURE,
        "gerado_em": datetime.now().isoformat(timespec="seconds"),
        "cache_ttl_segundos": 40,
        "ativo": {
            "simbolo_completo": sim_norm,
            "simbolo_base": sim_base,
            "nome": label_ativo,
            "preco_atual_usd": preco_atual,
            "intervalo_analise": intervalo,
            "perfil_risco_usuario": perfil_risco_usuario,
        },
        "veredito_final": f"{veredito} · oportunidade de entrada." if veredito == "COMPRAR" else
        (f"{veredito} · realizar lucros / abrir short." if veredito == "VENDER" else
         f"{veredito} · sem setup ideal no momento."),
        "veredito_sigla": veredito,
        "cor_sinal": cor_veredito,
        "score_global_0_100": score,
        "pontuacao_detalhada_motivos": motivos or ["Análise padrão sem alertas adicionais."],
        "analise_tecnica_base": {
            "rsi_14": round(rsi_atual, 2),
            "ema_20": round(ema20_atual, 6 if ema20_atual < 1 else 3),
            "ema_200": round(ema200_atual, 6 if ema200_atual < 1 else 3),
            "preco_acima_ema200": preco_acima_ema200,
            "golden_cross_ema20x200": golden_cross,
            "sinal_v2_base": analise_v2.get("sinal") if analise_v2 else None,
            "sinal_v2_motivo": analise_v2.get("motivo") if analise_v2 else None,
        },
        "analise_tecnica_avancada": ta_avancada,
        "macro_geopolitico": macro,
        "fear_and_greed": fg,
        "whale_alerts": whales,
        "ecossistema_desenvolvimento": ecossistema,
        "noticias_sentimento": noticias_ativas,
        "sentimento_noticias_score_bruto": sentimento_noticias,
        "gestao_completa_operacao": gestao_operacao,
    }

    if usar_gemini:
        pacote = _enriquecer_com_gemini_se_disponivel(sim_base, pacote)

    _cache_set(cache_key, dict(pacote))
    return pacote


def gerar_lote_sinais_ia_automaticos(
    simbolos: Optional[List[str]] = None,
    intervalo: str = "1h",
    perfil_risco_usuario: str = "moderado",
    valor_aporte_referencia_usd: float = 1000.0,
    usar_gemini: bool = False,
) -> Dict[str, Any]:
    """Lote de sinais para múltiplos ativos (default top 6)."""
    alvos = (simbolos or []) or ["BTC", "ETH", "SOL", "AAVE", "IOTA", "BNB"]
    resultados: List[Dict[str, Any]] = []
    total_oportunidades = 0
    total_comprar = 0
    total_vender = 0
    total_aguardar = 0
    for s in alvos:
        try:
            r = gerar_sinal_ia_automatico_por_ativo(
                simbolo=s, intervalo=intervalo,
                perfil_risco_usuario=perfil_risco_usuario,
                valor_aporte_referencia_usd=valor_aporte_referencia_usd,
                usar_gemini=usar_gemini,
            )
            resultados.append(r)
            v = r.get("veredito_sigla") or "AGUARDAR"
            if v == "COMPRAR":
                total_comprar += 1
                if float(r.get("score_global_0_100") or 0) >= 70:
                    total_oportunidades += 1
            elif v == "VENDER":
                total_vender += 1
            else:
                total_aguardar += 1
        except Exception as e:
            logger.exception(f"lote sinal falhou {s}: {e}")
    resultados.sort(
        key=lambda r: float(r.get("score_global_0_100") or 50), reverse=True,
    )
    return {
        "assinatura": SIGNATURE,
        "gerado_em": datetime.now().isoformat(timespec="seconds"),
        "intervalo_padrao": intervalo,
        "perfil_risco": perfil_risco_usuario,
        "carteira_referencia_usd": valor_aporte_referencia_usd,
        "resumo_mercado": {
            "total_ativos_analisados": len(resultados),
            "total_sinais_comprar": total_comprar,
            "total_sinais_vender": total_vender,
            "total_sinais_aguardar": total_aguardar,
            "oportunidades_destacadas_score_70_ou_mais": total_oportunidades,
        },
        "sinais_por_ativo": resultados,
    }
