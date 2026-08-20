/**
 * ticketBuilder.ts · Construtor do Bilhete Pronto
 * =================================================
 *
 * Requisitos:
 *   - Recebe lista de MatchPrediction (saídas do aiAdvisor.ts)
 *   - Filtra SELEÇÕES com confiança >= 70% (🎯 Alta Confirmação, pedido do usuário)
 *   - Junta odds acumuladas, cálcula probabilidade conjunta
 *   - Calcula stake sugerido em BRL (R$), retorno potencial e valor esperado
 *   - Inclui raciocínio tático EM CADA seleção (pedido passo 3)
 */
import type {
  BetTicket,
  MarketKey,
  MatchPrediction,
  RiskCategory,
  TicketSelection,
} from "../types";
import {
  categoryEmoji,
  categoryLabel,
  confidenceToCategory,
  getBankrollBRL,
  getDefaultStakeBRL,
  GEMINI_MISSING_KEY_BANNER,
} from "../utils/envValidation";

/**
 * Prioridade dos mercados para escolher a MELHOR seleção por jogo.
 *
 * Se um jogo tiver múltiplos mercados com alta confiança, pegamos o de
 * maior probabilidade primeiro (mas mantemos a ordem de preferência se
 * houver empate em pontos).
 */
const MERCADO_PRIORIDADE: MarketKey[] = [
  "winner",           // melhor odd confiável
  "goals",            // over/under + btts
  "corners",          // escanteios
  "shots_on_target",  // chutes ag
  "cards_fouls",      // cartões/faltas
];

export interface TicketBuildOptions {
  /** Quantidade MÍNIMA de mercados para o bilhete (default 2). */
  minSelecoes?: number;
  /** Quantidade MÁXIMA de seleções (default 6 — não ultrapassar para não estourar risco). */
  maxSelecoes?: number;
  /** Confiança mínima para entrar no bilhete principal (default 70). */
  confiancaMinimaPct?: number;
  /** Stake base em BRL (default: env DEFAULT_STAKE_BRL → 100). */
  stakePadraoBRL?: number;
}

/**
 * 1 ponto de seleção para cada mercado, ponderado por (EV × confiança)
 * para ranquear as melhores opções.
 */
function scoreMercado(p: MatchPrediction, m: MarketKey): number {
  const x = p.mercados[m];
  if (!x) return -1;
  const ev = x.valor_ev === "POSITIVO" ? 1.15 : x.valor_ev === "NEUTRO" ? 1.0 : 0.85;
  return x.probabilidade_pct * ev * (x.odd_sugerida / 1.7);
}

function melhorSelecaoPorJogo(
  p: MatchPrediction,
  confiancaMinima: number,
): TicketSelection | null {
  const rank = MERCADO_PRIORIDADE
    .filter((m) => !!p.mercados[m] && p.mercados[m].valor_ev !== "NEGATIVO")
    .sort((a, b) => scoreMercado(p, b) - scoreMercado(p, a));

  for (const mercado of rank) {
    const pred = p.mercados[mercado];
    if (!pred) continue;

    // Confiança da seleção = média entre predição geral e probabilidade do mercado
    const blendedConf =
      0.55 * p.confidence_score_pct + 0.45 * pred.probabilidade_pct;

    const cat: RiskCategory = confidenceToCategory(blendedConf);
    if (blendedConf < confiancaMinima) continue;

    const razoes = p.raciocinio_tatico.razoes.slice(0, 2).join(" ");
    const analise =
      `[${categoryEmoji(cat)} ${round1(blendedConf)}% · ${pred.label_humano}] ` +
      `${p.raciocinio_tatico.titulo} ${razoes}`.trim();

    return {
      fixture_id: p.fixture_id,
      time_casa: p.time_casa,
      time_fora: p.time_fora,
      liga: p.liga,
      horario_br: p.horario_br,
      mercado_escolhido: mercado,
      pick: pred.recomendacao,
      odd: round2(pred.odd_sugerida),
      confianca_pct: round1(blendedConf),
      categoria_risco: cat,
      analise_tatica: analise,
    };
  }
  return null;
}

/**
 * Pega o ranking inteiro de seleções ALTA (>70%) e MÉDIO (55-69%).
 * Se as Alta forem < minSelecoes, completamos com as melhores Médio.
 */
function gerarCandidatos(
  predicoes: MatchPrediction[],
  confiancaMinimaAlta: number,
  confiancaMinimaMedia: number,
): { alta: TicketSelection[]; media: TicketSelection[] } {
  const alta: TicketSelection[] = [];
  const media: TicketSelection[] = [];
  for (const p of predicoes) {
    const sAlta = melhorSelecaoPorJogo(p, confiancaMinimaAlta);
    if (sAlta) {
      alta.push(sAlta);
      continue;
    }
    const sMedia = melhorSelecaoPorJogo(p, confiancaMinimaMedia);
    if (sMedia) media.push(sMedia);
  }
  alta.sort((a, b) => b.confianca_pct - a.confianca_pct);
  media.sort((a, b) => b.confianca_pct - a.confianca_pct);
  return { alta, media };
}

