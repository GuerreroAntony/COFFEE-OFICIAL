FROM python:3.11-slim
WORKDIR /app

# System deps for Playwright Chromium headless in Docker (Debian Trixie)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core Chromium deps
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdbus-1-3 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 \
    libasound2 libatspi2.0-0 libxshmfence1 \
    # X11 libs
    libx11-6 libx11-xcb1 libxcb1 libxext6 libxrender1 \
    # Fonts (Debian-compatible names)
    libfontconfig1 libfreetype6 fonts-liberation fonts-noto-color-emoji \
    # Audio processing (ffmpeg for pydub)
    ffmpeg \
    # TLS + utils
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && playwright install chromium

COPY . .
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port $PORT"]
