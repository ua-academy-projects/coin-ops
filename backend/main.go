package main

import (
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
)

var ctx = context.Background()

func main() {
    http.HandleFunc("/weather", func(w http.ResponseWriter, r *http.Request) {
        lat := r.URL.Query().Get("lat")
        lon := r.URL.Query().Get("lon")
        if lat == "" || lon == "" {
            lat = "50.4501"
            lon = "30.5234"
        }

        apiURL := fmt.Sprintf(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true",
            lat, lon,
        )

        resp, err := http.Get(apiURL)
        if err != nil {
            http.Error(w, "Failed to fetch weather", http.StatusInternalServerError)
            return
        }
        defer resp.Body.Close()

        body, _ := ioutil.ReadAll(resp.Body)

        w.Header().Set("Content-Type", "application/json")
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Write(body)
    })

    log.Println("Weather proxy running on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}