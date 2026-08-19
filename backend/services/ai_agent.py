import os
import json
import time
import random
import asyncio
from datetime import datetime
from typing import AsyncGenerator, Optional, Dict, Any, List

try:
    from dotenv import load_dotenv
    load_dotenv()
except Exception:
    pass

try:
    import google.generativeai as genai
    _GEMINI_SDK_OK = True
except Exception:
    genai = None
    _GEMINI_SDK_OK = False

from database import SessionLocal
from models.chat_history import ChatHistory

PERSONA_TIAGO = """
Você é o TIAGO, uma IA brasileira especializada em apostas esportivas e análise de criptomoedas.
Sua MISSÃO PRINCIPAL é PROTEGER a banca do usuário (não deixá-lo perder dinheiro).
REGRAS OBRIGATÓRIAS:
1) SEMPRE comece e termine as respostas de forma natural, se apresente como TIAGO.
2) NUNCA recomende "apostar tudo" ou arriscar mais de 2% da banca por operação.
3) Categorias de jogos de futebol:
   - 🟢 ACERTOS_80: jogos acima de 80% de probabilidade real (melhores palpites)
   - 🎯 MULTIPLE_80: para montar múltiplas seguras
   - 🎯 LOW_ODDS_155: odds <= 1.55 (máxima segurança)
   - 🟡 VALUE: value bet oportunista
   - ⚠️ EVITAR: jogos de alto risco (baixa assertividade)
4) Cripto (BTC, ETH, SOL, AAVE, IOTA, BNB): use SEMPRE RSI(14), EMA 20 e EMA 200.
   - COMPRAR se RSI < 35 E preço > EMA200, ou no cruzamento de EMA20 acima da EMA200 (Golden Cross).
   - VENDER se RSI > 70, ou preço < EMA200 com tendência baixa.
   - SEMPRE informar: RSI atual, EMA 20, EMA 200, Ponto de Entrada, Stop Loss, Take Profit.
5) Para cada partida de futebol, SEMPRE classifique a flag:
   🏟️ EM_ANDAMENTO — se está rolando agora (1H / HT / 2H); use estatísticas LIVE (escanteios, chutes, posse).
   📅 FUTURO — se ainda não começou; priorize odds e probabilidades 1X2.
   SEMPRE analise 4 mercados separados e suas probabilidades:
   • VENCEDOR (1X2) + probabilidade casa/empate/fora %
   • ESCANTEIOS (Over X Cantos, linha 85% e 95%)
   • GOLS (Over 1.5 e Over 2.5, com % de chance)
   • CHUTES A GOL (Over Y chutes no jogo)
6) SEMPRE seja objetivo e direto. NÃO use markdown excessivo. Use emojis.
7) Responda sempre em PORTUGUÊS BRASILEIRO.
8) 🤖 GERADOR IA DE BILHETES PRONTOS (novo): quando o usuário pedir "montar jogo", "gerar bilhete", "montar múltipla" ou similar:
   - SEMPRE use os ENDPOINTS de /api/v3/sports/jogos-ranqueados-hoje e /api/v3/sports/gerar-bilhetes-ia.
   - Entregue 3 perfis PRONTOS para o usuário ESCOLHER: 🔒 SEGURO (2-3 jogos, odd ~1.30-2.50), ⚖️ BALANCEADO (3-4 jogos, odd ~2.50-6.00), 🔥 AGRESSIVO (4-6 jogos, odd >6.00).
   - Para CADA SELEÇÃO no bilhete, informe OBRIGATORIAMENTE: o time (ou Over 2.5 Gols / Over X Cantos / Over Y Chutes a Gol), a LINHA EXATA a usar (Ex: Over 7.5 Cantos), a ODD-ALVO que a IA considera razoável, a probabilidade % e 1 justificativa curta com dados reais (escanteios médios, chutes últimos 5 jogos).
   - NÃO invente odds ou linhas. Use os valores reais calculados pela função gerar_bilhetes_ia.
   - SEMPRE no final pergunte ao cliente: "Qual bilhete você vai usar? 🔒 Seguro / ⚖️ Balanceado / 🔥 Agressivo?"
"""

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
_gemini_configurado = False


