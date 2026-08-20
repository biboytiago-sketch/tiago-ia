/**
 * Validação de variáveis de ambiente + categorização de risco.
 *
 * Requisitos:
 *   (4) Banner UI explicito se GEMINI_API_KEY estiver ausente.
 *   (2) Mapear score de confiança para RiskCategory (Alta, Médio, Alto).
 */
import "dotenv/config";
import type { RiskCategory } from "../types";

/**
 * Banner padrão se a chave Gemini estiver ausente.
 * Texto copiado exatamente do requisito do usuário.
 */
export const GEMINI_MISSING_KEY_BANNER =
  "⚠️ GEMINI_API_KEY ausente no arquivo .env! Acesse `https://aistudio.google.com/`  para gerar sua chave gratuita do Google Gemini e ativar as análises da IA.";

/** Lê GEMINI_API_KEY do env (priority: env > fallback empty). */
export function getGeminiKey(): string {
  const v =
    (process.env.GEMINI_API_KEY || "").trim() ||
    (process.env.GOOGLE_GENAI_API_KEY || "").trim() ||
    (process.env.GEMINI_KEY || "").trim();
  return v;
}

/** Lê GEMINI_MODEL do env ou default rapido (flash).
 *  Atualizado 2026-08: gemini-2.0-flash descontinuado pela Google.
 *  Default = gemini-3.6-flash (mais recente recomendado pela msg de erro 404). */
export function getGeminiModel(): string {
  const raw = (process.env.GEMINI_MODEL || "").trim();
  if (raw) return raw;
  // backward compat: se o cara tinha 2.0-flash no env e esqueceu de atualizar
  const fallback = ["gemini-2.0-flash", "gemini-2.0-flash-lite"];
  if (fallback.includes(raw.toLowerCase())) {
    return "gemini-3.6-flash";
  }
  return "gemini-3.6-flash";
}

/**
 * Retorna null se a chave existe, senão retorna o texto do banner.
 * A UI do dashboard pode renderizar esse texto diretamente.
 */
export function checkGeminiKeyOrBanner(): string | null {
  const k = getGeminiKey();
  if (!k) return GEMINI_MISSING_KEY_BANNER;
  return null;
}

/**
 * ── Requisito (2) · CATEGORIA DE RISCO por confiança ─────────────────
 *  🎯 Alta Confirmação   >= 70%
 *  🟡 Risco Médio        55% ≤ x ≤ 69%
 *  🔴 Risco Alto/Tent.   < 55%
 */
export function confidenceToCategory(score_pct: number): RiskCategory {
  const s = Math.max(0, Math.min(100, Number(score_pct) || 0));
  if (s >= 70) return "HIGH_CONFIRMATION";
  if (s >= 55) return "MEDIUM_RISK";
  return "HIGH_RISK_SPEC";
}

/** Label humano + emoji para UI. */
export function categoryLabel(cat: RiskCategory): string {
  switch (cat) {
    case "HIGH_CONFIRMATION":
      return "🎯 Alta Confirmação (≥70%)";
    case "MEDIUM_RISK":
      return "🟡 Risco Médio (55% - 69%)";
    case "HIGH_RISK_SPEC":
      return "🔴 Risco Alto / Tentativa (< 55%)";
  }
}

/** Emoji curto (para cards). */
export function categoryEmoji(cat: RiskCategory): string {
  switch (cat) {
    case "HIGH_CONFIRMATION": return "🎯";
    case "MEDIUM_RISK":       return "🟡";
    case "HIGH_RISK_SPEC":    return "🔴";
  }
}

/** BANKROLL e stake default (em BRL). */
export function getDefaultStakeBRL(): number {
  const raw = Number(process.env.DEFAULT_STAKE_BRL || 100);
  return Number.isFinite(raw) && raw > 0 ? raw : 100;
}
export function getBankrollBRL(): number {
  const raw = Number(process.env.BANKROLL_BRL || 1000);
  return Number.isFinite(raw) && raw > 0 ? raw : 1000;
}
