# ==========================================
# ESTÁGIO 1: BUILDER
# ==========================================
FROM python:3.13-slim AS builder

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ==========================================
# ESTÁGIO 2: RUNNER
# ==========================================
FROM python:3.13-slim AS runner

WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

RUN groupadd --system nonroot && \
    useradd --system --gid nonroot --no-create-home --shell /bin/false nonroot

COPY --from=builder /opt/venv /opt/venv

COPY --chown=nonroot:nonroot . .

USER nonroot

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=5)" || exit 1

CMD ["gunicorn", "-w", "2", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8080", "--log-level", "info", "main:app"]
