package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
)

// Це структура — опис як виглядають дані від НБУ
type Rate struct {
	CC   string  `json:"cc"`
	Txt  string  `json:"txt"`
	Rate float64 `json:"rate"`
}

func getRates(w http.ResponseWriter, r *http.Request) {
	// Йдемо до НБУ API
	resp, err := http.Get("https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json")
	if err != nil {
		http.Error(w, "Помилка запиту до НБУ", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	// Читаємо відповідь
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, "Помилка читання відповіді", http.StatusInternalServerError)
		return
	}

	// Парсимо JSON
	var allRates []Rate
	json.Unmarshal(body, &allRates)

	// Фільтруємо тільки USD, EUR, GBP
	needed := map[string]bool{"USD": true, "EUR": true, "GBP": true}
	var filtered []Rate
	for _, rate := range allRates {
		if needed[rate.CC] {
			filtered = append(filtered, rate)
		}
	}

	// Відповідаємо Flask у форматі JSON
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(filtered)
}

func main() {
	// Реєструємо маршрут /rates
	http.HandleFunc("/rates", getRates)
	
	fmt.Println("Проксі сервіс запущено на порту 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
