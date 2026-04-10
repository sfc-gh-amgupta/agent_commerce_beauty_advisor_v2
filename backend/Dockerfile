# ============================================================================
# Agent Commerce - Backend + Frontend Dockerfile
# ============================================================================
# Expects frontend to be pre-built and copied to ./static/ before build
# Use deploy.sh which handles the frontend build automatically
# ============================================================================

FROM python:3.9-slim-bullseye

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    libopenblas-dev \
    liblapack-dev \
    libx11-dev \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Verify cmake version
RUN cmake --version

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install dlib (uses system cmake)
RUN pip install --no-cache-dir dlib==19.24.0

# Install face-recognition
RUN pip install --no-cache-dir face-recognition==1.3.0

# Install remaining dependencies
COPY requirements-final.txt .
RUN pip install --no-cache-dir -r requirements-final.txt

# Copy application code
COPY app/ ./app/

# Copy pre-built frontend (built by deploy.sh)
COPY static/ ./static/

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run the application
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
