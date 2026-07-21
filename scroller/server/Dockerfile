FROM python:3.13-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini .
COPY alembic ./alembic
COPY src ./src
# Full reel catalog for production seeding (7991 verse groups).
COPY data/manifest.json ./data/manifest.json
# BSB Strong's groupings + lexicon for /bible/word-study (define mode).
COPY data/word_study/ATTRIBUTION.md ./data/word_study/ATTRIBUTION.md
COPY data/word_study/lexicon/strongs.json ./data/word_study/lexicon/strongs.json
COPY data/word_study/display ./data/word_study/display
# Flutter web bundle (optional). Build with:
#   cd ../client && flutter build web --release --dart-define=API_BASE_URL=
#   copy build/web -> static/web
COPY static ./static

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

CMD ["sh", "-c", "alembic upgrade head && uvicorn src.main:app --host 0.0.0.0 --port 8000"]
