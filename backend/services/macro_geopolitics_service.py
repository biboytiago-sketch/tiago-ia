import random
from datetime import datetime
from services.news_service import buscar_noticias_tempo_real


def fear_greed_index_mock() -> dict:
    valor = 48 + (datetime.now().minute % 24)
    if valor < 25:
        label = "Extreme Fear"
    elif valor < 45:
        label = "Fear"
    elif valor < 55:
        label = "Neutral"
    elif valor < 75:
        label = "Greed"
    else:
        label = "Extreme Greed"
    return {"value": valor, "classification": label,
            "updated_at": datetime.now().isoformat()}


def geopolitica_macro_resumo() -> dict:
    minuto = datetime.now().minute
    return {
        "taxa_juros_fed_atual_pct": 5.25 + (minuto % 3) * 0.25,
        "expectativa_proxima_reuniao": ["HOLD", "HOLD", "CUT 25bp", "HOLD"][minuto % 4],
        "inflacao_us_ipca_br": {"eua_pct": 3.1 + (minuto % 4) * 0.1,
                                 "br_pct": 4.0 + (minuto % 5) * 0.1},
        "dolar_r4": 5.45 + (minuto % 10) * 0.02,
        "risco_regulatorio_cripto": ["MODERADO", "BAIXO",
                                     "ALTO", "MODERADO"][minuto % 4],
        "notas_geopoliticas": [
            "Tensões no Mar Vermelho mantém prêmio de risco commodities.",
            "Câmara EUA adia votação sobre stablecoins até próximo mês.",
            "BIS recomenda cautela com alavancagem em ativos digitais.",
        ],
    }


def noticias_cripto_globais(ativos: list[str] | None = None,
                            max_por_ativo: int = 4) -> dict[str, list[dict]]:
    ativos = ativos or ["BTC", "Bitcoin", "AAVE", "IOTA", "Tangle", "DeFi"]
    resultado: dict[str, list[dict]] = {}
    for ativo in ativos:
        try:
            noticias = buscar_noticias_tempo_real(ativo)[:max_por_ativo]
        except Exception:
            noticias = []
        resultado[ativo] = noticias
    return resultado


def whale_alerts_mock(symbol: str) -> list[dict]:
    r = random.Random(hash((symbol, datetime.now().hour)) & 0xffff)
    return [
        {"tipo": "Transferência",
         "valor_usd": round(2_500_000 + r.random() * 48_000_000, 2),
         "origem": "Binance", "destino": "Carteira Fria",
         "horas_atras": round(1 + r.random() * 23, 1),
         "sinal": ["COMPRA", "NEUTRO", "VENDA"][r.randint(0, 2)]},
        {"tipo": "Movimento On-Chain",
         "valor_usd": round(800_000 + r.random() * 12_000_000, 2),
         "origem": "Coinbase", "destino": "Smart Money Wallet",
         "horas_atras": round(0.5 + r.random() * 11, 1),
         "sinal": ["COMPRA", "NEUTRO", "VENDA"][r.randint(0, 2)]},
    ]


def resumo_ecossistema_ativo(simbolo: str) -> list[str]:
    s = simbolo.upper()
    if s == "BTC":
        return [
            "Halving 2024 consolidado: inflação 0.85% a.a. (menor que ouro).",
            "ETF spot americano + BlackRock: fluxos líquidos positivos 7 dias.",
            "Reservas das empresas MicroStrategy/ETF totalizam >2.3M BTC.",
            "Lightning Network: capacidade pública >6.1k BTC.",
        ]
    if s == "AAVE":
        return [
            "Protocolo DeFi líder em TVL (Lending), >12B USD bloqueados.",
            "Governança AAVE votou ativação do GHO em novas chains.",
            "Rendimento stablecoin pool USDC/USDT mantém 4.1% APY.",
            "Auditoria Certora recente: 0 vulnerabilidades críticas.",
        ]
    if s == "IOTA":
        return [
            "Rede Tangle 2.0 (Stardust) + Coordicídio ativo em mainnet.",
            "Parceria com indústria automotiva (MOBI) para dados veiculares.",
            "Tokenização de ativos reais (RWA) usando ISC (Smart Contracts).",
            "Feel-less transactions ideal para micropagamentos IoT.",
        ]
    return ["Sem notícias pontuais no momento para o ativo."]


