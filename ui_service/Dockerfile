# Stage 1 — Build React frontend
FROM node:20-slim AS builder

WORKDIR /app

# Copy React project files
COPY coin-rates-ui/package.json coin-rates-ui/package-lock.json ./

# Install Node dependencies
RUN npm ci

# Copy React source code
COPY coin-rates-ui/ .

# Build React app — output goes to /app/dist
RUN npm run build

# Stage 2 — Run Flask backend
FROM python:3.10-slim

WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy Flask app
COPY app.py .

# Copy built React files from Stage 1
COPY --from=builder /app/dist ./dist

EXPOSE 8080

CMD ["python3", "app.py"]
