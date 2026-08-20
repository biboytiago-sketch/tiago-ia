/**
 * ai-engine-ts · Demo end-to-end
 * ===============================
 *
 * Demonstração do pipeline completo:
 *   makeDemoMatchStats() → analyzeMatch() → buildReadyBetTicket()
 *
 * Para rodar:
 *   npm install
 *   npm run demo     (roda ts-node sem precisar buildar)
 *   npm run build && node dist/index.js
 *
 * Observação: sem GEMINI_API_KEY no .env, o pipeline usa fallback heurístico
 * determinístico (aiAdvisor.ts), mas retorna o mesmo schema JSON estruturado.
 */
import "dotenv/config";

import { analyzeMatch, analyzeMany } from "./services/aiAdvisor";
import { makeDemoMatchStats } from "./services/providerManager";
import { buildReadyBetTicket, ticketToHumanReadable } from "./services/ticketBuilder";
import { checkGeminiKeyOrBanner } from "./utils/envValidation";

async function demoUnitario() {
  console.log("\n=== 1) Análise unitária (Palmeiras x São Paulo) ===");
  const m = makeDemoMatchStats("Palmeiras x São Paulo");
  const pred = await analyzeMatch(m, { timeoutMs: 40000 });
  console.log(
    "Fixture:",
    pred.fixture_id,
    "·",
    pred.time_casa,
    "x",
    pred.time_fora,
    "·",
    pred.liga,
  );
  console.log("Confiança geral:", pred.confidence_score_pct, "% · Risco:", pred.categoria_risco);
  console.log("Versão modelo:", pred.versao_modelo);
  Object.entries(pred.mercados).forEach(([k, v]) => {
    const prefix = v.valor_ev === "POSITIVO" ? "✅" : v.valor_ev === "NEUTRO" ? "➖" : "❌";
    console.log(
      `  ${prefix} ${v.label_humano} → ${v.recomendacao} · odd ${v.odd_sugerida} · prob ${v.probabilidade_pct}% (EV: ${v.valor_ev})`,
    );
  });
  console.log("🧠 Tático:", pred.raciocinio_tatico.titulo);
  pred.raciocinio_tatico.razoes.forEach((r, i) => console.log(`     ${i + 1}. ${r}`));
}

async function demoBilhete() {
  console.log("\n=== 2) Bilhete pronto (Alta Confirmação ≥ 70%) ===");
  const seeds = [
    "Palmeiras x São Paulo",
    "Flamengo x Fluminense",
    "Corinthians x Santos",
    "Barcelona x Real Madrid",
    "Manchester City x Liverpool",
    "Juventus x Milan",
  ];
  const jogos = seeds.map((s) => makeDemoMatchStats(s));
  const predicoes = await analyzeMany(jogos, { timeoutMs: 40000 });

  const ticket = buildReadyBetTicket(predicoes, {
    maxSelecoes: 5,
    minSelecoes: 2,
    confiancaMinimaPct: 70,
  });

  ticketToHumanReadable(ticket).forEach((l) => console.log(l));

  console.log("\n=== 3) JSON bruto (integração Flutter / FastAPI) ===");
  console.log(JSON.stringify(ticket, null, 2));
}

async function main() {
  const banner = checkGeminiKeyOrBanner();
  if (banner) {
    console.log("\n[BANNER UI - INTEGRAR NO PAINEL]", banner, "\n");
  } else {
    console.log("\n[OK] GEMINI_API_KEY encontrada. Modelo ativo:", process.env.GEMINI_MODEL || "gemini-2.0-flash");
  }

  await demoUnitario();
  await demoBilhete();
}

main().catch((err) => {
  console.error("[ERRO DEMO]", err);
  process.exit(1);
});
