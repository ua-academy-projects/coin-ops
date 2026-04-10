# Stage 1: Builder
FROM python:3.12-alpine AS builder

WORKDIR /app

COPY requirements.txt .
# Install packages and clean up cache
RUN pip install --user --no-cache-dir -r requirements.txt && \
    find /root/.local -name "__pycache__" -type d -exec rm -rf {} + && \
    find /root/.local -name "*.pyc" -delete && \
    find /root/.local -name "*.pyo" -delete && \
    find /root/.local -name "*.pyd" -delete

# Stage 2: Runtime
FROM python:3.12-alpine

WORKDIR /app

# Copy installed packages from the first stage
COPY --from=builder /root/.local /root/.local
COPY . .

ENV PATH=/root/.local/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

EXPOSE 5000
CMD ["python", "app.py"]
