/**
 * ============================================================
 *  Tiago IA · AI Engine (TypeScript)
 *  Tipagens comuns usadas por providerManager / aiAdvisor / ticketBuilder
 * ============================================================
 */

// ── Enums ────────────────────────────────────────────────────────────────────

export type RiskCategory =
  | "HIGH_CONFIRMATION"  // 🎯 >= 70% confiança (seleção principal do bilhete)
  | "MEDIUM_RISK"         // 🟡 55% - 69%   (valor secundário)
  | "HIGH_RISK_SPEC";     // 🔴 < 55%        (jogos especulativos)

export type MarketKey =
  | "winner"          // 1X2 / Dupla Hipótese
  | "corners"         // Escanteios (Cantos)
  | "shots_on_target" // Chutes ao Gol
  | "cards_fouls"     // Cartões e Faltas
  | "goals";          // Over/Under Gols + Ambas Marcam (BTTS)

// ── Stats normalizadas (entrada da AI) ───────────────────────────────────────
/**
 * Formato UNIFICADO que sai do `providerManager.ts` e entra no `aiAdvisor.ts`.
 * Pode ser preenchido a partir de live_sports_service.py (FastAPI)
 * ou de qualquer fonte externa (FlashScore, Football-Data etc).
 */
export interface TeamStanding {
  posicao: number;
  pontos: number;
  jogos: number;
  vitorias: number;
  empates: number;
  derrotas: number;
  gols_pro: number;
  gols_contra: number;
}

export interface TeamStatsLive {
  escanteios: number;
  chutes_ao_gol: number;
  chutes_fora: number;
  ataques_perigosos: number;
  cartoes_amarelos: number;
  cartoes_vermelhos: number;
  faltas: number;
  posse_bola_pct: number; // 0 a 100
}

export interface MatchStats {
  fixture_id: string | number;
  liga: string;
  liga_pais?: string;
  time_casa: string;
  time_fora: string;
  horario_br: string;
  data_iso: string;
  status: "FUTURO" | "EM_ANDAMENTO" | "FIM";
  minuto?: number | null;
  placar_casa?: number;
  placar_fora?: number;

  stats_casa: Partial<TeamStatsLive>;
  stats_fora: Partial<TeamStatsLive>;

  /** Média de escanteios do time NOS ÚLTIMOS 5 JOGOS (histórico) */
  media_escanteios_casa_ult5?: number;
  media_escanteios_fora_ult5?: number;

  /** xG (gols esperados) do confronto. 0 = sem dado */
  xg_casa?: number;
  xg_fora?: number;

  /** Tabela da liga (se disponível) */
  colocacao_casa?: Partial<TeamStanding>;
  colocacao_fora?: Partial<TeamStanding>;

  /** Odds 1x2 de mercado aberto. 0 = sem dado */
  odds_1x2?: {
    casa: number;
    empate: number;
    fora: number;
  };

  /** Campos extras livre (para shims de providers antigos) */
  metadados?: Record<string, unknown>;
}

// ── Predições da IA (saída do aiAdvisor.ts) ───────────────────────────────────

export interface MarketPrediction {
  mercado: MarketKey;
  label_humano: string;
  recomendacao: string;            // Ex: "Over 8.5 Cantos", "Casa ou Empate (1X)", "Over 2.5 Gols"
  linha?: number | null;           // Ex: 8.5 (cantos), 2.5 (gols), 7.5 (chutes)
  odd_sugerida: number;            // Odd estimada/mercado em decimal (1.85)
  probabilidade_pct: number;       // 0 a 100
  valor_ev: "POSITIVO" | "NEUTRO" | "NEGATIVO";
  /** Indicadores específicos do mercado */
  metricas?: Record<string, number | string | boolean>;
}

export interface TacticalReasoning {
  titulo: string;
  razoes: string[];                // 1 ou 2 sentenças (pedido do usuario)
}

export interface MatchPrediction {
  fixture_id: string | number;
  time_casa: string;
  time_fora: string;
  liga: string;
  horario_br: string;

  /** Confiança geral da IA para esse jogo (média ponderada) — 0 a 100 */
  confidence_score_pct: number;

  /** Categoria de risco baseada em confidence_score_pct */
  categoria_risco: RiskCategory;

  /** Previsões por mercado (todos os 5 do pedido são sempre retornados) */
  mercados: Record<MarketKey, MarketPrediction>;

  /** Raciocínio tático textual (1 a 2 sentenças) */
  raciocinio_tatico: TacticalReasoning;

  /** Dado da fonte (para rastreio) */
  versao_modelo: string;
  timestamp_iso: string;
}

// ── Bilhete pronto (saída de ticketBuilder.ts) ──────────────────────────────

export interface TicketSelection {
  fixture_id: string | number;
  time_casa: string;
  time_fora: string;
  liga: string;
  horario_br: string;

  mercado_escolhido: MarketKey;
  pick: string;                          // Ex: "Over 8.5 Cantos"
  odd: number;
  confianca_pct: number;
  categoria_risco: RiskCategory;

  /** Justificativa tática por seleção (mostrada na UI do bilhete) */
  analise_tatica: string;

  /** Valor de odd multiplicado até agora (apenas informativo) */
  odd_acumulada_ate_aqui?: number;
}

export interface BetTicket {
  gerado_em_iso: string;
  total_selecoes: number;
  odd_acumulada: number;
  probabilidade_conjunta_pct: number;  // (p1 * p2 * ... * pn) / 100^(n-1)
  risco_geral: RiskCategory;

  stake_padrao_brl: number;             // Ex: 100.00
  stake_sugerido_pct_do_bankroll: number; // Ex: 2.5
  retorno_potencial_brl: number;        // stake * odd_acumulada
  valor_esperado_x_aposta: number;      // (odd * p) - 1

  selecoes: TicketSelection[];

  /** Se GEMINI_API_KEY estiver ausente, esse campo preenche o banner UI */
  banner_erro_config?: string;
}
