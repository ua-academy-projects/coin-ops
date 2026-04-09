FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
# Логи не буферизуються, а одразу виводяться
ENV PYTHONUNBUFFERED=1

# Копіюємо тільки requirements спочатку, щоб закешувати цей шар
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000
CMD ["python", "app.py"]
