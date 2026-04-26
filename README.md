# Nasazení The Elastic Stack (ELK) pro analýzu Spotify dat

Semestrální projekt do předmětu **BSQBD - NoSQL databáze** (UPCE FEI, 3. ročník LS 2026).

**Autor:** Matyáš Bláha

## O čem projekt je

Plně automatizované nasazení ELK stacku (Elasticsearch 8.17 + Logstash 8.17 + Kibana 8.17) v Dockeru pro analýzu hudebních dat ze Spotify. Cluster běží jako **HA setup se 4 master-eligible uzly** (1 dedikovaný master + 3 data uzly s rolí master,data,ingest), s replikačním faktorem 3 a TLS zabezpečením všude.

**Datové sady (Kaggle):** ~28 tisíc dokumentů ve 3 indexech — `tracks` (15 000 skladeb), `artists` (5 271 interpretů), `charts` (8 000 chart pozic).

## Předpoklady

- **Docker Desktop** s minimálně **10 GiB RAM** (doporučeno 12 GiB) — Settings → Resources → Memory
- Volné porty: `9200` (ES), `5601` (Kibana), `8080` (Elasticvue)

## Spuštění

```bash
# 1. Vstup do složky s docker-compose
cd "Funkční řešení"

# 2. Zkopíruj vzor konfigurace
cp .env.example .env

# 3. (Volitelné) Uprav hesla v .env
# 4. Spusť celý stack
docker compose up -d
```

Stack startuje ~3 minuty — Setup vygeneruje TLS certifikáty, ES uzly se spojí do clusteru, init kontejner vytvoří index templates, Logstash naimportuje 3 CSV ze složky `../Data/`.

## Ověření, že vše běží

```bash
# Stav kontejnerů
docker compose ps

# Cluster health (musí být GREEN, 4 nodes)
curl -sk -u elastic:SpotifyELK2025! https://localhost:9200/_cluster/health?pretty

# Počty dokumentů
curl -sk -u elastic:SpotifyELK2025! "https://localhost:9200/_cat/indices/tracks,artists,charts?v"
```

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

## Detaily

Plný popis architektury, konfigurace, dotazů a případových studií najdete v `Dokumentace.md`.
