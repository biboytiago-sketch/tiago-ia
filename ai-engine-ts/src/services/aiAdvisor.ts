import "dotenv/config";
import type {
  MarketKey,
  MarketPrediction,
  MatchPrediction,
  MatchStats,
  RiskCategory,
  TacticalReasoning,
} from "../types";
import {
  checkGeminiKeyOrBanner,
  confidenceToCategory,
  getGeminiKey,
  getGeminiModel,
} from "../utils/envValidation";

const OUTPUT_SCHEMA_DESC = [
  "VOCE SEMPRE RESPONDE APENAS COM 1 OBJETO JSON VALIDO, sem markdown, sem explicacoes.",
  "Schema do JSON:",
  "{",
  '  "mercados": {',
  '    "winner": { "recomendacao": string, "linha": null, "odd_sugerida": number, "probabilidade_pct": number, "valor_ev": "POSITIVO"|"NEUTRO"|"NEGATIVO" },',
  '    "corners": { "recomendacao": string, "linha": number, "odd_sugerida": number, "probabilidade_pct": number, "valor_ev": "POSITIVO"|"NEUTRO"|"NEGATIVO", "metricas": { "velocidade_cantos_por_min": number, "projetados_total_90min": number } },',
  '    "shots_on_target": { "recomendacao": string, "linha": number, "odd_sugerida": number, "probabilidade_pct": number, "valor_ev": "POSITIVO"|"NEUTRO"|"NEGATIVO" },',
  '    "cards_fouls": { "recomendacao": string, "linha": number, "odd_sugerida": number, "probabilidade_pct": number, "valor_ev": "POSITIVO"|"NEUTRO"|"NEGATIVO", "metricas": { "indice_agressividade": number, "rigidez_arbitro_historico": number } },',
  '    "goals": { "recomendacao": string, "linha": number, "odd_sugerida": number, "probabilidade_pct": number, "valor_ev": "POSITIVO"|"NEUTRO"|"NEGATIVO", "metricas": { "xg_casa": number, "xg_fora": number, "momentum_score": number } }',
  "  },",
  '  "confidence_score_pct": number,',
  '  "raciocinio_tatico": { "titulo": string, "razoes": ["frase 1", "frase 2"] }',
  "}",
].join("\n");

function buildPrompt(m: MatchStats): string {
  const statsStr = (
    s: Partial<MatchStats["stats_casa"]> & { posse_bola_pct?: number; ataques_perigosos?: number; chutes_ao_gol?: number; chutes_fora?: number; escanteios?: number; cartoes_amarelos?: number; cartoes_vermelhos?: number; faltas?: number },
    lado: "CASA" | "FORA",
  ): string =>
    `${lado}: esc=${s.escanteios ?? 0}, chutAG=${s.chutes_ao_gol ?? 0}, chutFora=${s.chutes_fora ?? 0}, ` +
    `ataqPerig=${s.ataques_perigosos ?? 0}, amarelos=${s.cartoes_amarelos ?? 0}, vermelhos=${s.cartoes_vermelhos ?? 0}, ` +
    `faltas=${s.faltas ?? 0}, posse=${s.posse_bola_pct ?? 0}%`;

  const oddStr = m.odds_1x2
    ? `Odds 1x2 mercado: CASA=${m.odds_1x2.casa} EMPATE=${m.odds_1x2.empate} FORA=${m.odds_1x2.fora}`
    : "Sem odds 1x2 da casa (calculo via IA).";

  const ult5 =
    `Media escanteios ultimos 5: CASA=${m.media_escanteios_casa_ult5 ?? "N/D"} FORA=${m.media_escanteios_fora_ult5 ?? "N/D"}`;
  const xgStr = `xG: CASA=${m.xg_casa ?? 0} FORA=${m.xg_fora ?? 0}`;

  const placar =
    m.status === "EM_ANDAMENTO"
      ? `\nJOGO EM ANDAMENTO ${m.minuto ?? "?"}min · Placar ${m.placar_casa ?? 0} x ${m.placar_fora ?? 0}\n`
      : "\nJOGO FUTURO (pre-jogo).\n";

  return [
    'Voce e o AI Advisor oficial do app "Tiago IA".',
    "Analise o confronto abaixo e gere predicoes de 5 mercados obrigatorios:",
    "Vencedor 1X2/Dupla, Cantos (Escanteios), Chutes ao Gol, Cartoes/Faltas, Gols (Over/Under + Ambas Marcam).",
    "Gere uma pontuacao de confianca de 0 a 100 e 1 ou 2 frases curtas de raciocinio tatico.",
    "Probabilidade * odd deve ser > 1.03 para +EV.",
    "",
    `Dados: Liga=${m.liga} Horario(BR)=${m.horario_br} Casa=${m.time_casa} Fora=${m.time_fora} Status=${m.status}`,
    placar,
    statsStr(m.stats_casa as any, "CASA"),
    statsStr(m.stats_fora as any, "FORA"),
    oddStr,
    ult5,
    xgStr,
    "",
    OUTPUT_SCHEMA_DESC,
  ].join("\n");
}

