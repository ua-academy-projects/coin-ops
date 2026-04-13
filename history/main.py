from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import pika
import psycopg2
import json
import threading
import time
import os
from datetime import datetime

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Функція для отримання з'єднання з БД з повторними спробами
def get_db_conn():
    db_host = os.getenv("DB_HOST", "db")
    db_name = os.getenv("POSTGRES_DB")
    db_user = os.getenv("POSTGRES_USER")
    db_pass = os.getenv("POSTGRES_PASSWORD")
    
    return psycopg2.connect(
        host=db_host,
        dbname=db_name,
        user=db_user,
        password=db_pass
    )

def consume_rabbitmq():
    rabbit_host = "rabbitmq"
    rabbit_user = os.getenv("RABBITMQ_DEFAULT_USER")
    rabbit_pass = os.getenv("RABBITMQ_DEFAULT_PASS")
    
    connection = None
    while connection is None:
        try:
            print(f"Connecting to RabbitMQ...")
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(
                    rabbit_host, 5672, '/',
                    pika.PlainCredentials(rabbit_user, rabbit_pass)
                )
            )
            print("Successfully connected to RabbitMQ")
        except Exception as e:
            print(f"RabbitMQ connection failed: {e}. Retrying in 5 seconds...")
            time.sleep(5)

    channel = connection.channel()
    channel.queue_declare(queue='weather_data')

    def callback(ch, method, properties, body):
        try:
            data = json.loads(body)
            current = data.get("current_weather", {})
            daily = data.get("daily", {})
            
            if current and daily:
                conn = get_db_conn()
                cur = conn.cursor()
                weather_time = current.get("time")
                
                cur.execute(
                    """
                    INSERT INTO weather_history (temp, temp_max, temp_min, windspeed, windspeed_max, time)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (time) DO UPDATE SET
                        temp = EXCLUDED.temp,
                        temp_max = EXCLUDED.temp_max,
                        temp_min = EXCLUDED.temp_min,
                        windspeed = EXCLUDED.windspeed,
                        windspeed_max = EXCLUDED.windspeed_max
                    """,
                    (
                        current.get("temperature"),
                        daily.get("temperature_2m_max", [0])[0],
                        daily.get("temperature_2m_min", [0])[0],
                        current.get("windspeed"),
                        daily.get("windspeed_10m_max", [0])[0],
                        weather_time
                    )
                )
                conn.commit()
                cur.close()
                conn.close()
                print(f"[{datetime.now()}] Data updated for {weather_time}")
        except Exception as e:
            print(f"Error processing message: {e}")

    channel.basic_consume(queue='weather_data', on_message_callback=callback, auto_ack=True)
    channel.start_consuming()

threading.Thread(target=consume_rabbitmq, daemon=True).start()

@app.get("/history")
def get_history():
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute("SELECT temp, temp_max, temp_min, windspeed, windspeed_max, time FROM weather_history ORDER BY time DESC LIMIT 50")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        return [{"temp": float(r[0]), "temp_max": float(r[1]), "temp_min": float(r[2]), "windspeed": float(r[3]), "windspeed_max": float(r[4]), "time": r[5].isoformat()} for r in rows]
    except Exception as e:
        return {"error": str(e)}

@app.get("/today")
def get_today_weather():
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute("SELECT temp, temp_max, temp_min, windspeed, windspeed_max, time FROM weather_history WHERE time >= NOW() - INTERVAL '24 hours' ORDER BY time DESC LIMIT 1")
        row = cur.fetchone()
        cur.close()
        conn.close()
        if row:
            return {
                "current_weather": {"temperature": float(row[0]), "windspeed": float(row[3]), "time": row[5].isoformat()},
                "daily": {"temperature_2m_max": [float(row[1])], "temperature_2m_min": [float(row[2])], "windspeed_10m_max": [float(row[4])]}
            }
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="No data")
    except Exception as e:
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