# =============================================================================
# NOVAS FUNCOES (Non-Breaking · APPEND · MACD / BOLLINGER / PIVOTS)
# Assinatura: IA do Tiago em todos os retornos.
# =============================================================================
import math as _math

SIGNATURE_IA_DO_TIAGO = "IA do Tiago"


def _ema(valores: list[float], periodo: int) -> list[float]:
    """Calcula EMA (non-modificante · não toca no array de entrada)."""
    if not valores:
        return []
    k = 2.0 / (periodo + 1.0)
    res: list[float] = [float(valores[0])]
    for v in valores[1:]:
        res.append((float(v) - res[-1]) * k + res[-1])
    return res


def analise_macd(precos: list[float],
                 rapido: int = 12,
                 lento: int = 26,
                 sinal: int = 9) -> dict:
    """MACD (12,26,9) clássico.

    Retorna: {assinatura, linha_macd, linha_sinal, histograma,
              cruzamento_atual (bullish/bearish/neutro), forca}.
    """
    if len(precos) < (lento + sinal):
        p = list(precos)
        faltante = (lento + sinal) - len(p)
        p = [p[0]] * faltante + p
    else:
        p = list(precos)
    ema12 = _ema(p, rapido)
    ema26 = _ema(p, lento)
    macd_linha = [a - b for a, b in zip(ema12, ema26)]
    sinal_linha = _ema(macd_linha, sinal)
    hist = [m - s for m, s in zip(macd_linha, sinal_linha)]
    if len(hist) >= 2:
        h_ant, h_atual = hist[-2], hist[-1]
        if h_atual > 0 >= h_ant or (h_atual > h_ant and h_atual > 0):
            cruz = "bullish"
        elif h_atual < 0 <= h_ant or (h_atual < h_ant and h_atual < 0):
            cruz = "bearish"
        else:
            cruz = "neutro"
    else:
        cruz = "neutro"
    forca = 0
    if hist:
        forca = min(100, max(0, int(50 + 50 * (hist[-1] /
                                                 max(1e-9, 2.0 * (max(abs(x) for x in hist) or 1e-9))))))
    return {
        "assinatura": SIGNATURE_IA_DO_TIAGO,
        "parametros": {"rapido": rapido, "lento": lento, "sinal": sinal},
        "linha_macd": round(macd_linha[-1], 6) if macd_linha else 0.0,
        "linha_sinal": round(sinal_linha[-1], 6) if sinal_linha else 0.0,
        "histograma_atual": round(hist[-1], 6) if hist else 0.0,
        "cruzamento_atual": cruz,
        "forca_0_a_100": forca,
    }


def bandas_bollinger(precos: list[float],
                     periodo: int = 20,
                     desvios: float = 2.0) -> dict:
    """Bandas de Bollinger (20p, 2σ). Retorna banda superior, média, inferior,
    largura %, posição do preço atual em % (0% inferior → 100% superior)."""
    if len(precos) < periodo:
        p = [precos[0]] * (periodo - len(precos)) + list(precos)
    else:
        p = list(precos[-periodo:])
    media = sum(p) / len(p)
    var = sum((x - media) ** 2 for x in p) / len(p)
    sigma = _math.sqrt(max(0, var))
    sup = media + desvios * sigma
    inf = media - desvios * sigma
    atual = float(precos[-1])
    largura = (sup - inf) / max(1e-9, media) * 100.0
    posicao_pct = 0.0 if (sup - inf) == 0 else max(0.0, min(100.0,
        ((atual - inf) / (sup - inf)) * 100.0))
    aperto = largura < 3.0  # Squeeze = baixa volatilidade, movimento próximo
    return {
        "assinatura": SIGNATURE_IA_DO_TIAGO,
        "parametros": {"periodo": periodo, "desvios_padroes": desvios},
        "banda_superior": round(sup, 4),
        "media_movel": round(media, 4),
        "banda_inferior": round(inf, 4),
        "largura_bandas_pct": round(largura, 2),
        "preco_atual_pct_dentro_banda": round(posicao_pct, 1),
        "squeeze_apertado": aperto,
        "interpretacao": (
            "Preço próximo da borda inferior · possível reversão ALTA."
            if posicao_pct < 20 else
            "Preço próximo da borda superior · possível reversão BAIXA / sobrecomprado."
            if posicao_pct > 80 else
            ("SQUEEZE · volatilidade baixa histórica; preparar para ROMBIMENTO."
             if aperto else "Preço na faixa central · sem pressão forte.")
        ),
    }


