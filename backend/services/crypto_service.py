import time
import math
import random
import logging
from datetime import datetime
from typing import List, Dict, Any, Optional

import httpx

try:
    import pandas as pd  # type: ignore
    _PD_OK = True
except Exception:
    _PD_OK = False

logger = logging.getLogger(__name__)

_SIGNATURE = "IA do Tiago · Crypto v2"

BINANCE_BASE_URL = "https://api.binance.com/api/v3"
_CACHE: Dict[str, tuple[float, Any]] = {}


def _cache_get(k: str, ttl: float = 60.0) -> Optional[Any]:
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


# ─────────────────────────────────────────────────────
# FUNÇÕES LEGADAS (mantidas para backward compatibility)
# ─────────────────────────────────────────────────────

def calculate_rsi(prices, period=14):
    prices = list(prices or [])
    if len(prices) < period + 1:
        return 50.0
    gains = []
    losses = []
    for i in range(1, len(prices)):
        change = prices[i] - prices[i - 1]
        if change > 0:
            gains.append(change); losses.append(0)
        else:
            gains.append(0); losses.append(abs(change))
    avg_gain = sum(gains[:period]) / period
    avg_loss = sum(losses[:period]) / period
    for i in range(period, len(gains)):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period
    if avg_loss == 0:
        return 100.0
    rs = avg_gain / avg_loss
    return round(100 - (100 / (1 + rs)), 2)


def calculate_ema(prices, period=20):
    prices = list(prices or [])
    if not prices:
        return 0.0
    if len(prices) < period:
        return float(prices[-1])
    multiplier = 2 / (period + 1)
    ema = sum(prices[:period]) / period
    for price in prices[period:]:
        ema = (price * multiplier) + (ema * (1 - multiplier))
    return round(ema, 2)


def get_klines(symbol, interval="1h", limit=100):
    try:
        with httpx.Client(timeout=15.0) as client:
            response = client.get(
                f"{BINANCE_BASE_URL}/klines",
                params={"symbol": symbol, "interval": interval, "limit": limit},
            )
            response.raise_for_status()
            data = response.json()
            return [float(k[4]) for k in data]
    except Exception as e:
        logger.warning(f"get_klines {symbol} falhou: {e}")
        return []


# ─────────────────────────────────────────────────────
# NOVA IMPLEMENTAÇÃO v2 (Binance + Pandas + RSI/EMA + Regras)
# ─────────────────────────────────────────────────────

