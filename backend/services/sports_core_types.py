"""
SPORT_ANALYTICS_CORE - TIPOS PYDANTIC (MÓDULO 1) + HELPERS GLOBAIS
CanonicalMatch, BetSelection, AutomatedTicket, FailureLesson.
NON-BREAKING: novo serviço isolado.
"""
from __future__ import annotations

import uuid
import time
import math
from enum import Enum
from datetime import datetime
from typing import Optional, Dict, Any, List

from pydantic import BaseModel, Field, field_validator

SIGNATURE = "IA do Tiago · Sports Autonomous Core Engine · Oficial"

# ============================================================
# 1. ENUMS (match TypeScript spec)
# ============================================================
class MarketCategory(str, Enum):
    WINNER = "WINNER"
    CORNERS = "CORNERS"
    GOALS = "GOALS"
    SHOTS_ON_TARGET = "SHOTS_ON_TARGET"
    CARDS = "CARDS"


class RiskLevel(str, Enum):
    HIGH_CONFIDENCE = "HIGH_CONFIDENCE"
    MEDIUM_RISK = "MEDIUM_RISK"
    HIGH_RISK_ATTEMPT = "HIGH_RISK_ATTEMPT"


class TicketStatus(str, Enum):
    PENDING = "PENDING"
    GREEN = "GREEN"
    RED = "RED"
    PARTIAL = "PARTIAL"
    INVALIDATED = "INVALIDATED"


class MatchStatus(str, Enum):
    SCHEDULED = "SCHEDULED"
    LIVE = "LIVE"
    FINISHED = "FINISHED"
    POSTPONED = "POSTPONED"
    CANCELLED = "CANCELLED"


# ============================================================
# 2. MÉTRICAS E STATS (Aninhados no CanonicalMatch)
# ============================================================
class ScoreSplit(BaseModel):
    home: int = 0
    away: int = 0


class MatchStats(BaseModel):
    corners: ScoreSplit = Field(default_factory=ScoreSplit)
    shotsOnTarget: ScoreSplit = Field(default_factory=ScoreSplit)
    shotsOffTarget: ScoreSplit = Field(default_factory=ScoreSplit)
    dangerousAttacks: ScoreSplit = Field(default_factory=ScoreSplit)
    yellowCards: ScoreSplit = Field(default_factory=ScoreSplit)
    redCards: ScoreSplit = Field(default_factory=ScoreSplit)
    fouls: ScoreSplit = Field(default_factory=ScoreSplit)


class MatchMetrics(BaseModel):
    pressureIndexHome: float = 0.0
    pressureIndexAway: float = 0.0
    cornerVelocity10m: float = 0.0
    shotVelocity10m: float = 0.0
    activeThreatScore: float = 0.0
    varAnalysisActive: bool = False
    oddsMovementLast10mPct: float = 0.0