def _configurar_gemini() -> bool:
    """Tenta configurar o SDK do Gemini. Retorna True se OK (chave válida e SDK presente)."""
    global _gemini_configurado
    if _gemini_configurado:
        return True
    if not _GEMINI_SDK_OK or not GEMINI_API_KEY:
        return False
    try:
        genai.configure(api_key=GEMINI_API_KEY)
        _gemini_configurado = True
        return True
    except Exception:
        _gemini_configurado = False
        return False


def _modelo_gemini():
    if not _configurar_gemini():
        return None
    try:
        config = genai.GenerationConfig(
            temperature=0.7,
            top_p=0.9,
            top_k=40,
            max_output_tokens=1024,
        )
        return genai.GenerativeModel("gemini-2.0-flash", generation_config=config)
    except Exception:
        try:
            config = genai.GenerationConfig(
                temperature=0.7, top_p=0.9, max_output_tokens=1024
            )
            return genai.GenerativeModel("gemini-1.5-flash", generation_config=config)
        except Exception:
            return None


def _montar_prompt_com_dados_reais(mensagem_usuario: str, contexto: Dict[str, Any]) -> str:
    """Monta o prompt injetando dados REAIS (jogos hoje, status da banca, sinais crypto, stats in-play e live timeline)."""
    jogos_hoje: List[Dict[str, Any]] = contexto.get("jogos_hoje") or []
    status_banca: Optional[Dict[str, Any]] = contexto.get("banca")
    sinais_crypto: List[Dict[str, Any]] = contexto.get("crypto") or []
    jogos_live_stats: List[Dict[str, Any]] = contexto.get("jogos_live") or []
    tendencias_inplay: List[Dict[str, Any]] = contexto.get("tendencias") or []

    blocos: List[str] = []
    blocos.append(PERSONA_TIAGO.strip())

    if status_banca is not None:
        blocos.append("\n[ DADOS ATUAIS DA BANCA DO USUÁRIO ]:")
        blocos.append(json.dumps(status_banca, ensure_ascii=False, indent=2))

    # Se vieram jogos LIVE com stats in-play (estilo FlashScore), usar esses
    # porque são muito mais ricos do que jogos_hoje.
    jogos_primarios: List[Dict[str, Any]] = jogos_live_stats if jogos_live_stats else jogos_hoje

    if jogos_primarios:
        e_live = bool(jogos_live_stats)
        if e_live:
            blocos.append(
                "\n[ JOGOS AO VIVO / PRÓXIMOS (FLASHCORE STYLE - RICOS COM STATS IN-PLAY) ]\n"
                "Use esses para identificar tendências de gol, escanteio, cartão e virada. "
                "Avalie pressão (dangerous_attacks), posse, chutes no alvo e diferença de força."
            )
        else:
            blocos.append("\n[ JOGOS DE HOJE DISPONÍVEIS ] (use estes ao dar palpites):")

        try:
            if e_live:
                jogos_resumo = []
                for m in (jogos_live_stats or [])[:18]:
                    h = m.get("home_team") or {}
                    a = m.get("away_team") or {}
                    st = m.get("stats") or {}
                    linha = {
                        "fixture_id": m.get("fixture_id") or m.get("jogo_id"),
                        "casa": h.get("name"), "fora": a.get("name"),
                        "liga": m.get("league"), "pais": m.get("country"),
                        "status": m.get("status_short"), "status_label": m.get("status_label"),
                        "minuto": m.get("minute_exact"), "horario": m.get("horario"),
                        "placar": f"{h.get('score',0)} x {a.get('score',0)}",
                        "placar_1T": f"{h.get('ht_score',0)} x {a.get('ht_score',0)}",
                        "categoria_tiago": m.get("categoria"),
                        "prob_real_%": m.get("probabilidade_real"),
                        "odds_1X2": [ (m.get("odds") or {}).get("home"),
                                       (m.get("odds") or {}).get("draw"),
                                       (m.get("odds") or {}).get("away") ],
                        "posse_bola_%": st.get("possession_pct"),
                        "ataques_perigosos": st.get("dangerous_attacks"),
                        "ataques_totais": st.get("total_attacks"),
                        "chutes_alvo": st.get("shots_on_target"),
                        "chutes_fora": st.get("shots_off_target"),
                        "escanteios": st.get("corners"),
                        "cartoes_amarelos": st.get("yellow_cards"),
                        "cartoes_vermelhos": st.get("red_cards"),
                        "ultimos_eventos": (m.get("timeline") or [])[-5:],
                    }
                    jogos_resumo.append(linha)
                blocos.append(json.dumps(jogos_resumo, ensure_ascii=False, indent=2))
            else:
                jogos_resumo = [
                    {
                        "casa": j.get("time_casa"),
                        "fora": j.get("time_fora"),
                        "liga": j.get("liga_nome"),
                        "pais": j.get("liga_pais"),
                        "horario": j.get("horario"),
                        "data": j.get("data_jogo"),
                        "categoria": j.get("categoria"),
                        "status": j.get("status"),
                        "minuto_live": j.get("minuto_live"),
                        "odds_1X2": [j.get("odd_casa"), j.get("odd_empate"), j.get("odd_fora")],
                        "prob_real_%": j.get("probabilidade_real"),
                    }
                    for j in jogos_hoje[:15]
                ]
                blocos.append(json.dumps(jogos_resumo, ensure_ascii=False, indent=2))
        except Exception:
            blocos.append(f"Total jogos hoje: {len(jogos_primarios)}")

    if tendencias_inplay:
        blocos.append("\n[ TENDÊNCIAS IN-PLAY CALCULADAS AUTOMATICAMENTE (Tiago Pré-Análise) ]:")
        blocos.append(json.dumps(tendencias_inplay, ensure_ascii=False, indent=2))

    if sinais_crypto:
        blocos.append("\n[ SINAIS CRYPTO (BTC, ETH, SOL, AAVE, IOTA, BNB) ATUAIS — RSI/EMA v2 ]:")
        blocos.append(json.dumps(sinais_crypto, ensure_ascii=False, indent=2))

    # ── BLOCO INCREMENTAL V2: PREVISÕES POR MERCADO + FLAG STATUS ──
    try:
        from services.live_sports_service import obter_jogos_hoje as _lj_hoje
        previsoes_hoje = (_lj_hoje() or [])[:12]
        if previsoes_hoje:
            blocos.append(
                "\n[ PREVISÕES POR MERCADO + STATUS FLAG (Tiago IA v2) ]\n"
                "USE esses valores em suas respostas quando pedirem palpites. "
                "status_flag: 🏟️ EM_ANDAMENTO (jogo rolando agora) ou 📅 FUTURO (ainda não começou)."
            )
            p_resumo = []
            for j in previsoes_hoje:
                merc = j.get("previsao_mercados") or {}
                venc = merc.get("vencedor") or {}
                cant = merc.get("escanteios") or {}
                gols = merc.get("gols") or {}
                chut = merc.get("chutes_a_gol") or {}
                p_resumo.append({
                    "fixture_id": j.get("fixture_id"),
                    "status_flag": j.get("status_flag") or "FUTURO",
                    "status_curto": j.get("status_curto"),
                    "minuto_decorrido": j.get("tempo_decorrido"),
                    "casa": j.get("time_casa"),
                    "fora": j.get("time_fora"),
                    "liga": j.get("liga"),
                    "placar_ou_horario": j.get("placar"),
                    "odds_1x2": j.get("odds_1x2"),
                    "mercado_vencedor_1x2": {
                        "recomendacao": venc.get("recomendacao"),
                        "probabilidades_pct": venc.get("probabilidades_pct"),
                    },
                    "mercado_escanteios": {
                        "linha_85pct": cant.get("over_linha_85pct"),
                        "linha_95pct": cant.get("over_linha_95pct"),
                        "total_ate_agora": cant.get("total_ate_agora"),
                        "prob_mais_escanteios_pct": cant.get("prob_over_next_pct"),
                    },
                    "mercado_gols": {
                        "over_1.5_pct": gols.get("over_1.5_prob_pct"),
                        "over_2.5_pct": gols.get("over_2.5_prob_pct"),
                        "recomendacao": gols.get("recomendacao"),
                    },
                    "mercado_chutes_a_gol": {
                        "total_ate_agora": chut.get("total_ate_agora"),
                        "over_prob_pct": chut.get("over_prob_pct"),
                        "recomendacao": chut.get("recomendacao"),
                    },
                    "desfalques_ou_alertas": j.get("desfalques_alertas"),
                })
            blocos.append(json.dumps(p_resumo, ensure_ascii=False, indent=2))
    except Exception as _pme:
        blocos.append(f"[Nota: previsões por mercado indisponíveis nesta rodada: {_pme}]")

    blocos.append(f"\n\nUsuário perguntou AGORA (às {datetime.now().strftime('%H:%M')}):")
    blocos.append(f'```\n{mensagem_usuario}\n```')
    blocos.append("\nResponda como o Tiago, em português, de forma natural e objetiva.")
    return "\n".join(blocos)



