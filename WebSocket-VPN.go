package main

import (
 "flag"
 "fmt"
 "io"
 "net"
 "os"
 "strings"
 "time"
)

const (
 BufferSize        = 16 * 1024 // 16KB
 ConnectionTimeout = 60 * time.Second
 HttpResponse101   = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
 HttpResponse200   = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 0\r\n\r\n"
)

type Proxy struct {
 listenAddr string
 targetAddr string
}

func NewProxy(listenAddr, targetAddr string) *Proxy {
 return &Proxy{
  listenAddr: listenAddr,
  targetAddr: targetAddr,
 }
}

func (p *Proxy) Start() error {
 listener, err := net.Listen("tcp", p.listenAddr)
 if err != nil {
  return fmt.Errorf("failed to listen on %s: %v", p.listenAddr, err)
 }
 defer listener.Close()

 fmt.Printf("Proxy listening on %s\n", p.listenAddr)
 for {
  client, err := listener.Accept()
  if err != nil {
   continue
  }
  go p.handleConnection(client)
 }
}

func (p *Proxy) handleConnection(client net.Conn) {
 defer client.Close()

 buffer := make([]byte, BufferSize)
 n, err := client.Read(buffer)
 if err != nil {
  return
 }

 reqHeaders := string(buffer[:n])
 targetAddr := p.getHeader(reqHeaders, "X-Real-Host")
 if targetAddr == "" {
  targetAddr = p.targetAddr
 }

 target, err := net.DialTimeout("tcp", targetAddr, ConnectionTimeout)
 if err != nil {
  return
 }
 defer target.Close()

 // Determine response based on "Upgrade" header
 if strings.Contains(reqHeaders, "Upgrade:") {
  client.Write([]byte(HttpResponse101))
 } else {
  client.Write([]byte(HttpResponse200))
 }

 // Relay traffic
 go io.Copy(target, client)
 io.Copy(client, target)
}

func (p *Proxy) getHeader(headers, key string) string {
 for _, line := range strings.Split(headers, "\r\n") {
  if strings.HasPrefix(line, key+": ") {
   return strings.TrimSpace(strings.TrimPrefix(line, key+": "))
  }
 }
 return ""
}

func main() {
 listenAddr := flag.String("listenAddr", "0.0.0.0:80", "Listening address (ip:port)")
 targetAddr := flag.String("targetAddr", "0.0.0.0:2000", "Default target address (ip:port)")
 flag.Parse()

 proxy := NewProxy(*listenAddr, *targetAddr)
 if err := proxy.Start(); err != nil {
  fmt.Fprintf(os.Stderr, "Proxy failed: %v\n", err)
  os.Exit(1)
 }
}