FROM python:3.11-slim

LABEL maintainer="Tiago IA Backend v3.4"
LABEL description="Live Sports Unified Fetcher + IA do Tiago. Docker mode, usado no Render tiago-ia-1."
LABEL build.hash_forcado_clear_cache="2026-08-20-v38-COMPAT-GARANTIA-100PORCENTO-MERCADOS-odds-previsao_mercados-NUNCA-MAIS-NULL-+-FLUTTER-RENDER-DEFAULT-+-TIMEOUTS-30-45s"

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# 1. Dependencias primeiro (cache estavel, so atualiza se requirements.txt mudar)
COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# 2. Copia EXPLICITA do main.py ANTES (forca quebrar cache SEMPRE que main.py mudar, evita layer velha sem /api-status)
COPY backend/main.py /app/main.py

# 3. Restante da aplicacao (modulos Python, templates/static se existir, etc)
COPY backend/ /app/

EXPOSE 8000

# 4. Startup FINAL usando shell form (sh -c) para EXPANDIR $PORT corretamente.
#    Render injeta PORT=10000 em runtime; caindo para 8000 se estiver vazio (localhost).
#    OBS: NAO usar CMD ["array", "json"] aqui pq ele NAO expande variaveis de ambiente!
#    OBS2: Removido --forwarded-allow-ips '*' por enquanto (evita glob expansion bug no sh-slim).
CMD sh -c "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1 --proxy-headers"
