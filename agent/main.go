package main

import (
	"crypto/rand"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"sync"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/host"
	"github.com/shirou/gopsutil/v4/load"
	"github.com/shirou/gopsutil/v4/mem"
	psnet "github.com/shirou/gopsutil/v4/net"
	"github.com/shirou/gopsutil/v4/process"
)

const version = "0.1.0"

type Meta struct {
	Hostname string `json:"hostname"`
	OS string `json:"os"`
	Kernel string `json:"kernel"`
	Architecture string `json:"architecture"`
	CPUModel string `json:"cpu_model"`
	CPUCores int `json:"cpu_cores"`
	AgentVersion string `json:"agent_version"`
	CollectIntervalSeconds int `json:"collect_interval_seconds"`
}

type Memory struct { Used uint64 `json:"used"`; Total uint64 `json:"total"` }
type Network struct { Up float64 `json:"up"`; Down float64 `json:"down"`; TotalUp uint64 `json:"total_up"`; TotalDown uint64 `json:"total_down"` }
type Connections struct { TCP int `json:"tcp"`; UDP int `json:"udp"` }
type Load struct { Load1 float64 `json:"load1"`; Load5 float64 `json:"load5"`; Load15 float64 `json:"load15"` }
type Metrics struct {
	Timestamp int64 `json:"timestamp"`
	CPUUsage float64 `json:"cpu_usage"`
	Memory Memory `json:"memory"`
	Swap Memory `json:"swap"`
	Disk Memory `json:"disk"`
	Network Network `json:"network"`
	Connections Connections `json:"connections"`
	ProcessCount int `json:"process_count"`
	Load Load `json:"load"`
	Uptime uint64 `json:"uptime"`
}
type Snapshot struct { Timestamp int64 `json:"timestamp"`; Metrics Metrics `json:"metrics"` }
type Server struct { token string; meta Meta; historyMinutes int; mu sync.RWMutex; metrics Metrics; history []Snapshot; lastHistory time.Time; previousIO psnet.IOCountersStat; previousAt time.Time }

func main() {
	listen := flag.String("listen", ":9977", "HTTPS listen address")
	token := flag.String("token", "", "required bearer token")
	historyMinutes := flag.Int("history-minutes", 360, "in-memory history retention")
	certPath := flag.String("cert", "", "certificate path (generated when omitted)")
	keyPath := flag.String("key", "", "private key path (generated when omitted)")
	flag.Parse()
	if *token == "" { log.Fatal("--token is required") }
	meta := collectMeta()
	s := &Server{token: *token, meta: meta, historyMinutes: *historyMinutes}
	s.collect()
	go func() { ticker := time.NewTicker(2*time.Second); defer ticker.Stop(); for range ticker.C { s.collect() } }()
	mux := http.NewServeMux(); mux.HandleFunc("/v1/meta", s.metaHandler); mux.HandleFunc("/v1/metrics", s.metricsHandler); mux.HandleFunc("/v1/history", s.historyHandler)
	cert, key, err := ensureCertificate(*certPath, *keyPath); if err != nil { log.Fatal(err) }
	fingerprint, err := certificateFingerprint(cert); if err != nil { log.Fatal(err) }
	log.Printf("aster-agent %s listening on https://%s", version, *listen); log.Printf("TLS SHA-256 fingerprint: %s", fingerprint)
	server := &http.Server{Addr:*listen, Handler:mux, ReadHeaderTimeout:5*time.Second, TLSConfig:&tls.Config{MinVersion:tls.VersionTLS13}}
	log.Fatal(server.ListenAndServeTLS(cert, key))
}

