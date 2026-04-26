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

### A3 – Obohaceni charts o streaming tier

Kazdemu chart zaznamu pridam kategorii podle poctu streamu a inverzni rank pro scoring.

```json
POST charts/_update_by_query
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "chart": "top200" } },
        { "exists": { "field": "streams" } }
      ]
    }
  },
  "script": {
    "source": "def s = ctx._source.streams; if (s > 1000000) ctx._source.stream_tier = 'viral'; else if (s > 100000) ctx._source.stream_tier = 'hit'; else ctx._source.stream_tier = 'niche'; ctx._source.rank_score = 201 - ctx._source.rank;",
    "lang": "painless"
  }
}
```

`update_by_query` s bool filtrem (jen top200 se streamy) + Painless s podminkami vytvori `stream_tier` (kategorizace) a `rank_score` (inverzni rank – cim vyssi pozice, tim vyssi skore). Aktualizovano ~5800 zaznamu.

---

### A4 – Klasifikace interpretu podle velikosti

Kazdemu interpretovi pridam tier podle followers a spocitam pocet zanru.

```json
POST artists/_update_by_query
{
  "query": {
    "bool": {
      "filter": [
        { "range": { "followers": { "gte": 0 } } }
      ]
    }
  },
  "script": {
    "source": "def f = ctx._source.followers; if (f >= 1000000) ctx._source.artist_tier = 'mega'; else if (f >= 100000) ctx._source.artist_tier = 'major'; else if (f >= 10000) ctx._source.artist_tier = 'mid'; else ctx._source.artist_tier = 'indie'; ctx._source.genres_count = (ctx._source.containsKey('genres') && ctx._source.genres instanceof List) ? ctx._source.genres.size() : 0;",
    "lang": "painless"
  }
}
```

Painless pristupuje k `followers` a pres podminky priradi tier. Pro `genres_count` kontroluje zda pole existuje a je List, pak vola `.size()`. Aktualizovano 5271 interpretu. Vysledek: mega (~50), major (~300), mid (~1500), indie (~3400).

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

### A6 – Cross-index vyhledavani pres tracks a artists

Hledam "love" soucasne ve skladbach i interpretech – jeden dotaz pres 2 indexy.

```json
POST tracks,artists/_search
{
  "size": 5,
  "_source": ["track_name", "name", "popularity", "followers", "track_genre", "genres"],
  "query": {
    "bool": {
      "must": [
        { "multi_match": { "query": "love", "fields": ["track_name", "name"], "type": "best_fields" } }
      ],
      "should": [
        { "range": { "popularity": { "gte": 60, "boost": 2 } } },
        { "range": { "followers": { "gte": 100000, "boost": 1.5 } } }
      ]
    }
  }
}
```

`POST tracks,artists/_search` prohleda oba indexy najednou. `multi_match` hleda "love" v polich obou indexu (`track_name` v tracks, `name` v artists). `should` boostuje popularni skladby i velke interprety. Vysledek micha oba typy dokumentu – skladby s "Love" v nazvu i interprety jako "Lovejoy".

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

### C3 – Fuzzy hledani + filtrace + agregace vysledku

Hledam s preklepem "Bohemain Rapsody", filtruji jen popularni, a agregatuji zanry nalezenych vysledku.

```json
POST tracks/_search
{
  "size": 3,
  "_source": ["track_name", "artists", "popularity", "track_genre"],
  "query": {
    "bool": {
      "must": {
        "match": { "track_name": { "query": "Bohemain Rapsody", "fuzziness": "AUTO" } }
      },
      "filter": [
        { "range": { "popularity": { "gte": 20 } } }
      ]
    }
  },
  "aggs": {
    "zanry_vysledku": {
      "terms": { "field": "track_genre", "size": 5 }
    },
    "avg_popularita": { "avg": { "field": "popularity" } }
  }
}
```

Kombinuje fuzzy match (Levenshtein – "Bohemain"→"Bohemian", 1 edit) + bool filter (range popularity) + dve agregace nad vysledky. `fuzziness: AUTO` = 0 editu pro 1-2 znaky, 1 pro 3-5, 2 pro 6+. Najde 4 verze "Bohemian Rhapsody" (různé re-releases), agregace zanrů ukazuje rock, avg popularita: 63.25.

---

### C4 – Fraze s proximity (slop) + bool boost + highlight

Hledam frazi "can't stop" s toleranci vzdalenosti slov, popularnejsi vyse.

