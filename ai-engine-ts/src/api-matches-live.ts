/**
 * providerManager API PROXY (bypass CORS server-side)
 * ===================================================
 * Roda com `node dist/api-matches-live.js` ou `ts-node src/api-matches-live.ts`.
 *
 * Endpoints:
 *   GET /api/matches/live            => partidas ao vivo (6 fontes cascade)
 *   GET /api/matches/today           => partidas de hoje (date default YYYY-MM-DD)
 *   GET /api/matches/today?date=...  => data específica
 *   GET /api/sports/api-status       => equivalente ao Python /api/v3/sports/api-status
 *
 * Header resposta: Access-Control-Allow-Origin: * (browser CORS OK)
 *
 * Usage Next.js: set PROXY_SPORTS_TODAY_URL=http://127.0.0.1:3100/api/matches/today
 */
import "dotenv/config";
import http from "node:http";
import { URL } from "node:url";
import { checkFontesStatus, fetchTodayMatches } from "./services/providerManager";
import { analyzeMany } from "./services/aiAdvisor";
import { buildReadyBetTicket } from "./services/ticketBuilder";

const PORT = Number(process.env.PROXY_PORT || process.env.PORT || 3100);
const HOST = (process.env.HOST || "127.0.0.1").trim();

function sendJson(res: http.ServerResponse, code: number, data: unknown) {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS,HEAD",
    "Cache-Control": "no-store, private",
    "Content-Length": Buffer.byteLength(body, "utf8"),
  });
  res.end(body);
}

function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

const server = http.createServer(async (req, res) => {
  if (!req.url) { sendJson(res, 400, { ok: false, erro: "sem url" }); return; }
  if (req.method === "OPTIONS") { sendJson(res, 204, {}); return; }

  const u = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);
  const pathname = u.pathname.replace(/\/+$/, "") || "/";

  try {
    // ── 1) Status badge: equivalente ao /api/v3/sports/api-status ──────────
    if (pathname === "/api/sports/api-status" || pathname === "/api/v3/sports/api-status") {
      const probeRaw = u.searchParams.get("probe");
      const probe = probeRaw === null ? true : probeRaw.toLowerCase() !== "false";
      const status = await checkFontesStatus({ timeoutMs: 6000, verboseLog: true });
      sendJson(res, 200, {
        assinatura: "TiagoIA · AI-Engine-TS Proxy",
        versao: "3.4.0-ts",
        gerado_em_utc: status.gerado_em_utc,
        status_geral: status.status_geral,
        fontes_online: status.fontes_online,
        fontes_chave_ok: status.fontes_chave_ok,
        total_fontes: status.total_fontes,
        fallback: { ativa: true, label: "IA do Tiago · Dinâmico" },
        fontes: status.fontes.map((f) => ({
          indice: f.ordem,
          nome: f.label,
          label_curto: f.label,
          tipo: f.camada,
          chave_configurada: f.chave_configurada,
          probe_online: f.online,
          http_status: f.http_status,
          latencia_ms: f.latencia_ms,
          qtd_jogos_recente: 0,
          ultimo_erro: f.mensagem,
          probe_url: f.probe_url,
        })),
      });
      return;
    }

    // ── 2) Hoje (fetchTodayMatches)  /api/matches/today /api/matches/live ──
    if (pathname === "/api/matches/today" || pathname === "/api/matches/live") {
      const dateIso = (u.searchParams.get("date") || "").trim() || new Date().toISOString().slice(0, 10);
      const withTicketRaw = u.searchParams.get("ticket");
      const withTicket = withTicketRaw === null ? false : withTicketRaw.toLowerCase() !== "false";

      const report = await fetchTodayMatches({ dateIso, verboseLog: true });
      const jogosFlat = report.jogos.map((j) => ({
        fixture_id: j.fixture_id,
        liga: j.liga,
        liga_pais: j.liga_pais ?? null,
        time_casa: j.time_casa,
        time_fora: j.time_fora,
        horario_br: j.horario_br,
        data: j.data_iso,
        status_flag: j.status,
        tempo_decorrido: j.minuto,
        placar_casa: j.placar_casa,
        placar_fora: j.placar_fora,
        xg_casa: j.xg_casa ?? null,
        xg_fora: j.xg_fora ?? null,
        odds_1x2: j.odds_1x2 ? { home: j.odds_1x2.casa, draw: j.odds_1x2.empate, away: j.odds_1x2.fora } : null,
        estatisticas_live: {
          escanteios_casa: j.stats_casa.escanteios,
          escanteios_fora: j.stats_fora.escanteios,
          chutes_gol_casa: j.stats_casa.chutes_ao_gol,
          chutes_gol_fora: j.stats_fora.chutes_ao_gol,
          cartoes_amarelos_casa: j.stats_casa.cartoes_amarelos,
          cartoes_amarelos_fora: j.stats_fora.cartoes_amarelos,
          faltas_casa: j.stats_casa.faltas,
          faltas_fora: j.stats_fora.faltas,
          posse_casa: j.stats_casa.posse_bola_pct,
          posse_fora: j.stats_fora.posse_bola_pct,
        },
        media_escanteios_casa_ult5: j.media_escanteios_casa_ult5 ?? null,
        media_escanteios_fora_ult5: j.media_escanteios_fora_ult5 ?? null,
      }));

      let ticket: unknown = null;
      if (withTicket && report.jogos.length > 0) {
        try {
          const predicoes = await analyzeMany(report.jogos, { timeoutMs: 45000 });
          ticket = buildReadyBetTicket(predicoes, { maxSelecoes: 5, minSelecoes: 2 });
        } catch (e: unknown) {
          ticket = { erro: String((e as Error)?.message ?? e) };
        }
      }

      sendJson(res, 200, {
        ok: true,
        gerado_em_utc: nowIso(),
        data_iso: report.data_iso,
        fonte_sucesso: report.primeira_fonte_sucesso,
        fallback_usado: report.fallback_usado,
        total_jogos: report.jogos.length,
        http_por_fonte: report.http_por_fonte,
        jogos: jogosFlat,
        bilhete_pronto: ticket,
      });
      return;
    }

    // ── 3) Health ───────────────────────────────────────────────────────────
    if (pathname === "/" || pathname === "/ping" || pathname === "/health") {
      sendJson(res, 200, {
        status: "ok",
        service: "TiagoIA · AI-Engine-TS Proxy",
        gerado_em_utc: nowIso(),
        endpoints: [
          "GET /api/sports/api-status?probe=true",
          "GET /api/matches/today?date=YYYY-MM-DD&ticket=true",
          "GET /api/matches/live",
        ],
      });
      return;
    }

    sendJson(res, 404, { ok: false, erro: "Endpoint nao encontrado", path: pathname });
  } catch (e) {
    sendJson(res, 500, { ok: false, erro: String((e as Error)?.message ?? e), stack: (e as Error)?.stack?.slice(0, 400) ?? null });
  }
});

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`[proxy] TiagoIA API-MATCHES-LIVE ouvindo em http://${HOST}:${PORT}`);
  // eslint-disable-next-line no-console
  console.log(`[proxy]   GET /api/sports/api-status`);
  // eslint-disable-next-line no-console
  console.log(`[proxy]   GET /api/matches/today?date=${new Date().toISOString().slice(0,10)}&ticket=true`);
});