func collectMeta() Meta { hi,_:=host.Info(); infos,_:=cpu.Info(); name:="unknown"; if len(infos)>0{name=infos[0].ModelName}; return Meta{Hostname:hi.Hostname,OS:hi.Platform,Kernel:hi.KernelVersion,Architecture:runtime.GOARCH,CPUModel:name,CPUCores:runtime.NumCPU(),AgentVersion:version,CollectIntervalSeconds:2} }
func (s *Server) collect() {
	percent,_:=cpu.Percent(0,false); vm,_:=mem.VirtualMemory(); sm,_:=mem.SwapMemory(); du,_:=disk.Usage("/"); io,_:=psnet.IOCounters(false); li,_:=load.Avg(); hi,_:=host.Info(); processes,_:=process.Pids(); conns,_:=psnet.Connections("all")
	now:=time.Now(); var up,down float64; var totalUp,totalDown uint64
	if len(io)>0 { totalUp=io[0].BytesSent; totalDown=io[0].BytesRecv; if !s.previousAt.IsZero() { seconds:=now.Sub(s.previousAt).Seconds(); up=float64(io[0].BytesSent-s.previousIO.BytesSent)/seconds; down=float64(io[0].BytesRecv-s.previousIO.BytesRecv)/seconds }; s.previousIO=io[0]; s.previousAt=now }
	tcp,udp:=0,0; for _,c:=range conns { if c.Type==1 {tcp++}; if c.Type==2 {udp++} }
	cpuUsage:=0.0; if len(percent)>0 {cpuUsage=percent[0]}; m:=Metrics{Timestamp:now.Unix(),CPUUsage:cpuUsage,Memory:Memory{vm.Used,vm.Total},Swap:Memory{sm.Used,sm.Total},Disk:Memory{du.Used,du.Total},Network:Network{up,down,totalUp,totalDown},Connections:Connections{tcp,udp},ProcessCount:len(processes),Load:Load{li.Load1,li.Load5,li.Load15},Uptime:hi.Uptime}
	s.mu.Lock(); defer s.mu.Unlock(); s.metrics=m; if now.Sub(s.lastHistory)>=30*time.Second {s.history=append(s.history,Snapshot{now.Unix(),m}); s.lastHistory=now}; cutoff:=now.Add(-time.Duration(s.historyMinutes)*time.Minute).Unix(); index:=sort.Search(len(s.history),func(i int)bool{return s.history[i].Timestamp>=cutoff}); s.history=s.history[index:]
}
func (s *Server) authorized(w http.ResponseWriter,r *http.Request) bool { if r.Header.Get("Authorization")!="Bearer "+s.token { writeError(w,http.StatusUnauthorized,"unauthorized"); return false }; return true }
func (s *Server) metaHandler(w http.ResponseWriter,r *http.Request) { if !s.authorized(w,r){return}; writeJSON(w,http.StatusOK,s.meta) }
func (s *Server) metricsHandler(w http.ResponseWriter,r *http.Request) { if !s.authorized(w,r){return}; s.mu.RLock(); defer s.mu.RUnlock(); writeJSON(w,http.StatusOK,s.metrics) }
func (s *Server) historyHandler(w http.ResponseWriter,r *http.Request) { if !s.authorized(w,r){return}; var since int64; if _,err:=fmt.Sscan(r.URL.Query().Get("since"),&since);err!=nil && r.URL.Query().Get("since")!="" {writeError(w,http.StatusNotFound,"invalid since");return}; s.mu.RLock(); defer s.mu.RUnlock(); out:=make([]Snapshot,0);for _,item:=range s.history {if item.Timestamp>since {out=append(out,item)}};writeJSON(w,http.StatusOK,out) }
func writeJSON(w http.ResponseWriter,status int,value any){w.Header().Set("Content-Type","application/json");w.WriteHeader(status);json.NewEncoder(w).Encode(value)}
func writeError(w http.ResponseWriter,status int,message string){writeJSON(w,status,map[string]string{"error":message})}
func ensureCertificate(certPath,keyPath string)(string,string,error){if certPath==""{certPath=filepath.Join(os.TempDir(),"aster-agent-cert.pem")};if keyPath==""{keyPath=filepath.Join(os.TempDir(),"aster-agent-key.pem")};if _,err:=os.Stat(certPath);err==nil {return certPath,keyPath,nil}; cert,key,err:=generateCertificate();if err!=nil{return "","",err};if err=os.WriteFile(certPath,cert,0600);err!=nil{return "","",err};if err=os.WriteFile(keyPath,key,0600);err!=nil{return "","",err};return certPath,keyPath,nil}
func generateCertificate()([]byte,[]byte,error){key,err:=ecdsa.GenerateKey(elliptic.P256(),rand.Reader);if err!=nil{return nil,nil,err};serial,_:=rand.Int(rand.Reader,new(big.Int).Lsh(big.NewInt(1),128));template:=x509.Certificate{SerialNumber:serial,Subject:pkix.Name{CommonName:"aster-agent"},NotBefore:time.Now().Add(-time.Minute),NotAfter:time.Now().AddDate(10,0,0),KeyUsage:x509.KeyUsageKeyEncipherment|x509.KeyUsageDigitalSignature,ExtKeyUsage:[]x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},DNSNames:[]string{"localhost"}};der,err:=x509.CreateCertificate(rand.Reader,&template,&template,&key.PublicKey,key);if err!=nil{return nil,nil,err};keyDER,err:=x509.MarshalECPrivateKey(key);if err!=nil{return nil,nil,err};return pem.EncodeToMemory(&pem.Block{Type:"CERTIFICATE",Bytes:der}),pem.EncodeToMemory(&pem.Block{Type:"EC PRIVATE KEY",Bytes:keyDER}),nil}
func certificateFingerprint(path string)(string,error){data,err:=os.ReadFile(path);if err!=nil{return "",err};block,_:=pem.Decode(data);if block==nil{return "",fmt.Errorf("invalid certificate")};sum:=sha256.Sum256(block.Bytes);return hex.EncodeToString(sum[:]),nil}