```json
POST tracks/_search
{
  "size": 5,
  "_source": ["track_name", "artists", "popularity"],
  "query": {
    "bool": {
      "must": {
        "match_phrase": {
          "track_name": {
            "query": "can't stop",
            "slop": 2
          }
        }
      },
      "should": [
        { "range": { "popularity": { "gte": 60, "boost": 3 } } }
      ]
    }
  },
  "highlight": {
    "fields": { "track_name": {} }
  }
}
```

`match_phrase` vyzaduje slova ve spravnem poradi. `slop: 2` povoli max 2 slova mezi nimi – "Can't Stop the Feeling" (slop=1) i "Can't Stop Loving You" (slop=2) projdou. `should` boost zvyhodní popularnejsi vysledky. Highlight ukazuje kde se fraze nachazi: `<em>Can't</em> <em>Stop</em> the Feeling`.

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

### D3 – Experiment s poctem replik a dopad na cluster

Zvysim repliky ze 2 na 3 a ukazem, ze cluster nema dost uzlu pro jejich alokaci.

```json
// 1. Vychozi stav (replicas=2)
GET _cluster/health/tracks
// → green, active_shards: 9 (3P + 6R, 3 kopie per shard na 3 uzlech)

// 2. Zvyseni replik na 3
PUT tracks/_settings
{ "index": { "number_of_replicas": 3 } }

// 3. Kontrola distribuce
GET _cat/shards/tracks?v&s=shard,prirep
// → 3 nove repliky se statusem UNASSIGNED
// (pro 4. kopii by byl potreba 4. datovy uzel – primary a repliky
//  musi byt na ruznych uzlech)

GET _cluster/health/tracks
// → yellow, unassigned_shards: 3

// 4. Navrat na 2 repliky
PUT tracks/_settings
{ "index": { "number_of_replicas": 2 } }

GET _cluster/health/tracks
// → green, unassigned_shards: 0
```

Demonstrace limitu topologie: se **3 datovymi uzly** lze mit max **2 repliky** (1 primary + 2 replica = 3 kopie na 3 ruznych uzlech). Pro `number_of_replicas >= 3` by byl treba 4+ datovy uzel. `number_of_replicas` je dynamicky parametr (na rozdil od `number_of_shards` ktery je immutable).

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

### D5 – Persistent runtime field v mappingu + agregace

Pridam trvale runtime pole `hit_potential` (kombinace popularity + danceability + energy) do mappingu.

```json
PUT tracks/_mapping
{
  "runtime": {
    "hit_potential": {
      "type": "double",
      "script": "emit(doc['popularity'].value * 0.4 + doc['danceability'].value * 100 * 0.3 + doc['energy'].value * 100 * 0.3)"
    }
  }
}

POST tracks/_search
{
  "size": 5,
  "fields": ["hit_potential"],
  "_source": ["track_name", "artists", "popularity", "danceability", "energy"],
  "sort": [{ "hit_potential": "desc" }],
  "aggs": {
    "hit_potential_per_genre": {
      "terms": { "field": "track_genre", "size": 5 },
      "aggs": {
        "avg_hit": { "avg": { "field": "hit_potential" } }
      }
    }
  }
}
```

Na rozdil od D4 (per-query `runtime_mappings`) se runtime field v `_mapping` uklada trvale – dostupny pro vsechny budouci dotazy bez opetovne definice. Kombinuje 3 metriky do jednoho skore. Sort + vnorena agregace per zanr. Top zanry dle hit_potential: electronic ~58.2, disco ~56.0, reggae ~52.4, rock ~44.3, jazz ~31.4 (electronic má vysokou energii i danceability, proto skóre dominuje).

---

### D6 – Profilovani dotazu (execution plan)

Pomoci `profile: true` zobrazim jak ES internee vykonava dotaz – na kterych shardech, jake operace, kolik casu.

```json
POST tracks/_search
{
  "profile": true,
  "size": 3,
  "_source": ["track_name", "popularity"],
  "query": {
    "bool": {
      "must": [
        { "match": { "track_name": "love" } }
      ],
      "filter": [
        { "term": { "track_genre": "pop" } },
        { "range": { "popularity": { "gte": 50 } } }
      ]
    }
  },
  "aggs": {
    "avg_danceability": { "avg": { "field": "danceability" } }
  }
}
```

Response obsahuje `profile` sekci s detailnim breakdown: 3 shardy (shard 0, 1, 2), kazdy s BooleanQuery → TermQuery("love") + TermQuery("pop") + IndexOrDocValuesQuery(popularity ≥ 50). Viditelne casy per shard a per operace. Uzitecne pro optimalizaci pomalych dotazu – ukazuje kde ES travi nejvic casu.

---