export function buildReadyBetTicket(
  predicoes: MatchPrediction[],
  opts: TicketBuildOptions = {},
): BetTicket {
  const min = opts.minSelecoes ?? 2;
  const max = opts.maxSelecoes ?? 6;
  const confiancaMinima = opts.confiancaMinimaPct ?? 70;
  const stakePadrao = Math.max(1, opts.stakePadraoBRL ?? getDefaultStakeBRL());
  const bankroll = Math.max(stakePadrao, getBankrollBRL());

  const { alta, media } = gerarCandidatos(predicoes, confiancaMinima, 55);
  let selecoes = alta.slice(0, max);

  // Completar até o mínimo com as melhores MÉDIAS, se houver
  if (selecoes.length < min && media.length) {
    const falta = min - selecoes.length;
    const usados = new Set(selecoes.map((s) => String(s.fixture_id)));
    for (const m of media) {
      if (selecoes.length >= min) break;
      if (usados.has(String(m.fixture_id))) continue;
      selecoes.push(m);
      usados.add(String(m.fixture_id));
    }
  }

  // Garantir que não ultrapassamos o limite máximo
  selecoes = selecoes.slice(0, max);

  // Odd acumulada e probabilidade
  let oddAc = 1.0;
  let probConjunta = 1.0;
  let maiorCat: RiskCategory = "HIGH_CONFIRMATION";
  const atualizaCat = (c: RiskCategory) => {
    const peso = { HIGH_CONFIRMATION: 1, MEDIUM_RISK: 2, HIGH_RISK_SPEC: 3 } as const;
    if (peso[c] > peso[maiorCat]) maiorCat = c;
  };

  for (let i = 0; i < selecoes.length; i++) {
    const s = selecoes[i];
    oddAc *= s.odd;
    probConjunta *= s.confianca_pct / 100;
    atualizaCat(s.categoria_risco);
    s.odd_acumulada_ate_aqui = round2(oddAc);
  }

  const oddAcFinal = round2(Math.max(1.0, oddAc));
  const probPct = round1(Math.max(0.01, probConjunta * 100));
  const valorEsperado = round2(oddAcFinal * probConjunta - 1);

  // Stake sugerido:
  //   Com base em Critério de Kelly fracionado (Kelly/2): f* = (p·b - q) / b
  //   Onde b = odd - 1 ; p = probConjunta ; q = 1 - p
  let stakePctBank = 0.5; // fallback 0.5% se cálculo quebrar
  try {
    const p = probConjunta;
    const q = 1 - p;
    const b = Math.max(0.1, oddAcFinal - 1);
    const kelly = (p * b - q) / b;
    stakePctBank = Math.max(0.1, Math.min(5.0, kelly * 50)); // Kelly/2 + teto 5%
  } catch {
    /* mantém 0.5 */
  }
  stakePctBank = round2(stakePctBank);
  const stake = round2(Math.max(1, Math.min(bankroll * (stakePctBank / 100), stakePadrao * 2)));
  const retornoPotencial = round2(stake * oddAcFinal);

  return {
    gerado_em_iso: new Date().toISOString(),
    total_selecoes: selecoes.length,
    odd_acumulada: oddAcFinal,
    probabilidade_conjunta_pct: probPct,
    risco_geral: maiorCat,
    stake_padrao_brl: stakePadrao,
    stake_sugerido_pct_do_bankroll: stakePctBank,
    retorno_potencial_brl: retornoPotencial,
    valor_esperado_x_aposta: valorEsperado,
    selecoes,
    banner_erro_config:
      process.env.GEMINI_API_KEY?.trim() ? undefined : GEMINI_MISSING_KEY_BANNER,
  };
}

/**
 * Helper UI: transforma o bilhete em linhas legíveis para dashboard/debug.
 */
export function ticketToHumanReadable(t: BetTicket): string[] {
  const lines: string[] = [];
  if (t.banner_erro_config) {
    lines.push("!!! " + t.banner_erro_config);
  }
  lines.push(
    `Bilhete Pronto [${t.total_selecoes} jogos] · Odd Ac. ${t.odd_acumulada} · ` +
      `${categoryLabel(t.risco_geral)} · Prob Conjunta ${t.probabilidade_conjunta_pct}%`,
  );
  lines.push(
    `  Stake sugerido: R$ ${t.stake_padrao_brl.toFixed(2)} (${t.stake_sugerido_pct_do_bankroll}% bankroll) · ` +
      `Retorno Potencial R$ ${t.retorno_potencial_brl.toFixed(2)} · EV ${t.valor_esperado_x_aposta >= 0 ? "+" : ""}${t.valor_esperado_x_aposta}`,
  );
  t.selecoes.forEach((s, i) => {
    lines.push(
      `  ${i + 1}. ${s.time_casa} x ${s.time_fora} [${s.liga} · ${s.horario_br}] → ` +
        `${s.pick} · odd ${s.odd} · conf ${round1(s.confianca_pct)}% ` +
        `(${categoryEmoji(s.categoria_risco)}) · odd acum. até aqui ${s.odd_acumulada_ate_aqui}`,
    );
    lines.push(`     📝 ${s.analise_tatica}`);
  });
  return lines;
}

function round1(n: number): number {
  return Math.round(Number(n) * 10) / 10;
}
function round2(n: number): number {
  return Math.round(Number(n) * 100) / 100;
}
