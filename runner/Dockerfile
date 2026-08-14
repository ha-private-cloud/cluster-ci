FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project --no-dev

COPY app.py auth.py buildqueue.py jobs.py storage.py ./
RUN uv sync --locked --no-dev

FROM python:3.13-slim-bookworm

RUN useradd --create-home --uid 1000 appuser
WORKDIR /app

COPY --from=builder --chown=appuser:appuser /app /app

USER appuser
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 5000

# Single worker process: the build queue and in-memory build-status map live
# in process memory (see README) , a second worker process would maintain
# its own, disconnected copy of both. Threaded so log-streaming SSE
# responses don't block build submission/status polling.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "8", "--worker-class", "gthread", "app:app"]