class CryptoAnalysisService:
    def __init__(self) -> None:
        self.binance_url = f"{BINANCE_BASE_URL}/klines"

    def _buscar_klines_binance(self, symbol: str, interval: str = "1h", limit: int = 250):
        cache_key = f"klines::{symbol}::{interval}::{limit}"
        cached = _cache_get(cache_key, ttl=45.0)
        if cached is not None:
            return cached
        try:
            with httpx.Client(timeout=12.0) as client:
                resp = client.get(
                    self.binance_url,
                    params={"symbol": symbol.upper(), "interval": interval, "limit": limit},
                )
                resp.raise_for_status()
                data = resp.json()
            if not isinstance(data, list) or not data:
                raise ValueError("vazio")
            _cache_set(cache_key, data)
            return data
        except Exception as e:
            logger.warning(f"Binance klines {symbol} falhou, usando fallback: {e}")
            return self._fallback_klines(symbol, limit)

    @staticmethod
    def _fallback_klines(symbol: str, limit: int = 250) -> List[Any]:
        seed_map = {"BTCUSDT": 68000.0, "ETHUSDT": 3400.0, "AAVEUSDT": 142.0, "IOTAUSDT": 0.42,
                    "SOLUSDT": 162.0, "BNBUSDT": 620.0}
        base = seed_map.get(symbol.upper(), 100.0)
        random.seed(time.time() // 120 + hash(symbol) % 100)
        candles = []
        ts = int(time.time() * 1000)
        price = base * (0.88 + random.random() * 0.24)
        for i in range(limit):
            drift = math.sin(i / 8.0) * base * 0.015
            noise = (random.random() - 0.5) * base * 0.012
            o = price
            h = max(o, o + abs(noise) + abs(drift) * 0.6) + base * 0.002
            l = min(o, o - abs(noise) - abs(drift) * 0.6) - base * 0.002
            c = o + drift + noise
            volume = base * 20 * (0.5 + random.random())
            candles.append([
                ts - (limit - i) * 3_600_000, o, h, l, c, volume,
                ts - (limit - i) * 3_600_000 + 3_599_999,
                volume * c, 42, volume * 0.6, volume * c * 0.6, 0,
            ])
            price = c
        return candles

    @staticmethod
    def _calcular_rsi_pandas(fechamentos: List[float], period: int = 14):
        if _PD_OK:
            s = pd.Series(fechamentos, dtype=float)
            delta = s.diff()
            gain = delta.clip(lower=0)
            loss = (-delta).clip(lower=0)
            avg_gain = gain.ewm(alpha=1 / period, adjust=False).mean()
            avg_loss = loss.ewm(alpha=1 / period, adjust=False).mean()
            rs = avg_gain / avg_loss.replace(0, 1e-9)
            out = (100 - (100 / (1 + rs)))
            return out.tolist()
        valores = list(fechamentos)
        n = len(valores)
        if n < period + 1:
            return [50.0] * n
        gains = [0.0] * n
        losses = [0.0] * n
        for i in range(1, n):
            ch = valores[i] - valores[i - 1]
            if ch > 0:
                gains[i] = ch
            else:
                losses[i] = abs(ch)
        alpha = 1.0 / period
        avg_g = sum(gains[1:period + 1]) / period
        avg_l = sum(losses[1:period + 1]) / period
        rsi = [50.0] * n
        for i in range(period, n):
            avg_g = (1 - alpha) * avg_g + alpha * gains[i]
            avg_l = (1 - alpha) * avg_l + alpha * losses[i]
            den = max(avg_l, 1e-9)
            rsi[i] = 100.0 - (100.0 / (1.0 + avg_g / den))
        return rsi

    @staticmethod
    def _calcular_ema(fechamentos: List[float], period: int) -> List[float]:
        valores = list(fechamentos)
        n = len(valores)
        if n < period:
            return [valores[-1]] * n if valores else []
        mult = 2.0 / (period + 1)
        ema = [0.0] * n
        seed = sum(valores[:period]) / period
        for i in range(period):
            ema[i] = seed
        for i in range(period, n):
            ema[i] = valores[i] * mult + ema[i - 1] * (1 - mult)
        return ema

    def analisar_par(self, symbol: str = "BTCUSDT", interval: str = "1h"):
        try:
            data = self._buscar_klines_binance(symbol, interval=interval, limit=250)
            fechamentos = [float(k[4]) for k in data if len(k) >= 5]
            if _PD_OK:
                df = pd.DataFrame(data, columns=[
                    "timestamp", "open", "high", "low", "close",
                    "volume", "close_time", "qav", "num_trades",
                    "taker_base_vol", "taker_quote_vol", "ignore",
                ])
                df["close"] = df["close"].astype(float)
                precos = df["close"]
                rsi_lista = self._calcular_rsi_pandas(precos.tolist(), 14)
                ema20_lista = self._calcular_ema(precos.tolist(), 20)
                ema200_lista = self._calcular_ema(precos.tolist(), 200)
                preco_atual = float(precos.iloc[-1])
            else:
                rsi_lista = self._calcular_rsi_pandas(fechamentos, 14)
                ema20_lista = self._calcular_ema(fechamentos, 20)
                ema200_lista = self._calcular_ema(fechamentos, 200)
                preco_atual = float(fechamentos[-1])

            rsi_atual = round(float(rsi_lista[-1]), 2)
            ema_20_atual = round(float(ema20_lista[-1]), 2)
            ema_200_atual = round(float(ema200_lista[-1]), 2) if ema200_lista else round(preco_atual * 0.98, 2)
            ema_20_anterior = round(float(ema20_lista[-2]), 2) if len(ema20_lista) >= 2 else ema_20_atual
            ema_200_anterior = round(float(ema200_lista[-2]), 2) if len(ema200_lista) >= 2 else ema_200_atual

            cruzou_20_acima_200 = (ema_20_anterior <= ema_200_anterior) and (ema_20_atual > ema_200_atual)
            precos_ok = preco_atual > ema_200_atual

            sinal = "AGUARDAR"
            motivo = "Mercado neutro — sem sinal forte. Acompanhe o preço e o RSI."
            stop_loss = round(preco_atual * 0.98, 2)
            take_profit = round(preco_atual * 1.05, 2)
            ponto_entrada = round(preco_atual, 2)

            regra_compra_rsi = (rsi_atual < 35) and precos_ok
            regra_compra_cruzamento = cruzou_20_acima_200 and precos_ok

            if regra_compra_rsi:
                sinal = "COMPRAR"
                motivo = f"RSI({rsi_atual:.1f}) sobrevendido e preço acima da EMA200 — entrada segura."
                stop_loss = round(min(preco_atual * 0.97, ema_200_atual * 0.995), 2)
                take_profit = round(preco_atual * 1.06, 2)
            elif regra_compra_cruzamento:
                sinal = "COMPRAR"
                motivo = "Cruzamento de EMA20 acima da EMA200 — Golden Cross / tendência de alta iniciando."
                ponto_entrada = round(preco_atual, 2)
                stop_loss = round(ema_200_atual * 0.99, 2)
                take_profit = round(preco_atual * 1.08, 2)
            elif rsi_atual > 70:
                sinal = "VENDER"
                motivo = f"RSI({rsi_atual:.1f}) sobrecomprado — realize lucros ou espere pullback."
                stop_loss = round(preco_atual * 1.02, 2)
                take_profit = round(preco_atual * 0.96, 2)
            elif (preco_atual < ema_200_atual) and (ema_20_atual <= ema_200_atual) and rsi_atual > 55:
                sinal = "VENDER"
                motivo = "Tendência de queda (preço < EMA200) com RSI ainda alto — venda antes da correção."
                stop_loss = round(ema_200_atual * 1.01, 2)
                take_profit = round(preco_atual * 0.97, 2)
            elif precos_ok and (35 <= rsi_atual <= 55):
                sinal = "COMPRAR"
                motivo = "Tendência de alta (preço > EMA200) + RSI moderado — acumular em dips."
                stop_loss = round(ema_200_atual * 0.995, 2)
                take_profit = round(preco_atual * 1.04, 2)

            ratio_rr = round((take_profit - ponto_entrada) / max(0.1, abs(ponto_entrada - stop_loss)), 2) \
                if sinal == "COMPRAR" else (
                round((ponto_entrada - take_profit) / max(0.1, abs(stop_loss - ponto_entrada)), 2)
                if sinal == "VENDER" else 0.0
            )

            _LABELS = {"BTCUSDT": "Bitcoin", "ETHUSDT": "Ethereum", "SOLUSDT": "Solana",
                       "AAVEUSDT": "AAVE", "IOTAUSDT": "IOTA", "BNBUSDT": "BNB",
                       "ADAUSDT": "Cardano", "XRPUSDT": "Ripple"}
            sym_up = symbol.upper()
            return {
                "assinatura": _SIGNATURE,
                "simbolo": sym_up,
                "label": _LABELS.get(sym_up, sym_up.replace("USDT", "")),
                "intervalo": interval,
                "preco_atual": round(preco_atual, 2),
                "sinal": sinal,
                "motivo": motivo,
                "indicadores": {
                    "rsi_14": rsi_atual,
                    "ema_20": ema_20_atual,
                    "ema_200": ema_200_atual,
                    "cruzamento_ema_20x200": cruzou_20_acima_200,
                    "preco_acima_ema200": precos_ok,
                },
                "gestao_risco": {
                    "ponto_entrada": ponto_entrada,
                    "stop_loss": stop_loss,
                    "take_profit": take_profit,
                    "recomendacao_stake_pct": (
                        5.0 if (regra_compra_rsi or regra_compra_cruzamento) else
                        3.0 if sinal == "COMPRAR" else
                        2.5 if sinal == "VENDER" else 0.5
                    ),
                    "relacao_risco_retorno": ratio_rr if ratio_rr > 0 else None,
                },
                "atualizado_em": datetime.now().isoformat(),
            }
        except Exception as e:
            logger.exception(f"Falha analisar_par {symbol}: {e}")
            _LABELS = {"BTCUSDT": "Bitcoin", "ETHUSDT": "Ethereum", "SOLUSDT": "Solana",
                       "AAVEUSDT": "AAVE", "IOTAUSDT": "IOTA", "BNBUSDT": "BNB",
                       "ADAUSDT": "Cardano", "XRPUSDT": "Ripple"}
            sym_up = symbol.upper()
            fallback_preco = {
                "BTCUSDT": 64250.0, "ETHUSDT": 3180.0, "SOLUSDT": 142.5,
                "AAVEUSDT": 138.5, "IOTAUSDT": 0.32, "BNBUSDT": 590.0,
            }.get(sym_up, 100.0)
            return {
                "assinatura": _SIGNATURE,
                "erro": True,
                "mensagem": str(e),
                "simbolo": sym_up,
                "label": _LABELS.get(sym_up, sym_up.replace("USDT", "")),
                "intervalo": interval,
                "preco_atual": fallback_preco,
                "sinal": "AGUARDAR",
                "motivo": (
                    "Binance offline ou chave inválida no momento. "
                    "Valores padrão exibidos como referência. Tente novamente em alguns minutos."
                ),
                "indicadores": {
                    "rsi_14": 50.0,
                    "ema_20": fallback_preco * 0.999,
                    "ema_200": fallback_preco * 0.992,
                    "cruzamento_ema_20x200": False,
                    "preco_acima_ema200": True,
                },
                "gestao_risco": {
                    "ponto_entrada": fallback_preco,
                    "stop_loss": fallback_preco * 0.97,
                    "take_profit": fallback_preco * 1.05,
                    "recomendacao_stake_pct": 0.5,
                    "relacao_risco_retorno": 1.67,
                },
                "atualizado_em": datetime.now().isoformat(),
            }

    def obter_resumo_top(self, pairs: Optional[List[str]] = None, interval: str = "1h"):
        pares = pairs or ["BTCUSDT", "ETHUSDT", "SOLUSDT", "AAVEUSDT", "IOTAUSDT", "BNBUSDT"]
        labels = {"BTCUSDT": "Bitcoin", "ETHUSDT": "Ethereum", "SOLUSDT": "Solana",
                  "AAVEUSDT": "AAVE", "IOTAUSDT": "IOTA", "BNBUSDT": "BNB",
                  "ADAUSDT": "Cardano", "XRPUSDT": "Ripple"}
        out = []
        for p in pares:
            r = self.analisar_par(p, interval=interval)
            # Label oficial sempre (sobrescreve qualquer fallback)
            r["label"] = labels.get(p, p.replace("USDT", ""))
            out.append(r)
        return {
            "assinatura": _SIGNATURE,
            "total": len(out),
            "pares": out,
            "atualizado_em": datetime.now().isoformat(),
        }


_CRYPTO_SVC = CryptoAnalysisService()


def get_crypto_signals_v2(pairs=None, interval: str = "1h"):
    return _CRYPTO_SVC.obter_resumo_top(pairs=pairs, interval=interval)


def analisar_par_v2(symbol: str = "BTCUSDT", interval: str = "1h"):
    return _CRYPTO_SVC.analisar_par(symbol, interval=interval)


# ─────────────────────────────────────────────────────
# FUNÇÃO LEGADA (compatibilidade com main.py imports)
# ─────────────────────────────────────────────────────

def get_crypto_signals():
    pairs = ["BTCUSDT", "AAVEUSDT", "IOTAUSDT"]
    labels = {"BTCUSDT": "Bitcoin", "AAVEUSDT": "AAVE", "IOTAUSDT": "IOTA"}
    resumo = _CRYPTO_SVC.obter_resumo_top(pairs=pairs, interval="1h")["pares"]
    out = []
    for r in resumo:
        sym = r["simbolo"]
        side_map = {"COMPRAR": "BUY", "VENDER": "SELL"}
        side = side_map.get(r["sinal"], "HOLD")
        gr = r["gestao_risco"]
        ind = r["indicadores"]
        signal_line = (f"PAIR: {sym.replace('USDT', '/USDT')} | SIDE: {side} | "
                      f"ENTRY: ${gr['ponto_entrada']:,.2f} | STOP: ${gr['stop_loss']:,.2f} | "
                      f"TARGET: ${gr['take_profit']:,.2f}")
        out.append({
            "symbol": sym.replace("USDT", "/USDT"),
            "label": labels.get(sym, sym.replace("USDT", "")),
            "raw_symbol": sym,
            "current_price": r["preco_atual"],
            "rsi_14": ind["rsi_14"],
            "ema_20": ind["ema_20"],
            "ema_200": ind["ema_200"],
            "side": side,
            "entry": gr["ponto_entrada"],
            "stop": gr["stop_loss"],
            "target": gr["take_profit"],
            "trend": r["motivo"],
            "signal_quantfury": signal_line,
            "sinal_v2": r["sinal"],
            "preco_acima_ema200": ind["preco_acima_ema200"],
            "relacao_risco_retorno": gr["relacao_risco_retorno"],
            "timestamp": r.get("atualizado_em", datetime.now().isoformat()),
        })
    return out