/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-var-requires */
async function callGeminiSdk(prompt: string): Promise<any | null> {
  try {
    const apiKey = getGeminiKey();
    if (!apiKey) return null;
    const mod: any = require("@google/genai");
    const GoogleGenAI: any = mod.GoogleGenAI;
    if (!GoogleGenAI) return null;
    const genai = new GoogleGenAI({ apiKey });
    const model = getGeminiModel();
    const result: any = await genai.models.generateContent({
      model,
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      config: {
        responseMimeType: "application/json",
        temperature: 0.15,
        topP: 0.8,
      },
    });
    // Shapes possiveis do SDK 0.7.x:
    //   1) result.text (string direta), 2) result.response.text,
    //   3) result.candidates[0].content.parts[0].text
    let raw: string | undefined;
    if (typeof result === "string") raw = result;
    else if (typeof result?.text === "string") raw = result.text;
    else if (typeof result?.response?.text === "string") raw = result.response.text;
    else if (typeof result?.text === "function") {
      try { raw = String(result.text()); } catch { raw = undefined; }
    }
    if (!raw && Array.isArray(result?.candidates)) {
      const first =
        result?.candidates?.[0]?.content?.parts?.[0]?.text ||
        result?.candidates?.[0]?.text;
      if (first) raw = String(first);
    }
    if (!raw) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function callGeminiRest(prompt: string): Promise<any | null> {
  const apiKey = getGeminiKey();
  if (!apiKey) return null;
  try {
    const model = getGeminiModel();
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
    const body = JSON.stringify({
      contents: [{ parts: [{ text: prompt }], role: "user" }],
      generationConfig: {
        response_mime_type: "application/json",
        temperature: 0.15,
        topP: 0.8,
      },
    });

    const res = await doPostHttp(url, body);
    if (!res.ok) return null;
    const data = JSON.parse(res.text);
    const first =
      (data &&
        data.candidates &&
        data.candidates[0] &&
        data.candidates[0].content &&
        data.candidates[0].content.parts &&
        data.candidates[0].content.parts[0] &&
        data.candidates[0].content.parts[0].text) ||
      null;
    if (!first) return null;
    return JSON.parse(first);
  } catch {
    return null;
  }
}

function doPostHttp(
  url: string,
  body: string,
): Promise<{ ok: boolean; text: string }> {
  // Tenta fetch global (Node 18+)
  try {
    const g = globalThis as any;
    if (typeof g.fetch === "function") {
      return g
        .fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body,
        })
        .then((r: any) => r.text().then((t: string) => ({ ok: !!r.ok, text: t })));
    }
  } catch {
    /* continua abaixo */
  }
  // Fallback https nativo do Node 16
  return new Promise((resolve) => {
    try {
      const https: any = require("https");
      const urlU: any = new (require("url").URL)(url);
      const req: any = https.request(
        {
          hostname: urlU.hostname,
          path: `${urlU.pathname}${urlU.search}`,
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(body, "utf-8"),
          },
        },
        (res: any) => {
          const chunks: Buffer[] = [];
          res.on("data", (c: Buffer) => chunks.push(c));
          res.on("end", () => {
            const text = Buffer.concat(chunks).toString("utf-8");
            resolve({ ok: String(res.statusCode).startsWith("2"), text });
          });
        },
      );
      req.on("error", () => resolve({ ok: false, text: "" }));
      req.write(body);
      req.end();
    } catch {
      resolve({ ok: false, text: "" });
    }
  });
}

/* =============================================================
 * FALLBACK HEURISTICO DETERMINISTICO (sem chave / timeout etc)
 * ============================================================= */
