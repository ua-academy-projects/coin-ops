FROM python:3.12-slim

WORKDIR /app

# Не пишемо .pyc файли на диск
ENV PYTHONDONTWRITEBYTECODE=1
# Логи не буферизуються, а одразу виводяться (важливо для Docker)
ENV PYTHONUNBUFFERED=1

# Копіюємо тільки requirements спочатку, щоб закешувати цей шар
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копіюємо решту коду
COPY . .

EXPOSE 5000
CMD ["python", "app.py"]
