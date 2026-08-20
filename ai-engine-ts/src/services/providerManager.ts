/**
 * providerManager.ts
 * ==================
 * Camada COMPLETA:
 *   1) NORMALIZAÇÃO: recebe dados JSON externos (Python FastAPI, Flutter, WS) e
 *      converte em `MatchStats` usado em `aiAdvisor.ts`.
 *   2) FETCHER REAL: consulta as 6 fontes diretamente, ou via PROXY server-side
 *      (solução definitiva p/ CORS no browser).
 *   3) STATUS BADGE: equivalente ao /api/v3/sports/api-status do Python, mas em
 *      TypeScript, com logs HTTP 401/403/429 detalhados por fonte.
 *   4) CACHE LAYER COM PURGE AUTOMÁTICO POR DATA: se data ISO mudou (hoje != ontem),
 *      purge automático. Força refresh network, não carrega seed ontem.
 */
import "dotenv/config";
import https from "node:https";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import type { MatchStats, TeamStatsLive } from "../types";

// ============================================================================
// CAMADA 4 · CACHE + PURGE AUTOMÁTICO POR DATA
// ============================================================================
const CACHE_DIR = (() => {
  try {
    const base = (process.env.CACHE_DIR as string) || path.join(os.tmpdir(), "tiago-ia-cache");
    fs.mkdirSync(base, { recursive: true });
    return base;
  } catch {
    return null;
  }
})();

const CACHE_KEYS = {
  status: "provider-status-latest.json",
  hojePrefix: "today-matches",
  diaCorrente: "current-day-iso.txt",
};

function _cachePath(key: string): string | null {
  if (!CACHE_DIR) return null;
  try { return path.join(CACHE_DIR, key); } catch { return null; }
}

function _cacheRead(key: string): unknown | null {
  const p = _cachePath(key);
  if (!p) return null;
  try {
    if (!fs.existsSync(p)) return null;
    const txt = fs.readFileSync(p, "utf8");
    if (!txt || txt.length < 2) return null;
    return JSON.parse(txt);
  } catch { return null; }
}

function _cacheWrite(key: string, val: unknown): boolean {
  const p = _cachePath(key);
  if (!p) return false;
  try { fs.writeFileSync(p, JSON.stringify(val, null, 0), "utf8"); return true; } catch { return false; }
}

function _cacheDelete(key: string): boolean {
  const p = _cachePath(key);
  if (!p) return false;
  try { if (fs.existsSync(p)) fs.unlinkSync(p); return true; } catch { return false; }
}

/**
 * PURGE TOTAL: apaga TUDO do cache do providerManager (status + today de todos os dias).
 * Útil para botão "Limpar Cache" na UI.
 */
export function purgeAllCache(): void {
  if (!CACHE_DIR) return;
  try {
    const items = fs.readdirSync(CACHE_DIR);
    for (const it of items) {
      if (
        it === CACHE_KEYS.status ||
        it.startsWith(CACHE_KEYS.hojePrefix) ||
        it === CACHE_KEYS.diaCorrente
      ) {
        try { fs.unlinkSync(path.join(CACHE_DIR, it)); } catch { /* ignore */ }
      }
    }
    // eslint-disable-next-line no-console
    console.log("[providerManager] 🧹 Cache providerManager APAGADO (purgeAllCache)");
  } catch { /* ignore */ }
}

/**
 * PURGE AUTOMÁTICO SE A DATA MUDOU: compara a data salva no cache com hoje.
 * Se diferente → apaga caches velhos, atualiza arquivo dia corrente.
 * Deve ser chamado NO BOOT DO APP / inicialização do componente Dashboard.
 * Retorna true se purge REALMENTE aconteceu.
 */
export function purgeStaleCacheIfDateChanged(todayIsoOverride?: string): {
  purged: boolean;
  previousDate: string | null;
  currentDate: string;
} {
  const hoje = (todayIsoOverride ?? new Date().toISOString().slice(0, 10)).slice(0, 10);
  const stored = (_cacheRead(CACHE_KEYS.diaCorrente) as string | null) ?? null;
  const mudou = stored !== null && stored !== hoje;
  if (mudou) {
    purgeAllCache();
  }
  _cacheWrite(CACHE_KEYS.diaCorrente, hoje);
  if (mudou) {
    // eslint-disable-next-line no-console
    console.log(`[providerManager] 🧹 PURGE_AUTO: data mudou ${stored} → ${hoje}. Caches antigos apagados.`);
  }
  return { purged: mudou, previousDate: stored, currentDate: hoje };
}

/**
 * FORÇA REFRESH TOTAL:
 *   1) purgeStaleCacheIfDateChanged (se necessário)
 *   2) purgeAllCache (garante sem nenhum cache velho)
 *   3) Roda checkFontesStatus + fetchTodayMatches com useCache=false
 * Útil para o botão "Forçar Atualização" da UI.
 */
