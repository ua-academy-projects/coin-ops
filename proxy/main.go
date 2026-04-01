package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
)


type Rate struct {
	CC   string  `json:"cc"`
	Txt  string  `json:"txt"`
	Rate float64 `json:"rate"`
}

func getRates(w http.ResponseWriter, r *http.Request) {
	resp, err := http.Get("https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json")
	if err != nil {
		http.Error(w, "Помилка запиту до НБУ", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, "Помилка читання відповіді", http.StatusInternalServerError)
		return
	}


	var allRates []Rate
	json.Unmarshal(body, &allRates)

	needed := map[string]bool{"USD": true, "EUR": true, "GBP": true}
	var filtered []Rate
	for _, rate := range allRates {
		if needed[rate.CC] {
			filtered = append(filtered, rate)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(filtered)
}

func main() {
	http.HandleFunc("/rates", getRates)
	
	fmt.Println("Проксі сервіс запущено на порту 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