## E) Cluster, distribuce a vypadek

### E1 – Multi-search pres vsechny 3 indexy

Jeden HTTP request se 3 nezavislymi analytickymi dotazy – po jednom na kazdy dataset.

```json
POST _msearch
{"index": "tracks"}
{"size": 0, "query": {"bool": {"filter": [{"range": {"popularity": {"gte": 50}}}]}}, "aggs": {"top_genres": {"terms": {"field": "track_genre", "size": 5}}, "avg_dance": {"avg": {"field": "danceability"}}}}
{"index": "artists"}
{"size": 0, "query": {"bool": {"filter": [{"range": {"followers": {"gte": 100000}}}]}}, "aggs": {"top_genres": {"terms": {"field": "genres", "size": 5}}, "avg_pop": {"avg": {"field": "popularity"}}}}
{"index": "charts"}
{"size": 0, "query": {"bool": {"filter": [{"term": {"chart": "top200"}}, {"range": {"rank": {"lte": 10}}}]}}, "aggs": {"per_region": {"terms": {"field": "region"}}, "avg_streams": {"avg": {"field": "streams"}}}}
```

`_msearch` posle 3 dotazy v jednom requestu (NDJSON – stridaji se header a body). Kazdy cili jiny index s vlastnim filtrem a agregacemi. Vysledek: popularni tracks = top zanry pop/hip-hop, avg dance 0.67; velci artists = top zanry rock/pop; top10 charts = prumer ~2.1M streamu per region. Setri network roundtripy.

---

### E2 – Shard preference – vliv distribuce na vysledky

Porovnani vysledku pri dotazu na konkretni shard vs. vsechny shardy.

```json
// 1. Dotaz na vsechny shardy (default)
POST tracks/_search
{
  "size": 0,
  "query": { "bool": { "filter": { "term": { "track_genre": "rock" } } } },
  "aggs": {
    "count": { "value_count": { "field": "track_id" } },
    "avg_pop": { "avg": { "field": "popularity" } }
  }
}
// → 1000 docs, avg pop ~21

// 2. Dotaz jen na shard 0
POST tracks/_search?preference=_shards:0
{
  "size": 0,
  "query": { "bool": { "filter": { "term": { "track_genre": "rock" } } } },
  "aggs": {
    "count": { "value_count": { "field": "track_id" } },
    "avg_pop": { "avg": { "field": "popularity" } }
  }
}
// → ~330 docs (1/3), avg pop ~20.5
```

`preference=_shards:0` smeruje dotaz jen na shard 0. Dokumenty se do shardu rozdeluji hashem `_id` → kazdy shard drzi ~1/3 rockovych skladeb. Avg popularity se mirne lisi (statisticky rozptyl na mensim vzorku). Ukazuje ze data NEJSOU na jednom miste, ale rovnomerne distribuovana.

---

### E3 – SQL dotaz s CASE, HAVING a prekladem do DSL

Netrivialni SQL s podminenou agregaci (CASE WHEN), filtrovanim pres HAVING a nahledem na internal preklad do Query DSL.

```json
// 1. Samotny dotaz – percent explicit skladeb per zanr, jen zanry s >500 skladbami a avg pop >30
POST _sql?format=txt
{
  "query": """
    SELECT
      track_genre,
      COUNT(*)                                                       AS pocet,
      ROUND(AVG(popularity), 1)                                      AS avg_pop,
      ROUND(MIN(popularity), 1)                                      AS min_pop,
      ROUND(MAX(popularity), 1)                                      AS max_pop,
      SUM(CASE WHEN explicit = true THEN 1 ELSE 0 END)               AS explicit_count,
      ROUND(100.0 * SUM(CASE WHEN explicit = true THEN 1 ELSE 0 END)
            / COUNT(*), 1)                                           AS explicit_pct
    FROM tracks
    GROUP BY track_genre
    HAVING COUNT(*) > 500 AND AVG(popularity) > 30
    ORDER BY COUNT(*) DESC
    LIMIT 10
  """
}

// 2. Preklad SQL -> DSL (ES ukaze, jak internee prepisuje dotaz)
POST _sql/translate
{
  "query": "SELECT track_genre, COUNT(*), AVG(popularity) FROM tracks GROUP BY track_genre HAVING COUNT(*) > 500"
}
// → vrati Query DSL s bucket_selector pipeline agregaci pro HAVING
```