export async function forceRefreshPipeline(opts: { dateIso?: string; verboseLog?: boolean } = {}): Promise<{
  purge: ReturnType<typeof purgeStaleCacheIfDateChanged>;
  status: ProviderStatusReport;
  hoje: FetchTodayReport;
}> {
  const verbose = opts.verboseLog ?? true;
  const purge = purgeStaleCacheIfDateChanged(opts.dateIso);
  purgeAllCache();
  if (verbose) console.log("[providerManager] ⚡ FORCE_REFRESH pipeline iniciado");
  const status = await checkFontesStatus({ timeoutMs: 7000, verboseLog: verbose });
  const hoje = await fetchTodayMatches({
    dateIso: opts.dateIso,
    useFallbackIfEmpty: true,
    timeoutMs: 12000,
    verboseLog: verbose,
  });
  if (verbose) console.log(`[providerManager] ⚡ FORCE_REFRESH pronto. status=${status.status_geral} jogos=${hoje.jogos.length} fonte=${hoje.primeira_fonte_sucesso}`);
  return { purge, status, hoje };
}


// ── HELPERS ENV DINÂMICO (aceita NEXT_PUBLIC_ e s/ prefixo) ─────────────────
function envTry(...keys: string[]): string {
  for (const k of keys) {
    const raw = (process.env[k] ?? "").trim();
    if (raw) return raw;
  }
  return "";
}

const RAPIDAPI_KEY = envTry(
  "NEXT_PUBLIC_RAPIDAPI_KEY",
  "RAPIDAPI_KEY",
  "FOOTBALL_API_KEY",
  "NEXT_PUBLIC_FOOTBALL_API_KEY",
);

const API_FOOTBALL_KEY = envTry(
  "NEXT_PUBLIC_API_FOOTBALL_KEY",
  "API_FOOTBALL_KEY",
);

const FOOTBALL_DATA_ORG_KEY = envTry(
  "NEXT_PUBLIC_FOOTBALL_DATA_ORG_KEY",
  "FOOTBALL_DATA_ORG_KEY",
);

const PROXY_SPORTS_TODAY_URL = envTry(
  "NEXT_PUBLIC_PROXY_SPORTS_TODAY_URL",
  "PROXY_SPORTS_TODAY_URL",
  "BACKEND_TODAY_URL",
);

const HOSTS = {
  flashlive: envTry("RAPIDAPI_HOST_FLASHLIVE") || "flashlive-sports.p.rapidapi.com",
  freeapi:   envTry("RAPIDAPI_HOST_FREEAPI")   || "free-api-live-football-data.p.rapidapi.com",
  legacy:    envTry("RAPIDAPI_HOST_LEGACY")    || "api-football-v1.p.rapidapi.com",
  footpro:   envTry("RAPIDAPI_HOST_FOOTBALL_PRO") || "football-pro.p.rapidapi.com",
};

// ── Tipos internos fontes ───────────────────────────────────────────────────
type FonteId =
  | "F1_FLASHLIVE"
  | "F2_FREEAPI"
  | "F3_API_FOOT_RAPID"
  | "F4_FOOTBALL_PRO"
  | "F5_API_FOOT_DIRETO"
  | "F6_FOOTBALL_DATA";

type FonteMeta = {
  id: FonteId;
  ordem: number;
  label: string;
  camada: "RAPIDAPI" | "DIRETA";
  chave_env: string[];
  probeUrl: (d?: string) => string;
  fixturesUrl: (d: string) => string;
};

const FONTES_6: FonteMeta[] = [
  {
    id: "F1_FLASHLIVE", ordem: 1, label: "F1 · FlashLive", camada: "RAPIDAPI",
    chave_env: ["RAPIDAPI_KEY"],
    probeUrl: () => `https://${HOSTS.flashlive}/v1/events/live?sport_id=1`,
    fixturesUrl: (d) => `https://${HOSTS.flashlive}/v1/events/list?sport_id=1&date=${d}`,
  },
  {
    id: "F2_FREEAPI", ordem: 2, label: "F2 · FreeAPI", camada: "RAPIDAPI",
    chave_env: ["RAPIDAPI_KEY"],
    probeUrl: () => `https://${HOSTS.freeapi}/football-today-matches`,
    fixturesUrl: (d) => `https://${HOSTS.freeapi}/football-fixtures-by-date?date=${d}`,
  },
  {
    id: "F3_API_FOOT_RAPID", ordem: 3, label: "F3 · API-Foot Rapid", camada: "RAPIDAPI",
    chave_env: ["RAPIDAPI_KEY"],
    probeUrl: () => `https://${HOSTS.legacy}/v3/timezone`,
    fixturesUrl: (d) => `https://${HOSTS.legacy}/v3/fixtures?date=${d}`,
  },
  {
    id: "F4_FOOTBALL_PRO", ordem: 4, label: "F4 · Football-Pro", camada: "RAPIDAPI",
    chave_env: ["RAPIDAPI_KEY"],
    probeUrl: () => `https://${HOSTS.footpro}/v3/football/fixtures?date=${todayIso()}`,
    fixturesUrl: (d) => `https://${HOSTS.footpro}/v3/football/fixtures?date=${d}`,
  },
  {
    id: "F5_API_FOOT_DIRETO", ordem: 5, label: "F5 · API-Foot Direto", camada: "DIRETA",
    chave_env: ["API_FOOTBALL_KEY"],
    probeUrl: () => "https://v3.football.api-sports.io/timezone",
    fixturesUrl: (d) => `https://v3.football.api-sports.io/fixtures?date=${d}`,
  },
  {
    id: "F6_FOOTBALL_DATA", ordem: 6, label: "F6 · Football-Data.org", camada: "DIRETA",
    chave_env: ["FOOTBALL_DATA_ORG_KEY"],
    probeUrl: () => "https://api.football-data.org/v4/competitions",
    fixturesUrl: (d) => `https://api.football-data.org/v4/matches?dateFrom=${d}&dateTo=${d}`,
  },
];

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

