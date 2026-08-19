"""accumulator_ai_optimizer.py (NOVO MODULO · Non-Breaking)

Extensão da IA do Tiago para múltiplas:
  1. Calibração dinâmica de linhas (sugestão de ajuste com % de melhoria).
  2. Guia "Como Apostar Para Ganhar" (Pré vs Ao Vivo / Stake %).
  3. Comando direto / chat rápido: interpreta frases do usuário e ajusta o bilhete.
Assinatura: "IA do Tiago" em toda resposta.
"""
from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

SIGNATURE = "IA do Tiago"

# -----------------------------------------------------------------------------
# 1 · CALIBRACAO DINAMICA DE LINHAS
# -----------------------------------------------------------------------------
_LINHAS_ESCANTEIOS = (3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5)
_LINHAS_CARTOES = (3.5, 4.5, 5.5, 6.5, 7.5, 8.5)
_LINHAS_CHUTES_JOGADOR = (0.5, 1.5, 2.5, 3.5)


def _procurar_linha_mais_proxima(valor: float, opcoes: tuple[float, ...],
                                 preferir_abaixo: bool = True) -> float:
    diffs = sorted(opcoes, key=lambda lx: (abs(lx - valor),
                                            -lx if preferir_abaixo else lx))
    return diffs[0]


def calibrar_linha_aposta(selecao: dict[str, Any]) -> dict[str, Any]:
    """Analisa a linha do usuário e sugere ajuste com percentual de melhoria.

    selecao esperada: {mercado, escolha_linha_numerica, odd_apostada,
                       estatisticas:{media_casa,media_fora,rivalidade_ult5}}
    Retorna: {linha_atual, linha_sugerida, odd_antes_pct_hit,
              odd_depois_pct_hit, melhoria_pct_absoluta, orientacao_texto}
    """
    mercado = (selecao.get("mercado") or "").strip().lower()
    linha_atual: float = float(selecao.get("escolha_linha_numerica") or 0)
    stats = dict(selecao.get("estatisticas") or {})
    mc = float(stats.get("media_casa") or 0)
    mf = float(stats.get("media_fora") or 0)
    rival = float(stats.get("rivalidade_ult5") or 1.0)  # 1.0 neutro

    if mercado.startswith("escan") or "corner" in mercado:
        proj = (mc + mf) * (0.85 + 0.15 * rival)
        opcoes = _LINHAS_ESCANTEIOS
    elif "carta" in mercado or "cartao" in mercado:
        proj = (mc + mf) * (0.80 + 0.20 * rival)
        opcoes = _LINHAS_CARTOES
    elif "chute" in mercado:
        proj = (mc + mf) * (0.82 + 0.18 * rival)
        opcoes = _LINHAS_CHUTES_JOGADOR
    else:
        return {
            "assinatura": SIGNATURE,
            "ajuste_recomendado": False,
            "motivo": "Mercado sem linha numérica calibrável.",
        }

    linha_ideal = _procurar_linha_mais_proxima(proj, opcoes, preferir_abaixo=True)

    def hit_pct(linha: float, projetada: float) -> float:
        # distribuição normal aproximada · desvio padrão 1.8 para cantos, 1.2 cartões, 0.9 chute
        sigma = {"e": 1.8, "c": 1.2, "h": 0.9}
        s = sigma.get("e" if "escan" in mercado else "c" if "cartao" in mercado else "h", 1.3)
        z = (linha - projetada) / s
        # erf(x) approx
        import math
        t = 1.0 / (1.0 + 0.3275911 * abs(z))
        y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-z * z)
        return max(1.0, min(99.0, 50.0 + 50.0 * (y if z >= 0 else -y)))

    antes = hit_pct(linha_atual, proj)
    depois = hit_pct(linha_ideal, proj)
    melhoria = round(max(0.0, depois - antes), 1)
    if linha_ideal == linha_atual:
        texto = f"Linha atual {linha_atual:.1f} já é a mais adequada estatisticamente."
        ajuste = False
    elif linha_ideal < linha_atual:
        ajuste = True
        texto = (f"Baixe a linha de +{linha_atual:.1f} para +{linha_ideal:.1f}. "
                 f"Chance de acerto sobe de {antes:.0f}% para {depois:.0f}% (melhoria de +{melhoria} pontos percentuais).")
    else:
        ajuste = True
        texto = (f"Aumente a linha de +{linha_atual:.1f} para +{linha_ideal:.1f}. "
                 f"Risco aumenta mas odd melhora — chance de hit vai de {antes:.0f}% para {depois:.0f}%.")
    return {
        "assinatura": SIGNATURE,
        "ajuste_recomendado": ajuste,
        "linha_atual": linha_atual,
        "linha_sugerida": linha_ideal,
        "probabilidade_hit_antes_pct": round(antes, 1),
        "probabilidade_hit_depois_pct": round(depois, 1),
        "melhoria_pontos_pct": melhoria,
        "orientacao_texto": texto,
        "projecao_mercado_90min": round(proj, 1),
    }


