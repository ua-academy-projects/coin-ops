# Base image — Python 3.10 on slim Debian (smaller than full Ubuntu)
FROM python:3.10-slim

# Set working directory inside the container
# All next commands run from here
WORKDIR /app

# Copy requirements first — Docker caches this layer
# If only app.py changes, this layer is reused (faster builds)
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Document that app runs on port 5000
EXPOSE 5000

# Command to run when container starts
CMD ["python3", "app.py"]
