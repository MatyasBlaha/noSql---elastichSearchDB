# Dotazy – ELK Stack

30 dotazu, 5 kategorii po 6. Testovano na clusteru ES 8.17.0 (3 uzly, indexy tracks/artists/charts).
Vsechny dotazy spustitelne v Kibana Dev Tools (http://localhost:5601, login: elastic).

---

## A) Prace s daty

### A1 – Hromadny update popularity

Zvysim popularitu o 5 u vsech explicit rockovych skladeb (s limitem na 95, aby nepretekla pres 100).

```json
POST tracks/_update_by_query
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "explicit": true } },
        { "term": { "track_genre": "rock" } },
        { "range": { "popularity": { "lte": 95 } } }
      ]
    }
  },
  "script": {
    "source": "ctx._source.popularity += 5",
    "lang": "painless"
  }
}
```

`_update_by_query` projde dokumenty matchujici query a na kazdy aplikuje Painless skript. Pouzivam `filter` misto `must`, protoze nepotrebuju scoring – jen filtraci. Aktualizovano 43 skladeb.

---

### A2 – Reindex s filtraci a transformaci

Kopiruju jen popularni skladby (pop >= 70) do noveho indexu, kazdemu pridavam pole `popularity_tier`.

```json
POST _reindex
{
  "source": {
    "index": "tracks",
    "query": { "range": { "popularity": { "gte": 70 } } }
  },
  "dest": { "index": "tracks_popular" },
  "script": {
    "source": "ctx._source.popularity_tier = 'high'"
  }
}
```

`_reindex` cte ze zdroje, filtruje, aplikuje skript a zapisuje do cile. Originalni index zustava beze zmeny. Vytvoreno 1382 dokumentu.

---

### A3 – Multi-get z vice indexu

Nactu konkretni skladby a interpreta z ruznych indexu v jednom requestu.

```json
POST _mget
{
  "docs": [
    { "_index": "tracks", "_id": "5MAK1nd8R6PWnle1Q1WJvh", "_source": ["track_name", "artists", "popularity"] },
    { "_index": "tracks", "_id": "2tznHmp70DxMyr2XhWLOW0", "_source": ["track_name", "artists", "popularity"] },
    { "_index": "artists", "_id": "7frYUe4C7A42uZqCzD34Y4", "_source": ["name", "followers", "popularity"] }
  ]
}
```

Misto 3 GET requestu jeden `_mget` – setri network roundtripy. Vraci "I See Red" (pop 76), "Cigarette Daydreams" (pop 79) a interpreta Sultaan (53636 followers).

---

### A4 – Bulk operace

Vlozim 2 testovaci dokumenty, prvnimu zvysim popularitu na 100 a druhy smazu – vsechno v jednom POST.

```json
POST _bulk
{"index": {"_index": "tracks_popular", "_id": "custom_1"}}
{"track_name": "Test Song Alpha", "artists": ["Test Artist"], "popularity": 99, "track_genre": "test", "danceability": 0.8}
{"index": {"_index": "tracks_popular", "_id": "custom_2"}}
{"track_name": "Test Song Beta", "artists": ["Test Artist 2"], "popularity": 50, "track_genre": "test", "danceability": 0.3}
{"update": {"_index": "tracks_popular", "_id": "custom_1"}}
{"doc": {"popularity": 100}, "doc_as_upsert": true}
{"delete": {"_index": "tracks_popular", "_id": "custom_2"}}
```

NDJSON format – strida se action + body. Podporuje `index`, `create`, `update`, `delete`. 4 operace bez chyb.

---

### A5 – Skriptovany update – prepocet a novy field

U blues skladeb delsich nez 5 minut prepocitam delku na minuty a oznacim flagrem.

```json
POST tracks/_update_by_query
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "track_genre": "blues" } },
        { "range": { "duration_ms": { "gte": 300000 } } }
      ]
    }
  },
  "script": {
    "source": "ctx._source.duration_min = Math.round(ctx._source.duration_ms / 60000.0 * 100) / 100.0; ctx._source.is_long = true",
    "lang": "painless"
  }
}
```

Painless pristupuje k polim pres `ctx._source` a muze vytvaret nova pole. ES automaticky vytvori mapping pro `duration_min` (double) a `is_long` (boolean). Aktualizovano 94 skladeb.

---

### A6 – Delete by query

Smazu testovaci data se zanrem "test" z indexu `tracks_popular`.

```json
POST tracks_popular/_delete_by_query
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "track_genre": "test" } }
      ]
    }
  }
}
```

Na rozdil od `DELETE /tracks_popular` (smaze cely index), tohle maze jen dokumenty matchujici query. Smazano 1 doc.

---

## B) Agregacni funkce

### B1 – Prumer podle zanru + celkovy prumer (pipeline)

Pro kazdy zanr prumerna popularita a tanecnost, plus celkovy prumer pres vsechny zanry.

```json
POST tracks/_search
{
  "size": 0,
  "aggs": {
    "zanry": {
      "terms": { "field": "track_genre", "size": 15 },
      "aggs": {
        "prumerna_popularita": { "avg": { "field": "popularity" } },
        "prumerna_tanecnost": { "avg": { "field": "danceability" } }
      }
    },
    "celkovy_prumer_popularity": {
      "avg_bucket": { "buckets_path": "zanry>prumerna_popularita" }
    }
  }
}
```

`terms` rozdeli skladby do bucketu per zanr, vnorene `avg` pocitaji metriky v kazdem bucketu. `avg_bucket` je pipeline agregace – pocita prumer z vystupu jine agregace (ne primo z dokumentu). Vysledek: pop avg 50.0, electronic 44.3, classical 13.3.

---

### B2 – Range buckety popularity s vnorenym filtrem

Skladby rozdelene do 5 pasem popularity, v kazdem pocitam energii a pocet explicit.

```json
POST tracks/_search
{
  "size": 0,
  "aggs": {
    "popularita_pasma": {
      "range": {
        "field": "popularity",
        "ranges": [
          { "key": "nezname (0-10)", "to": 10 },
          { "key": "nizka (10-30)", "from": 10, "to": 30 },
          { "key": "stredni (30-60)", "from": 30, "to": 60 },
          { "key": "vysoka (60-80)", "from": 60, "to": 80 },
          { "key": "hit (80+)", "from": 80 }
        ]
      },
      "aggs": {
        "prumerna_energie": { "avg": { "field": "energy" } },
        "prumerna_tanecnost": { "avg": { "field": "danceability" } },
        "pocet_explicit": { "filter": { "term": { "explicit": true } } }
      }
    }
  }
}
```

Vnorena `filter` agregace uvnitr range bucketu pocita kolik dokumentu v pasmu splnuje dalsi podminku. Pasmo "hit 80+": 403 skladeb, 109 explicit (27%) – cim popularnejsi, tim vic explicit obsahu.

---

### B3 – Casovy vyvoj streamu + kumulativni soucet

Vyvoj streamu po kvartalech s narstajicim souctem.

```json
POST charts/_search
{
  "size": 0,
  "aggs": {
    "po_kvartalech": {
      "date_histogram": {
        "field": "date",
        "calendar_interval": "quarter"
      },
      "aggs": {
        "celkem_streamu": { "sum": { "field": "streams" } },
        "prumer_streamu": { "avg": { "field": "streams" } },
        "max_streamu": { "max": { "field": "streams" } },
        "kumulativni": { "cumulative_sum": { "buckets_path": "celkem_streamu" } }
      }
    }
  }
}
```

`date_histogram` rozdeluje casovou osu na intervaly. `cumulative_sum` pridava ke kazdemu bucketu soucet vsech predchozich – ukazuje celkovy trend. Q1 2017: max stream 7.6M, Q1 2018: max 7.8M.

---

### B4 – Extended stats + percentily + max_bucket

Rozsirene statistiky energie a percentily tempa per zanr, plus ktery zanr ma nejvyssi max popularitu.

```json
POST tracks/_search
{
  "size": 0,
  "aggs": {
    "zanry": {
      "terms": { "field": "track_genre", "size": 15 },
      "aggs": {
        "max_popularita": { "max": { "field": "popularity" } },
        "stat_energie": { "extended_stats": { "field": "energy" } },
        "percentily_tempa": { "percentiles": { "field": "tempo", "percents": [25, 50, 75] } }
      }
    },
    "zanr_s_nejvyssi_max_popularitou": {
      "max_bucket": { "buckets_path": "zanry>max_popularita" }
    }
  }
}
```

`extended_stats` vraci navic smerodatnou odchylku a varianci. `percentiles` pocita kvantily (25. percentil = 25% skladeb ma tempo nizsi). `max_bucket` projde buckety a vrati ten s nejvyssi hodnotou. Vysledek: pop a hip-hop maji max 100.

---

### B5 – Porovnani explicit vs non-explicit

Dve paralelni filter agregace – porovnam prumernou popularitu, tanecnost a top zanry.

```json
POST tracks/_search
{
  "size": 0,
  "aggs": {
    "explicit_skladby": {
      "filter": { "term": { "explicit": true } },
      "aggs": {
        "prumerna_popularita": { "avg": { "field": "popularity" } },
        "prumerna_tanecnost": { "avg": { "field": "danceability" } },
        "prumerna_energie": { "avg": { "field": "energy" } },
        "top_zanry": { "terms": { "field": "track_genre", "size": 5 } }
      }
    },
    "neexplicit_skladby": {
      "filter": { "term": { "explicit": false } },
      "aggs": {
        "prumerna_popularita": { "avg": { "field": "popularity" } },
        "prumerna_tanecnost": { "avg": { "field": "danceability" } },
        "prumerna_energie": { "avg": { "field": "energy" } },
        "top_zanry": { "terms": { "field": "track_genre", "size": 5 } }
      }
    }
  }
}
```

Explicit (1056 skladeb): avg pop 35.8, tanecnost 0.70, top zanr hip-hop. Non-explicit (12063): avg pop 30.7, tanecnost 0.58, top zanr jazz. Explicit skladby jsou popularnejsi a tanecnejsi.

---

### B6 – Multi-terms + cardinality

Buckety podle kombinace region + typ zebricku, s poctem unikatnich skladeb.

```json
POST charts/_search
{
  "size": 0,
  "aggs": {
    "region_chart": {
      "multi_terms": {
        "terms": [
          { "field": "region" },
          { "field": "chart" }
        ],
        "size": 12
      },
      "aggs": {
        "prumer_streamu": { "avg": { "field": "streams" } },
        "celkem_streamu": { "sum": { "field": "streams" } },
        "unikatni_skladby": { "cardinality": { "field": "title.keyword" } }
      }
    }
  }
}
```

`multi_terms` = GROUP BY pres vice poli. `cardinality` odhaduje pocet unikatnich hodnot (HyperLogLog). France top200: 1406 zaznamu, 517 unikatnich skladeb. Czech Republic top200: 1270 zaznamu, 421 skladeb.

---

## C) Fulltextove vyhledavani

### C1 – Slozeny bool query

Tanecni a energicke skladby (>= 0.8), ne-explicit, zanr pop/dance/electronic, popularita min 70.

```json
POST tracks/_search
{
  "size": 3,
  "_source": ["track_name", "artists", "popularity", "danceability", "energy", "track_genre"],
  "query": {
    "bool": {
      "must": [
        { "range": { "danceability": { "gte": 0.8 } } },
        { "range": { "energy": { "gte": 0.8 } } }
      ],
      "should": [
        { "range": { "popularity": { "gte": 70 } } }
      ],
      "must_not": [
        { "term": { "explicit": true } }
      ],
      "filter": [
        { "terms": { "track_genre": ["pop", "dance", "electronic"] } }
      ],
      "minimum_should_match": 1
    }
  },
  "sort": [{ "popularity": "desc" }]
}
```

Pouzivam vsechny 4 typy klauzuli: `must` (povinne, pocita skore), `should` s `minimum_should_match: 1` (alespon 1 musi platit), `must_not` (vylouceni), `filter` (povinne, ale nescoruje – cachuje se). Vraci "Calm Down" (Rema + Selena Gomez, pop 92), "Bad Habits" (Ed Sheeran, pop 88).

---

### C2 – Multi-match s boostingem + highlight

Hledani "love heart" pres nazev skladby (3x boost), album (2x) a interpreta.

```json
POST tracks/_search
{
  "size": 3,
  "_source": ["track_name", "artists", "album_name", "popularity"],
  "query": {
    "multi_match": {
      "query": "love heart",
      "fields": ["track_name^3", "album_name^2", "artists"],
      "type": "best_fields",
      "fuzziness": "AUTO"
    }
  },
  "highlight": {
    "pre_tags": ["**"],
    "post_tags": ["**"],
    "fields": {
      "track_name": {},
      "album_name": {},
      "artists": {}
    }
  }
}
```

`^3` je boost – match v nazvu sklaby ma 3x vyssi vahu. `best_fields` bere skore z pole s nejlepsim matchem. Highlight vraci fragmenty se zvyraznenymi shody: `**Heart** Attack`.

---

### C3 – Fuzzy hledani s preklepem

Umyslne spatne napsane "Bohemain Rapsody" – overuju ze ES najde spravny vysledek.

```json
POST tracks/_search
{
  "size": 3,
  "_source": ["track_name", "artists", "popularity"],
  "query": {
    "match": {
      "track_name": {
        "query": "Bohemain Rapsody",
        "fuzziness": "AUTO"
      }
    }
  }
}
```

`fuzziness: AUTO` pocita Levenshteinovu vzdalenost – pocet editaci nutnych k oprave. "Bohemain"→"Bohemian" (1 edit), "Rapsody"→"Rhapsody" (1 edit). Nalezena "Bohemian Rhapsody" od Queen (pop 75 a 82).

---

### C4 – Analyze API – kroky zpracovani textu

Ukazka jak analyzator krok za krokem zpracuje text.

```json
POST _analyze
{
  "tokenizer": "standard",
  "filter": ["lowercase", "stop", "snowball"],
  "text": "The Bohemian Rhapsody is Playing Loudly"
}
```

Pipeline: tokenizer rozdelil na 6 tokenu → lowercase → stop odstranil "the" a "is" → snowball (stemmer) zredukoval "Playing"→"play", "Loudly"→"loud", "Rhapsody"→"rhapsodi". Vysledek: ["bohemian", "rhapsodi", "play", "loud"]. Proto hledani "plays" najde i "playing" – oba se stemnou na "play".

---

### C5 – Function score

Hledam "fire" v nazvu, ale popularnejsi a rockove skladby chci vyse.

```json
POST tracks/_search
{
  "size": 5,
  "_source": ["track_name", "artists", "popularity", "track_genre"],
  "query": {
    "function_score": {
      "query": { "match": { "track_name": "fire" } },
      "functions": [
        {
          "field_value_factor": {
            "field": "popularity",
            "factor": 1.5,
            "modifier": "log1p",
            "missing": 1
          }
        },
        {
          "filter": { "term": { "track_genre": "rock" } },
          "weight": 2
        }
      ],
      "boost_mode": "multiply",
      "score_mode": "sum"
    }
  }
}
```

`field_value_factor` pouziva hodnotu popularity jako faktor skore (s log modifikaci aby rozdily nebyly extremni). Druha funkce pridava weight 2 rockovym skladbam. Rockove "fire" skladby vyskoci nahoru.

---

### C6 – Match phrase prefix (autocomplete)

Simulace autocomplete – uzivatel napsal "i see", system nabizi skladby.

```json
POST tracks/_search
{
  "size": 5,
  "_source": ["track_name", "artists", "popularity"],
  "query": {
    "bool": {
      "must": {
        "match_phrase_prefix": {
          "track_name": {
            "query": "i see",
            "max_expansions": 20
          }
        }
      },
      "should": [
        { "range": { "popularity": { "gte": 50, "boost": 3 } } }
      ]
    }
  }
}
```

`match_phrase_prefix` matchuje frazi a posledni term expanduje jako prefix – "i see" najde "I See Red", "I See a Boat...". Should s boostem zvyhodnil popularnejsi skladby. Vraci "I See Red" (pop 76), "When I See You Smile" (pop 65).

---

## D) Indexy a konfigurace

### D1 – Vlastni analyzator

Spotify data casto obsahuji "Remastered", "feat." v nazvech. Vytvorim analyzator ktery tohle filtruje.

```json
PUT test_analyzer
{
  "settings": {
    "analysis": {
      "analyzer": {
        "spotify_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "asciifolding", "spotify_stop", "spotify_stemmer"]
        }
      },
      "filter": {
        "spotify_stop": {
          "type": "stop",
          "stopwords": ["feat", "ft", "remix", "remastered", "version", "edit"]
        },
        "spotify_stemmer": { "type": "stemmer", "language": "english" }
      }
    }
  }
}
```

Test: `POST test_analyzer/_analyze {"analyzer": "spotify_analyzer", "text": "Bohemian Rhapsody - Remastered 2011 (feat. Someone)"}`
Vysledek: ["bohemian", "rhapsodi", "2011", "someon"] – "Remastered" a "feat" odstranen, zbytek stemovan.

---

### D2 – Aliasy

Filtrovany alias pro popularni skladby + multi-index alias spojujici tracks a artists.

```json
POST _aliases
{
  "actions": [
    { "add": { "index": "tracks", "alias": "popular_tracks", "filter": { "range": { "popularity": { "gte": 70 } } } } },
    { "add": { "index": "artists", "alias": "all_music", "is_write_index": false } },
    { "add": { "index": "tracks", "alias": "all_music", "is_write_index": false } }
  ]
}
```

`GET popular_tracks/_count` → 1382 (automaticky filtrovano). `GET all_music/_count` → 18390 (tracks + artists dohromady). Klient nepozna ze pracuje s filtrem nebo vice indexy.

---

### D3 – Zmena nastaveni indexu

Zmena refresh intervalu – urcuje jak casto se nova data stanou prohledatelnymi.

```json
GET tracks/_settings

PUT tracks/_settings
{ "index": { "refresh_interval": "5s" } }

PUT tracks/_settings
{ "index": { "refresh_interval": "1s" } }
```

`number_of_shards` je immutable po vytvoreni, ale `refresh_interval` a `number_of_replicas` se daji menit dynamicky. Pri hromadnem importu se refresh typicky zvysuje pro vykon.

---

### D4 – Runtime fields

Vypoctena pole za behu dotazu – nic se neuklada do indexu, neni treba reindexovat.

```json
POST tracks/_search
{
  "size": 3,
  "runtime_mappings": {
    "duration_minutes": {
      "type": "double",
      "script": "emit(doc['duration_ms'].value / 60000.0)"
    },
    "energy_category": {
      "type": "keyword",
      "script": "if (doc['energy'].value > 0.8) emit('high'); else if (doc['energy'].value > 0.5) emit('medium'); else emit('low')"
    }
  },
  "fields": ["duration_minutes", "energy_category"],
  "_source": ["track_name", "duration_ms", "energy"],
  "query": { "range": { "popularity": { "gte": 90 } } },
  "sort": [{ "popularity": "desc" }]
}
```

"Unholy" (pop 100): duration_minutes = 2.62, energy_category = "low". Runtime fields se daji pouzit i pro filtrovani a agregace.

---

### D5 – Inspekce mappingu

Overeni ze mapping odpovida definici v index template.

```json
GET tracks/_mapping/field/track_name,popularity,explicit,track_genre
```

Vysledek: `track_name` = text + keyword, `popularity` = integer, `explicit` = boolean, `track_genre` = keyword. Odpovida explicitnimu mappingu v template `spotify-tracks`.

---

### D6 – Index templates

Zobrazeni vsech spotify templates.

```json
GET _index_template/spotify-*
```

3 templates: `spotify-tracks`, `spotify-artists`, `spotify-charts`. Kazdy: 3 shardy, 1 replika, explicitni mapping. Priorita 100 = prednost pred default templates. Aplikuji se automaticky pri vytvoreni indexu.

---

## E) Cluster, distribuce a vypadek

### E1 – Info o uzlech

```
GET _cat/nodes?v&h=name,role,heap.percent,ram.percent,cpu,disk.used_percent,node.role,master
```

3 uzly: `es-master` (role m, master *), `es-data-1` (di – data+ingest), `es-data-2` (di). Master nema data, ridi cluster state a alokaci shardu.

---

### E2 – Distribuce shardu

```
GET _cat/shards/tracks,artists,charts?v&s=index,shard
```

Kazdy index ma 3 primary + 3 replica = 6 shardu. Primary a jeho replica jsou vzdy na ruznych uzlech. Celkem 18 shardu, 9 na kazdem datovem uzlu. Master nema zadne (nema data roli).

---

### E3 – SQL dotaz

```json
POST _sql?format=txt
{
  "query": "SELECT track_genre, COUNT(*) as pocet, ROUND(AVG(popularity),1) as avg_pop, ROUND(AVG(danceability),3) as avg_dance, ROUND(AVG(energy),3) as avg_energy FROM tracks GROUP BY track_genre ORDER BY COUNT(*) DESC LIMIT 10"
}
```

ES SQL internee prevadi na Query DSL agregace. Vysledek: reggae (1000, avg pop 20.6), pop (937, avg pop 50.0), classical (916, avg pop 13.3).

---

### E4 – Simulace vypadku uzlu

```bash
# 1. Pred vypadkem
GET _cluster/health
# → green, 3 uzly, 82 shardu

# 2. Zastavim datovy uzel
docker compose stop es-data-2

# 3. Cluster – yellow
GET _cluster/health
# → yellow, 2 uzly, 41 active, 11 unassigned (repliky z padleho uzlu)

# 4. Data stale dostupna
GET tracks/_count   → 13119
GET artists/_count  → 5271

# 5. Dotazy fungujou
GET tracks/_search {"query": {"match": {"track_name": "Bohemian Rhapsody"}}}
# → 3 vysledky

# 6. Obnovim uzel
docker start nosql-es-data-2-1

# 7. Cluster → green (ES automaticky synchronizuje repliky)
GET _cluster/health → green, 3 uzly, 82 shardu
```

Yellow = primary shardy ok (data dostupna), repliky z padleho uzlu nejsou alokovane. Dotazy funguji protoze kazdy shard ma alespon 1 exemplar na zbyvajicim uzlu. Po restartu ES automaticky synchronizuje repliky a vraci se na green.

Scenare: padne 1 datovy uzel → yellow, data ok. Padnou oba datove uzly → red, data nedostupna. Padne master → datove uzly zvoli noveho (master election).

---

### E5 – Allocation explain

Proc je shard na konkretnim uzlu.

```json
POST _cluster/allocation/explain
{
  "index": "tracks",
  "shard": 0,
  "primary": true
}
```

Shard 0 je na es-data-1, `can_remain: yes`, `can_rebalance_to_other: no` – uz je vyvazene. Uzitecne kdyz shardy zustanou UNASSIGNED – ES rekne presne proc.

---

### E6 – Cluster stats

```
GET _cluster/stats
```

Celkovy prehled: 28217 dokumentu, 32 MB, 82 shardu (41P + 41R), 3 uzly, ES 8.17.0. Jedno API volani pro kompletni stav.

---

## Prehled

| Kat | # | Dotaz | API |
|-----|---|-------|-----|
| A | 1 | Hromadny update popularity | _update_by_query + Painless |
| A | 2 | Reindex s filtraci | _reindex + query + script |
| A | 3 | Multi-get | _mget |
| A | 4 | Bulk operace | _bulk |
| A | 5 | Skriptovany update | _update_by_query + Math |
| A | 6 | Delete by query | _delete_by_query |
| B | 1 | Prumer per zanr + pipeline | terms + avg + avg_bucket |
| B | 2 | Range buckety + filter | range + avg + filter |
| B | 3 | Casovy vyvoj | date_histogram + cumulative_sum |
| B | 4 | Extended stats + percentily | extended_stats + percentiles + max_bucket |
| B | 5 | Porovnani skupin | 2x filter + avg + terms |
| B | 6 | Multi-terms | multi_terms + cardinality |
| C | 1 | Slozeny bool | must/should/must_not/filter |
| C | 2 | Multi-match + highlight | multi_match + boost + highlight |
| C | 3 | Fuzzy | fuzziness AUTO |
| C | 4 | Analyze pipeline | _analyze |
| C | 5 | Function score | field_value_factor + weight |
| C | 6 | Autocomplete | match_phrase_prefix |
| D | 1 | Custom analyzer | stop words + stemmer |
| D | 2 | Aliasy | filtrovany + multi-index |
| D | 3 | Index settings | refresh_interval |
| D | 4 | Runtime fields | runtime_mappings + Painless |
| D | 5 | Inspekce mappingu | _mapping/field |
| D | 6 | Index templates | _index_template |
| E | 1 | Info o uzlech | _cat/nodes |
| E | 2 | Distribuce shardu | _cat/shards |
| E | 3 | SQL dotaz | _sql |
| E | 4 | Vypadek uzlu | docker stop/start + recovery |
| E | 5 | Allocation explain | _cluster/allocation/explain |
| E | 6 | Cluster stats | _cluster/stats |