# -----------------------------------------------------------------------------
# 2 · GUIA "COMO APOSTAR PARA GANHAR"
# -----------------------------------------------------------------------------
def guia_como_apostar_para_ganhar(selecoes: list[dict[str, Any]],
                                  stake_total_usd: float,
                                  perfil_usuario: str = "moderado") -> dict[str, Any]:
    """Sugere entrada Pré-Jogo vs Ao Vivo, tipo bilhete e stake %.

    Assinatura IA do Tiago.
    """
    qtd = max(1, len(selecoes))
    medias = [float((s.get("probabilidade_ia") or s.get("probabilidade_real_pct") or 50)) for s in selecoes]
    media_hit = sum(medias) / len(medias) if medias else 50.0

    # Momento da entrada
    arriscados = [m for m in medias if m < 58]
    if len(arriscados) >= max(1, qtd // 2):
        momento = "⚠️ Aguardar Ao Vivo (in-play) pelos primeiros 15 a 20 minutos. " \
                  f"{len(arriscados)} seleção(ões) abaixo do limiar de 58% — confirme padrão de jogo " \
                  "(posse, cantos, pressão) antes de entrar."
    elif media_hit >= 72:
        momento = "✅ Pode entrar **Pré-Jogo**. Confiabilidade geral muito acima da média (%.0f%%). " \
                  "Se houver linha a calibrar, prefere a versão mais conservadora sugerida." % media_hit
    else:
        momento = "🟡 Entrada Híbrida: metade do stake Pré-Jogo e o restante no intervalo (HT), " \
                  "após confirmar time a favor está dominando estatísticas."

    # Tipo bilhete ideal
    if qtd <= 2:
        tipo = "Bilhete Simples / Dupla · baixa volatilidade. Evite múltipla de 1; se for 2, ambos acima de 62%."
    elif qtd <= 4:
        tipo = "Múltipla de 3 a 4 seleções · doce spot ideal para combinar favoritos + mercado linha (escanteios/cartões)."
    else:
        tipo = f"Múltipla muito longa ({qtd} jogos). Recomendo dividir em 2 ou 3 bilhetes menores " \
               "com 3-4 jogos cada, usando a mesma banca, para preservar expectancy."

    # Stake por jogo / percentual
    perfil_limites = {
        "conservador": {"max_pct_jogo": 1.5, "max_pct_bilhete": 3.0, "cor": "baixo"},
        "moderado":    {"max_pct_jogo": 2.5, "max_pct_bilhete": 5.0, "cor": "médio"},
        "agressivo":   {"max_pct_jogo": 4.0, "max_pct_bilhete": 8.0, "cor": "alto"},
    }
    p = perfil_limites.get(perfil_usuario, perfil_limites["moderado"])
    stake_por_jogo_max = round(stake_total_usd * p["max_pct_jogo"] / 100, 2)
    stake_bilhete_max = round(stake_total_usd * p["max_pct_bilhete"] / 100, 2)
    stake_sugerido_por_partida = [
        round(max(1.0, (medias[i] / 100) * stake_por_jogo_max * 2.2), 2)
        for i in range(len(medias))
    ]
    return {
        "assinatura": SIGNATURE,
        "perfil_risco": perfil_usuario,
        "momento_ideal_entrada": momento,
        "tipo_bilhete_ideal": tipo,
        "gestao_banca": {
            "stake_total_referencia_usd": stake_total_usd,
            "max_stake_por_jogo_pct_banca": p["max_pct_jogo"],
            "max_stake_por_jogo_usd": stake_por_jogo_max,
            "max_stake_bilhete_inteiro_usd": stake_bilhete_max,
            "nivel_gerenciamento": p["cor"],
            "sugestao_stake_individual_por_partida_usd": stake_sugerido_por_partida,
        },
    }


# -----------------------------------------------------------------------------
# 3 · COMANDO DIRETO / CHAT RAPIDO (IA do Tiago)
# -----------------------------------------------------------------------------
PALAVRAS_REMOVER_RISCO = (
    "tire", "remov", "tirar", "arriscado", "risco", "perigoso", "inseguro", "ruim",
)
PALAVRAS_OTIMIZAR = ("otimize", "otimizar", "melhor", "melhore", "ajusta", "ajustar",
                     "aumentar", "chance", "hit", "acerto", "80%", "70%", "75%")
PALAVRAS_DIMINUIR_LINHA = ("baixa", "baixar", "abaixe", "abaixar", "reduz", "reduzir",
                           "conservador", "seguro", "menos")
PALAVRAS_AUMENTAR_LINHA = ("aumenta", "aumentar", "suba", "subir", "agressivo", "mais odd",
                           "maior odd")


def interpretar_comando_e_ajustar_bilhete(
    comando_usuario: str,
    selecoes: list[dict[str, Any]],
    meta_pct_hit_alvo: float = 70.0,
) -> dict[str, Any]:
    """Recebe frase do usuário e re-avalia automaticamente o bilhete.

    Exemplos:
      · "Tiago, tire os jogos arriscados e deixe com 80% de chance"
      · "Tiago, otimize essa múltipla"
      · "Baixe todas as linhas de escanteio para ficar mais seguro"
    """
    cmd = comando_usuario.lower().strip()
    acoes_aplicadas: list[str] = []
    selecoes_novas = [dict(s) for s in selecoes]

    # (A) Alvo de probabilidade: captura "80%", "75%" etc.
    numeros = re.findall(r"(\d+(?:[,.]\d+)?)\s*%", comando_usuario.replace(',', '.'))
    if numeros:
        try:
            meta_pct_hit_alvo = float(numeros[0])
        except ValueError:
            pass
    meta_pct_hit_alvo = max(50.0, min(92.0, meta_pct_hit_alvo))

    # (B) Otimização global
    if any(p in cmd for p in PALAVRAS_OTIMIZAR):
        for i, sel in enumerate(selecoes_novas):
            cal = calibrar_linha_aposta(sel)
            if cal.get("ajuste_recomendado"):
                sel["escolha_linha_numerica"] = cal["linha_sugerida"]
                sel["orientacao_calibracao"] = cal
        acoes_aplicadas.append(f"Otimização geral aplicada · meta de {meta_pct_hit_alvo:.0f}% de hit.")

    # (C) Remover arriscados
    if any(p in cmd for p in PALAVRAS_REMOVER_RISCO):
        antes = len(selecoes_novas)
        selecoes_novas = [s for s in selecoes_novas
                          if float(s.get("probabilidade_ia") or s.get("probabilidade_real_pct") or 50)
                          >= max(55, meta_pct_hit_alvo - 6)]
        removidos = antes - len(selecoes_novas)
        if removidos:
            acoes_aplicadas.append(f"Removidas {removidos} seleção(ões) arriscada(s) que estavam abaixo do limiar.")

    # (D) Diminuir linhas (mais seguro)
    if any(p in cmd for p in PALAVRAS_DIMINUIR_LINHA):
        qtd = 0
        for sel in selecoes_novas:
            cal = calibrar_linha_aposta(sel)
            if cal.get("ajuste_recomendado") and cal["linha_sugerida"] < cal["linha_atual"]:
                sel["escolha_linha_numerica"] = cal["linha_sugerida"]
                sel["orientacao_calibracao"] = cal
                qtd += 1
        if qtd:
            acoes_aplicadas.append(f"{qtd} linha(s) reduzida(s) para aumentar segurança.")

    # (E) Aumentar linhas (mais odd)
    if any(p in cmd for p in PALAVRAS_AUMENTAR_LINHA):
        qtd = 0
        for sel in selecoes_novas:
            cal = calibrar_linha_aposta(sel)
            if cal.get("ajuste_recomendado") and cal["linha_sugerida"] > cal["linha_atual"]:
                sel["escolha_linha_numerica"] = cal["linha_sugerida"]
                sel["orientacao_calibracao"] = cal
                qtd += 1
        if qtd:
            acoes_aplicadas.append(f"{qtd} linha(s) aumentada(s) para buscar maior odd.")

    if not acoes_aplicadas:
        acoes_aplicadas.append("Nenhum ajuste automático disparado. Comando não reconhecido — dica: "
                               "use 'otimize', 'remova arriscados', 'baixe as linhas' ou '80% de chance'.")

    return {
        "assinatura": SIGNATURE,
        "comando_recebido": comando_usuario,
        "meta_pct_hit_alvo": meta_pct_hit_alvo,
        "acoes_aplicadas_resumo": acoes_aplicadas,
        "quantidade_selecoes_antes": len(selecoes),
        "quantidade_selecoes_depois": len(selecoes_novas),
        "selecoes_apos_ajuste": selecoes_novas,
        "hora_execucao_utc": datetime.now(tz=timezone.utc).isoformat(),
    }