function hashStr(s: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

function r1(n: number): number {
  return Math.round(Number(n || 0) * 10) / 10;
}
function r2(n: number): number {
  return Math.round(Number(n || 0) * 100) / 100;
}

function predicaoHeuristica(m: MatchStats): MatchPrediction {
  const seed = hashStr(
    `${m.fixture_id}|${m.time_casa}|${m.time_fora}|${m.liga}|${m.data_iso}`,
  );
  let s = seed || 1;
  const rand = (): number => {
    s = (Math.imul(s, 741103597) + 1254353) >>> 0;
    return s / 0xffffffff;
  };

  const odds = m.odds_1x2;
  const cHouse = odds ? 1 / odds.casa : 0.38;
  const cDraw = odds ? 1 / odds.empate : 0.29;
  const cAway = odds ? 1 / odds.fora : 0.33;
  const sumProb = cHouse + cDraw + cAway;
  let pCasa = (cHouse / sumProb) * 100;
  let pEmp = (cDraw / sumProb) * 100;
  let pFora = (cAway / sumProb) * 100;
  if (m.status === "EM_ANDAMENTO" && typeof m.minuto === "number" && m.minuto > 30) {
    const dif = (m.placar_casa ?? 0) - (m.placar_fora ?? 0);
    const peso = Math.min(1, m.minuto / 90);
    if (dif > 0) pCasa += (20 + 30 * peso) * (1 - 1 / (1 + dif));
    if (dif < 0) pFora += (20 + 30 * peso) * (1 - 1 / (1 + Math.abs(dif)));
  }
  pCasa = Math.max(1, Math.min(98, pCasa));
  pFora = Math.max(1, Math.min(98, pFora));
  pEmp = Math.max(1, 100 - pCasa - pFora);

  let rec: string;
  let oddRec: number;
  let pRec: number;
  if (pCasa > pFora && pCasa > pEmp + 6) {
    rec = pCasa >= 75 && pEmp >= 18 ? "Casa ou Empate (1X)" : "Casa (1)";
    oddRec = odds?.casa ?? 100 / Math.max(20, pCasa);
    pRec = rec === "Casa (1)" ? pCasa : Math.min(95, pCasa + pEmp * 0.7);
  } else if (pFora > pCasa && pFora > pEmp + 6) {
    rec = pFora >= 72 && pEmp >= 18 ? "Empate ou Fora (X2)" : "Fora (2)";
    oddRec = odds?.fora ?? 100 / Math.max(20, pFora);
    pRec = rec === "Fora (2)" ? pFora : Math.min(95, pFora + pEmp * 0.7);
  } else {
    rec = "Empate ou Fora (X2)";
    oddRec = odds?.fora ?? 2.6;
    pRec = Math.round(pEmp + pFora);
  }
  oddRec = r2(oddRec);
  const ev1: "POSITIVO" | "NEUTRO" | "NEGATIVO" =
    pRec * oddRec / 100 >= 1.05 ? "POSITIVO" : "NEUTRO";

  const totC = (m.stats_casa.escanteios ?? 0) + (m.stats_fora.escanteios ?? 0);
  const mediaC5 =
    (m.media_escanteios_casa_ult5 ?? 0) + (m.media_escanteios_fora_ult5 ?? 0);
  const projC =
    mediaC5 > 1
      ? mediaC5 +
        (m.status === "EM_ANDAMENTO"
          ? totC * (90 / Math.max(5, m.minuto ?? 60)) * 0.25
          : 0)
      : 8.5 + rand() * 2.5 + totC;
  const linhaC: number = projC >= 10 ? 9.5 : projC >= 8 ? 8.5 : 7.5;
  const overC_pct = Math.min(90, 40 + (projC - linhaC + 2.5) * 12);
  const recC = `Over ${linhaC} Cantos`;
  const oddC = r2(Math.max(1.45, 100 / Math.max(25, overC_pct) + 0.05));

  const totAG =
    (m.stats_casa.chutes_ao_gol ?? 0) + (m.stats_fora.chutes_ao_gol ?? 0);
  const projAG =
    (m.xg_casa ?? 1.2) * 3.2 +
    (m.xg_fora ?? 0.9) * 2.8 +
    (m.status === "EM_ANDAMENTO"
      ? totAG * (90 / Math.max(5, m.minuto ?? 60)) * 0.15
      : 0);
  const linhaAG: number = projAG >= 9 ? 8.5 : projAG >= 7 ? 7.5 : 6.5;
  const overAG_pct = Math.min(88, 38 + (projAG - linhaAG + 2) * 10);
  const recAG = `Over ${linhaAG} Chutes AG (Total)`;
  const oddAG = r2(Math.max(1.4, 100 / Math.max(25, overAG_pct) + 0.05));

  const agres =
    (m.stats_casa.cartoes_amarelos ?? 0) +
    (m.stats_casa.faltas ?? 0) / 6 +
    (m.stats_fora.cartoes_amarelos ?? 0) +
    (m.stats_fora.faltas ?? 0) / 6 +
    rand() * 2;
  const linhaCart: number = agres >= 10 ? 5.5 : agres >= 7 ? 4.5 : 3.5;
  const pCart = Math.min(90, 35 + (agres - linhaCart + 2) * 10);
  const recCart =
    agres >= 8 ? `Over ${linhaCart} Cartoes` : `Under ${linhaCart + 1} Cartoes`;
  const oddCart = r2(Math.max(1.4, 100 / Math.max(25, pCart) + 0.05));

  const xgTot = (m.xg_casa ?? 1.1) + (m.xg_fora ?? 0.9);
  const placarTot = (m.placar_casa ?? 0) + (m.placar_fora ?? 0);
  const projG =
    xgTot +
    (m.status === "EM_ANDAMENTO"
      ? placarTot * (90 / Math.max(5, m.minuto ?? 60)) * 0.15
      : 0);
  const linhaG: number = projG >= 2.8 ? 2.5 : 3.5;
  const overG_pct = Math.min(92, 35 + (projG - linhaG + 1.5) * 14);
  const btts_pct = Math.min(
    85,
    35 + (m.xg_casa ?? 0) * 10 + (m.xg_fora ?? 0) * 9,
  );
  const useBtts = btts_pct >= 62 && overG_pct >= 55;
  let recG: string;
  if (useBtts) {
    recG = btts_pct >= 68 ? "Ambas Marcam - Sim" : "Over 2.5 Gols";
  } else {
    recG = projG < 2.2 ? "Under 3.5 Gols" : "Over 2.5 Gols";
  }
  const oddG = r2(
    useBtts
      ? 100 / Math.max(25, btts_pct) + 0.05
      : Math.max(1.35, 100 / Math.max(25, overG_pct) + 0.05),
  );
  const pG_rec = useBtts ? btts_pct : overG_pct;

  const winnerPred: MarketPrediction = {
    mercado: "winner",
    label_humano: "Vencedor 1X2 / Dupla",
    recomendacao: rec,
    linha: null,
    odd_sugerida: oddRec,
    probabilidade_pct: r1(pRec),
    valor_ev: ev1,
  };
  const corners: MarketPrediction = {
    mercado: "corners",
    label_humano: "Escanteios (Cantos)",
    recomendacao: recC,
    linha: linhaC,
    odd_sugerida: oddC,
    probabilidade_pct: r1(overC_pct),
    valor_ev: overC_pct * oddC / 100 >= 1.04 ? "POSITIVO" : "NEUTRO",
    metricas: {
      velocidade_cantos_por_min: r2(
        m.status === "EM_ANDAMENTO"
          ? totC / Math.max(5, m.minuto ?? 1)
          : projC / 90,
      ),
      projetados_total_90min: r1(projC),
    },
  };
  const shots: MarketPrediction = {
    mercado: "shots_on_target",
    label_humano: "Chutes ao Gol (SoT)",
    recomendacao: recAG,
    linha: linhaAG,
    odd_sugerida: oddAG,
    probabilidade_pct: r1(overAG_pct),
    valor_ev: overAG_pct * oddAG / 100 >= 1.04 ? "POSITIVO" : "NEUTRO",
  };
  const cards: MarketPrediction = {
    mercado: "cards_fouls",
    label_humano: "Cartoes · Faltas · Agressividade",
    recomendacao: recCart,
    linha: linhaCart,
    odd_sugerida: oddCart,
    probabilidade_pct: r1(pCart),
    valor_ev: pCart * oddCart / 100 >= 1.03 ? "POSITIVO" : "NEUTRO",
    metricas: {
      indice_agressividade: r1(Math.min(10, agres / 2)),
      rigidez_arbitro_historico: r1(Math.max(1, Math.min(10, 4 + (seed % 6)))),
    },
  };
  const goals: MarketPrediction = {
    mercado: "goals",
    label_humano: "Gols (Over/Under + Ambas Marcam)",
    recomendacao: recG,
    linha: linhaG,
    odd_sugerida: oddG,
    probabilidade_pct: r1(pG_rec),
    valor_ev: pG_rec * oddG / 100 >= 1.05 ? "POSITIVO" : "NEUTRO",
    metricas: {
      xg_casa: r2(m.xg_casa ?? 1.1),
      xg_fora: r2(m.xg_fora ?? 0.9),
      momentum_score: r1(
        Math.max(
          -10,
          Math.min(
            10,
            ((m.xg_casa ?? 0) - (m.xg_fora ?? 0)) * 4 + (seed % 5) - 2,
          ),
        ),
      ),
    },
  };

  const confidence = r1(
    0.3 * winnerPred.probabilidade_pct +
      0.22 * corners.probabilidade_pct +
      0.22 * goals.probabilidade_pct +
      0.13 * shots.probabilidade_pct +
      0.13 * cards.probabilidade_pct +
      (odds ? 3 : 0),
  );

  const rac: TacticalReasoning = {
    titulo: tituloRac(m, winnerPred, corners, goals),
    razoes: razoesCurta(m, winnerPred, corners, goals, shots, cards),
  };

  return finalizarPredicao(
    m,
    {
      winner: winnerPred,
      corners,
      shots_on_target: shots,
      cards_fouls: cards,
      goals,
    },
    confidence,
    rac,
    false,
  );
}

function finalizarPredicao(
  m: MatchStats,
  mercados: Record<MarketKey, MarketPrediction>,
  confidence: number,
  rac: TacticalReasoning,
  usouGeminiReal: boolean,
): MatchPrediction {
  const conf = Math.max(0, Math.min(100, Number(confidence) || 0));
  const cat: RiskCategory = confidenceToCategory(conf);
  const modelo = usouGeminiReal
    ? `google/${getGeminiModel()}`
    : "heuristico-fallback-local";
  return {
    fixture_id: m.fixture_id,
    time_casa: m.time_casa,
    time_fora: m.time_fora,
    liga: m.liga,
    horario_br: m.horario_br,
    confidence_score_pct: r1(conf),
    categoria_risco: cat,
    mercados,
    raciocinio_tatico: rac,
    versao_modelo: modelo,
    timestamp_iso: new Date().toISOString(),
  };
}

function tituloRac(
  m: MatchStats,
  w: MarketPrediction,
  c: MarketPrediction,
  g: MarketPrediction,
): string {
  if (g.valor_ev === "POSITIVO" && g.probabilidade_pct >= 65) {
    return `Ofensividade em alta: ${g.recomendacao} vs ${m.time_casa} x ${m.time_fora}`;
  }
  if (c.valor_ev === "POSITIVO" && c.probabilidade_pct >= 63) {
    return `Ritmo pelas laterais favorece ${c.recomendacao}`;
  }
  return `${w.recomendacao} pick por historico e posse da bola`;
}
function razoesCurta(
  m: MatchStats,
  w: MarketPrediction,
  c: MarketPrediction,
  g: MarketPrediction,
  s: MarketPrediction,
  k: MarketPrediction,
): string[] {
  const gxg = (g.metricas && typeof g.metricas.xg_casa === "number" && typeof g.metricas.xg_fora === "number")
    ? g.metricas.xg_casa + g.metricas.xg_fora
    : 2.5;
  const r1s =
    g.valor_ev === "POSITIVO"
      ? `xG projetado em ${gxg} sugere ${g.recomendacao.toLowerCase()}.`
      : c.valor_ev === "POSITIVO"
        ? `Velocidade de cantos em ${r2(
            (c.metricas && typeof c.metricas.velocidade_cantos_por_min === "number"
              ? c.metricas.velocidade_cantos_por_min
              : 0.1) || 0.1,
          )}/min indica ${c.recomendacao.toLowerCase()}.`
        : `${w.recomendacao} tem valor esperado positivo (odd ${w.odd_sugerida} ${r1(w.probabilidade_pct)}%).`;
  const r2s =
    k.valor_ev === "POSITIVO"
      ? `Indice de agressividade ${r1(
          (k.metricas && typeof k.metricas.indice_agressividade === "number"
            ? k.metricas.indice_agressividade
            : 0) || 0,
        )}/10 = ${k.recomendacao.toLowerCase()}.`
      : s.valor_ev === "POSITIVO"
        ? `Finalizadores clinicos favorecem ${s.recomendacao.toLowerCase()}.`
        : `Media de escanteios ultimos 5 jogos = ${r1(
            (m.media_escanteios_casa_ult5 || 0) +
              (m.media_escanteios_fora_ult5 || 0),
          )} projetados no 90min.`;
  return [r1s, r2s];
}

/* =============================================================
 * FUNCOES PUBLICAS
 * ============================================================= */
export interface AIAdvisorOptions {
  forceFallback?: boolean;
  timeoutMs?: number;
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T | null> {
  return Promise.race([
    p,
    new Promise<null>((res) => setTimeout(() => res(null), ms)),
  ]);
}

export async function analyzeMatch(
  stats: MatchStats,
  opts: AIAdvisorOptions = {},
): Promise<MatchPrediction> {
  const bannerMsg = checkGeminiKeyOrBanner();
  const usaGemini = !bannerMsg && !opts.forceFallback;
  if (usaGemini) {
    const prompt = buildPrompt(stats);
    const t = opts.timeoutMs ?? 25000;
    const viaSdk = await withTimeout(callGeminiSdk(prompt), t);
    const parsed = viaSdk ?? (await withTimeout(callGeminiRest(prompt), t));
    if (parsed && typeof parsed === "object") {
      const h = parseGeminiResponse(stats, parsed);
      if (h) return h;
    }
  }
  return predicaoHeuristica(stats);
}

export async function analyzeMany(
  jogos: MatchStats[],
  opts: AIAdvisorOptions = {},
): Promise<MatchPrediction[]> {
  const out: MatchPrediction[] = [];
  for (let i = 0; i < jogos.length; i += 3) {
    const chunk = jogos.slice(i, i + 3);
    const res = await Promise.all(chunk.map((j) => analyzeMatch(j, opts)));
    out.push(...res);
  }
  return out;
}

function parseGeminiResponse(
  m: MatchStats,
  raw: any,
): MatchPrediction | null {
  try {
    const mercIn = (raw.mercados ?? {}) as Record<MarketKey, any>;
    const conf = Number(raw.confidence_score_pct) || 0;
    const racIn: any = raw.raciocinio_tatico ?? {};

    const build = (
      k: MarketKey,
      label: string,
      defaultRec: string,
    ): MarketPrediction => {
      const x: any = mercIn?.[k] ?? {};
      const p = Math.max(0, Math.min(100, Number(x.probabilidade_pct) || 0));
      const odd = Math.max(1.01, Number(x.odd_sugerida) || 1.5);
      const evRaw = String(x.valor_ev || "").toUpperCase();
      const ev: "POSITIVO" | "NEUTRO" | "NEGATIVO" =
        evRaw === "NEGATIVO"
          ? "NEGATIVO"
          : p * odd / 100 >= 1.04
            ? "POSITIVO"
            : "NEUTRO";
      return {
        mercado: k,
        label_humano: label,
        recomendacao: String(x.recomendacao || defaultRec).trim(),
        linha: x.linha == null ? null : Number(x.linha),
        odd_sugerida: r2(odd),
        probabilidade_pct: r1(p),
        valor_ev: ev,
        metricas: x.metricas && typeof x.metricas === "object"
          ? (x.metricas as Record<string, any>)
          : undefined,
      };
    };

    const mercados: Record<MarketKey, MarketPrediction> = {
      winner: build("winner", "Vencedor 1X2 / Dupla", "Casa ou Empate (1X)"),
      corners: build("corners", "Escanteios (Cantos)", "Over 8.5 Cantos"),
      shots_on_target: build(
        "shots_on_target",
        "Chutes ao Gol (SoT)",
        "Over 7.5 Chutes AG (Total)",
      ),
      cards_fouls: build(
        "cards_fouls",
        "Cartoes · Faltas · Agressividade",
        "Over 4.5 Cartoes",
      ),
      goals: build(
        "goals",
        "Gols (Over/Under + Ambas Marcam)",
        "Over 2.5 Gols",
      ),
    };

    const rac: TacticalReasoning = {
      titulo: String(racIn.titulo || "Analise AI com valor esperado positivo.").trim(),
      razoes: (Array.isArray(racIn.razoes) ? (racIn.razoes as any[]) : [])
        .map((r: any) => String(r || "").trim())
        .filter(Boolean)
        .slice(0, 2),
    };
    if (rac.razoes.length === 0) {
      rac.razoes = predicaoHeuristica(m).raciocinio_tatico.razoes;
    }
    return finalizarPredicao(m, mercados, conf, rac, true);
  } catch {
    return null;
  }
}