`CASE WHEN` umoznuje podminenou agregaci (ekvivalent `filter` agregace v DSL). `HAVING` je filtr nad vysledkem agregace – internee se prevadi na `bucket_selector` pipeline agregaci. `ORDER BY COUNT(*) DESC` razeni dle poctu skladeb (ES SQL ma omezeni na ORDER BY agregat z SELECT, takze ne kazdy alias funguje). `_sql/translate` ukazuje, ze SQL neni "magie", ale syntaktickym cukrem nad Query DSL – uzitecne pro pochopeni, co se deje pod kapotou. Vysledek: electronic (981 skladeb, avg pop 44.3, 11.7 % explicit), pop (937, avg 50.0, 6.6 % explicit), hip-hop (758, avg 39.2, **37.2 % explicit – nejvyssi pomer ze vsech zanru**).

---

### E4 – Simulace vypadku uzlu

```bash
# 1. Pred vypadkem
GET _cluster/health
# → green, 4 uzly (1 master + 3 data), 9 primary + 18 replica = 27 user shardu (per 3 indexy: 3P+6R)
#   plus systemove indexy → celkem ~87 active_shards

# 2. Zastavim jeden datovy uzel
docker compose stop es-data-2

# 3. Cluster – yellow (2 datove uzly stale drzi vsechny primary + 1 repliku)
GET _cluster/health
# → yellow, 3 uzly, vsech 9 user primary STARTED, ~9 unassigned_shards
#   (chybi 1 kopie z kazdeho shardu – ta co byla na es-data-2)

# 4. Data stale dostupna – zadna ztrata, cluster ma stale 2 kopie vseho
GET tracks/_count   → 13119
GET artists/_count  → 5271

# 5. Dotazy fungujou plnou rychlosti
GET tracks/_search {"query": {"match": {"track_name": "Bohemian Rhapsody"}}}
# → vysledky stejne jako pred vypadkem

# 6. Zastavim druhy datovy uzel (stress test – zbyva jen 1 datovy uzel)
docker compose stop es-data-3
GET _cluster/health
# → yellow, 2 uzly (master + es-data-1), ale vsechny primary shardy stale dostupne na es-data-1
GET tracks/_count → 13119 (data jeste dostupna – cluster prezije 2 soucasne vypadky!)

# 7. Obnovim oba uzly
docker compose start es-data-2 es-data-3

# 8. Cluster → green (ES automaticky synchronizuje repliky)
GET _cluster/health → green, 4 uzly, 9 primary + 18 replica active
```

**Klicovy pruvlom oproti 1-replika reseni:** s replikacnim faktorem 3 (1 primary + 2 replica) cluster **prezije soucasny vypadek 2 ze 3 datovych uzlu** bez ztraty dat. Yellow = degradovany stav (chybi kopie), ale data ok. RED by nastal az pri padu vsech 3 datovych uzlu.

Scenare:
- Padne 1 data uzel → yellow, data ok, vykonnost mirne degradovana.
- Padnou 2 data uzly → yellow, data ok, vsechno bezi z 1 uzlu.
- Padnou vsechny 3 data uzly → red, data nedostupna.
- Padne dedikovany master (es-master) → cluster nadale funguje, protoze vsechny 3 datove uzly maji roli `master,data,ingest` (HA setup). Quorum 3 ze 4 master-eligible uzlu zustava splnen, jeden z data uzlu je zvolen novym leaderem behem nekolika sekund. Cteni/zapis pokracuje bez prerusenii.

---

### E5 – Mereni latence dotazu pri degradovanem clusteru

Stejny analyticky dotaz pred a po vypadku uzlu – porovnani `took` v odpovedi.

```json
// 1. Stav: 4 uzly (master + 3 data), green – dotazy paralelne na 3 datove uzly
POST tracks/_search
{
  "size": 5,
  "_source": ["track_name", "popularity"],
  "query": {
    "bool": {
      "must": { "match": { "track_name": "love" } },
      "filter": { "range": { "popularity": { "gte": 30 } } }
    }
  },
  "aggs": {
    "per_genre": { "terms": { "field": "track_genre", "size": 10 } },
    "avg_energy": { "avg": { "field": "energy" } }
  }
}
// → took: ~10ms, 156 hits (kazdy shard na vlastnim uzlu)

// 2. docker compose stop es-data-2
// → cluster yellow, 9 unassigned replica shardu

// 3. Stejny dotaz – 2 datove uzly
// POST tracks/_search { ... stejny dotaz ... }
// → took: ~14ms, 156 hits (stejna data, mirne vyssi latence)

// 4. docker compose stop es-data-3
// → cluster yellow, 18 unassigned, vsechno jede z es-data-1

// 5. Stejny dotaz – 1 datovy uzel
// → took: ~22ms, 156 hits (vsech 3 shardy resi 1 uzel)

// 6. docker compose start es-data-2 es-data-3
// → po recovery (~30s) se cluster vrati na green a took se normalizuje
```

