from sqlalchemy import create_engine, Column, Integer, String, Float, Boolean, DateTime, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime

SQLALCHEMY_DATABASE_URL = "sqlite:///./tiago_ia.db"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    password_hash = Column(String)


class LearningMemory(Base):
    __tablename__ = "learning_memory"

    id = Column(Integer, primary_key=True, index=True)
    jogo_id = Column(String, index=True)
    motivo_red = Column(Text)
    data = Column(DateTime, default=datetime.utcnow)


class ChatHistory(Base):
    __tablename__ = "chat_history"

    id = Column(Integer, primary_key=True, index=True)
    user_message = Column(Text)
    ai_response = Column(Text)
    timestamp = Column(DateTime, default=datetime.utcnow)


class BankrollProtection(Base):
    __tablename__ = "bankroll_protection"

    id = Column(Integer, primary_key=True, index=True)
    daily_limit = Column(Float, default=100.0)
    current_loss = Column(Float, default=0.0)
    is_locked = Column(Boolean, default=False)


class HistoricalPerformance(Base):
    __tablename__ = "historical_performance"

    id = Column(Integer, primary_key=True, index=True)
    data = Column(DateTime, default=datetime.utcnow)
    resultados = Column(Text)


class UserFeedback(Base):
    __tablename__ = "user_feedback"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, index=True, default="default")
    categoria = Column(String, index=True)
    item_id = Column(String, index=True)
    item_label = Column(String)
    decisao = Column(String)
    sinal_ia = Column(String)
    confianca_ia = Column(Float)
    risco_aceito = Column(Boolean, default=False)
    perfil_risco_usuario = Column(String, default="moderado")
    valor_stake = Column(Float, default=0.0)
    resultado_real = Column(String, nullable=True)
    comentario_usuario = Column(Text, nullable=True)
    extra_json = Column(Text, nullable=True)
    timestamp = Column(DateTime, default=datetime.utcnow)


class AutonomousTicket(Base):
    __tablename__ = "autonomous_tickets"

    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(String, unique=True, index=True)
    risk_level = Column(String, index=True)
    total_odds = Column(Float, default=1.0)
    win_probability = Column(Float, default=0.0)
    stake_brl = Column(Float, default=0.0)
    bankroll_ref_brl = Column(Float, default=1000.0)
    selections_json = Column(Text, default="[]")
    status = Column(String, index=True, default="PENDING")
    grading_json = Column(Text, nullable=True)
    source_provider = Column(String, default="IA_DO_TIAGO")
    created_at = Column(DateTime, default=datetime.utcnow)
    finalised_at = Column(DateTime, nullable=True)


class AutonomousLesson(Base):
    __tablename__ = "autonomous_lessons"

    id = Column(Integer, primary_key=True, index=True)
    lesson_id = Column(String, unique=True, index=True)
    market = Column(String, index=True)
    match_context = Column(Text, default="")
    key_takeaway = Column(Text, default="")
    ticket_id = Column(String, index=True, nullable=True)
    selection_ref = Column(String, nullable=True)
    gemini_enriched = Column(Boolean, default=False)
    gemini_summary = Column(Text, nullable=True)
    applied_as_rule = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class CircuitBreakerState(Base):
    __tablename__ = "circuit_breaker_state"

    id = Column(Integer, primary_key=True, index=True)
    market_key = Column(String, unique=True, index=True)
    consecutive_reds = Column(Integer, default=0)
    is_tripped = Column(Boolean, default=False)
    tripped_until_iso = Column(String, nullable=True)
    last_odds_move_pct = Column(Float, default=0.0)
    updated_at = Column(DateTime, default=datetime.utcnow)


def obter_perfil_risco_usuario(user_id: str = "default") -> dict:
    from collections import Counter
    from statistics import mean

    db = SessionLocal()
    try:
        rows = db.query(UserFeedback).filter(UserFeedback.user_id == user_id).all()
        if not rows:
            return {"perfil": "moderado",
                    "score_risco": 5.0,
                    "total_decisoes": 0,
                    "taxa_aceitacao_risco_alto": 0.30,
                    "stake_medio_pct_banca": 2.5,
                    "top_decisao": "aceitar"}
        decisoes = [r.decisao for r in rows if r.decisao]
        aceitos_risco_alto = sum(1 for r in rows if r.sinal_ia == "nao_apostar" and r.decisao == "aceitar")
        total_vermelhos = sum(1 for r in rows if r.sinal_ia == "nao_apostar")
        taxa = aceitos_risco_alto / max(1, total_vermelhos)
        stakes = [r.valor_stake for r in rows if r.valor_stake and r.valor_stake > 0]
        cnt = Counter(decisoes)
        perfil = "conservador"
        if taxa > 0.55 and stakes and mean(stakes) > 5:
            perfil = "agressivo"
        elif taxa > 0.30 or (stakes and mean(stakes) > 2):
            perfil = "moderado"
        return {"perfil": perfil,
                "score_risco": round(min(10.0, max(1.0, 3.0 + taxa * 7.0 + (mean(stakes) * 0.2 if stakes else 0))), 2),
                "total_decisoes": len(rows),
                "taxa_aceitacao_risco_alto": round(taxa, 3),
                "stake_medio_pct_banca": round(mean(stakes), 2) if stakes else 2.5,
                "top_decisao": cnt.most_common(1)[0][0] if cnt else "aceitar"}
    finally:
        db.close()


def init_db():
    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        bankroll = db.query(BankrollProtection).first()
        if not bankroll:
            default_bankroll = BankrollProtection(
                daily_limit=100.0,
                current_loss=0.0,
                is_locked=False
            )
            db.add(default_bankroll)
            db.commit()
    finally:
        db.close()