def generate_response(message: str, contexto: Optional[Dict[str, Any]] = None) -> str:
    """Síncrono: gera a resposta (usado pela rota antiga /chat/message)."""
    texto_completo: List[str] = []
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            for chunk in loop.run_until_complete(
                _collect_stream(message, contexto or {})
            ):
                texto_completo.append(chunk)
        finally:
            loop.close()
    except Exception:
        texto_completo = [_fallback_resposta(message)]
    return "".join(texto_completo)


async def _collect_stream(message: str, contexto: Dict[str, Any]) -> List[str]:
    out: List[str] = []
    async for c in generate_response_stream(message, contexto):
        out.append(c)
    return out


def _fallback_resposta(msg: str) -> str:
    m = msg.lower()
    if "quem" in m or "você é" in m:
        return "Olá! Eu sou o Tiago, sua IA de análise esportiva e cripto. Minha missão é proteger a sua banca 💚. Em que posso te ajudar hoje?"
    if "banca" in m or "bankroll" in m:
        return "Sou o Tiago. Regra principal: nunca arrisque mais de 2% da sua banca por operação. Use stop loss diário de 5% — se perder, pare imediatamente."
    if "futebol" in m or "jogo" in m or "partida" in m or "palpite" in m:
        return "Tiago aqui. Categorias principais: 🟢 Acertos 80%+ (melhores palpites), 🎯 Múltipla Segura (acumuladas), 🎯 Odds ≤ 1.55 (máxima segurança), 🟡 Valor e ⚠️ Evitar."
    if "cripto" in m or "btc" in m or "bitcoin" in m or "aave" in m:
        return "Sou o Tiago. Sinais cripto (BTC + AAVE) seguem EMA 20 + RSI 14 como referência: RSI < 30 oversold, > 70 overbought."
    if "multipla" in m or "múltipla" in m:
        return "Múltiplas são perigosas! Eu recomendo no MÁXIMO 4 jogos, todos de categoria ACERTOS_80 ou LOW_ODDS_155. Nunca misture categorias."
    if "trava" in m or "travar" in m or "perdi" in m:
        return "Importante: defina um limite diário de perda! Se atingir esse limite, PARE imediatamente. Não tente recuperar perdas no mesmo dia. Isso é disciplina."
    if any(x in m for x in ["olá", "ola", "bom dia", "boa tarde", "boa noite", "oi"]):
        return "Olá! Eu sou o Tiago 💚. Estou aqui para preservar sua banca. Qual análise deseja agora: futebol, cripto ou banca?"
    if "obrigado" in m or "valeu" in m or "thanks" in m:
        return "De nada! Lembre-se: banca preservada é banca para amanhã. Qualquer coisa, é só chamar."
    return f"Entendi. Sou o Tiago 💚. Posso ajudar com: (1) análise de jogos de futebol com categorias 🟢 ACERTOS 80%+, 🎯 LOW_ODDS_155, 🟡 VALUE, ⚠️ EVITAR; (2) sinais de criptomoedas (BTC + AAVE) por RSI/EMA; (3) gerenciamento de banca. O que precisa?"


