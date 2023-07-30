package main

import (
	"log"
	"fmt"
	"math"
	"math/rand"
	"net/http"

	"golang.org/x/crypto/acme/autocert"
	"github.com/gorilla/websocket"
)

func main() {
	m := autocert.Manager{
		Prompt:     autocert.AcceptTOS,
		HostPolicy: autocert.HostWhitelist("markmakave.com", "onnx.tech"),
		Cache:      autocert.DirCache("certs"),
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/dashboard" {
			ws, err := websocket.Upgrade(w, r, nil, 1024, 1024)
			if err != nil {
				log.Println(err)
				return
			}
			defer ws.Close()
			
			log.Println("connected")
			
			for {
				// generate random point coordinates in spherical coordinates 
				r := rand.Float64()
				theta := math.Pi * rand.Float64()
				phi := 2.0 * math.Pi * rand.Float64()

				x := r * math.Sin(theta) * math.Cos(phi)
				y := r * math.Sin(theta) * math.Sin(phi)
				z := r * math.Cos(theta)

				json := fmt.Sprintf(`{"x": %f, "y": %f, "z": %f}`, x, y, z)

				err := ws.WriteMessage(websocket.TextMessage, []byte(json))
				if err != nil {
					log.Println(err)
					break
				}
			}

		} else {
			http.FileServer(http.Dir("public")).ServeHTTP(w, r)
		}
	})

	s := &http.Server{
		Addr:      	":8080",
		TLSConfig: 	m.TLSConfig(),
		Handler: 	handler,
	}

	log.Fatal(s.ListenAndServeTLS("", ""))
}