// ── HTTP fetch universal (funciona em Node com https/http, e em browser usa global fetch) ──
type HttpResponse = {
  status: number;
  ok: boolean;
  bodyText: string;
  headers: Record<string, string>;
  ms: number;
};

function _fetchNode(url: string, opts: { method?: string; headers?: Record<string, string>; timeoutMs?: number } = {}): Promise<HttpResponse> {
  return new Promise<HttpResponse>((resolve) => {
    const u = new URL(url);
    const lib = u.protocol === "https:" ? https : http;
    const t0 = Date.now();
    const timeoutMs = opts.timeoutMs ?? 12000;
    const req = lib.request({
      hostname: u.hostname,
      port: u.port || (u.protocol === "https:" ? 443 : 80),
      path: u.pathname + u.search,
      method: (opts.method || "GET").toUpperCase(),
      headers: opts.headers || {},
      timeout: timeoutMs,
    }, (res) => {
      const chunks: Buffer[] = [];
      res.on("data", (c: Buffer) => chunks.push(c));
      res.on("end", () => {
        const buf = Buffer.concat(chunks);
        const hdrs: Record<string, string> = {};
        for (const k of Object.keys(res.headers)) {
          const v = res.headers[k];
          hdrs[k] = Array.isArray(v) ? v.join(", ") : String(v ?? "");
        }
        resolve({
          status: res.statusCode ?? 0,
          ok: (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300,
          bodyText: buf.toString("utf8"),
          headers: hdrs,
          ms: Date.now() - t0,
        });
      });
    });
    req.on("timeout", () => { req.destroy(new Error("TIMEOUT")); });
    req.on("error", (e) => {
      resolve({
        status: 0, ok: false, bodyText: "EXC:" + String(e?.message ?? e),
        headers: {}, ms: Date.now() - t0,
      });
    });
    req.end();
  });
}

async function fetchAny(url: string, opts: { method?: string; headers?: Record<string, string>; timeoutMs?: number } = {}): Promise<HttpResponse> {
  // browser / Next edge: globalThis.fetch existe
  if (typeof (globalThis as unknown as { fetch?: unknown }).fetch === "function") {
    const t0 = Date.now();
    const ctrl = new AbortController();
    const tm = setTimeout(() => ctrl.abort(), opts.timeoutMs ?? 12000);
    try {
      const r = await (globalThis as unknown as { fetch(input: string, init?: RequestInit): Promise<Response>; }).fetch(url, {
        method: opts.method || "GET",
        headers: opts.headers || {},
        signal: ctrl.signal,
      });
      const txt = await r.text();
      const hdrs: Record<string, string> = {};
      r.headers.forEach((v, k) => { hdrs[k] = v; });
      return { status: r.status, ok: r.ok, bodyText: txt, headers: hdrs, ms: Date.now() - t0 };
    } catch (e) {
      return { status: 0, ok: false, bodyText: "EXC:" + String((e as Error)?.message ?? e), headers: {}, ms: Date.now() - t0 };
    } finally { clearTimeout(tm); }
  }
  return _fetchNode(url, opts);
}

function headersForFonte(f: FonteMeta): Record<string, string> {
  if (f.camada === "RAPIDAPI") {
    let host = HOSTS.flashlive;
    if (f.id === "F2_FREEAPI") host = HOSTS.freeapi;
    if (f.id === "F3_API_FOOT_RAPID") host = HOSTS.legacy;
    if (f.id === "F4_FOOTBALL_PRO") host = HOSTS.footpro;
    return {
      "x-rapidapi-key": RAPIDAPI_KEY,
      "x-rapidapi-host": host,
      "accept": "application/json",
      "user-agent": "TiagoIA-AIEngine/1.0",
    };
  }
  if (f.id === "F5_API_FOOT_DIRETO") {
    return {
      "x-apisports-key": API_FOOTBALL_KEY,
      "x-rapidapi-key": API_FOOTBALL_KEY,
      "accept": "application/json",
    };
  }
  // F6 Football-Data.org
  return {
    "X-Auth-Token": FOOTBALL_DATA_ORG_KEY,
    "accept": "application/json",
  };
}

function apiKeyForFonte(f: FonteMeta): string {
  if (f.camada === "RAPIDAPI") return RAPIDAPI_KEY;
  if (f.id === "F5_API_FOOT_DIRETO") return API_FOOTBALL_KEY;
  return FOOTBALL_DATA_ORG_KEY;
}

function classificacaoHttp(status: number): { online: boolean; label: string } {
  if (status === 0) return { online: false, label: "Sem conexão / DNS / CORS bloqueado" };
  if (status === 200) return { online: true, label: "HTTP 200 OK" };
  if (status === 204 || status === 206) return { online: true, label: `HTTP ${status} (vazio / parcial)` };
  if (status === 401) return { online: false, label: "HTTP 401 Unauthorized (chave inválida)" };
  if (status === 403) return { online: true,  label: "HTTP 403 (chave válida · plano/saiba mais)" };
  if (status === 429) return { online: true,  label: "HTTP 429 Rate Limit (chave OK)" };
  if (status === 404) return { online: false, label: "HTTP 404 endpoint não existe" };
  if (status >= 500) return { online: false, label: `HTTP ${status} servidor remoto falhou` };
  if (status >= 300 && status < 400) return { online: false, label: `HTTP ${status} redirect (CORS?)` };
  return { online: false, label: `HTTP ${status}` };
}

// ── STATUS BADGE: equivalente ao /api/v3/sports/api-status ──────────────────
export type ProviderStatusReport = {
  gerado_em_utc: string;
  status_geral: "EXCELENTE" | "BOM" | "REDUZIDO" | "SOMENTE_FALLBACK";
  fontes_online: number;
  fontes_chave_ok: number;
  total_fontes: 6;
  fontes: Array<{
    id: FonteId;
    ordem: number;
    label: string;
    camada: "RAPIDAPI" | "DIRETA";
    chave_configurada: boolean;
    probe_url: string;
    http_status: number;
    latencia_ms: number;
    online: boolean;
    mensagem: string;
    corpo: string;
  }>;
};

/**
 * Equivalente ao /api/v3/sports/api-status.
 * Faz probe HTTP real em TODAS as 6 fontes, loga status codes 401/403/429.
 */
export async function checkFontesStatus(opts: { timeoutMs?: number; verboseLog?: boolean } = {}): Promise<ProviderStatusReport> {
  const timeoutMs = opts.timeoutMs ?? 5000;
  const verbose = opts.verboseLog ?? true;
  const resultados = await Promise.all(
    FONTES_6.map(async (f) => {
      const key = apiKeyForFonte(f);
      const chave_configurada = !!key;
      const probeUrl = f.probeUrl();
      let http_status = 0;
      let latencia_ms = 0;
      let mensagem = chave_configurada ? "Aguardando probe..." : "Chave ausente no .env";
      let corpo = "";
      let online = false;
      if (chave_configurada) {
        const r = await fetchAny(probeUrl, { headers: headersForFonte(f), timeoutMs });
        http_status = r.status;
        latencia_ms = r.ms;
        const c = classificacaoHttp(http_status);
        online = c.online;
        mensagem = c.label;
        corpo = r.bodyText.length > 600 ? r.bodyText.slice(0, 600) + "…[trunc]" : r.bodyText;
      }
      const rec = {
        id: f.id, ordem: f.ordem, label: f.label, camada: f.camada,
        chave_configurada, probe_url: probeUrl, http_status, latencia_ms,
        online, mensagem, corpo,
      };
      if (verbose) {
        const pre = rec.online ? "🟢" : rec.chave_configurada ? "🔴" : "⚪";
        // eslint-disable-next-line no-console
        console.log(`[providerManager] ${pre} ${rec.label.padEnd(24, " ")} HTTP=${String(rec.http_status).padEnd(3)} ${rec.latencia_ms}ms · ${rec.mensagem}`);
      }
      return rec;
    }),
  );
  const online = resultados.filter((r) => r.online).length;
  const chave_ok = resultados.filter((r) => r.chave_configurada).length;
  let status_geral: ProviderStatusReport["status_geral"] = "SOMENTE_FALLBACK";
  if (online >= 5) status_geral = "EXCELENTE";
  else if (online >= 3) status_geral = "BOM";
  else if (online >= 1) status_geral = "REDUZIDO";
  return {
    gerado_em_utc: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    status_geral, fontes_online: online, fontes_chave_ok: chave_ok,
    total_fontes: 6, fontes: resultados.sort((a, b) => a.ordem - b.ordem),
  };
}

// ── FETCH TODAY: busca partidas REAIS de hoje via cadeia 6 fontes ou proxy ──
export type FetchTodayReport = {
  data_iso: string;
  fontes_tentadas: number;
  primeira_fonte_sucesso: FonteId | "PROXY" | "NONE";
  http_por_fonte: Array<{ id: FonteId; status: number; ms: number; qtd: number; msg: string }>;
  jogos: MatchStats[];
  fallback_usado: boolean;
  seed_local: MatchStats[];
};

/**
 * Busca partidas de hoje (YYYY-MM-DD) na seguinte ordem:
 *   1) PROXY server-side (se PROXY_SPORTS_TODAY_URL setado) → NÃO sofre CORS
 *   2) Cadeia 6 fontes EM ORDEM (F1 → F6)
 *   3) Fallback: makeDemoMatchStats (seed local por data)
 */
export async function fetchTodayMatches(opts: { dateIso?: string; useFallbackIfEmpty?: boolean; timeoutMs?: number; verboseLog?: boolean } = {}): Promise<FetchTodayReport> {
  const dateIso = (opts.dateIso ?? todayIso()).slice(0, 10);
  const useFallback = opts.useFallbackIfEmpty ?? true;
  const timeoutMs = opts.timeoutMs ?? 10000;
  const verbose = opts.verboseLog ?? true;

  const httpPorFonte: FetchTodayReport["http_por_fonte"] = [];
  let primeiraFonte: FetchTodayReport["primeira_fonte_sucesso"] = "NONE";
  let jogos: MatchStats[] = [];

  // 1) Proxy server-side (FastAPI Python) → bypass CORS definitivo
  if (PROXY_SPORTS_TODAY_URL) {
    try {
      const sep = PROXY_SPORTS_TODAY_URL.includes("?") ? "&" : "?";
      const url = `${PROXY_SPORTS_TODAY_URL}${sep}date=${dateIso}`;
      const r = await fetchAny(url, { timeoutMs: timeoutMs + 5000 });
      if (r.ok && r.bodyText) {
        let parsed: unknown;
        try { parsed = JSON.parse(r.bodyText); } catch { parsed = null; }
        if (parsed && typeof parsed === "object") {
          const list = Array.isArray(parsed) ? parsed as unknown[] : ((parsed as Record<string, unknown>).jogos as unknown[]) || ((parsed as Record<string, unknown>).matches as unknown[]) || [];
          const normalized = list
            .filter((x) => x && typeof x === "object")
            .map((j) => normalizeToMatchStats(j as Record<string, unknown>));
          if (normalized.length > 0) {
            jogos = normalized;
            primeiraFonte = "PROXY";
            if (verbose) console.log(`[providerManager] 🟢 PROXY OK (${jogos.length} jogos · ${r.ms}ms) · URL=${PROXY_SPORTS_TODAY_URL}`);
          }
        }
      } else {
        if (verbose) console.log(`[providerManager] 🔴 PROXY falhou HTTP ${r.status} · ${r.bodyText.slice(0, 120)}`);
      }
    } catch (e) {
      if (verbose) console.log(`[providerManager] 🔴 PROXY exception: ${String((e as Error)?.message ?? e).slice(0, 120)}`);
    }
  }

  // 2) Cadeia 6 fontes (apenas se proxy falhou)
  if (primeiraFonte === "NONE") {
    for (const f of FONTES_6) {
      const key = apiKeyForFonte(f);
      if (!key) {
        httpPorFonte.push({ id: f.id, status: 0, ms: 0, qtd: 0, msg: "Chave não configurada" });
        continue;
      }
      const url = f.fixturesUrl(dateIso);
      const r = await fetchAny(url, { headers: headersForFonte(f), timeoutMs });
      const klass = classificacaoHttp(r.status);
      let qtd = 0;
      let normalized: MatchStats[] = [];
      try {
        const parsed = JSON.parse(r.bodyText);
        const arr = _extractList(f.id, parsed);
        qtd = arr.length;
        normalized = arr
          .filter((x) => x && typeof x === "object")
          .map((j) => _mapFonteToFlat(f.id, j, dateIso))
          .filter((j) => !!j)
          .map((j) => normalizeToMatchStats(j as Record<string, unknown>));
      } catch {
        qtd = 0;
      }
      httpPorFonte.push({ id: f.id, status: r.status, ms: r.ms, qtd, msg: klass.label });
      if (verbose) console.log(`[providerManager] · ${klass.online ? "🟢" : "🔴"} ${f.label.padEnd(22)} HTTP=${String(r.status).padEnd(3)} ${r.ms}ms · jogos=${qtd} · ${klass.label}`);
      if (klass.online && normalized.length > 0 && jogos.length === 0) {
        jogos = normalized;
        primeiraFonte = f.id;
        break;
      }
    }
  }

  // 3) Fallback seed local por data
  const fallbackJogos: MatchStats[] = useFallback ? _fallbackSeed(dateIso) : [];
  if (jogos.length === 0 && useFallback) {
    jogos = fallbackJogos;
  }

  return {
    data_iso: dateIso,
    fontes_tentadas: FONTES_6.length,
    primeira_fonte_sucesso: primeiraFonte,
    http_por_fonte: httpPorFonte,
    jogos,
    fallback_usado: primeiraFonte === "NONE",
    seed_local: fallbackJogos,
  };
}

// ── Helpers extração por fonte ──────────────────────────────────────────────
function _extractList(id: FonteId, parsed: unknown): unknown[] {
  if (!parsed || typeof parsed !== "object") return [];
  const d = parsed as Record<string, unknown>;
  switch (id) {
    case "F1_FLASHLIVE":
      if (Array.isArray(d.data)) return d.data as unknown[];
      if (Array.isArray(d.results)) return d.results as unknown[];
      break;
    case "F2_FREEAPI":
      if (Array.isArray(d.data)) return d.data as unknown[];
      if (Array.isArray(d.matches)) return d.matches as unknown[];
      break;
    case "F3_API_FOOT_RAPID":
    case "F5_API_FOOT_DIRETO":
      if (Array.isArray(d.response)) return d.response as unknown[];
      break;
    case "F4_FOOTBALL_PRO":
      if (Array.isArray(d.data)) return d.data as unknown[];
      if (d.results && typeof d.results === "object") {
        const r2 = d.results as Record<string, unknown>;
        if (Array.isArray(r2.data)) return r2.data as unknown[];
      }
      break;
    case "F6_FOOTBALL_DATA":
      if (Array.isArray(d.matches)) return d.matches as unknown[];
      break;
  }
  for (const k of Object.keys(d)) {
    const v = d[k];
    if (Array.isArray(v) && v.length > 0) return v as unknown[];
  }
  return [];
}

function _mapFonteToFlat(id: FonteId, j: unknown, _dateIso: string): Record<string, unknown> | null {
  if (!j || typeof j !== "object") return null;
  const obj = j as Record<string, unknown>;
  switch (id) {
    case "F3_API_FOOT_RAPID":
    case "F5_API_FOOT_DIRETO": {
      const fix = (obj.fixture as Record<string, unknown> | undefined) || {};
      const lg = (obj.league as Record<string, unknown> | undefined) || {};
      const teams = (obj.teams as Record<string, unknown> | undefined) || {};
      const goals = (obj.goals as Record<string, unknown> | undefined) || {};
      const h = (teams.home as Record<string, unknown> | undefined) || {};
      const a = (teams.away as Record<string, unknown> | undefined) || {};
      return {
        fixture_id: fix.id,
        liga: lg.name,
        liga_pais: lg.country,
        time_casa: h.name,
        time_fora: a.name,
        data: (fix.date as string || "").slice(0, 10),
        horario_br: _toBrTime(fix.date as string | undefined),
        status_flag: ((fix.status as Record<string, unknown> | undefined)?.short as string) || "FUT",
        tempo_decorrido: (fix.status as Record<string, unknown> | undefined)?.elapsed ?? null,
        placar_casa: goals.home,
        placar_fora: goals.away,
      };
    }
    case "F6_FOOTBALL_DATA": {
      const comp = (obj.competition as Record<string, unknown> | undefined) || {};
      const ht = (obj.homeTeam as Record<string, unknown> | undefined) || {};
      const at = (obj.awayTeam as Record<string, unknown> | undefined) || {};
      const score = (obj.score as Record<string, unknown> | undefined) || {};
      const ft = (score.fullTime as Record<string, unknown> | undefined) || {};
      return {
        fixture_id: obj.id,
        liga: comp.name,
        time_casa: ht.name,
        time_fora: at.name,
        data: (obj.utcDate as string || "").slice(0, 10),
        horario_br: _toBrTime(obj.utcDate as string | undefined),
        status_flag: obj.status as string || "SCHEDULED",
        placar_casa: ft.home,
        placar_fora: ft.away,
      };
    }
    case "F1_FLASHLIVE":
    case "F2_FREEAPI":
    case "F4_FOOTBALL_PRO":
    default:
      return obj;
  }
}

function _toBrTime(date?: string): string {
  if (!date) return "--:--";
  try {
    const d = new Date(date);
    if (isNaN(d.getTime())) return date.slice(11, 16) || "--:--";
    const parts = new Intl.DateTimeFormat("pt-BR", {
      timeZone: "America/Sao_Paulo",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(d);
    const h = parts.find((p) => p.type === "hour")?.value ?? "00";
    const m = parts.find((p) => p.type === "minute")?.value ?? "00";
    return `${h}:${m}`;
  } catch {
    return date.slice(11, 16) || "--:--";
  }
}

function _fallbackSeed(dateIso: string): MatchStats[] {
  const seeds = [
    "Palmeiras x São Paulo", "Flamengo x Fluminense", "Corinthians x Santos",
    "Barcelona x Real Madrid", "Manchester City x Liverpool", "Juventus x Milan",
  ];
  return seeds.map((s, i) => {
    const seedStr = `${dateIso}::${s}::${i}`;
    return makeDemoMatchStats(seedStr);
  });
}

// ============================================================================
// SEÇÃO ANTIGA (normalização + demo) preservada, 100% compatibilidade com API antiga
// ============================================================================

const ZERO_STATS: TeamStatsLive = {
  escanteios: 0,
  chutes_ao_gol: 0,
  chutes_fora: 0,
  ataques_perigosos: 0,
  cartoes_amarelos: 0,
  cartoes_vermelhos: 0,
  faltas: 0,
  posse_bola_pct: 50,
};

function pickNum(obj: unknown, keys: string[], fallback = 0): number {
  if (!obj || typeof obj !== "object") return fallback;
  const dict = obj as Record<string, unknown>;
  for (const k of keys) {
    const val = dict[k];
    if (val === undefined || val === null) continue;
    const n = Number(val);
    if (!Number.isNaN(n)) return n;
  }
  return fallback;
}

function pickStr(obj: unknown, keys: string[], fallback = ""): string {
  if (!obj || typeof obj !== "object") return fallback;
  const dict = obj as Record<string, unknown>;
  for (const k of keys) {
    const val = dict[k];
    if (typeof val === "string" && val.trim()) return val.trim();
    if (val !== undefined && val !== null && String(val).trim()) return String(val).trim();
  }
  return fallback;
}

/**
 * Extrai stats de time a partir do flat JSON (Python live_sports_service).
 * O Python retorna estatísticas_live.escanteios_casa / chutes_gol_casa etc.
 */
function extraiStatsFlat(
  jogoFlat: Record<string, unknown>,
  lado: "casa" | "fora",
): Partial<TeamStatsLive> {
  const ladoSuf = lado === "casa" ? "casa" : "fora";
  const lv =
    (jogoFlat.estatisticas_live as Record<string, unknown> | undefined) ??
    (jogoFlat.stats as Record<string, unknown> | undefined) ??
    {};
  return {
    escanteios: pickNum(lv, [`escanteios_${ladoSuf}`, `cantos_${ladoSuf}`, `corners_${ladoSuf}`]),
    chutes_ao_gol: pickNum(lv, [`chutes_gol_${ladoSuf}`, `sot_${ladoSuf}`, `shots_on_target_${ladoSuf}`]),
    chutes_fora: pickNum(lv, [`chutes_fora_${ladoSuf}`, `shots_off_${ladoSuf}`]),
    ataques_perigosos: pickNum(lv, [`ataques_perigosos_${ladoSuf}`, `dangerous_attacks_${ladoSuf}`]),
    cartoes_amarelos: pickNum(lv, [`cartoes_amarelos_${ladoSuf}`, `yellow_cards_${ladoSuf}`]),
    cartoes_vermelhos: pickNum(lv, [`cartoes_vermelhos_${ladoSuf}`, `red_cards_${ladoSuf}`]),
    faltas: pickNum(lv, [`faltas_${ladoSuf}`, `fouls_${ladoSuf}`]),
    posse_bola_pct: pickNum(lv, [`posse_${ladoSuf}`], lado === "casa" ? 50 : 50),
  };
}

/**
 * Shapes aceitos (todos viram o mesmo MatchStats no fim):
 *
 *  1) Resposta FLAT do Python /api/v3/sports/hoje:
 *     { fixture_id, liga, time_casa, time_fora, horario_br, data, status_flag,
 *       tempo_decorrido, placar_casa, placar_fora, estatisticas_live: {...},
 *       odds_1x2: {home, draw, away} }
 *
 *  2) Objeto any (FlashScore / manual) — campos aninhados `teams.home.name` etc.
 */
export function normalizeToMatchStats(input: Record<string, unknown>): MatchStats {
  // ── times e liga ──────────────────────────────────────────────────────────
  const teams =
    (input.teams as Record<string, unknown> | undefined) ??
    ({} as Record<string, unknown>);
  const h = teams.home as Record<string, unknown> | undefined;
  const a = teams.away as Record<string, unknown> | undefined;
  const league =
    (input.league as Record<string, unknown> | undefined) ??
    ({} as Record<string, unknown>);
  const fixture =
    (input.fixture as Record<string, unknown> | undefined) ??
    ({} as Record<string, unknown>);
  const goals =
    (input.goals as Record<string, unknown> | undefined) ??
    ({} as Record<string, unknown>);

  const time_casa =
    pickStr(input, ["time_casa", "home", "home_team", "homeName", "mandante", "casa"]) ||
    pickStr(h, ["name"]);
  const time_fora =
    pickStr(input, ["time_fora", "away", "away_team", "awayName", "visitante", "fora"]) ||
    pickStr(a, ["name"]);
  const liga =
    pickStr(input, ["liga", "league", "campeonato", "tournament"]) ||
    pickStr(league, ["name"]);
  const horario_br =
    pickStr(input, ["horario_br", "hr", "horario", "kickoff", "time", "start_br"]);

  const data_iso =
    pickStr(input, ["data", "date", "data_iso"]) ||
    pickStr(fixture, ["date"]) ||
    new Date().toISOString().slice(0, 10);

  const fixture_id: string | number =
    typeof input.fixture_id === "string" || typeof input.fixture_id === "number"
      ? (input.fixture_id as string | number)
      : typeof fixture.id === "string" || typeof fixture.id === "number"
        ? (fixture.id as string | number)
        : `${liga}::${time_casa}::${time_fora}::${data_iso}`;

  // ── status ─────────────────────────────────────────────────────────────────
  const status_raw =
    pickStr(input, ["status", "status_flag", "state"], "FUTURO").toUpperCase();
  let status: MatchStats["status"] = "FUTURO";
  if (status_raw.startsWith("EM_ANDAMENTO") || ["1H", "HT", "2H", "LIVE", "INPROGRESS", "EM JOGO"].includes(status_raw)) {
    status = "EM_ANDAMENTO";
  } else if (["FT", "AET", "PEN", "FINISHED", "FIM", "TERMINADO"].includes(status_raw)) {
    status = "FIM";
  }

  const minuto_raw =
    pickNum(input, ["tempo_decorrido", "minuto", "minute", "elapsed"], -1);
  const minuto = status === "EM_ANDAMENTO" && minuto_raw >= 0 ? minuto_raw : null;

  const placar_casa =
    pickNum(input, ["placar_casa", "gc", "home_score", "score_home"], -1);
  const placar_fora =
    pickNum(input, ["placar_fora", "gf", "away_score", "score_away"], -1);

  const goals_h = pickNum(goals, ["home"]);
  const goals_a = pickNum(goals, ["away"]);

  // ── odds 1x2 ───────────────────────────────────────────────────────────────
  const odds_in =
    (input.odds_1x2 as Record<string, unknown> | undefined) ??
    ({} as Record<string, unknown>);
  const oc = pickNum(odds_in, ["home", "casa", "1"]);
  const oe = pickNum(odds_in, ["draw", "empate", "x"]);
  const of = pickNum(odds_in, ["away", "fora", "2"]);
  const odds_1x2 =
    oc > 0 && oe > 0 && of > 0 ? { casa: oc, empate: oe, fora: of } : undefined;

  // ── xG ─────────────────────────────────────────────────────────────────────
  const xg_casa = pickNum(input, ["xg_casa", "xg_home", "expected_goals_home"]);
  const xg_fora = pickNum(input, ["xg_fora", "xg_away", "expected_goals_away"]);

  // ── stats ao vivo ──────────────────────────────────────────────────────────
  let stats_casa = extraiStatsFlat(input, "casa");
  let stats_fora = extraiStatsFlat(input, "fora");

  // Fallback: se tudo for 0 e jogo estiver EM_ANDAMENTO, usar equipes e
  // estatísticas parciais. Nunca retornar undefined para campos de porcentagem.
  const completar = (s: Partial<TeamStatsLive>): TeamStatsLive => ({
    ...ZERO_STATS,
    ...s,
    posse_bola_pct: s.posse_bola_pct ?? 50,
  });

  return {
    fixture_id,
    liga: liga || "Liga Desconhecida",
    liga_pais: pickStr(league, ["country"]) || pickStr(input, ["liga_pais"]),
    time_casa,
    time_fora,
    horario_br: horario_br || "--:--",
    data_iso,
    status,
    minuto,
    placar_casa: placar_casa >= 0 ? placar_casa : goals_h,
    placar_fora: placar_fora >= 0 ? placar_fora : goals_a,
    stats_casa: completar(stats_casa),
    stats_fora: completar(stats_fora),
    media_escanteios_casa_ult5: pickNum(input, ["media_escanteios_casa_ult5", "corners_h_mean5"]),
    media_escanteios_fora_ult5: pickNum(input, ["media_escanteios_fora_ult5", "corners_a_mean5"]),
    xg_casa,
    xg_fora,
    odds_1x2,
    metadados: input,
  };
}

/**
 * Cria um MatchStats MOCK (para demo, testes unitários, UI preview).
 * Usa a mesma regra de seed estável do Python para não mudar em cada reload.
 */
export function makeDemoMatchStats(
  seed = "Palmeiras x Sao Paulo",
): MatchStats {
  const n = (Math.abs(hashStr(seed)) % 50) + 1;
  return normalizeToMatchStats({
    fixture_id: 900000 + n,
    liga: "Brasileirão Série A 2025",
    liga_pais: "Brazil",
    time_casa: seed.includes("x") ? seed.split("x")[0].trim() : "Palmeiras",
    time_fora: seed.includes("x") ? seed.split("x")[1].trim() : "São Paulo",
    horario_br: "16:00",
    data_iso: new Date().toISOString().slice(0, 10),
    status_flag: "FUTURO",
    tempo_decorrido: null,
    placar_casa: 0,
    placar_fora: 0,
    odds_1x2: { home: 1.85, draw: 3.4, away: 4.1 },
    media_escanteios_casa_ult5: 5.8,
    media_escanteios_fora_ult5: 4.9,
    xg_casa: 1.62,
    xg_fora: 0.94,
    estatisticas_live: {},
  });
}

/** Pequeno helper de hash estavel (String -> 32bit int). */
function hashStr(s: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h | 0;
}