Vysledky (hits) jsou **vzdy identicke** – repliky zajistuji, ze kazdy shard ma kopii nejmene na 1 zivem uzlu. Latence (`took`) roste umerne tomu, na kolika uzlech dotaz bezi paralelne. Demonstrace **trade-off mezi dostupnosti a vykonem**: replikace zaruci kontinuitu sluzby i pri 2 soucasnych vypadcich, ale vykonnost klesne.

---

### E6 – Validace dat – kontrola konzistence a kvality

Analyticky dotaz overujici kvalitu importovanych dat: duplicity, chybejici pole, rozlozeni.

```json
POST tracks/_search
{
  "size": 0,
  "aggs": {
    "celkem_dokumentu": { "value_count": { "field": "track_id" } },
    "unikatnich_id": { "cardinality": { "field": "track_id" } },
    "chybejici_zanr": { "missing": { "field": "track_genre" } },
    "chybejici_popularita": { "missing": { "field": "popularity" } },
    "rozlozeni_zanru": {
      "terms": { "field": "track_genre", "size": 20 },
      "aggs": {
        "avg_popularity": { "avg": { "field": "popularity" } },
        "min_popularity": { "min": { "field": "popularity" } },
        "max_popularity": { "max": { "field": "popularity" } }
      }
    }
  }
}
```

`value_count` vs `cardinality` odhali duplicity: 13119 celkem, ~12867 unikatnich (default `cardinality` agregace pouziva HyperLogLog++ aproximaci s `precision_threshold: 3000`, takze pri ~13k dokumentech ma 1-2% chybu; pro presny pocet by bylo treba `precision_threshold: 40000` → vrati 13121 ≈ 13119). Po deduplikaci Logstashem pres `document_id => "%{track_id}"` jsou track_id ve skutecnosti unikatni. `missing` zkontroluje chybejici pole (0 = data kompletni). Vnorena agregace per zanr ukazuje rozlozeni – reggae (1000, avg pop 20.6) vs pop (937, avg pop 50.0). Slouzi jako validace ETL pipeline.


## Prehled

| Kat | # | Dotaz | API |
|-----|---|-------|-----|
| A | 1 | Hromadny update popularity | _update_by_query + Painless |
| A | 2 | Reindex s filtraci | _reindex + query + script |
| A | 3 | Obohaceni charts dat | _update_by_query + Painless conditionals |
| A | 4 | Klasifikace interpretu | _update_by_query + Painless + .size() |
| A | 5 | Skriptovany update | _update_by_query + Math |
| A | 6 | Cross-index vyhledavani | multi-index + multi_match + bool |
| B | 1 | Prumer per zanr + pipeline | terms + avg + avg_bucket |
| B | 2 | Range buckety + filter | range + avg + filter |
| B | 3 | Casovy vyvoj | date_histogram + cumulative_sum |
| B | 4 | Extended stats + percentily | extended_stats + percentiles + max_bucket |
| B | 5 | Porovnani skupin | 2x filter + avg + terms |
| B | 6 | Multi-terms | multi_terms + cardinality |
| C | 1 | Slozeny bool | must/should/must_not/filter |
| C | 2 | Multi-match + highlight | multi_match + boost + highlight |
| C | 3 | Fuzzy + filter + agregace | match fuzzy + bool + terms + avg |
| C | 4 | Fraze s proximity | match_phrase + slop + bool + highlight |
| C | 5 | Function score | field_value_factor + weight |
| C | 6 | Autocomplete | match_phrase_prefix |
| D | 1 | Custom analyzer | stop words + stemmer |
| D | 2 | Aliasy | filtrovany + multi-index |
| D | 3 | Experiment s replikami | _settings + _cat/shards + health |
| D | 4 | Runtime fields | runtime_mappings + Painless |
| D | 5 | Persistent runtime field | _mapping runtime + sort + aggs |
| D | 6 | Profilovani dotazu | profile: true + bool + aggs |
| E | 1 | Multi-search 3 indexy | _msearch + bool + aggs per index |
| E | 2 | Shard preference | preference=_shards + bool + aggs |
| E | 3 | SQL: CASE + HAVING + translate | _sql + _sql/translate |
| E | 4 | Vypadek uzlu | docker stop/start + recovery |
| E | 5 | Latence pri vypadku | took comparison + bool + aggs |
| E | 6 | Validace dat | cardinality + missing + terms + nested aggs |
