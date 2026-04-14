FROM python:3.12-alpine

# set working directory inside image/container to /app
WORKDIR /app

# copy requirements.txt from the current directory (where the Dockerfile is located) to the working directory in the image/container (/app/requirements.txt)
COPY requirements.txt .
# --no-cache-dir: Avoids caching the installed packages, which can save space in the final image.
RUN pip install --no-cache-dir -r requirements.txt

# copy files from ui to /app in the image/container
COPY . .

# declare that container listens on port 5000 at runtime    
EXPOSE 5000

CMD ["python", "app.py"]
