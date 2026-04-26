# Nasazení The Elastic Stack (ELK) pro analýzu Spotify dat

Semestrální projekt do předmětu **BSQBD - NoSQL databáze** (UPCE FEI, 3. ročník LS 2026).

**Autor:** Matyáš Bláha

## O čem projekt je

Plně automatizované nasazení ELK stacku (Elasticsearch 8.17 + Logstash 8.17 + Kibana 8.17) v Dockeru pro analýzu hudebních dat ze Spotify. Cluster běží jako **HA setup se 4 master-eligible uzly** (1 dedikovaný master + 3 data uzly s rolí master,data,ingest), s replikačním faktorem 3 a TLS zabezpečením všude.

**Datové sady (Kaggle):** ~28 tisíc dokumentů ve 3 indexech — `tracks` (15 000 skladeb), `artists` (5 271 interpretů), `charts` (8 000 chart pozic).

## Předpoklady

- **Docker Desktop** s minimálně **10 GiB RAM** (doporučeno 12 GiB) — Settings → Resources → Memory
- Volné porty: `9200` (ES), `5601` (Kibana), `8080` (Elasticvue)

## Spuštění (jediný příkaz)

```bash
# 1. Vstup do složky s docker-compose
cd "Funkční řešení"

# 2. Pokud .env NEEXISTUJE (např. po git clone), zkopíruj vzor:
[ ! -f .env ] && cp .env.example .env

# 3. Spusť celý stack
docker compose up -d
```

Stack startuje **~2-3 minuty**:
- Setup vygeneruje TLS certifikáty (~6 s)
- 4 ES uzly nabootují, master se zvolí leaderem (~80 s)
- Init kontejner vytvoří 3 index templates (~5 s)
- Logstash importuje 3 CSV ze složky `../Data/` (~60-90 s)
- Kibana naběhne (~30 s)

## Ověření, že vše běží

```bash
# 1. Stav kontejnerů (musí být všechny Up healthy, init/setup Exited (0))
docker compose ps

# 2. Cluster health (musí být GREEN, 4 nodes)
curl -sk -u elastic:SpotifyELK2025! https://localhost:9200/_cluster/health?pretty

# 3. Počty dokumentů (očekávané: tracks 13119, artists 5271, charts 8000)
curl -sk -u elastic:SpotifyELK2025! "https://localhost:9200/_cat/indices/tracks,artists,charts?v"

# 4. Test fulltext search (musí vrátit 4× Bohemian Rhapsody i s překlepem):
curl -sk -u elastic:SpotifyELK2025! -X POST "https://localhost:9200/tracks/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '{"size":3,"_source":["track_name","popularity"],"query":{"match":{"track_name":{"query":"Bohemain Rapsody","fuzziness":"AUTO"}}}}'
```

**Pokud všech 4 testy projdou → stack je 100% funkční.** Otevři Kibanu na http://localhost:5601 a klikni do **Discover** pro interaktivní vyhledávání.

## Přístupové body

| Služba | URL | Login |
|---|---|---|
| **Kibana** (webové GUI) | http://localhost:5601 | `elastic` / `SpotifyELK2025!` |
| **Elasticsearch API** | https://localhost:9200 | `elastic` / `SpotifyELK2025!` |
| **Elasticvue** (cluster GUI) | http://localhost:8080 | předkonfigurovaný v compose |

## Struktura projektu

```
noSql/
├── README.md                   # Tento soubor
├── Dokumentace.md / .docx      # Plná dokumentace dle šablony
├── schema_architektury.png     # Schéma architektury (draw.io)
├── semestralni_prace_bsqbd.docx  # Formální titulní šablona
│
├── Funkční řešení/             # Vše pro spuštění (3 přílohy zadání: Data/, Dotazy/, Funkční řešení/)
│   ├── docker-compose.yml      # Infrastruktura: 9 služeb, HA setup
│   ├── .env / .env.example     # Hesla, RAM limity, verze
│   ├── init/setup.sh           # Vytváří index templates pro ES
│   ├── logstash/
│   │   ├── pipelines.yml       # 3 oddělené pipelines
│   │   └── pipeline/           # tracks.conf, artists.conf, charts.conf
│   └── kibana_dashboard_export.ndjson  # Volitelně: import do Kibany
│
├── Data/                       # 3 datasety + Python analýza
│   ├── *.csv                   # tracks (15k), artists (5271), charts (8000)
│   ├── analyza.ipynb           # Jupyter analýza dat (Pandas)
│   └── *.png                   # Grafy z analýzy
│
└── Dotazy/
    └── vsechny_dotazy.md       # 30 netriviálních dotazů (5 kategorií)
```

## Zastavení

```bash
docker compose down       # zachová data ve volumes
docker compose down -v    # smaže VŠE (čistý stav)
```

## 🚨 Troubleshooting

| Problém | Příčina | Řešení |
|---|---|---|
| Kontejnery padají s `Exited (137)` | OOM kill — Docker Desktop má méně než 10 GiB RAM | Settings → Resources → Memory → posuň na **12 GiB** → Apply & Restart |
| `master_not_discovered_exception` v curl | Master právě restartuje | Počkej 30 s, případně `docker compose restart es-master` |
| Cluster trvá ve stavu yellow s mnoha unassigned shards | Recovery po startu — repliky se ještě alokují | Počkej 60 s, pak znovu zkontroluj health (mělo by se ustálit na green) |
| Logstash přetěžuje CPU (1000 % +) | 3 paralelní pipelines × 10 workerů | Po dokončení importu: `docker compose stop logstash` (data už jsou v ES) |
| Kibana „kibana server is not ready yet" | Kibana startuje pomalu (~30 s po ES) | Počkej 60 s |
| Stack Monitoring v Kibaně „Access Denied" | Bug ES 8.x role check | Použij Dev Tools `_cat/*` dotazy místo Stack Monitoring |
| Elasticvue (port 8080) prázdná stránka / nedostupná | Browser nedůvěřuje self-signed TLS certu ES | Klikni Open / Otevřít v Elasticvue → přesměruje na https://localhost:9200 → Advanced → Proceed (Chrome) nebo „visit this website" (Safari) → zavři login alert → vrať se na :8080 |
| Elasticvue „400 Bad Request — Cookie Too Large" | Cookies overflow z jiných localhost služeb | Otevři v incognito okně (Chrome ⌘+Shift+N) |
| Port 9200 / 5601 / 8080 obsazen | Předchozí spuštění ELK ještě běží, nebo jiná služba | `docker ps` → najdi konflikt → `docker stop <name>`, případně `docker compose down -v` v jiné složce |

## Detaily

Plný popis architektury, konfigurace, dotazů a případových studií najdete v `Dokumentace.md`.
