FROM python:3.11-slim

LABEL maintainer="Tiago IA Backend v3.4"
LABEL description="Live Sports Unified Fetcher + IA do Tiago. Docker mode, usado no Render tiago-ia-1."

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

# 4. Startup final: uvicorn direto, respeita porta $PORT do Render
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "${PORT:-8000}", "--workers", "1", "--proxy-headers", "--forwarded-allow-ips", "*"]