# ============================================================
# 3. CANONICAL MATCH (unifica qualquer fonte)
# ============================================================
class CanonicalMatch(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    externalIds: Dict[str, str] = Field(default_factory=dict)
    homeTeam: str
    awayTeam: str
    league: str = "Unknown"
    country: str = "BR"
    minute: int = 0
    status: MatchStatus = MatchStatus.SCHEDULED
    score: ScoreSplit = Field(default_factory=ScoreSplit)
    stats: MatchStats = Field(default_factory=MatchStats)
    metrics: MatchMetrics = Field(default_factory=MatchMetrics)
    odds1X2: Dict[str, float] = Field(default_factory=lambda: {"1": 2.5, "X": 3.2, "2": 2.7})
    sourceProvider: str = "FALLBACK_IA_DO_TIAGO"
    kickoffAt: Optional[str] = None
    generatedAt: str = Field(default_factory=lambda: datetime.utcnow().isoformat())

    @field_validator("homeTeam", "awayTeam", mode="before")
    @classmethod
    def _trim_teams(cls, v):
        return (str(v).strip()[:60]) if v else "Unknown"

    def total_corners(self) -> int:
        return self.stats.corners.home + self.stats.corners.away

    def total_sot(self) -> int:
        return self.stats.shotsOnTarget.home + self.stats.shotsOnTarget.away

    def total_goals(self) -> int:
        return self.score.home + self.score.away

    def total_yellow(self) -> int:
        return self.stats.yellowCards.home + self.stats.yellowCards.away


# ============================================================
# 4. BET SELECTION + AUTOMATED TICKET
# ============================================================
class BetSelection(BaseModel):
    matchId: str
    homeTeam: str
    awayTeam: str
    league: str
    market: MarketCategory
    selectionName: str  # Ex: "Over 9.5 Corners", "Home Win", "Over 4.5 Shots on Target"
    bookmakerOdds: float = 1.0
    minimumAcceptableOdds: float = 1.0
    confidenceScore: float = 0.0  # 0.0 - 1.0
    riskLevel: RiskLevel = RiskLevel.MEDIUM_RISK
    recommendedStakePercentage: float = 1.0
    tacticalReasoning: str = ""
    safeguardsTriggered: List[str] = Field(default_factory=list)
    marketLine: Optional[float] = None  # Ex: 9.5 for CORNERS


class AutomatedTicket(BaseModel):
    ticketId: str = Field(default_factory=lambda: "TKT-" + uuid.uuid4().hex[:10].upper())
    createdAt: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    riskLevel: RiskLevel
    totalOdds: float = 1.0
    estimatedWinProbability: float = 0.0
    recommendedStakeAmountBRL: float = 0.0
    bankrollReferenceBRL: float = 1000.0
    selections: List[BetSelection] = Field(default_factory=list)
    status: TicketStatus = TicketStatus.PENDING
    maxSelections: int = 10
    engineSignature: str = SIGNATURE
    gradingDetails: Dict[str, Any] = Field(default_factory=dict)
    finalisedAt: Optional[str] = None

    def add_selection_if_fits(self, s: BetSelection) -> bool:
        if len(self.selections) >= self.maxSelections:
            return False
        # Não duplicar partida + mercado
        key = f"{s.matchId}::{s.market.value}"
        for ex in self.selections:
            if f"{ex.matchId}::{ex.market.value}" == key:
                return False
        self.selections.append(s)
        self._recalc()
        return True

    def _recalc(self) -> None:
        odds_prod = 1.0
        conf_sum = 0.0
        stake_pct_sum = 0.0
        for s in self.selections:
            odds_prod *= max(1.01, s.bookmakerOdds)
            conf_sum += s.confidenceScore
            stake_pct_sum += s.recommendedStakePercentage
        self.totalOdds = round(odds_prod, 2)
        n = max(1, len(self.selections))
        mean_conf = conf_sum / n
        # Probabilidade estilo "odds implícitas médias ajustadas pela confiança"
        mean_implied = 1.0 / max(1.01, (odds_prod ** (1.0 / n)))
        self.estimatedWinProbability = round(min(0.99, max(0.01, mean_implied * (0.6 + 0.6 * mean_conf))), 3)
        stake_ref = stake_pct_sum / max(1, min(5, n))  # Média sobre primeiros 5
        self.recommendedStakeAmountBRL = round(self.bankrollReferenceBRL * (stake_ref / 100.0), 2)


# ============================================================
# 5. FAILURE LESSON (Auto-crítica pós RED)
# ============================================================
class FailureLesson(BaseModel):
    id: str = Field(default_factory=lambda: "LSS-" + uuid.uuid4().hex[:9].upper())
    market: MarketCategory
    matchContext: str = ""
    keyTakeaway: str = ""
    triggeredByTicketId: Optional[str] = None
    triggeredBySelection: Optional[str] = None
    geminiEnriched: bool = False
    geminiSummary: Optional[str] = None
    createdAt: str = Field(default_factory=lambda: datetime.utcnow().isoformat())


# ============================================================
# 6. CONSTANTES GLOBAIS
# ============================================================
STAKE_PCT_BY_RISK: Dict[RiskLevel, float] = {
    RiskLevel.HIGH_CONFIDENCE: 2.5,       # 2-3% banca
    RiskLevel.MEDIUM_RISK: 1.0,           # 1% banca
    RiskLevel.HIGH_RISK_ATTEMPT: 0.5,     # 0.5% banca
}

MIN_SELECTIONS_BY_RISK: Dict[RiskLevel, int] = {
    RiskLevel.HIGH_CONFIDENCE: 3,
    RiskLevel.MEDIUM_RISK: 5,
    RiskLevel.HIGH_RISK_ATTEMPT: 7,
}

CONFIDENCE_FLOOR_BY_RISK: Dict[RiskLevel, float] = {
    RiskLevel.HIGH_CONFIDENCE: 0.55,    # 55% (peneira branda; a filtragem principal vem dos safeguards)
    RiskLevel.MEDIUM_RISK: 0.42,        # 42%
    RiskLevel.HIGH_RISK_ATTEMPT: 0.30,  # 30%
}

# Safeguards (MÓDULO 5)
SAFEGUARD_MIN_ODDS = 1.05
SAFEGUARD_MAX_ODDS_NORMAL = 50.0
SAFEGUARD_CIRCUIT_BREAKER_REDS = 3
SAFEGUARD_CIRCUIT_BREAKER_ODDS_MOVE_PCT = 30.0  # +/-30% em 10min = bloqueia

MARKET_LABEL_CATEGORY_MAP: Dict[str, MarketCategory] = {
    "WINNER": MarketCategory.WINNER, "1X2": MarketCategory.WINNER, "1": MarketCategory.WINNER,
    "2": MarketCategory.WINNER, "X": MarketCategory.WINNER, "DOUBLE": MarketCategory.WINNER,
    "CORNERS": MarketCategory.CORNERS, "ESCANT": MarketCategory.CORNERS, "CANT": MarketCategory.CORNERS,
    "GOALS": MarketCategory.GOALS, "OVER": MarketCategory.GOALS, "GOL": MarketCategory.GOALS, "BTTS": MarketCategory.GOALS,
    "SHOTS_ON_TARGET": MarketCategory.SHOTS_ON_TARGET, "SOT": MarketCategory.SHOTS_ON_TARGET, "CHUT": MarketCategory.SHOTS_ON_TARGET,
    "CARDS": MarketCategory.CARDS, "CARD": MarketCategory.CARDS, "YELLOW": MarketCategory.CARDS, "AMARELO": MarketCategory.CARDS,
}


def categorize_market(raw: str) -> MarketCategory:
    raw_up = (str(raw) or "").upper()
    for key, cat in MARKET_LABEL_CATEGORY_MAP.items():
        if key in raw_up:
            return cat
    return MarketCategory.WINNER