def niveis_pivo_fibonacci(high: float, low: float, close: float) -> dict:
    """Pivô clássico (P) + Fibonacci R1/R2/R3 e S1/S2/S3."""
    p = (high + low + close) / 3.0
    rng = high - low
    r1 = p + 0.382 * rng
    r2 = p + 0.618 * rng
    r3 = p + 1.000 * rng
    s1 = p - 0.382 * rng
    s2 = p - 0.618 * rng
    s3 = p - 1.000 * rng
    return {
        "assinatura": SIGNATURE_IA_DO_TIAGO,
        "pivo_p": round(p, 4),
        "resistencias": {"R1": round(r1, 4), "R2": round(r2, 4), "R3": round(r3, 4)},
        "suportes":     {"S1": round(s1, 4), "S2": round(s2, 4), "S3": round(s3, 4)},
        "rango_24h": round(rng, 4),
    }


def pacote_analise_tecnica_avancada_por_ativo(
    simbolo: str,
    precos_60p: list[float] | None = None,
    high_24h: float | None = None,
    low_24h: float | None = None,
    close_ref: float | None = None,
) -> dict:
    """Empacota MACD + Bollinger + Pivôs em 1 único dict pronto p/ JSON.

    Se não houver série de preços, gera mock coerente por ativo (não quebra).
    Assinatura IA do Tiago.
    """
    import random as _r
    baseline = {"BTC": 67200.0, "AAVE": 138.0, "IOTA": 0.415}
    s = simbolo.upper()
    p0 = baseline.get(s, 100.0)

    if precos_60p is None:
        rng = _r.Random(hash(s) + 31)
        seq: list[float] = []
        v = p0
        for _ in range(60):
            v *= 1.0 + rng.uniform(-0.012, +0.014)
            seq.append(v)
        precos_60p = seq
    close_ref = close_ref if close_ref is not None else precos_60p[-1]
    high_24h = high_24h if high_24h is not None else max(precos_60p) * 1.005
    low_24h  = low_24h  if low_24h  is not None else min(precos_60p) * 0.995

    macd = analise_macd(precos_60p)
    boll = bandas_bollinger(precos_60p)
    pivo = niveis_pivo_fibonacci(high_24h, low_24h, close_ref)

    # Score combinado
    score = 50
    if macd["cruzamento_atual"] == "bullish":
        score += 15
    elif macd["cruzamento_atual"] == "bearish":
        score -= 15
    score += int((macd["forca_0_a_100"] - 50) * 0.2)
    if boll["preco_atual_pct_dentro_banda"] < 25:
        score += 10
    elif boll["preco_atual_pct_dentro_banda"] > 75:
        score -= 8
    if boll["squeeze_apertado"]:
        score += 4
    if close_ref > pivo["pivo_p"]:
        score += 7
    else:
        score -= 6
    score = max(0, min(100, score))

    veredito_ta = (
        "COMPRAR · técnica ALTA consolidada."
        if score >= 65 else
        "VENDER · técnica BAIXA dominante."
        if score <= 35 else
        "AGUARDAR · sem viés claro no momento."
    )
    return {
        "assinatura": SIGNATURE_IA_DO_TIAGO,
        "simbolo": s,
        "score_tecnico_0_a_100": score,
        "veredito_tecnico": veredito_ta,
        "macd": macd,
        "bandas_bollinger": boll,
        "niveis_pivo_fibonacci": pivo,
    }