async def generate_response_stream(
    message: str, contexto: Optional[Dict[str, Any]] = None
) -> AsyncGenerator[str, None]:
    """
    Streaming REAL:
      1) Tenta SDK do Gemini oficial (stream=True) se tiver GEMINI_API_KEY.
         Transmite os chunks recebidos do modelo.
      2) Fallback: gera resposta mock e envia pedaço por pedaço com delay.
    Salva a resposta completa no ChatHistory ao final.
    """
    contexto = contexto or {}
    prompt_final = _montar_prompt_com_dados_reais(message, contexto)
    resposta_completa_parts: List[str] = []
    usou_gemini_real = False

    # === 1) GEMINI OFICIAL ===
    modelo = _modelo_gemini()
    if modelo is not None:
        try:
            resposta = modelo.generate_content_async(prompt_final, stream=True)
            async for evento in resposta:
                try:
                    if hasattr(evento, "text"):
                        chunk_txt = evento.text or ""
                    else:
                        candidates = getattr(evento, "candidates", None) or []
                        chunk_txt = ""
                        if candidates:
                            parts = getattr(candidates[0], "content", None)
                            if parts and hasattr(parts, "parts"):
                                for p in parts.parts:
                                    if hasattr(p, "text"):
                                        chunk_txt += p.text or ""
                    if chunk_txt:
                        resposta_completa_parts.append(chunk_txt)
                        usou_gemini_real = True
                        for sub in _chunk_text(chunk_txt, size=2):
                            yield sub
                            await asyncio.sleep(0.005)
                except StopAsyncIteration:
                    break
                except Exception:
                    continue
        except Exception:
            usou_gemini_real = False

    # === 2) FALLBACK (sem chave, ou SDK falhou) ===
    if not usou_gemini_real:
        fallback = _fallback_resposta(message)
        # Simula digitação humana ~45 chars/seg
        async for pedaco in _ai_iter_chunked(fallback, chunk_size=2, delay=0.022):
            resposta_completa_parts.append(pedaco)
            yield pedaco

    # === Salvar histórico ===
    try:
        _salvar_historico(message, "".join(resposta_completa_parts))
    except Exception:
        pass


def _chunk_text(txt: str, size: int = 2) -> List[str]:
    if not txt:
        return []
    return [txt[i : i + size] for i in range(0, len(txt), size)]


async def _ai_iter_chunked(texto: str, chunk_size: int = 3, delay: float = 0.018) -> AsyncGenerator[str, None]:
    """Divide o texto em chunks e envia com delay (efeito digitação)."""
    for i in range(0, len(texto), chunk_size):
        yield texto[i : i + chunk_size]
        if delay > 0:
            await asyncio.sleep(delay)


def _salvar_historico(pergunta: str, resposta: str) -> None:
    try:
        db = SessionLocal()
        try:
            chat = ChatHistory(
                user_message=pergunta[:2000],
                ai_response=resposta[:4000],
                timestamp=datetime.now(),
            )
            db.add(chat)
            db.commit()
        finally:
            db.close()
    except Exception:
        pass
