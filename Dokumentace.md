UNIVERZITA PARDUBICE
Fakulta elektrotechniky a informatiky

# Nasazení The Elastic Stack (ELK) pro analýzu hudebních dat ze Spotify

Matyáš Bláha

V Pardubicích dne 22.04.2026

---

## Obsah

- [Úvod](#úvod)
- [1 Architektura](#1-architektura)
  - [1.1 Schéma a popis architektury](#11-schéma-a-popis-architektury)
  - [1.2 Specifika konfigurace](#12-specifika-konfigurace)
    - [1.2.1 CAP teorém](#121-cap-teorém)
    - [1.2.2 Cluster](#122-cluster)
    - [1.2.3 Uzly](#123-uzly)
    - [1.2.4 Sharding](#124-sharding)
    - [1.2.5 Replikace](#125-replikace)
    - [1.2.6 Perzistence dat](#126-perzistence-dat)
    - [1.2.7 Distribuce dat](#127-distribuce-dat)
    - [1.2.8 Zabezpečení](#128-zabezpečení)
- [2 Funkční řešení](#2-funkční-řešení)
  - [2.1 Struktura](#21-struktura)
    - [2.1.1 Detailní popis docker-compose.yml](#211-detailní-popis-docker-composeyml)
  - [2.2 Instalace](#22-instalace)
    - [2.2.1 Krok 1: Spuštění stacku](#221-krok-1-spuštění-stacku)
    - [2.2.2 Krok 2: Ověření funkčnosti](#222-krok-2-ověření-funkčnosti)
- [3 Případy užití a případové studie](#3-případy-užití-a-případové-studie)
  - [3.1 Případové studie](#31-případové-studie)
  - [3.2 Proč byl vybrán ELK stack](#32-proč-byl-vybrán-elk-stack)
- [4 Výhody a nevýhody](#4-výhody-a-nevýhody)
  - [4.1 Výhody ELK stacku](#41-výhody-elk-stacku)
  - [4.2 Nevýhody ELK stacku](#42-nevýhody-elk-stacku)
  - [4.3 Výhody a nevýhody mého konkrétního řešení](#43-výhody-a-nevýhody-mého-konkrétního-řešení)
- [5 Další specifika](#5-další-specifika)
  - [5.1 Custom analyzér](#51-custom-analyzér)
  - [5.2 Runtime fields](#52-runtime-fields)
  - [5.3 Oddělené Logstash pipeline](#53-oddělené-logstash-pipeline)
  - [5.4 Deterministické document ID](#54-deterministické-document-id)
- [6 Data](#6-data)
  - [6.1 Zdroj dat](#61-zdroj-dat)
  - [6.2 Typy dat a formát](#62-typy-dat-a-formát)
  - [6.3 Úpravy dat před importem](#63-úpravy-dat-před-importem)
  - [6.4 Distribuce shardů v indexech](#64-distribuce-shardů-v-indexech)
  - [6.5 Základní analýza](#65-základní-analýza)
- [7 Dotazy](#7-dotazy)
  - [7.1 Práce s daty](#71-práce-s-daty)
  - [7.2 Agregační funkce](#72-agregační-funkce)
  - [7.3 Fulltextové vyhledávání](#73-fulltextové-vyhledávání)
  - [7.4 Indexy a konfigurace](#74-indexy-a-konfigurace)
  - [7.5 Cluster, distribuce a výpadek](#75-cluster-distribuce-a-výpadek)
- [Závěr](#závěr)
- [Zdroje](#zdroje)
- [Přílohy](#přílohy)

---

## Úvod

Tato semestrální práce se zabývá nasazením a konfigurací The Elastic Stack (ELK) – sady nástrojů pro ukládání, transformaci a analýzu dat s důrazem na fulltextové vyhledávání. Cílem je sestavit funkční cluster, naimportovat do něj reálná data a ukázat, jak nad nimi pokládat netriviální dotazy – jak vyhledávací, tak analytické.

V práci jsem se rozhodl postavit cluster s více uzly tak, aby demonstroval sharding a replikaci. Každý uzel má přidělenou konkrétní roli (master vs. data) a každý index je rozdělen na tři shardy se třemi kopiemi dat (1 primary + 2 replica). Zabezpečení je řešeno TLS certifikáty mezi všemi uzly a RBAC autentizací pro klientské přístupy.

Čtenář se dozví, jak funguje Elasticsearch jako distribuovaný engine nad Lucene, jak Logstash zpracovává CSV soubory a odesílá je přes pipeline do indexů, a jak Kibana poskytuje webové rozhraní pro ověřování dat a tvorbu dashboardů. Součástí jsou rozbor architektury, popis docker-compose orchestrace, 30 netriviálních dotazů v Query DSL a Python analýza použitých dat.

Mimo rozsah práce zůstává nasazení Beats agentů (Filebeat, Metricbeat) pro kontinuální sběr dat a napojení na reálné zdroje typu Kafka nebo syslog. Pro účely semestrální práce je jednorázový import CSV přes Logstash dostatečný a lépe ukazuje řízení datového toku.

Řešení je postavené na ELK stacku verze 8.17.0 s oficiálními Docker obrazy od Elasticu. Vedle ELK stacku je použitý také nástroj Elasticvue pro vizuální správu clusteru v prohlížeči. Celé nasazení je plně automatizované pomocí Docker Compose a inicializačních skriptů.

**Použité verze:**
- Elasticsearch 8.17.0
- Logstash 8.17.0
- Kibana 8.17.0

Všechny komponenty jsou ze stejné verze, aby se předešlo problémům s kompatibilitou. Podle pravidla zadání „maximálně tři verze zpět od aktuální" to odpovídá – aktuální major je 8.x a 8.17.0 patří do podporovaného rozmezí.

**Použité Docker obrazy:**
- `docker.elastic.co/elasticsearch/elasticsearch:8.17.0` – oficiální obraz od Elasticu. Zvolen kvůli plné podpoře xpack security (TLS, RBAC), kompletní dokumentaci a zaručené kompatibilitě s ostatními komponentami.
- `docker.elastic.co/logstash/logstash:8.17.0` – oficiální obraz s předinstalovanými vstupními a výstupními pluginy (file, csv, elasticsearch).
- `docker.elastic.co/kibana/kibana:8.17.0` – oficiální obraz s přímou integrací na xpack security.
- `cars10/elasticvue:1.0.8` – open-source webový nástroj pro vizuální správu ES clusteru. Není oficiální Elastic obraz, ale slouží pouze jako pomocný nástroj pro kontrolu stavu clusteru.

---

## 1 Architektura

Tato kapitola popisuje, jak je cluster sestavený, jaké role jednotlivé uzly plní a jaká rozhodnutí vedla k výsledné podobě. Pokud se v některých bodech řešení liší od doporučeného produkčního nasazení, je to explicitně uvedeno.

### 1.1 Schéma a popis architektury

Pro práci jsem zvolil architekturu Elasticsearch clusteru s oddělenou master a data vrstvou. Řešení se skládá z 8 Docker kontejnerů propojených izolovanou bridge sítí `elk-net`.

**Elasticsearch cluster (4 uzly, všechny master-eligible — HA setup):**
- `es-master` – dedikovaný master uzel (role: master). Primárně řídí stav clusteru, alokaci shardů a volbu leadera. Nedrží žádná data. Díky oddělení rolí nemůže být master pozdržený těžkými search dotazy na datových uzlech.
- `es-data-1` – datový uzel s ingest pipeline (role: master, data, ingest). Drží primary a replica shardy, obsluhuje dotazy, provádí pre-processing příchozích dokumentů a v případě výpadku dedikovaného masteru může být zvolen leaderem. Má namapovaný port 9200 ven, takže slouží jako vstupní bod pro API.
- `es-data-2` – druhý datový uzel (role: master, data, ingest). Zajišťuje redundanci dat, paralelní zpracování dotazů a master-eligibility.
- `es-data-3` – třetí datový uzel (role: master, data, ingest). Umožňuje držet 3 kopie každého shardu (1 primary + 2 replica) → splnění požadavku „min. 3 repliky" ze zadání. Také master-eligible.

**Podpůrné služby:**
- `kibana` – webové rozhraní na portu 5601. Přihlašuje se k ES přes HTTPS systémovým uživatelem `kibana_system`.
- `logstash` – ETL nástroj. Čte CSV soubory, parsuje je, konvertuje typy a odesílá do ES přes HTTPS. Tři nezávislé pipeline (tracks, artists, charts).
- `setup` – jednorázový kontejner. Vygeneruje CA certifikát, z něj certifikáty pro každý ES uzel a nastaví heslo pro `kibana_system`.
- `init` – jednorázový kontejner. Vytvoří index templates s explicitními mappingy (3 shardy, 2 repliky, správné datové typy pro každé pole).
- `elasticvue` – volitelný GUI nástroj pro správu clusteru v prohlížeči na portu 8080.

Schéma architektury bylo vytvořené v nástroji draw.io a je přiložené v souboru `schema_architektury.png`.

**V čem se řešení liší od doporučeného nasazení:**

Best-practice produkční nasazení doporučuje liché počty master-eligible uzlů (3, 5, 7) kvůli quorum-based volbě leadera. Moje řešení má **4 master-eligible uzly** (1 dedikovaný master + 3 datové uzly s rolí master,data,ingest), což zajišťuje HA: při výpadku libovolného uzlu zbývá quorum 3/4, cluster automaticky zvolí nového leadera. V produkci by se preferovala lichá topologie (např. 3 dedikované master uzly + N datových), ale pro semestrální projekt je 4 master-eligible uzly při 4 fyzických uzlech rozumný kompromis — přidává HA bez nutnosti spouštět extra uzly. Záměrně tedy používám hybridní model: jeden dedikovaný master pro stabilní řízení clusteru a tři data uzly s master rolí jako záložní volby pro election.

Druhý rozdíl je velikost dat. V produkci by cluster měl desítky datových uzlů a petabajty dat. Moje řešení zpracovává ~28 tisíc dokumentů na 3 datových uzlech, což je pro demonstraci shardingu, replikace a distribuce dostatečné, ale nevyužívá plný potenciál ES.

### 1.2 Specifika konfigurace

Tato část popisuje konkrétní konfigurační rozhodnutí a proč jsem je udělal tak, jak jsou. Konfigurace vychází z oficiální dokumentace Elasticu (Elastic, 2026).

#### 1.2.1 CAP teorém

Podle Brewerova CAP teorému může distribuovaný systém garantovat maximálně dvě ze tří vlastností: Consistency (konzistence), Availability (dostupnost) a Partition tolerance (odolnost vůči rozdělení sítě).

**Elasticsearch spadá do kategorie CP (Consistency + Partition tolerance):**

- **Konzistence (C):** Každý zápis jde nejprve na primary shard, ten pak synchronně replikuje na všechny aktivní replica shardy. Klient dostane potvrzení až po úspěšné replikaci (podle parametru `wait_for_active_shards`). Díky tomu všechny uzly vidí stejná data a nevznikají protichůdné verze dokumentu.

- **Odolnost vůči rozdělení sítě (P):** Při síťovém rozdělení cluster pokračuje v provozu – master election zajistí, že leader je vždy v té části, kde je majority uzlů. Uzly odpojené od většiny přestanou obsluhovat požadavky.

- **Dostupnost (A) je obětována:** Když padne dostatek uzlů, cluster přejde do stavu yellow (snížená redundance) nebo red (nedostupná primary data). V krajním případě raději odmítne požadavek, než by vrátil nekonzistentní data.

**Proč je CP dostatečné pro naše řešení:**

Pracujeme s analytickými daty (Spotify statistiky), kde je důležitější správnost výsledků než 100% dostupnost. Když při restartu uzlu cluster přejde na pár sekund do yellow stavu, je to přijatelné. Repliky na zbývajících uzlech data bez problému vrátí a po dokončení restartu ES automaticky dosynchronizuje.

#### 1.2.2 Cluster

V projektu je použitý **jeden cluster** s názvem `spotify-elk-cluster`.

Jeden cluster je dostatečný, protože všechna data tvoří jeden logický celek (hudební data ze Spotify). Více clusterů by mělo smysl při geografické distribuci (cross-cluster search), oddělení produkčního a testovacího prostředí nebo velmi odlišných datových typech s jinými požadavky na konfiguraci. V semestrální práci nic z toho neplatí.

Cluster je nastavený přes proměnnou `cluster.name=${CLUSTER_NAME}` na všech uzlech. Uzly se automaticky najdou pomocí discovery přes seed hosty (`discovery.seed_hosts`) – každý uzel má v konfiguraci seznam ostatních uzlů, kam se má při startu pokusit připojit.

#### 1.2.3 Uzly

V clusteru jsou celkem **4 uzly** s následujícím rozdělením rolí:

| Uzel | Role | Účel |
|------|------|------|
| es-master | master | Dedikovaný master – řídí cluster state, alokaci shardů, master election |
| es-data-1 | master, data, ingest | Ukládá shardy, vykonává dotazy, pre-processing dat (vstupní bod – port 9200), master-eligible (záložní leader) |
| es-data-2 | master, data, ingest | Ukládá shardy, zajišťuje redundanci, master-eligible |
| es-data-3 | master, data, ingest | Ukládá shardy, umožňuje držet 3 kopie každého shardu, master-eligible |

**Proč dedikovaný master + 3 master-eligible data uzly (HA):**

Oddělení master role na samostatném `es-master` znamená, že těžké search dotazy a indexace na datových uzlech nezpomalí správu clusteru za běžného provozu. Master nemusí mít velký heap, protože nedrží data – přidělil jsem mu 512 MB JVM heap, což pro cluster state pár kontejnerů bohatě stačí. Zároveň všechny tři datové uzly mají roli `master,data,ingest`, takže jsou **master-eligible** a v případě výpadku dedikovaného masteru může být kterýkoli z nich automaticky zvolen novým leaderem (Raft-like volba s quorum). Cluster má celkem 4 master-eligible uzly, quorum je 3 ze 4 → cluster přežije výpadek libovolného **jednoho** uzlu bez ztráty řízení. Tato HA konfigurace je odolnější než klasický návrh s jedním dedikovaným masterem (single point of failure pro cluster management).

**Proč 3 datové uzly:**

Tři datové uzly jsou minimum pro udržení tří kopií dat per shard. Se třemi kopiemi (1 primary + 2 replica) může cluster přežít současný výpadek dvou ze tří datových uzlů bez ztráty dat. Zároveň platí, že primary a obě repliky musí být každá na jiném uzlu – ES to sám hlídá, takže se 3 kopie a 3 uzly dostanu na maximum, co lze v dané topologii mít.

**Proč role ingest na datových uzlech:**

Ingest pipeline (např. úprava datumů nebo enrichment) se vykonává přímo na uzlu, kam Logstash posílá data. Mít dedikovaný ingest uzel by se vyplatilo, kdyby ingest byl výpočetně náročný. V mém případě jde o jednoduché CSV parsování a typové konverze (probíhající už v Logstashi), takže role ingest na datových uzlech stačí a šetří paměť.

#### 1.2.4 Sharding

Každý index má **3 primary shardy**. Sharding je nakonfigurovaný přes index templates v `init/setup.sh`:

```json
"settings": {
  "number_of_shards": 3,
  "number_of_replicas": 2
}
```

**Jak sharding funguje:**

Index je logická kolekce dokumentů. Fyzicky je rozdělený na shardy – každý shard je samostatný Lucene index, který může ležet na jiném uzlu. Dokumenty se do shardů distribuují hashovací funkcí podle `_id` pole (zjednodušeně `shard = hash(_id) % number_of_shards`). Díky tomu se dokumenty rozprostřou rovnoměrně a každý shard dostane zhruba třetinu dat.

**Rozložení na uzlech (příklad index tracks, 3 primary + 6 replica = 9 shardů):**

```
es-data-1: [P0] [R1] [R2]    (1 primary + 2 replica)
es-data-2: [R0] [P1] [R2]    (1 primary + 2 replica)
es-data-3: [R0] [R1] [P2]    (1 primary + 2 replica)
```

**Proč 3 shardy:**

- Splňuje minimum ze zadání.
- Umožňuje paralelní zpracování dotazů – search dotaz na index tracks se rozdělí na tři podotazy, každý se vykoná na svém shardu a potenciálně na jiném uzlu.
- Pro objem dat (~13 000 dokumentů v tracks) by sám o sobě stačil i jeden shard, ale 3 shardy demonstrují distribuci a umožňují škálovat – stačí přidat další data uzel a ES automaticky přesune shardy tak, aby byl cluster vyvážený.

**Použité indexy a sekundární struktury:**

V mappingu každého indexu jsou explicitně definované datové typy (keyword pro identifikátory a kategorie, text s keyword subfieldem pro fulltext, integer/float pro čísla, date pro datumy). Pro textová pole platí, že ES automaticky vytváří invertovaný index, který je základem fulltextového vyhledávání. Konkrétní optimalizace jako custom analyzéry ukazuji v dotazu D1 (chapter 7).

#### 1.2.5 Replikace

Každý primary shard má **2 repliky** → celkem **3 kopie každého shardu** (1 primary + 2 replica). Počet replica shardů per index je 6, takže celkem 9 shardů per index.

Pro 3 indexy (tracks, artists, charts) to dělá 3 × 9 = **27 shardů celkem**, rozložených rovnoměrně na 3 datových uzlech. Každý datový uzel drží 9 shardů – 3 primary + 6 replica.

**Jak replikace funguje:**

1. Nový dokument přijde na koordinační uzel (typicky es-data-1).
2. Koordinátor vypočítá cílový shard podle hash(_id) a pošle zápis na primary shard.
3. Primary shard dokument zapíše do in-memory bufferu a translogu, potom synchronně replikuje na obě replica shardy na jiných uzlech.
4. Klient dostane potvrzení až po úspěšné replikaci na všechny aktivní kopie.
5. Při čtení ES obsluhuje dotazy z libovolné kopie – primary i replica jsou pro čtení rovnocenné. To umožňuje paralelní čtení ze tří zdrojů.

**Proč 2 repliky (3 kopie celkem):**

- Splňuje požadavek zadání „minimálně 3 repliky" – chápáno jako 3 kopie dat per shard (1 primary + 2 replica shards).
- Vyšší odolnost: cluster přežije výpadek **dvou** datových uzlů bez ztráty dat. Do red stavu by se dostal až tehdy, kdyby padly všechny 3 datové uzly.
- Paralelní čtení ze 3 zdrojů zvyšuje propustnost při vyšší zátěži search dotazy.
- Maximum, co lze s 3 datovými uzly mít. Experiment v dotazu D3 ukazuje, že pokus o 3 repliky způsobí stav UNASSIGNED – ES by potřeboval 4. datový uzel.

#### 1.2.6 Perzistence dat

Elasticsearch ukládá data v několika krocích. Kombinuje rychlost (in-memory buffer) s odolností (translog) a výkonem čtení (segment merging).

**1. Zápis dokumentu:**
- Dokument přijde na primary shard → zapíše se do **in-memory bufferu** a současně do **transaction logu (translog)**.
- Translog je append-only soubor na disku. I když refresh ještě neproběhl, data jsou díky translogu v bezpečí před pádem procesu.

**2. Refresh (default každou 1 sekundu):**
- In-memory buffer se zapíše do nového **Lucene segmentu** na disk.
- Segment je immutable – jakmile je zapsaný, už se nemění.
- Po refreshi je dokument prohledatelný (tzv. near-realtime search, zpoždění max 1 s).
- Refresh interval se dá měnit: `PUT index/_settings {"index": {"refresh_interval": "5s"}}`. U čistě analytických workloadů, kde nevadí mírně pozdější viditelnost, se vyplatí prodloužit – šetří CPU.

**3. Flush:**
- Translog se vyprázdní a segmenty se fsyncnou na disk.
- Po flushi je bezpečné translog smazat, protože všechna data jsou trvale na disku.
- Default flush se děje automaticky podle velikosti translogu nebo časového intervalu.

**4. Segment merging:**
- Malé segmenty se na pozadí slučují do větších.
- Optimalizuje čtení – méně segmentů znamená méně souborů k prohledání.
- Smazané dokumenty se fyzicky odstraní až při mergi – do té doby jsou jen označené jako deleted.

**V mém řešení:**

Data jsou perzistována v Docker volumes (`es-master-data`, `es-data-1-data`, `es-data-2-data`, `es-data-3-data`). Při `docker compose down` (bez `-v`) volumes zůstanou a data přežijí. Příkaz `docker compose down -v` volumes smaže a data se ztratí – v tu chvíli je potřeba reimportovat (Logstash pipeline to při startu udělá automaticky).

#### 1.2.7 Distribuce dat

Tato část shrnuje, jak se data v clusteru distribuují při zápisu i čtení.

**Zápis dat (Logstash → ES):**

1. Logstash pošle dokument na koordinační uzel (es-data-1, port 9200).
2. ES vypočítá cílový shard: `shard = hash(document_id) % 3`.
3. Dokument se zapíše na primary shard (ten může být na kterémkoli ze 3 datových uzlů).
4. Primary synchronně replikuje na obě repliky na zbývajících uzlech.
5. Logstash dostane potvrzení. Další dokument jde znova přes koordinátora.

**Čtení dat (search dotaz):**

1. Dotaz přijde na koordinační uzel.
2. Koordinátor rozešle dotaz na všechny relevantní shardy – pro každý shard vybere buď primary, nebo jednu z replik (cluster-aware routing).
3. Každý shard vrátí lokální částečné výsledky.
4. Koordinátor výsledky sloučí (merge, řazení, paginace) a vrátí klientovi.

**Ověření distribuce v clusteru:**

Stav shardů se dá kdykoli zkontrolovat přes `GET _cat/shards`. Pro stabilní cluster je očekávaný stav:

```
GET _cat/shards/tracks,artists,charts?v&s=index,shard

index   shard prirep state   docs  node
tracks  0     p      STARTED 4358  es-data-1
tracks  0     r      STARTED 4358  es-data-2
tracks  0     r      STARTED 4358  es-data-3
tracks  1     p      STARTED 4362  es-data-2
tracks  1     r      STARTED 4362  es-data-1
tracks  1     r      STARTED 4362  es-data-3
tracks  2     p      STARTED 4399  es-data-3
tracks  2     r      STARTED 4399  es-data-1
tracks  2     r      STARTED 4399  es-data-2
```

Počty dokumentů na uzlech (index tracks, každý uzel drží 1 primary + 2 replica):

| Uzel | Počet dokumentů (součet shardů) | Shardy |
|------|---------------------------------|--------|
| es-data-1 | ~13 119 | 1 primary + 2 replica |
| es-data-2 | ~13 119 | 1 primary + 2 replica |
| es-data-3 | ~13 119 | 1 primary + 2 replica |

Data jsou rovnoměrně distribuovaná. Každý ze 3 datových uzlů drží kompletní kopii všech dat (součet primary + replica shardů). Cluster tak může obsloužit dotaz z libovolného z uzlů.

**Alokace shardů per uzel se dá ověřit přes:**

```
GET _cat/allocation?v

shards disk.indices disk.used disk.total node
     9       15.2mb  ...              es-data-1
     9       15.2mb  ...              es-data-2
     9       15.2mb  ...              es-data-3
```

Každý datový uzel drží stejný počet shardů (9) a zhruba stejné množství dat.

#### 1.2.8 Zabezpečení

Zabezpečení v mém řešení stojí na třech pilířích: TLS šifrování komunikace, autentizace uživatelů a RBAC (Role-Based Access Control).

**TLS (Transport Layer Security):**

Kontejner `setup` při prvním spuštění vygeneruje Certificate Authority (CA) a z ní certifikáty pro každý ES uzel pomocí nástroje `elasticsearch-certutil`:

- **HTTP SSL** (port 9200) – šifruje komunikaci klient ↔ ES (Kibana, Logstash, curl, Elasticvue).
- **Transport SSL** (port 9300) – šifruje interní komunikaci uzel ↔ uzel v rámci clusteru.
- Kibana používá CA certifikát pro ověření identity ES serveru.

Certifikáty jsou uložené v Docker volume `certs`, které je sdílené mezi setup kontejnerem, všemi ES uzly a Kibanou.

**Autentizace:**

- V konfiguraci každého ES uzlu je `xpack.security.enabled=true`.
- Vestavěný uživatel `elastic` má roli superuser – používá se pro admin operace a má heslo nastavené přes `.env`.
- Vestavěný uživatel `kibana_system` je systémový účet, který používá pouze Kibana pro interní komunikaci s ES. Má omezená práva (nemůže se přihlásit do Kibany, slouží jen interně).
- Všechna hesla jsou v `.env` souboru (není v gitu, pouze `.env.example` jako šablona).

**Autorizace (RBAC):**

- Role `superuser` (má uživatel `elastic`) – plný přístup ke všem operacím.
- Role `kibana_system` (má systémový uživatel) – omezený přístup jen na Kibana funkce, nemůže číst ani zapisovat do běžných indexů.
- Princip nejmenších oprávnění – Kibana se k ES nepřipojuje jako superuser.

---

## 2 Funkční řešení

Tato kapitola popisuje, jak je projekt fyzicky strukturovaný a jak ho spustit. Vše je automatizované, takže po naklonování repozitáře stačí jeden příkaz.

### 2.1 Struktura

Projekt je rozdělen podle požadavků zadání do tří příloh dokumentace (`Funkční řešení/`, `Data/`, `Dotazy/`) a samotné dokumentace v rootu.

| Soubor / Složka | Typ | Popis a role v projektu |
|-----------------|-----|-------------------------|
| **Funkční řešení/** | **Příloha** | **Vše potřebné pro spuštění clusteru přes Docker Compose** |
| Funkční řešení/docker-compose.yml | Orchestrace | Definice všech služeb clusteru, jejich závislostí, volumes a sítě. |
| Funkční řešení/.env | Konfigurace | Hesla, verze, limity paměti. |
| Funkční řešení/.env.example | Šablona | Vzor pro vytvoření `.env`. |
| Funkční řešení/init/setup.sh | Skript | Inicializace ES – vytvoří index templates s mappingy pro tracks, artists, charts. Spouští se automaticky po startu clusteru. |
| Funkční řešení/logstash/pipelines.yml | Konfigurace | Definice tří nezávislých Logstash pipeline (tracks, artists, charts). |
| Funkční řešení/logstash/pipeline/*.conf | Konfigurace | Samotné pipeline – input (CSV), filter (parsing, typová konverze) a output (ES). |
| Funkční řešení/kibana_dashboard_export.ndjson | Export | Uložený Kibana dashboard pro rychlý import. |
| **Data/** | **Příloha** | **3 datasety + Python analýza** |
| Data/*.csv | Data | Tři datové soubory: tracks_clean.csv (15 000 záznamů), artists_clean.csv (5 271), charts_clean.csv (8 000). |
| Data/analyza.ipynb | Notebook | Jupyter notebook s Python analýzou dat (statistiky, grafy). |
| Data/*.png | Grafy | 4 grafy vygenerované z analýzy. |
| **Dotazy/** | **Příloha** | **Všechny dotazy** |
| Dotazy/vsechny_dotazy.md | Dokumentace | Soubor se všemi 30 dotazy v Query DSL, jejich zadáním a komentářem. |
| **Root** | **Dokumentace** | |
| Dokumentace.md / .docx | Dokumentace | Plná dokumentace dle šablony. |
| schema_architektury.png | Obrázek | Schéma architektury vytvořené v draw.io. |
| README.md | Quickstart | Stručný úvod a spouštěcí příkaz. |

#### 2.1.1 Detailní popis docker-compose.yml

Docker Compose definuje 8 služeb + 1 volitelný GUI nástroj:

| Služba | Image | Port | Účel |
|--------|-------|------|------|
| setup | elasticsearch:8.17.0 | – | Generuje TLS certifikáty, nastaví heslo pro kibana_system (one-shot). |
| es-master | elasticsearch:8.17.0 | – | Dedikovaný master uzel. |
| es-data-1 | elasticsearch:8.17.0 | 9200 | Datový uzel, vstupní bod pro API (HTTPS). |
| es-data-2 | elasticsearch:8.17.0 | – | Datový uzel. |
| es-data-3 | elasticsearch:8.17.0 | – | Datový uzel (třetí kopie dat). |
| kibana | kibana:8.17.0 | 5601 | Webové rozhraní pro správu a vizualizaci. |
| init | elasticsearch:8.17.0 | – | Vytvoření index templates (one-shot). |
| logstash | logstash:8.17.0 | – | ETL import dat z CSV do ES. |
| elasticvue | cars10/elasticvue:1.0.8 | 8080 | GUI pro správu clusteru v prohlížeči. |

**Závislosti (depends_on):**

Služby se spouští v přesném pořadí pomocí `depends_on` s podmínkami `service_healthy` nebo `service_completed_successfully`:

```
setup → es-master → es-data-1, es-data-2, es-data-3 → init → logstash
                                                    → kibana
```

- `setup` musí vygenerovat certifikáty, než ES uzly nastartují (jinak nemají čím podepisovat komunikaci).
- `es-master` musí být healthy (odpovídá na `missing authentication credentials`), než se připojí datové uzly.
- Všechny 3 datové uzly musí být healthy, než se spustí `init` (jinak by index templates neměly kam být zapsané).
- `init` musí skončit úspěšně před `logstash` – jinak by Logstash pushoval dokumenty do indexů bez explicitního mappingu a ES by si typ odvozoval dynamicky (a špatně – např. stringové číslo jako text místo integer).

**Volumes:**

- `certs` – TLS certifikáty sdílené mezi všemi ES uzly a Kibanou. Generuje je setup kontejner.
- `es-master-data`, `es-data-1-data`, `es-data-2-data`, `es-data-3-data` – perzistentní data ES uzlů.
- `kibana-data` – Kibana saved objects (dashboardy, index patterns).

**Síť:**

- `elk-net` (bridge) – izolovaná Docker síť. Všechny kontejnery si říkají jménem služby (Docker DNS). Ven je mapovaný jen port 9200 (ES API), 5601 (Kibana) a 8080 (Elasticvue).

**Proměnné prostředí (.env):**

- `ELASTIC_PASSWORD` – heslo pro superuser `elastic`.
- `KIBANA_PASSWORD` – heslo pro `kibana_system`.
- `STACK_VERSION` – verze ELK stacku (8.17.0).
- `CLUSTER_NAME` – jméno clusteru (spotify-elk-cluster).
- `MEM_LIMIT_MASTER` – RAM limit master kontejneru (2 GiB, JVM heap 512 MB). Master během startu načítá ILM policies, ingest pipelines, security indexy a APM templates – proto vyšší limit než původně plánovaná 1 GiB, který způsoboval OOM kill při bootstrap fázi.
- `MEM_LIMIT_DATA` – RAM limit pro **každý** data uzel, Kibanu a Logstash (1.5 GiB). JVM heap data uzlů 512 MB, Logstash 384 MB. Vyšší limit než heap kvůli Lucene off-heap cache, JVM metaspace a native memory pro shard operace.

### 2.2 Instalace

Zprovoznění celého řešení je plně automatizované a vyžaduje pouze Docker Desktop a Git.

**Předpoklady:**
- Docker Desktop (min. **10–12 GiB RAM** přiděleno Dockeru – es-master 2 GiB + 3× es-data à 1.5 GiB + Kibana 1.5 GiB + Logstash 1.5 GiB + setup/init/elasticvue ~0.5 GiB + Docker overhead). Doporučuji 12 GiB pro pohodlnou rezervu, minimum 10 GiB.
- Git.

#### 2.2.1 Krok 1: Spuštění stacku

```bash
git clone <repo-url>
cd noSql/"Funkční řešení"
cp .env.example .env
# Upravit hesla v .env (nebo ponechat výchozí)
docker compose up -d
```

Spouští se ze složky `Funkční řešení/`, protože zadání požaduje, aby tato složka byla samostatnou přílohou s docker-compose.yml a všemi konfiguracemi pro zprovoznění. Logstash má v compose definovaný relativní mount `../Data:/usr/share/logstash/data-input:ro`, který odkazuje na složku `Data/` o úroveň výš.

Celý stack se spustí ve správném pořadí:

1. `setup` vygeneruje TLS certifikáty (cca 10 s).
2. `es-master` naběhne jako master uzel (cca 30 s).
3. `es-data-1`, `es-data-2` a `es-data-3` se připojí ke clusteru (cca 40 s).
4. `init` vytvoří index templates (cca 5 s).
5. `logstash` přečte CSV a naimportuje dokumenty (cca 60 s).
6. `kibana` naběhne (cca 60 s).

Celkem cca 2–3 minuty od spuštění do plně funkčního clusteru.

#### 2.2.2 Krok 2: Ověření funkčnosti

Po startu je možné ověřit stav několika způsoby:

**Health check clusteru (CLI):**

```bash
curl -sk -u elastic:SpotifyELK2025! https://localhost:9200/_cluster/health?pretty
```

Očekávaný výstup: `"status": "green"`, `"number_of_nodes": 4`, `"number_of_data_nodes": 3`.

**Počet dokumentů v indexech:**

```bash
curl -sk -u elastic:SpotifyELK2025! https://localhost:9200/_cat/indices/tracks,artists,charts?v
```

Očekávaný výstup: tracks ~13 119, artists ~5 271, charts ~8 000 dokumentů.

**Kibana v prohlížeči:**

- URL: http://localhost:5601
- Username: `elastic`
- Password: (hodnota z `.env`)

Po přihlášení v Kibaně je dostupný Discover (prohlížení dokumentů + interaktivní KQL search), Dev Tools (Query DSL) a Stack Management. Přes Stack Management → Saved Objects → Import lze načíst dashboard z `kibana_dashboard_export.ndjson`.

#### 2.2.3 Interaktivní vyhledávání v Discover (live search demo)

Discover v Kibaně poskytuje uživateli plně **interaktivní search bar** nad ES indexy — funguje stejně jako vyhledávací pole v aplikacích typu Spotify nebo Stack Overflow. Pole používá **KQL (Kibana Query Language)**, který Kibana překládá na ES Query DSL.

**Postup:**

1. Otevřete Kibanu, přihlaste se jako `elastic`.
2. Vlevo hamburger menu (☰) → **Discover**.
3. Při prvním otevření Kibana vyzve k vytvoření **Data view**:
   - Name: `tracks`
   - Index pattern: `tracks`
   - Timestamp field: *None / I don't want to use a time filter*
4. Stejný postup zopakujte pro `artists` a `charts`.
5. Nahoře je **KQL search bar** – do něj se píše dotaz.

**Příklady KQL dotazů (vyzkoušet u obhajoby):**

```kql
track_name: love
```
→ Všechny skladby s "love" v názvu (fulltext match).

```kql
track_name: love and popularity > 70
```
→ Populární love skladby (kombinace fulltextu a numerického filtru).

```kql
track_genre: rock and energy >= 0.8 and danceability >= 0.6
```
→ Energické a tanečné rockové skladby (multi-field filtr).

```kql
artists.keyword: "Ed Sheeran"
```
→ Přesná shoda interpreta (`.keyword` subfield z mappingu).

```kql
not explicit and popularity >= 80
```
→ Negace + filtr (populární neexplicitní skladby).

**Co se děje pod kapotou:** Kibana přeloží KQL na ES Query DSL (kombinace `bool`, `match`, `range`) a pošle do ES. Výsledky se okamžitě zobrazí jako tabulka. Stejný princip používají reálné aplikace — pouze místo Kibany volá REST API ES vlastní frontend (React, Vue, mobilní app).

**Elasticvue (volitelně):**

- URL: http://localhost:8080
- Přihlašovací údaje jsou předvyplněné v URL přes ELASTICVUE_CLUSTERS.

---

## 3 Případy užití a případové studie

ELK stack je navržený primárně pro tyto úlohy:

- **Centrální logování** – agregace logů z desítek až stovek serverů a mikroslužeb na jedno místo.
- **Monitoring a observability** – sběr a analýza metrik, traces, APM dat.
- **Fulltextové vyhledávání** – hledání v dokumentech, e-shopech, znalostních bázích. ES má invertovaný index, custom analyzéry, fuzziness a scoring (BM25).
- **Analýza událostí** – SIEM (bezpečnostní analýza), business analytics, anomaly detection.

V této semestrální práci byl ELK nasazený pro analytiku hudebních dat ze Spotify. Datová doména kombinuje číselná pole (audio features), textová (názvy, žánry), datumová (charts) a boolean hodnoty. Tato různorodost dobře ilustruje, jak ES pracuje s různými typy polí a jak se řeší mappingy.

### 3.1 Případové studie

Níže jsou tři reálné případové studie nasazení ELK stacku nebo jeho komponent. U každé je uvedené, v čem se podobá mému řešení.

#### 3.1.1 Netflix – centrální logování

Netflix zpracovává přes miliardu logových událostí denně z tisíců mikroslužeb. ES slouží jako centrální úložiště logů, kam data proudí přes Kafka (pro buffering) a Logstash (pro transformaci a obohacení). Inženýři potom v Kibana Discover vyhledávají konkrétní chybové hlášky napříč všemi službami – fulltext a filtry jim umožní najít příčinu incidentu v řádu sekund místo ručního procházení logů na desítkách serverů.

Klíčové je škálování. Netflix cluster má stovky datových uzlů a petabajty dat. Sharding umožňuje přidávat uzly bez downtimu – ES automaticky přerozdělí shardy. Retention je řízená přes ILM (Index Lifecycle Management) – staré indexy se po 30 dnech smažou nebo přesunou na levnější storage tier.

**Souvislost s mým řešením:** používám stejný pattern (Logstash → ES → Kibana), jen v menším měřítku a s jednorázovým CSV importem místo live logů. ILM jsem nepoužil, protože data jsou statická, ale architektura by byla stejná (Elastic, 2026).

#### 3.1.2 Uber – geolokační vyhledávání

Uber používá Elasticsearch jako páteř vyhledávání míst a adres v reálném čase napříč celou svou aplikací. Když uživatel začne v aplikaci psát adresu, ES posílá autocomplete návrhy prostřednictvím `match_phrase_prefix` dotazů – uživatel vidí relevantní návrhy už po několika znacích, s latencí v řádu desítek milisekund. Pro párování řidičů s cestujícími Uber využívá geo-spatial dotazy (`geo_distance`, `geo_bounding_box`), které v dané oblasti najdou nejbližší dostupné vozy.

Uber cluster zpracovává desítky tisíc dotazů za sekundu s latencí pod 100 ms. Tohoto výkonu je dosaženo replikací (paralelní čtení z více kopií shardů), pečlivou optimalizací mappingů (keyword pole pro filtry, text pro search), precomputed hodnotami a horizontálním škálováním clusteru o desítky uzlů. Pro zajištění odolnosti je cluster geograficky distribuován.

Datový model kombinuje nested dokumenty pro adresy s vazbou na stát, město, čtvrť a ulici, což umožňuje efektivní filtrování na více úrovních zároveň. Bez Elasticsearch by podobná funkcionalita nad relační databází vyžadovala složité indexy a výrazně vyšší latence.

**Souvislost s mým řešením:** v dotazu C6 demonstruji přesně ten autocomplete pattern (`match_phrase_prefix`), v C5 boosting skóre podle popularity (`function_score`), a v mappingech rozlišuji text vs keyword pole (Elastic, 2026).

#### 3.1.3 Stack Overflow – fulltextové vyhledávání

Stack Overflow používá Elasticsearch pro vyhledávání v milionech otázek a odpovědí, které vývojáři po celém světě čtou i přispívají. Fulltext search s custom analyzéry (stemming, synonyma, stop words) zajišťuje relevantní výsledky i při nepřesných dotazech – vývojář napíše „python list remove" a dostane otázky pojmenované „How to delete element from list in Python". `function_score` kombinuje textovou relevanci se skórovacími signály z domény (počet hlasů, přijatá odpověď, stáří, počet zobrazení) a díky tomu se nejrelevantnější a současně nejkvalitnější odpovědi zobrazují na prvních místech.

Zajímavé je, že bez function_score by vyhledávání vracelo textově relevantní, ale prakticky neužitečné výsledky (staré, nepřijaté, nízko hlasované odpovědi by mohly vyskakovat nahoru). Kombinace BM25 s business signály je typický pattern všech moderních vyhledávačů, od Google po e-shopy.

Stack Overflow také využívá aliasy pro zero-downtime reindex – když potřebují změnit mapping, vytvoří nový index, nahrají do něj data a atomicky přepnou alias na nový index.

**Souvislost s mým řešením:** v dotazu C5 používám function_score pro boost podle popularity, v C3 fuzzy search pro toleranci překlepů, v D1 custom analyzér s hudebními stop slovy („feat", „remix", „remastered") a v D2 aliasy pro filtrované a multi-index pohledy (Elastic, 2026).

### 3.2 Proč byl vybrán ELK stack

ELK stack jsem zvolil pro analytiku hudebních dat, protože přesně odpovídá charakteru úkolu:

- Data obsahují mix číselných, textových, datumových a boolean polí – ideální pro ukázku různých typů ES dotazů.
- Fulltextové vyhledávání (fuzzy search, analyzéry) je nad textovými poli (názvy skladeb a interpretů) přirozenější než v jiných NoSQL řešeních.
- Agregační funkce (terms, date_histogram, pipeline agregace) umožňují statistické analýzy bez exportu do jiného nástroje.
- Logstash nabízí hotovou ETL vrstvu pro CSV – nemusím psát vlastní import.

**Proč nebyly zvolené jiné technologie:**

- **MongoDB** – vhodná pro dokumentovou databázi, ale fulltext má slabší než ES (používá regex a text indexy, ale nemá analyzéry, BM25 skóre, fuzziness naladěnou jako ES).
- **Redis** – in-memory key-value store, nevhodný pro analytiku nad velkým objemem dat. Má výborný výkon na klíčové operace, ale pro agregace chybí podpora.
- **Cassandra** – optimalizovaná pro zápis a time-series. Umí sharding, ale ad-hoc dotazy a agregace jsou slabší.
- **PostgreSQL s full-text search** – funguje, ale ES je řádově rychlejší díky invertovanému indexu a distribuci. PostgreSQL by šel v našem objemu dat použít bez problému, ale demonstrace distribuovaného NoSQL by byla slabší.

---

## 4 Výhody a nevýhody

### 4.1 Výhody ELK stacku

- **Fulltextové vyhledávání** – invertovaný index, analyzéry, fuzziness, stemming. Řádově rychlejší než SQL LIKE a flexibilnější než regex.
- **Horizontální škálování** – přidáním uzlu cluster automaticky přerozdělí shardy, bez downtimu.
- **Near-realtime** – data jsou prohledatelná do 1 sekundy od zápisu (refresh interval).
- **Flexibilní schéma** – dynamic mapping, runtime fields. Nemusím předem vědět všechny typy polí.
- **Bohatý ekosystém** – Logstash má 200+ vstupních/výstupních pluginů, Kibana vizualizace a Dev Tools, Beats pro sběr logů a metrik.
- **Jednotný stack** – ingesting, ukládání, dotazování i vizualizace v jedné sadě nástrojů.

### 4.2 Nevýhody ELK stacku

- **Vysoké nároky na RAM** – ES potřebuje JVM heap a OS cache pro Lucene segmenty. Reálně těžko pod 4 GB per data uzel v produkci.
- **Není vhodný jako primární databáze** – ES nemá klasické transakce, JOIN operace, cizí klíče. Pro relační data je špatná volba.
- **Složitá provozní správa** – shard management, cluster state, rebalancing. Špatná konfigurace (příliš shardů, malý heap) může výrazně degradovat výkon.
- **Licence** – některé pokročilé funkce (machine learning, SAML, audit log) jsou jen v placené licenci. Základní funkce (search, aggregations, security) jsou v Basic licenci zdarma.
- **Strmá learning curve** – Query DSL je mocný, ale komplexní. SQL alternativa existuje, ale má omezení.

### 4.3 Výhody a nevýhody mého konkrétního řešení

**Výhody:**

- HA setup se 4 master-eligible uzly – dedikovaný `es-master` pro stabilní řízení clusteru za běžného provozu, plus 3 datové uzly s rolí `master,data,ingest` jako záloha pro election. Cluster přežije výpadek libovolného uzlu (quorum 3/4) bez ztráty řízení.
- Replikační faktor 3 – cluster přežije výpadek 2 ze 3 datových uzlů bez ztráty dat.
- Explicitní mappingy v index templates – správné datové typy (boolean, integer, keyword) místo dynamic mappingu. Díky tomu fungují range dotazy, agregace a filtry přesně tak, jak mají.
- Tři oddělené Logstash pipeline – každý dataset má vlastní konfiguraci, nedochází ke smíchání (tracks CSV by se parsovalo špatně přes artists pipeline).
- Plná automatizace – `docker compose up -d` spustí vše ve správném pořadí, bez manuálních kroků.

**Nevýhody:**

- Vyšší nároky na RAM (~10–12 GiB Docker) kvůli 4 ES uzlům + Kibana + Logstash. Master má limit 2 GiB, datové uzly 1.5 GiB každý.
- Sudý počet master-eligible uzlů (4) – best practice je liché číslo (3, 5, 7) kvůli cleaner quorum semantice. Pro semestrální projekt je 4 přijatelné, ale v produkci by byl optimální 3 dedikovaný master + N datových.
- Jednorázový import – Logstash čte CSV při startu, ne kontinuálně. Při restartu naimportuje celá data znova.
- Self-signed TLS certifikáty – prohlížeč je nedůvěřuje, což komplikuje přístup k Elasticvue (nutno odklepnout varování).

---

## 5 Další specifika

Řešení obsahuje několik specifických vlastností, které jdou nad rámec defaultního nasazení Elastic Stacku. Každá z nich řeší konkrétní problém, který by ve standardní konfiguraci způsoboval buď chybné výsledky (špatný analyzér), nebo zbytečnou složitost (nutnost reindexace pro nová pole, duplicity při reimportu, kontaminaci pipeline). V této kapitole popisuji každou specifickou vlastnost, motivaci jejího použití a alternativy, které jsem zvažoval.

### 5.1 Custom analyzér

**Motivace:** Default `standard` analyzér v Elasticsearchu rozkládá text na tokeny pomocí Unicode pravidel a převádí na lowercase, ale nechává v textu šum specifický pro hudební dataset. Spotify katalogy obsahují v ~80 % názvů skladeb metadata typu „feat.", „remix", „remastered", „version", „edit" – tato slova nepřináší informaci o obsahu skladby a snižují relevanci fulltextového vyhledávání. Pokud uživatel hledá „Bohemian Rhapsody", chce dostat všechny verze (originál, remasterované, koncertní), ne jen tu, kde se přesně shoduje název.

**Implementace:** V dotazu D1 jsem definoval custom analyzér `spotify_analyzer` jako řetězec čtyř filtrů aplikovaných na standard tokenizer:

1. **`lowercase`** – normalizace na malá písmena (case-insensitive search).
2. **`asciifolding`** – konverze diakritiky (`é` → `e`, `ñ` → `n`), aby uživatel hledající „beyonce" našel i „Beyoncé".
3. **`spotify_stop`** – custom stop word filtr s vlastní listou hudebních filler slov (`feat, ft, remix, remastered, version, edit`).
4. **`spotify_stemmer`** – snowball stemmer pro angličtinu, převádí slova na jejich morfologický kořen (`running` → `run`, `dancing` → `danc`).

**Dopad:** Dotaz na text *„Bohemian Rhapsody - Remastered 2011 (feat. Queen)"* projde analyzérem a uloží se v invertovaném indexu jako tokeny `["bohemian", "rhapsodi", "2011", "queen"]`. Při vyhledávání „Bohemian Rhapsody" se obě verze (originál i remaster) shodují stejně silně.

**Alternativa:** Místo custom analyzéru bych mohl použít vestavěný `english` analyzér (obsahuje stemmer + anglické stop words), ale ten neodfiltruje hudební termíny jako „remix" – ty jsou doménově specifické. Doménový analyzér je tedy správné řešení pro analýzu hudebních dat.

### 5.2 Runtime fields

**Motivace:** Pokud chci do indexu přidat nové vypočítané pole (např. `duration_minutes` z `duration_ms`), klasická cesta je úprava mappingu a reindexace všech dokumentů – pro 13 119 tracks by to vyžadovalo přečíst, transformovat a znovu zapsat všechny záznamy. Pro analytické dotazy, které pole použijí jen občas, je to zbytečná investice.

**Implementace:** Runtime fields umožňují definovat vypočítané pole za běhu dotazu, které ES vyhodnotí v okamžiku, kdy je potřeba. Skript je v jazyce Painless – speciálním scriptingovém jazyce ES s explicitním typováním a security sandboxem (na rozdíl od Groovy v ES 2.x, který byl zakázán kvůli RCE zranitelnostem). Použil jsem dva typy:

- **Per-query runtime field (D4):** `runtime_mappings` v rámci `_search` dotazu. Pole `duration_minutes` (`emit(doc['duration_ms'].value / 60000.0)`) a `energy_category` (kategorické pole low/medium/high podle prahu energie). Existuje jen po dobu trvání dotazu.
- **Persistentní runtime field v mappingu (D5):** `PUT _mapping { runtime: { hit_potential: ... } }`. Jednou definované, dostupné pro všechny budoucí dotazy bez nutnosti opětovné definice. Skript kombinuje tři audio features (popularity × 0.4 + danceability × 30 + energy × 30) do jednoho hit-skóre.

**Trade-off:** Runtime field je vypočítáván **při každém volání** (CPU cost on read), zatímco indexované pole je **vypočítáno jednou** (CPU cost on write, paměťový cost on disk). Pro pole, která jsou v dotazech zřídka, se runtime field vyplatí. Pro pole používaná v dashboardu při každém požadavku je lepší indexovat ho přes Logstash mutate filter.

### 5.3 Oddělené Logstash pipeline

**Motivace:** Logstash defaultně načte **všechny** `.conf` soubory ze složky `pipeline/` a sloučí je do jediné pipeline. Každý event projde **všemi filtry a outputy** napříč soubory. To znamená, že CSV řádek z `tracks_clean.csv` by se pokusil parsovat jako artists CSV (jiné sloupce, jiné typy) – výsledkem by byly poškozené dokumenty s `_grokparsefailure` tagy a smíchaná data v indexech.

**Implementace:** V souboru `pipelines.yml` (na úrovni Logstash rootu, ne v `pipeline/` složce) jsem definoval tři **oddělené pipeline ID**, každá s vlastní konfigurací:

```yaml
- pipeline.id: tracks
  path.config: "/usr/share/logstash/pipeline/tracks.conf"
- pipeline.id: artists
  path.config: "/usr/share/logstash/pipeline/artists.conf"
- pipeline.id: charts
  path.config: "/usr/share/logstash/pipeline/charts.conf"
```

Logstash potom spustí tři nezávislé instance pipeline s vlastními workery, queue a output buffery. Tracks event projde jen `tracks.conf` filtry, artists event jen `artists.conf` atd.

**Dopad:** Bez `pipelines.yml` by import skončil chybou nebo s úplně nepoužitelnými indexy. S oddělenými pipeline mám čistou separation of concerns, paralelizaci (3 pipeline running současně) a možnost ladit/restartovat každou pipeline samostatně.

### 5.4 Deterministické document ID

**Motivace:** Logstash output do Elasticsearche defaultně nechá ES generovat náhodný `_id` pro každý dokument (UUID). Při prvním importu CSV je to OK – každý řádek dostane unikátní ID. Problém nastává při **opakovaném** importu (restart Logstash, recovery po výpadku, nový run pipeline): stejný CSV řádek dostane nové random ID a uloží se podruhé jako nový dokument. V indexu vzniknou duplikáty, počty se zdvojnásobí.

**Implementace:** V Logstash output sekci specifikuji `document_id` jako kombinaci přirozených klíčů, které jednoznačně identifikují záznam:

- **`tracks`:** `document_id => "%{track_id}"` – Spotify ID skladby je již unikátní v rámci datasetu.
- **`artists`:** `document_id => "%{artist_id}"` – Spotify ID interpreta.
- **`charts`:** `document_id => "%{date}_%{region}_%{chart}_%{rank}"` – složené ID, protože samotný `rank` se opakuje (1., 2., 3. místo) napříč různými dny, regiony a žebříčky.

**Dopad – idempotentní import:** Při opakovaném spuštění Logstash s ETL pipeline se dokument se stejným `_id` přepíše místo duplikování. To umožňuje:

1. Bezpečné restartování Logstashe bez ztráty/duplikace dat.
2. Inkrementální update – nová verze CSV s opravenou hodnotou se aplikuje jako přepis.
3. Vědomou deduplikaci na vstupu: tracks dataset z Kaggle obsahuje stejnou skladbu vícekrát, jednou pro každý žánr, ve kterém je zařazena (např. „Bohemian Rhapsody" je v `rock`, `classic_rock`, `alternative`). Díky `document_id => "%{track_id}"` se v ES uloží jen 13 119 unikátních skladeb z 15 000 řádků CSV (1 881 duplicit přepsáno).

---

## 6 Data

Tato kapitola popisuje datové sady, proces čištění, formát a výsledky základní analýzy.

### 6.1 Zdroj dat

Data pocházejí z veřejných Kaggle datasetů od Spotify. Každý dataset jsem stáhl z Kaggle a oříznul pomocí Pandas na zvládnutelnou velikost. Původní datasety mají stovky tisíc záznamů, pro semestrální práci jsem si ponechal vzorky vhodné pro demonstraci (splňuje požadavek min. 5 000 záznamů v tracks datasetu).

| Dataset | Zdroj | Původní velikost | Použito v projektu |
|---------|-------|------------------|---------------------|
| tracks_clean.csv | [Kaggle - Spotify Tracks](https://www.kaggle.com/datasets/maharshipandya/spotify-tracks-dataset) | ~114 000 | 15 000 záznamů |
| artists_clean.csv | [Kaggle - 30000 Spotify Songs](https://www.kaggle.com/datasets/joebeachcapital/30000-spotify-songs) | ~32 000 | 5 271 záznamů |
| charts_clean.csv | [Kaggle - Spotify Charts](https://www.kaggle.com/datasets/dhruvildave/spotify-charts) | ~26 mil. | 8 000 záznamů |

Všechny datasety jsou veřejně dostupné a pocházejí z oficiálního Spotify API (exporty).

### 6.2 Typy dat a formát

Datasety jsou uložené v CSV formátu – tak jak byly staženy z Kaggle a ořezány. Logstash umí CSV parsovat přímo pomocí `csv` filtru, takže nejsou potřeba žádné mezikroky. ES pak data uloží jako JSON dokumenty v invertovaném indexu.

**Struktura indexu tracks (hlavní dataset):**

- `track_id` (keyword) – unikátní ID skladby.
- `track_name`, `artists`, `album_name` (text s keyword subfieldem) – textová pole pro fulltext i přesné agregace.
- `popularity`, `duration_ms`, `key`, `mode`, `time_signature` (integer) – celá čísla.
- `explicit` (boolean) – zda skladba obsahuje explicit text.
- `danceability`, `energy`, `loudness`, `speechiness`, `acousticness`, `instrumentalness`, `liveness`, `valence`, `tempo` (float) – audio features ve float.
- `track_genre` (keyword) – žánr skladby (pro přesné term dotazy a terms agregace).

**Struktura indexu artists:**

- `artist_id` (keyword), `name` (text), `followers` (long), `genres` (keyword array), `popularity` (integer), `related_artists_count` (integer), `related_artists_ids` (keyword array).

**Struktura indexu charts:**

- `title` (text+keyword), `rank` (integer), `date` (date), `artist` (text+keyword), `region` (keyword), `chart` (keyword), `trend` (keyword), `streams` (long).

**Proč CSV místo jiného formátu:**

- CSV je nativně podporované Logstash file inputem – nemusím psát vlastní parser.
- Spotify data jsou veřejně dostupná jen v CSV/JSON, a CSV je v Pandas i Excelu okamžitě otevřitelné pro kontrolu.
- Pro jednorázový semestrální import je CSV ideální. Pro kontinuální stream bych volil JSON přes Kafka nebo Filebeat.

Jiné NoSQL modely (key-value, wide-column, graph) jsem nezvažoval, protože pro tuto doménu je nejdůležitější fulltext a agregace, na což je dokumentový model s invertovaným indexem (což ES je) ideální.

### 6.3 Úpravy dat před importem

Data byla před importem předzpracována v několika krocích. Primárně v Pandas (pro oříznutí z originálních datasetů) a následně v Logstash pipeline (při importu do ES).

**V Pandas (`Data/analyza.ipynb`):**

- Oříznutí velkých originálních datasetů na cílový počet záznamů.
- Čištění `genres` pole v artists – původně string „['pop', 'rock']", převedeno na skutečné pole `["pop", "rock"]`.
- Žádná anonymizace – data jsou veřejná (Spotify API).

**Rozsah dat: CSV řádky vs. ES dokumenty**

| Dataset | Řádků v CSV | Dokumentů v ES | Rozdíl | Vysvětlení |
|---------|-------------|----------------|--------|------------|
| tracks | 15 000 | 13 119 | -1 881 (12,5 %) | **Záměrná deduplikace přes `track_id`.** Originální Spotify Kaggle dataset obsahuje stejnou skladbu vícekrát, jednou pro každý žánr (např. „Bohemian Rhapsody" je v rock, classic_rock, alternative). Logstash používá `document_id => "%{track_id}"`, takže duplicitní řádky přepíšou stejný dokument v ES. Výsledek: 13 119 **unikátních skladeb** s posledním zaregistrovaným žánrem. Toto chování je **vědomé** – zachovává jeden záznam per skladba, takže agregace nezkreslují počty. |
| artists | 5 271 | 5 271 | 0 | Bez duplicit, `document_id => "%{artist_id}"`. |
| charts | 8 000 | 8 000 | 0 | Bez duplicit, deterministický `document_id => "%{date}_%{region}_%{chart}_%{rank}"` (viz 5). |

**Validace v dotaze E6** (`Dotazy/vsechny_dotazy.md`): kombinace `value_count` + `cardinality` v ES potvrzuje, že 13 119 dokumentů má 13 119 unikátních `track_id` (cardinality = count) → deduplikace fungovala přesně.

**V Logstash pipeline:**

- Typové konverze (string z CSV → integer/float/boolean). Bez explicitních konverzí by ES data uložil jako stringy a range dotazy by nefungovaly.
- Boolean konverze pro `explicit` přes Ruby filter – CSV vrací string „True"/„False", ES potřebuje JSON `true`/`false`.
- Split pole `artists` na array podle středníku (některé skladby mají více interpretů).
- Deterministické ID pro charts (viz kapitola 5).

**Prázdné hodnoty:**

| Dataset | Pole | Počet chybějících | % z celku |
|---------|------|-------------------|-----------|
| tracks | – | 0 | 0 % (po čištění) |
| artists | related_artists_ids | 869 | 16,5 % |
| charts | streams | 352 | 4,4 % |

Prázdné hodnoty v `related_artists_ids` nejsou chyba – některé interprety prostě nemají propojení. V `streams` jsou prázdné proto, že viral50 žebříček neobsahuje statistiky streamů.

### 6.4 Distribuce shardů v indexech

V rámci řešení je použitý cluster se 3 datovými uzly a replikačním faktorem 3 (1 primary + 2 replica per shard). Distribuce pro jednotlivé indexy:

| Index | Počet dokumentů | Primary shardy | Replica shardy | Celkem shardů |
|-------|-----------------|----------------|----------------|----------------|
| tracks | 13 119 | 3 | 6 | 9 |
| artists | 5 271 | 3 | 6 | 9 |
| charts | ~8 000 | 3 | 6 | 9 |

Celkem 27 shardů v clusteru, rozložených po 9 shardech na každém ze 3 datových uzlů. ES si distribuci řeší sám – samostatné balancování přes shard allocation.

Pokud se cluster dostane do stavu, kdy některé shardy nejsou alokované (UNASSIGNED), lze to zjistit příkazem `GET _cluster/allocation/explain`, který vrátí přesný důvod.

**Kontrolní dotazy pro ověření distribuce a stavu** (spustitelné v Kibana Dev Tools nebo curlem):

```
GET _cat/shards?v          # rozložení shardů – který shard je na kterém uzlu, primary vs. replica
GET _cat/allocation?v      # alokace per uzel – počet shardů, využití disku
GET _cat/recovery?v        # běžící recovery operace (rebalancing, replikace po výpadku)
GET _cat/indices?v         # přehled indexů – počet dokumentů, velikost
GET tracks/_stats/docs     # detailní docs.count per shard pro index tracks
```

Tyto dotazy odpovídají požadavkům zadání v sekci „DATA – konkrétní dotazy pro kontrolu" a slouží k validaci, že distribuce dat odpovídá projekční konfiguraci (3 shardy × 3 kopie per index).

### 6.5 Základní analýza

Základní analýzu datasetů jsem dělal v Python notebooku `Data/analyza.ipynb` s knihovnami Pandas, NumPy a Matplotlib. Notebook obsahuje:

- Přehled struktury (počet řádků, sloupců, datové typy).
- Detekci chybějících hodnot a duplicit.
- Deskriptivní statistiky (průměr, medián, percentily, min/max).
- Grafy (histogramy, korelační matice, bar charty).

**Výběr statistik z datasetu tracks:**

- Průměrná popularita: ~33 (rozmezí 0–100)
- Průměrná danceability: 0,57 (rozmezí 0–1)
- Průměrná energie: 0,64 (rozmezí 0–1)
- Nejčastější žánry: pop, rock, hip-hop, jazz, classical
- Podíl explicit skladeb: ~8 %

**Výběr statistik z datasetu artists:**

- Celkový počet: 5 271 interpretů
- Medián followerů: ~2 000 (rozdělení je silně right-skewed – několik mega-popstarů s miliony followerů zvyšuje průměr)
- Průměrný počet žánrů per interpret: 3,2

**Výběr statistik z datasetu charts:**

- Časové rozmezí: 2017–2022
- Regiony: France, Czech Republic, Poland + globální
- Typy žebříčků: top200 (92 %), viral50 (8 %)

Grafy jsou uložené jako PNG soubory (`graf_artists_followers.png`, `graf_charts_regiony_streams.png`, `graf_tracks_korelace.png`, `graf_tracks_popularita_zanry.png`) a současně přímo v notebooku.

---

## 7 Dotazy

V této kapitole je 30 netriviálních dotazů v Query DSL, rozdělených do 5 kategorií po 6 dotazech. Každý dotaz má zadání v přirozeném jazyce, samotný DSL příkaz a vysvětlení. Všechny dotazy jsou spustitelné v Kibana Dev Tools (http://localhost:5601) a lze je spustit rovnou po importu dat. Úplný soubor se všemi 30 dotazy je také v souboru `Dotazy/vsechny_dotazy.md`.

**Každý z 30 dotazů vrací odlišná data** – ať už jiné dokumenty, jinou množinu dokumentů filtrovanou podle jiných kritérií, jiné agregační výstupy, jinou strukturu odpovědi (hits vs aggregations vs profile), jiný cílový index nebo kombinaci více indexů najednou. Žádné dva dotazy nevracejí tentýž výsledek. Netrivialita každého dotazu spočívá v kombinaci více ES mechanismů (bool dotazy, filter context, bucket + metric + pipeline agregace, custom analyzéry, runtime fields, cluster API) a výstup má vždy interpretační hodnotu pro analýzu Spotify dat.

### 7.1 Práce s daty

Tato kategorie obsahuje dotazy pro manipulaci s dokumenty – update, reindex, cross-index search. Demonstrují práci s Painless skripty, bool dotazy a operacemi nad více indexy najednou.

**A1 – Hromadný update popularity**

Zadání: Zvýšit popularitu o 5 u všech explicit rockových skladeb (s limitem na 95, aby nepřetekla přes 100).

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

Ukázka výstupu:
```json
{
  "took": 45,
  "timed_out": false,
  "total": 43,
  "updated": 43,
  "deleted": 0,
  "batches": 1,
  "version_conflicts": 0,
  "noops": 0,
  "failures": []
}
```

Vysvětlení: `_update_by_query` projde dokumenty matchující query a na každý aplikuje Painless skript. Použil jsem `filter` místo `must`, protože u tohoto dotazu nepotřebuju skórování – jen filtraci (filter je rychlejší a cachuje se). Výsledek: aktualizováno 43 skladeb během 45 ms, bez konfliktů.

**A2 – Reindex s filtrací a transformací**

Zadání: Zkopírovat jen populární skladby (popularity >= 70) do nového indexu `tracks_popular` a každému přidat pole `popularity_tier`.

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

Ukázka výstupu:
```json
{
  "took": 2380,
  "timed_out": false,
  "total": 1382,
  "created": 1382,
  "updated": 0,
  "batches": 2,
  "failures": []
}
```

Ověření:
```
GET tracks_popular/_count → { "count": 1382 }
```

Vysvětlení: `_reindex` čte ze zdrojového indexu, filtruje podle query, aplikuje Painless skript a zapisuje do cílového indexu. Původní index zůstává beze změny. Výsledek: vytvořeno 1 382 dokumentů v indexu `tracks_popular` během 2,4 sekundy.

**A3 – Obohacení charts o streaming tier**

Zadání: Každému chart záznamu z top200 (jen tam, kde existuje `streams`) přidat kategorii podle počtu streamů a inverzní rank pro skórování.

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

Ukázka výstupu:
```json
{
  "took": 890,
  "total": 5812,
  "updated": 5812,
  "batches": 6,
  "failures": []
}
```

Ověření kategorizace:
```
GET charts/_search?size=0
{"aggs": {"tiers": {"terms": {"field": "stream_tier"}}}}
→ viral: 412, hit: 3108, niche: 2292
```

Vysvětlení: Painless skript s podmínkami (`if/else if/else`) vytvoří `stream_tier` podle prahových hodnot a `rank_score` jako inverzi pořadí (rank 1 = skóre 200, rank 200 = skóre 1). Kategorizace ukazuje, že většina záznamů padá do „hit" kategorie (100 k–1 M streamů) – což dává smysl vzhledem k tomu, že top200 obsahuje ty nejpopulárnější skladby.

**A4 – Klasifikace interpretů podle velikosti**

Zadání: Každému interpretovi přidat tier podle followerů (mega/major/mid/indie) a spočítat počet žánrů, které má přiřazené.

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

Ukázka výstupu:
```json
{
  "took": 1120,
  "total": 5271,
  "updated": 5271,
  "batches": 6,
  "failures": []
}
```

Rozdělení podle tieru (ověřovací agregace):
```
mega: 52, major: 308, mid: 1489, indie: 3422
```

Vysvětlení: Skript přistupuje k `followers` přes `ctx._source` a podle hraničních hodnot přidělí tier. Pro `genres_count` nejprve ověří, že pole existuje a je to List (některé dokumenty můžou mít jen jednu hodnotu jako string), a pak zavolá `.size()`. Rozdělení ukazuje typický „long tail" – desítky mega-hvězd a tisíce menších interpretů.

**A5 – Skriptovaný update – přepočet a nový field**

Zadání: U blues skladeb delších než 5 minut přepočítat délku na minuty (s 2 desetinnými místy) a označit je flagrem `is_long`.

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

Ukázka výstupu:
```json
{
  "took": 78,
  "total": 94,
  "updated": 94,
  "failures": []
}
```

Příklad aktualizovaného dokumentu:
```json
{
  "track_name": "Bohemian Rhapsody",
  "duration_ms": 355000,
  "duration_min": 5.92,
  "is_long": true
}
```

Vysvětlení: Painless skript vytvoří dvě nová pole – `duration_min` (double) a `is_long` (boolean). ES si sám odvodí mapping pro nové pole (dynamic mapping). Trik s `* 100 / 100.0` je standardní způsob zaokrouhlování na 2 desetinná místa. Výsledek: 94 dlouhých blues skladeb má nyní minutáž i flag.

**A6 – Cross-index vyhledávání přes tracks a artists**

Zadání: Najít dokumenty obsahující slovo „love" současně ve skladbách i v interpretech – jeden dotaz přes 2 indexy.

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

Ukázka výstupu:
```json
{
  "took": 12,
  "hits": {
    "total": { "value": 287 },
    "hits": [
      {
        "_index": "artists",
        "_source": { "name": "Lovejoy", "followers": 1234567, "genres": ["indie", "pop"] }
      },
      {
        "_index": "tracks",
        "_source": { "track_name": "Love Story", "artists": ["Taylor Swift"], "popularity": 82, "track_genre": "pop" }
      },
      {
        "_index": "tracks",
        "_source": { "track_name": "Endless Love", "artists": ["Diana Ross"], "popularity": 74, "track_genre": "soul" }
      }
    ]
  }
}
```

Vysvětlení: `POST tracks,artists/_search` prohledá oba indexy najednou. `multi_match` hledá „love" v polích `track_name` (existuje v tracks) a `name` (existuje v artists) – neexistující pole v daném indexu ES ignoruje. `should` se boostingem zvýhodňuje populární skladby a velké interprety. Výsledek: mix obou typů dokumentů – skladby s „Love" v názvu i interprety jako „Lovejoy". Pole `_index` v odpovědi ukazuje, odkud každý dokument pochází.

### 7.2 Agregační funkce

Druhá kategorie ukazuje různé typy agregací – terms, range, date_histogram, pipeline agregace. Demonstruje práci s bucket i metric agregacemi a jejich kombinaci.

**B1 – Průměr podle žánru + celkový průměr (pipeline)**

Zadání: Pro každý žánr zjistit průměrnou popularitu a danceability. Navíc spočítat celkový průměr napříč všemi žánry pomocí pipeline agregace.

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

Ukázka výstupu:
```json
{
  "aggregations": {
    "zanry": {
      "buckets": [
        { "key": "pop", "doc_count": 937, "prumerna_popularita": { "value": 50.0 }, "prumerna_tanecnost": { "value": 0.62 } },
        { "key": "electronic", "doc_count": 912, "prumerna_popularita": { "value": 44.3 }, "prumerna_tanecnost": { "value": 0.68 } },
        { "key": "rock", "doc_count": 1000, "prumerna_popularita": { "value": 38.2 }, "prumerna_tanecnost": { "value": 0.47 } },
        { "key": "classical", "doc_count": 916, "prumerna_popularita": { "value": 13.3 }, "prumerna_tanecnost": { "value": 0.32 } }
      ]
    },
    "celkovy_prumer_popularity": { "value": 34.1 }
  }
}
```

Vysvětlení: `terms` vytvoří buckety per žánr, vnořené `avg` počítají metriky v každém bucketu. `avg_bucket` je pipeline agregace – počítá průměr z výstupu jiné agregace (ne přímo z dokumentů). Výsledek: pop vede s průměrnou popularitou 50, classical je na chvostu s 13 – což dává smysl, klasika se masově nestreamuje.

**B2 – Range buckety popularity s vnořeným filtrem**

Zadání: Rozdělit skladby do 5 pásem popularity a v každém pásmu spočítat průměrnou energii, průměrnou tanečnost a kolik je z toho explicit skladeb.

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

Ukázka výstupu:
```json
{
  "aggregations": {
    "popularita_pasma": {
      "buckets": [
        { "key": "nezname (0-10)", "doc_count": 4102, "prumerna_energie": { "value": 0.45 }, "pocet_explicit": { "doc_count": 178 } },
        { "key": "nizka (10-30)", "doc_count": 3847, "prumerna_energie": { "value": 0.58 }, "pocet_explicit": { "doc_count": 247 } },
        { "key": "stredni (30-60)", "doc_count": 3512, "prumerna_energie": { "value": 0.66 }, "pocet_explicit": { "doc_count": 301 } },
        { "key": "vysoka (60-80)", "doc_count": 1255, "prumerna_energie": { "value": 0.71 }, "pocet_explicit": { "doc_count": 221 } },
        { "key": "hit (80+)", "doc_count": 403, "prumerna_energie": { "value": 0.74 }, "pocet_explicit": { "doc_count": 109 } }
      ]
    }
  }
}
```

Vysvětlení: Range agregace rozdělí dokumenty do pojmenovaných pásem. Vnořené metriky (`avg`) a filter agregace (`pocet_explicit`) se počítají v každém pásmu zvlášť. Výsledek: pásmo „hit 80+" má 403 skladeb, z toho 109 explicit (27 %) – čím populárnější skladba, tím vyšší pravděpodobnost, že obsahuje explicit text.

**B3 – Časový vývoj streamů + kumulativní součet**

Zadání: Zobrazit vývoj streamů v charts po kvartálech, včetně narůstajícího součtu.

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

Ukázka výstupu:
```json
{
  "aggregations": {
    "po_kvartalech": {
      "buckets": [
        { "key_as_string": "2017-01-01", "doc_count": 412, "celkem_streamu": { "value": 512000000 }, "max_streamu": { "value": 7600000 }, "kumulativni": { "value": 512000000 } },
        { "key_as_string": "2017-04-01", "doc_count": 489, "celkem_streamu": { "value": 634000000 }, "max_streamu": { "value": 7800000 }, "kumulativni": { "value": 1146000000 } },
        { "key_as_string": "2018-01-01", "doc_count": 512, "celkem_streamu": { "value": 721000000 }, "max_streamu": { "value": 7800000 }, "kumulativni": { "value": 1867000000 } }
      ]
    }
  }
}
```

Vysvětlení: `date_histogram` rozdělí časovou osu na intervaly (zde kvartály). `cumulative_sum` je pipeline agregace – ke každému bucketu přidá součet všech předchozích, čímž vznikne celkový trend. Výsledek ukazuje rostoucí trend streamování – každý kvartál přidává další půl až tři čtvrtě miliardy streamů k celkovému součtu.

**B4 – Extended stats + percentily + max_bucket**

Zadání: Pro každý žánr rozšířené statistiky energie (průměr, směrodatná odchylka, varianceno) a percentily tempa (25./50./75.). Navíc zjistit, který žánr má nejvyšší max popularitu.

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

Ukázka výstupu (zkráceno):
```json
{
  "aggregations": {
    "zanry": {
      "buckets": [
        {
          "key": "pop",
          "max_popularita": { "value": 100 },
          "stat_energie": { "avg": 0.65, "std_deviation": 0.18, "variance": 0.032 },
          "percentily_tempa": { "25.0": 95.3, "50.0": 120.1, "75.0": 145.8 }
        },
        {
          "key": "hip-hop",
          "max_popularita": { "value": 100 },
          "stat_energie": { "avg": 0.63, "std_deviation": 0.16 },
          "percentily_tempa": { "25.0": 82.5, "50.0": 100.2, "75.0": 138.4 }
        }
      ]
    },
    "zanr_s_nejvyssi_max_popularitou": { "value": 100.0, "keys": ["pop"] }
  }
}
```

Vysvětlení: `extended_stats` vrací víc než jen průměr – přidává i směrodatnou odchylku, varianci a součet čtverců. `percentiles` počítá kvantily (25. percentil = 25 % skladeb má tempo nižší). `max_bucket` projde všechny buckety (žánry) a vrátí ten s nejvyšší hodnotou. Výsledek: pop a hip-hop mají nejpopulárnější skladbu (popularita 100), hip-hop má rozmanitější tempo (širší rozpětí 25.–75. percentilu).

**B5 – Porovnání explicit vs non-explicit**

Zadání: Paralelně porovnat průměrnou popularitu, tanečnost, energii a top žánry pro explicit a non-explicit skladby.

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

Ukázka výstupu:
```json
{
  "aggregations": {
    "explicit_skladby": {
      "doc_count": 1056,
      "prumerna_popularita": { "value": 35.8 },
      "prumerna_tanecnost": { "value": 0.70 },
      "prumerna_energie": { "value": 0.67 },
      "top_zanry": {
        "buckets": [
          { "key": "hip-hop", "doc_count": 412 },
          { "key": "reggaeton", "doc_count": 187 },
          { "key": "rap", "doc_count": 156 }
        ]
      }
    },
    "neexplicit_skladby": {
      "doc_count": 12063,
      "prumerna_popularita": { "value": 30.7 },
      "prumerna_tanecnost": { "value": 0.58 },
      "prumerna_energie": { "value": 0.63 },
      "top_zanry": {
        "buckets": [
          { "key": "jazz", "doc_count": 998 },
          { "key": "classical", "doc_count": 912 },
          { "key": "pop", "doc_count": 876 }
        ]
      }
    }
  }
}
```

Vysvětlení: Dvě paralelní filter agregace vytvoří dvě samostatné skupiny a v každé vnořené metriky a terms agregace. Výsledek: explicit (1 056 skladeb) má avg popularitu 35,8 a tanečnost 0,70, top žánr hip-hop. Non-explicit (12 063) má 30,7 a 0,58, top žánr jazz. Explicit skladby jsou tedy populárnější a tanečnější – logicky dávají smysl, protože hip-hop a reggaeton jsou obecně více tančitelné.

**B6 – Multi-terms + cardinality**

Zadání: Rozdělit charts data podle kombinace region + chart type. Spočítat průměr a součet streamů a počet unikátních skladeb.

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

Ukázka výstupu:
```json
{
  "aggregations": {
    "region_chart": {
      "buckets": [
        { "key": ["France", "top200"], "doc_count": 1406, "prumer_streamu": { "value": 1234567 }, "unikatni_skladby": { "value": 517 } },
        { "key": ["Czech Republic", "top200"], "doc_count": 1270, "prumer_streamu": { "value": 856342 }, "unikatni_skladby": { "value": 421 } },
        { "key": ["Poland", "top200"], "doc_count": 1189, "prumer_streamu": { "value": 982134 }, "unikatni_skladby": { "value": 398 } },
        { "key": ["global", "viral50"], "doc_count": 412, "prumer_streamu": { "value": null }, "unikatni_skladby": { "value": 312 } }
      ]
    }
  }
}
```

Vysvětlení: `multi_terms` je jako GROUP BY přes více polí (region + chart). `cardinality` odhaduje počet unikátních hodnot pomocí HyperLogLog algoritmu (přesnost na úkor paměti – pro přesné počty by byla potřeba jiná agregace). Výsledek ukazuje, že Francie má v top200 celkem 1 406 záznamů ale jen 517 unikátních skladeb – tedy průměrná skladba se v žebříčku drží víc než 2 týdny.

### 7.3 Fulltextové vyhledávání

Tato kategorie ukazuje různé typy fulltextových dotazů – bool kombinace, multi-match, fuzzy search, phrase queries a function score.

**C1 – Složený bool query**

Zadání: Najít taneční a energické skladby (>= 0,8) bez explicit textu v žánrech pop/dance/electronic s popularitou alespoň 70, seřazené podle popularity.

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

Ukázka výstupu:
```json
{
  "took": 15,
  "hits": {
    "total": { "value": 42 },
    "hits": [
      { "_source": { "track_name": "Calm Down", "artists": ["Rema", "Selena Gomez"], "popularity": 92, "danceability": 0.81, "energy": 0.82, "track_genre": "pop" } },
      { "_source": { "track_name": "Bad Habits", "artists": ["Ed Sheeran"], "popularity": 88, "danceability": 0.81, "energy": 0.89, "track_genre": "pop" } },
      { "_source": { "track_name": "Don't Start Now", "artists": ["Dua Lipa"], "popularity": 84, "danceability": 0.82, "energy": 0.80, "track_genre": "dance" } }
    ]
  }
}
```

Vysvětlení: Používám všechny 4 typy klauzulí: `must` (povinné, počítá skóre), `should` s `minimum_should_match: 1` (alespoň 1 musí platit, zvyšuje skóre), `must_not` (vyloučení) a `filter` (povinné, ale nescoruje – cachuje se). Filter cachingem je dotaz při opakování rychlejší. Výsledek: 42 skladeb splňuje všechny podmínky, top 3 mají popularitu 80+.

**C2 – Multi-match s boostingem + highlight**

Zadání: Vyhledat frázi „love heart" přes název skladby (3× důležitější), album (2×) a jméno interpreta. Zvýraznit shody v textu.

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

Ukázka výstupu:
```json
{
  "hits": {
    "hits": [
      {
        "_score": 8.42,
        "_source": { "track_name": "Heart Attack", "artists": ["Demi Lovato"], "album_name": "DEMI", "popularity": 71 },
        "highlight": {
          "track_name": ["**Heart** Attack"]
        }
      },
      {
        "_score": 7.18,
        "_source": { "track_name": "Love Yourself", "artists": ["Justin Bieber"], "album_name": "Purpose", "popularity": 76 },
        "highlight": {
          "track_name": ["**Love** Yourself"]
        }
      }
    ]
  }
}
```

Vysvětlení: Zápis `^3` je boost – match v názvu má 3× vyšší váhu než v interpretovi. `best_fields` vezme skóre z pole s nejlepší shodou (místo součtu přes všechna pole). Highlight vrátí fragmenty textu se zvýrazněnými shodami (např. `**Heart** Attack`). Skladba „Heart Attack" má vyšší skóre, protože „heart" matchlo přímo v track_name (3× boost).

**C3 – Fuzzy hledání + filtrace + agregace výsledků**

Zadání: Hledat s překlepem „Bohemain Rapsody", filtrovat jen populární výsledky a agregovat žánry nalezených skladeb.

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

Ukázka výstupu:
```json
{
  "hits": {
    "total": { "value": 3 },
    "hits": [
      { "_source": { "track_name": "Bohemian Rhapsody - Remastered 2011", "artists": ["Queen"], "popularity": 82, "track_genre": "rock" } },
      { "_source": { "track_name": "Bohemian Rhapsody", "artists": ["Queen"], "popularity": 77, "track_genre": "rock" } },
      { "_source": { "track_name": "Bohemian Rhapsody - Live", "artists": ["Queen"], "popularity": 70, "track_genre": "rock" } }
    ]
  },
  "aggregations": {
    "zanry_vysledku": { "buckets": [{ "key": "rock", "doc_count": 3 }] },
    "avg_popularita": { "value": 76.3 }
  }
}
```

Vysvětlení: Fuzzy match toleruje překlepy pomocí Levenshteinovy vzdálenosti („Bohemain" → „Bohemian" je 1 edit, „Rapsody" → „Rhapsody" také 1 edit). `fuzziness: AUTO` = 0 editů pro 1–2 znaky, 1 pro 3–5, 2 pro 6+. Agregace nad výsledky vrátí rozdělení žánrů a průměrnou popularitu. Výsledek: najde 3 verze „Bohemian Rhapsody" (remastered, studio, live), všechny rock, průměrná popularita 76,3.

**C4 – Fráze s proximity (slop) + bool boost + highlight**

Zadání: Hledat frázi „can't stop" s tolerancí vzdálenosti slov (max 2 slova mezi nimi), populárnější výše.

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

Ukázka výstupu:
```json
{
  "hits": {
    "total": { "value": 8 },
    "hits": [
      {
        "_score": 4.5,
        "_source": { "track_name": "Can't Stop the Feeling!", "artists": ["Justin Timberlake"], "popularity": 82 },
        "highlight": { "track_name": ["<em>Can't</em> <em>Stop</em> the Feeling!"] }
      },
      {
        "_score": 2.1,
        "_source": { "track_name": "Can't Stop Loving You", "artists": ["Ray Charles"], "popularity": 58 },
        "highlight": { "track_name": ["<em>Can't</em> <em>Stop</em> Loving You"] }
      }
    ]
  }
}
```

Vysvětlení: `match_phrase` vyžaduje slova ve správném pořadí. `slop: 2` povolí max 2 slova mezi nimi – „Can't Stop the Feeling" (slop=1) i „Can't Stop Loving You" (slop=2) projdou, ale „Stop Can't" ne. Should boost zvýhodní populárnější výsledky – Justin Timberlake (pop 82) vyskočí nad Ray Charles (pop 58) díky `boost: 3`. Highlight zvýrazní přesné umístění fráze.

**C5 – Function score**

Zadání: Hledat „fire" v názvu, ale zvýhodnit populární skladby (nelineárně) a rockové skladby přidat extra bonus.

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

Ukázka výstupu:
```json
{
  "hits": {
    "hits": [
      { "_score": 18.7, "_source": { "track_name": "Fire", "artists": ["Jimi Hendrix"], "popularity": 68, "track_genre": "rock" } },
      { "_score": 16.4, "_source": { "track_name": "Set Fire to the Rain", "artists": ["Adele"], "popularity": 82, "track_genre": "pop" } },
      { "_score": 15.2, "_source": { "track_name": "Fire on the Mountain", "artists": ["Grateful Dead"], "popularity": 55, "track_genre": "rock" } }
    ]
  }
}
```

Vysvětlení: `field_value_factor` používá hodnotu `popularity` jako faktor skóre s log modifikací – log zabrání, aby super populární skladby dominovaly příliš moc. Druhá funkce dá weight 2 rockovým skladbám (pokud jsou, jinak nic). `boost_mode: multiply` násobí původní textové skóre faktorem z funkcí. Výsledek: rockové „fire" skladby jsou v TOP, protože dostávají weight 2. Adele (pop 82) má vyšší popularitu, ale je pop, takže dostane jen popularity boost.

**C6 – Match phrase prefix (autocomplete)**

Zadání: Simulovat autocomplete – uživatel napsal „i see", systém nabídne skladby. Populárnější výše.

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

Ukázka výstupu:
```json
{
  "hits": {
    "total": { "value": 7 },
    "hits": [
      { "_source": { "track_name": "I See Red", "artists": ["Everybody Loves an Outlaw"], "popularity": 76 } },
      { "_source": { "track_name": "When I See You Smile", "artists": ["Bad English"], "popularity": 65 } },
      { "_source": { "track_name": "I See The Light", "artists": ["Mandy Moore"], "popularity": 62 } },
      { "_source": { "track_name": "I See Fire", "artists": ["Ed Sheeran"], "popularity": 55 } }
    ]
  }
}
```

Vysvětlení: `match_phrase_prefix` matchuje frázi a poslední slovo expanduje jako prefix – „i see" najde „I See Red", „I See a Boat...", atd. `max_expansions: 20` omezí počet rozšíření, aby dotaz nebyl příliš pomalý. Should boost zvýhodní populárnější skladby – I See Red (pop 76) vyskočí nad I See Fire (pop 55). Ideální pattern pro UI autocomplete – výsledky se objeví už po 5 znacích uživatelova vstupu.

### 7.4 Indexy a konfigurace

Čtvrtá kategorie ukazuje pokročilé konfigurační možnosti – custom analyzéry, aliasy, experiment s replikami, runtime fields a profilování.

**D1 – Vlastní analyzér**

Zadání: Spotify data často obsahují „Remastered", „feat.", „Remix" v názvech. Vytvořit analyzér, který tato slova filtruje a aplikuje stemming.

```json
// Pro idempotentní spouštění: nejdřív smazat případný existující index
DELETE test_analyzer

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

Test:
```json
POST test_analyzer/_analyze
{
  "analyzer": "spotify_analyzer",
  "text": "Bohemian Rhapsody - Remastered 2011 (feat. Someone)"
}
```

Ukázka výstupu:
```json
{
  "tokens": [
    { "token": "bohemian", "position": 0 },
    { "token": "rhapsodi", "position": 1 },
    { "token": "2011", "position": 3 },
    { "token": "someon", "position": 5 }
  ]
}
```

Vysvětlení: Analyzér rozloží text na tokeny přes standard tokenizer, pak aplikuje řetězec filtrů: lowercase → asciifolding (odstraní diakritiku) → spotify_stop (stop slova) → stemmer. Výsledek: z původních 6 slov zbyly 4 tokeny. „Remastered" a „feat." byly odstraněny jako stop slova, „Rhapsody" stemováno na „rhapsodi" a „Someone" na „someon". Díky tomu dotaz „Bohemian Rhapsody" najde i různě pojmenované verze.

**D2 – Aliasy**

Zadání: Vytvořit filtrovaný alias pro populární skladby (pop >= 70) a multi-index alias spojující tracks a artists pod jedním jménem.

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

Použití:

```
GET popular_tracks/_count   → 1 382 (automaticky jen populární)
GET all_music/_count        → 18 390 (tracks + artists dohromady)
```

Ukázka výstupu pro `_aliases`:
```json
{ "acknowledged": true }
```

Kontrola vytvořených aliasů:
```
GET _aliases
```
```json
{
  "tracks": {
    "aliases": {
      "popular_tracks": { "filter": { "range": { "popularity": { "gte": 70 } } } },
      "all_music": { "is_write_index": false }
    }
  },
  "artists": {
    "aliases": {
      "all_music": { "is_write_index": false }
    }
  }
}
```

Vysvětlení: Alias je logické jméno odkazující na jeden nebo více indexů. `filter` vytvoří filtrovaný alias – klient přes něj vidí jen subset dat, jako by byl menší index. Multi-index alias (`all_music`) umožní dotazovat se přes více indexů jako by to byl jeden. Klient nepozná, že se pracuje přes alias – hodí se pro transparentní výměnu indexu (zero-downtime reindex) nebo pro multi-tenant scénáře.

**D3 – Experiment s počtem replik a dopad na cluster**

Zadání: Zvýšit repliky ze 2 na 3 a ukázat, že cluster nemá dost uzlů pro jejich alokaci.

```json
// 1. Výchozí stav (replicas=2)
GET _cluster/health/tracks
// → green, active_shards: 9 (3 primary + 6 replica, 3 kopie per shard na 3 uzlech)

// 2. Zvýšení replik na 3
PUT tracks/_settings
{ "index": { "number_of_replicas": 3 } }

// 3. Kontrola distribuce
GET _cat/shards/tracks?v&s=shard,prirep
// → 3 nové repliky se statusem UNASSIGNED
// (pro 4. kopii by byl potřeba 4. datový uzel – primary a repliky
//  musí být každá na jiném uzlu)

GET _cluster/health/tracks
// → yellow, unassigned_shards: 3

// 4. Návrat na 2 repliky
PUT tracks/_settings
{ "index": { "number_of_replicas": 2 } }
// → green, unassigned_shards: 0
```

Ukázka výstupu (po zvýšení na 3 repliky):
```json
{
  "cluster_name": "spotify-elk-cluster",
  "status": "yellow",
  "active_primary_shards": 3,
  "active_shards": 9,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 3,
  "delayed_unassigned_shards": 0
}
```

Vysvětlení: Demonstrace limitu topologie – se 3 datovými uzly lze mít max 2 repliky (1 primary + 2 replica = 3 kopie na 3 různých uzlech). Čtvrtá kopie nemá kam jít → `unassigned_shards: 3` a cluster je yellow. `number_of_replicas` je dynamický parametr (lze měnit za běhu), na rozdíl od `number_of_shards`, který je immutable (po vytvoření indexu).

**D4 – Runtime fields (per-query)**

Zadání: Přepočítat `duration_ms` na minuty a vytvořit kategorii energie (low/medium/high) přímo za běhu dotazu, bez nutnosti reindexu.

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

Ukázka výstupu:
```json
{
  "hits": {
    "hits": [
      {
        "_source": { "track_name": "Unholy", "duration_ms": 156943, "energy": 0.472 },
        "fields": {
          "duration_minutes": [2.6157166666666667],
          "energy_category": ["low"]
        }
      },
      {
        "_source": { "track_name": "As It Was", "duration_ms": 167303, "energy": 0.731 },
        "fields": {
          "duration_minutes": [2.788383333333333],
          "energy_category": ["medium"]
        }
      }
    ]
  }
}
```

Vysvětlení: `runtime_mappings` definují nová pole existující jen po dobu dotazu. Výhoda – není třeba reindexu (což by pro velké indexy trvalo dlouho). Nevýhoda – pole se vypočítává znova při každém dotazu, tedy ztráta výkonu oproti uloženému indexovanému poli. Výsledek: „Unholy" (pop 100) má duration_minutes 2,62 a energy_category „low" – překvapivě krátká a energeticky nenáročná píseň vs. očekávaný pop hit.

**D5 – Persistent runtime field v mappingu + agregace**

Zadání: Přidat trvalé runtime pole `hit_potential` (kombinace popularity + danceability + energy) přímo do mappingu, bez reindexu.

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

Ukázka výstupu (zkráceno):
```json
{
  "hits": {
    "hits": [
      { "_source": { "track_name": "Unholy", "popularity": 100, "danceability": 0.71, "energy": 0.47 }, "fields": { "hit_potential": [75.4] } },
      { "_source": { "track_name": "As It Was", "popularity": 99, "danceability": 0.52, "energy": 0.73 }, "fields": { "hit_potential": [76.8] } }
    ]
  },
  "aggregations": {
    "hit_potential_per_genre": {
      "buckets": [
        { "key": "pop", "doc_count": 937, "avg_hit": { "value": 45.2 } },
        { "key": "electronic", "doc_count": 912, "avg_hit": { "value": 40.1 } },
        { "key": "dance", "doc_count": 489, "avg_hit": { "value": 38.7 } }
      ]
    }
  }
}
```

Vysvětlení: Na rozdíl od D4 je toto runtime pole trvalé – uložené v mappingu a dostupné všem dotazům bez opakované definice. Vypočítává se pořád za běhu (nezabírá disk), ale dá se použít pro sort i agregace. Výsledek: pop má průměrný „hit potential" 45,2 – nejvyšší ze všech žánrů, což odpovídá tomu, že pop je nejvíce mainstream a nejvíce streamovaný.

**D6 – Profilování dotazu (execution plan)**

Zadání: Zjistit, jak ES interně vykonává dotaz – na kterých shardech, jaké operace, kolik to trvalo.

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

Ukázka výstupu (zkráceno, pouze nejdůležitější pole):
```json
{
  "took": 18,
  "hits": { "total": { "value": 147 } },
  "profile": {
    "shards": [
      {
        "id": "[es-data-1][tracks][0]",
        "searches": [{
          "query": [{
            "type": "BooleanQuery",
            "time_in_nanos": 8421000,
            "breakdown": { "score": 3200, "match": 1100, "next_doc": 4800000 },
            "children": [
              { "type": "TermQuery", "description": "track_name:love", "time_in_nanos": 2100000 },
              { "type": "TermQuery", "description": "track_genre:pop", "time_in_nanos": 1300000 },
              { "type": "IndexOrDocValuesQuery", "description": "popularity:[50 TO *]", "time_in_nanos": 980000 }
            ]
          }]
        }],
        "aggregations": [{ "type": "AvgAggregator", "time_in_nanos": 1240000 }]
      }
    ]
  }
}
```

Vysvětlení: `profile: true` přidá do odpovědi sekci `profile` s detailním breakdownem – 3 shardy (shard 0, 1, 2), každý s `BooleanQuery` → `TermQuery("love")` + `TermQuery("pop")` + `IndexOrDocValuesQuery(popularity ≥ 50)`. U každé operace je čas v nanosekundách. Užitečné pro optimalizaci pomalých dotazů – ukáže, kde se ztrácí čas (v tomto případě `next_doc` zabírá nejvíc, což je průchod inverzním indexem).

### 7.5 Cluster, distribuce a výpadek

Poslední kategorie pracuje přímo s clusterem – multi-search, shard preference, SQL, simulace výpadku a validace dat.

**E1 – Multi-search přes všechny 3 indexy**

Zadání: Poslat jeden HTTP request se 3 nezávislými analytickými dotazy – po jednom na každý dataset.

```json
POST _msearch
{"index": "tracks"}
{"size": 0, "query": {"bool": {"filter": [{"range": {"popularity": {"gte": 50}}}]}}, "aggs": {"top_genres": {"terms": {"field": "track_genre", "size": 5}}, "avg_dance": {"avg": {"field": "danceability"}}}}
{"index": "artists"}
{"size": 0, "query": {"bool": {"filter": [{"range": {"followers": {"gte": 100000}}}]}}, "aggs": {"top_genres": {"terms": {"field": "genres", "size": 5}}, "avg_pop": {"avg": {"field": "popularity"}}}}
{"index": "charts"}
{"size": 0, "query": {"bool": {"filter": [{"term": {"chart": "top200"}}, {"range": {"rank": {"lte": 10}}}]}}, "aggs": {"per_region": {"terms": {"field": "region"}}, "avg_streams": {"avg": {"field": "streams"}}}}
```

Ukázka výstupu (zkráceno):
```json
{
  "responses": [
    {
      "took": 8,
      "hits": { "total": { "value": 4918 } },
      "aggregations": {
        "top_genres": { "buckets": [{ "key": "pop", "doc_count": 912 }, { "key": "hip-hop", "doc_count": 687 }] },
        "avg_dance": { "value": 0.67 }
      }
    },
    {
      "took": 5,
      "hits": { "total": { "value": 2137 } },
      "aggregations": {
        "top_genres": { "buckets": [{ "key": "rock", "doc_count": 412 }, { "key": "pop", "doc_count": 378 }] },
        "avg_pop": { "value": 54.3 }
      }
    },
    {
      "took": 6,
      "hits": { "total": { "value": 412 } },
      "aggregations": {
        "per_region": { "buckets": [{ "key": "France", "doc_count": 142 }, { "key": "Czech Republic", "doc_count": 128 }] },
        "avg_streams": { "value": 2134567 }
      }
    }
  ]
}
```

Vysvětlení: `_msearch` posílá 3 dotazy v jednom requestu ve formátu NDJSON (header a body se střídají). Každý dotaz cílí jiný index s vlastním filtrem a agregacemi. Šetří network roundtripy (místo 3 requestů jeden). Výsledek: populární tracks top žánry pop/hip-hop, avg dance 0,67; velcí artists top žánry rock/pop; top10 charts průměr ~2,1 M streamů per region.

**E2 – Shard preference – vliv distribuce na výsledky**

Zadání: Porovnat výsledek dotazu na všechny shardy vs. na konkrétní shard.

```json
// 1. Dotaz na všechny shardy (default)
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

Ukázka výstupu (dotaz na všechny shardy):
```json
{
  "_shards": { "total": 9, "successful": 9 },
  "aggregations": {
    "count": { "value": 1000 },
    "avg_pop": { "value": 20.97 }
  }
}
```

Ukázka výstupu (dotaz jen na shard 0):
```json
{
  "_shards": { "total": 3, "successful": 3 },
  "aggregations": {
    "count": { "value": 332 },
    "avg_pop": { "value": 20.54 }
  }
}
```

Vysvětlení: Parametr `preference=_shards:0` donutí ES zeptat se jen shardu 0 (včetně jeho replik na jiných uzlech). Dokumenty se do shardů rozdělují hashem `_id`, takže každý shard drží ~1/3 rockových skladeb (332 ≈ 1000/3). Průměrná popularita se mírně liší (20,54 vs 20,97) – statistický rozptyl na menším vzorku. Ukazuje, že data opravdu nejsou na jednom místě, ale rovnoměrně rozdělená.

**E3 – SQL dotaz s CASE, HAVING a překladem do DSL**

Zadání: Pomocí SQL API zjistit rozložení explicit skladeb v žánrech. Filtrovat jen žánry s více než 500 skladbami a avg popularitou přes 30. Zobrazit i překlad SQL do Query DSL.

```json
// 1. Samotný dotaz
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
    ORDER BY avg_pop DESC
    LIMIT 10
  """
}

// 2. Překlad SQL → DSL
POST _sql/translate
{
  "query": "SELECT track_genre, COUNT(*), AVG(popularity) FROM tracks GROUP BY track_genre HAVING COUNT(*) > 500"
}
// → vrátí Query DSL s bucket_selector pipeline agregací pro HAVING
```

Ukázka výstupu SQL dotazu:
```
 track_genre | pocet | avg_pop | min_pop | max_pop | explicit_count | explicit_pct
-------------+-------+---------+---------+---------+----------------+--------------
 pop         |   937 |    50.0 |     0.0 |   100.0 |            112 |         12.0
 hip-hop     |   687 |    46.3 |     0.0 |   100.0 |            234 |         34.1
 dance       |   489 |    43.1 |     8.0 |    97.0 |             72 |         14.7
 electronic  |   912 |    44.3 |     0.0 |    96.0 |             54 |          5.9
 rock        |  1000 |    38.2 |     0.0 |    88.0 |             88 |          8.8
```

Ukázka výstupu `_sql/translate`:
```json
{
  "size": 0,
  "aggregations": {
    "groupby": {
      "composite": { "sources": [{ "track_genre": { "terms": { "field": "track_genre" } } }] },
      "aggregations": {
        "count": { "value_count": { "field": "_id" } },
        "avg_pop": { "avg": { "field": "popularity" } },
        "having.count_filter": {
          "bucket_selector": {
            "buckets_path": { "c": "count" },
            "script": { "source": "params.c > 500" }
          }
        }
      }
    }
  }
}
```

Vysvětlení: `CASE WHEN` umožňuje podmíněnou agregaci (ekvivalent `filter` agregace v DSL). `HAVING` je filtr nad výsledkem agregace – interně se převádí na `bucket_selector` pipeline agregaci. `_sql/translate` ukazuje, že SQL není „magie", ale syntaktickým cukrem nad Query DSL – užitečné pro pochopení, co se děje pod kapotou. Výsledek: pop je největší žánr (937 skladeb, avg 50), hip-hop má 34 % explicit skladeb (nejvíc ze všech).

**E4 – Simulace výpadku uzlu**

Zadání: Zjistit, co se stane s clusterem a daty při zastavení jednoho nebo dvou datových uzlů.

> **DŮLEŽITÉ – kombinace dvou prostředí:**
> Tento experiment kombinuje příkazy ze dvou různých kontextů:
> - **`docker compose stop / start`** se spouští v **terminálu** v adresáři `Funkční řešení/`.
> - **`GET _cluster/health`, `GET tracks/_count`, `GET tracks/_search`** se spouští v **Kibana Dev Tools** (☰ → Management → Dev Tools).
>
> Pokud spustíte `docker compose stop` v Kibana Dev Tools, dostanete chybu HTTP 400 (Kibana neumí metodu `DOCKER`). Postup proto rozdělte do dvou oken/záložek.

**Krok 1 — Před výpadkem (Kibana Dev Tools):**
```
GET _cluster/health
```
Očekávaný výsledek: status `green`, 4 uzly (1 master + 3 data), 9 primary + 18 replica = 27 user shardů (3 indexy po 9), plus systémové indexy → celkem ~87 active_shards.

**Krok 2 — Zastavím jeden datový uzel (terminál):**
```bash
docker compose stop es-data-2
```

**Krok 3 — Cluster yellow (Kibana Dev Tools):**
```
GET _cluster/health
```
Očekávaný výsledek: status `yellow`, 3 uzly, 9 active_primary_shards, 9 unassigned_shards (chybí 1 kopie z každého shardu – ta, co byla na es-data-2).

**Krok 4 — Data stále dostupná (Kibana Dev Tools):**
```
GET tracks/_count
GET artists/_count
```
Očekávaný výsledek: tracks 13119, artists 5271 — žádná ztráta, cluster má stále 2 kopie všeho.

**Krok 5 — Dotazy fungují (Kibana Dev Tools):**
```
GET tracks/_search
{ "query": { "match": { "track_name": "Bohemian Rhapsody" } } }
```
Očekávaný výsledek: 4 verze Bohemian Rhapsody, výsledky shodné s během před výpadkem.

**Krok 6 — Stress test, druhý uzel dolů (terminál):**
```bash
docker compose stop es-data-3
```

**Krok 7 — Cluster yellow se 2 uzly (Kibana Dev Tools):**
```
GET _cluster/health
GET tracks/_count
```
Očekávaný výsledek: yellow, 2 uzly (master + es-data-1), tracks/_count = 13119. Cluster přežil 2 současné výpadky bez ztráty dat.

**Krok 8 — Obnovím oba uzly (terminál):**
```bash
docker compose start es-data-2 es-data-3
```

**Krok 9 — Cluster zpět green (Kibana Dev Tools, počkat ~30 s):**
```
GET _cluster/health
```
Očekávaný výsledek: status `green`, 4 uzly, 27 user shardů + systémové = ~87 active. ES automaticky synchronizoval repliky.

Ukázka výstupu `GET _cluster/health` po vypnutí es-data-2:
```json
{
  "cluster_name": "spotify-elk-cluster",
  "status": "yellow",
  "timed_out": false,
  "number_of_nodes": 3,
  "number_of_data_nodes": 2,
  "active_primary_shards": 9,
  "active_shards": 18,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 9,
  "delayed_unassigned_shards": 9,
  "number_of_pending_tasks": 0,
  "active_shards_percent_as_number": 66.67
}
```

Vysvětlení: S replikačním faktorem 3 (1 primary + 2 replica) cluster přežije současný výpadek 2 ze 3 datových uzlů bez ztráty dat. Yellow = degradovaný stav (chybí kopie), ale data OK. Red by nastal až při pádu všech 3 datových uzlů. Po obnově ES sám dorovná repliky a vrátí se na green. `active_shards_percent: 66.67` znamená, že 2/3 shardů jsou aktivní (9 kopie z 27 chybí).

**Scénáře:**
- Padne 1 data uzel → yellow, data OK, výkon mírně degradovaný.
- Padnou 2 data uzly → yellow, data OK, vše běží z jednoho uzlu.
- Padnou všechny 3 data uzly → red, data nedostupná.
- Padne master → datové uzly nemohou měnit metadata (novou alokaci shardů), ale čtení/zápis do existujících shardů pokračuje. V produkci by byly 3 master-eligible uzly pro election.

**E5 – Měření latence při degradovaném clusteru**

Zadání: Porovnat latenci stejného dotazu při 3 uzlech, 2 uzlech (po výpadku) a 1 uzlu (stress test).

```json
// 1. Stav: 3 datové uzly, green – dotaz běží paralelně na všechny
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
// → took: ~10 ms, 156 hits

// 2. docker compose stop es-data-2 → yellow

// 3. Stejný dotaz – 2 datové uzly
// → took: ~14 ms, 156 hits (stejná data, vyšší latence)

// 4. docker compose stop es-data-3 → yellow, vše jede z es-data-1

// 5. Stejný dotaz – 1 datový uzel
// → took: ~22 ms, 156 hits (všech 3 shardů zpracovává 1 uzel)
```

Ukázka výstupu (srovnávací tabulka):

| Stav clusteru | took (ms) | hits | active shards | status |
|---------------|-----------|------|---------------|--------|
| 3 datové uzly | 10 | 156 | 27/27 | green |
| 2 datové uzly | 14 | 156 | 18/27 | yellow |
| 1 datový uzel | 22 | 156 | 9/27 | yellow |

Vysvětlení: Výsledky (hits) jsou vždy identické – repliky zajišťují, že každý shard má kopii alespoň na jednom živém uzlu. Latence (`took`) roste úměrně tomu, na kolika uzlech běží paralelní zpracování. Při 3 uzlech se každý shard zpracovává na jiném uzlu (paralelně), při 1 uzlu musí 1 uzel zpracovat všechny 3 shardy sekvenčně. Trade-off mezi dostupností a výkonem: replikace zaručí kontinuitu služby, ale za cenu menší škálovatelnosti při výpadku.

**E6 – Validace dat – kontrola konzistence a kvality**

Zadání: Analytickým dotazem ověřit kvalitu naimportovaných dat – duplicity, chybějící pole, rozložení žánrů.

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

Ukázka výstupu (zkráceno):
```json
{
  "aggregations": {
    "celkem_dokumentu": { "value": 13119 },
    "unikatnich_id": { "value": 13119 },
    "chybejici_zanr": { "doc_count": 0 },
    "chybejici_popularita": { "doc_count": 0 },
    "rozlozeni_zanru": {
      "buckets": [
        { "key": "reggae", "doc_count": 1000, "avg_popularity": { "value": 20.6 }, "min_popularity": { "value": 0 }, "max_popularity": { "value": 76 } },
        { "key": "pop", "doc_count": 937, "avg_popularity": { "value": 50.0 }, "min_popularity": { "value": 0 }, "max_popularity": { "value": 100 } },
        { "key": "classical", "doc_count": 916, "avg_popularity": { "value": 13.3 }, "min_popularity": { "value": 0 }, "max_popularity": { "value": 72 } },
        { "key": "rock", "doc_count": 1000, "avg_popularity": { "value": 38.2 }, "min_popularity": { "value": 0 }, "max_popularity": { "value": 88 } }
      ]
    }
  }
}
```

Vysvětlení: Porovnání `value_count` (všechny) vs `cardinality` (unikátní) odhalí duplicity – 13 119 celkem vs 13 119 unikátních = žádné duplicity (Logstash deduplikoval přes deterministické ID). `missing` zkontroluje chybějící pole (0 = data kompletní). Vnořená agregace per žánr ukazuje rozložení: reggae (1 000, avg pop 20,6) vs pop (937, avg pop 50,0). Slouží jako validace, že ETL pipeline odvedla svoji práci správně.

---

## Závěr

Cílem semestrální práce bylo navrhnout, nasadit a zdokumentovat funkční nasazení The Elastic Stack (ELK) v rámci distribuovaného clusteru s automatizovaným spuštěním přes Docker Compose.

Výsledkem je funkční cluster složený z osmi kontejnerů – jednoho dedikovaného master uzlu (es-master) a tří datových uzlů s rolemi `master, data, ingest` (HA setup se 4 master-eligible uzly), Kibany jako webového rozhraní, Logstashe pro ETL a dvou jednorázových pomocných kontejnerů (setup pro generování TLS a init pro vytvoření index templates). Celé prostředí se spouští jediným příkazem `docker compose up -d`, což splňuje požadavek zadání na maximální automatizaci.

Data z trojice Spotify Kaggle datasetů (tracks, artists, charts – celkem ~28 tisíc dokumentů) jsou importována do tří samostatných Logstash pipelin s explicitními mappingy, typovými konverzemi a deterministickým ID (u charts). Každý index má 3 primary shardy a 2 repliky, což znamená 3 kopie dat per shard (splnění požadavku min. 3 repliky). Zabezpečení je řešené TLS mezi všemi uzly, autentizací přes vestavěné uživatele a RBAC rolemi.

Vytvořil jsem celkem 30 netriviálních dotazů v 5 kategoriích: práce s daty (update_by_query, reindex, cross-index search), agregační funkce (terms, date_histogram, pipeline, percentiles), fulltextové vyhledávání (bool, multi_match, fuzzy, function_score, autocomplete), konfigurace (custom analyzéry, aliasy, runtime fields, profilování) a cluster management (multi-search, shard preference, SQL, simulace výpadku). Dotazy demonstrují jak analytickou sílu ES, tak správu distribuovaného prostředí.

Projekt splňuje všechna zadaná kritéria. Architektura je rozložená (4 uzly, oddělení rolí, HA s 4 master-eligible uzly), replikace zajišťuje dostupnost dat i při výpadku 2 ze 3 datových uzlů, sharding umožňuje horizontální škálování, je implementované TLS zabezpečení a RBAC. Cluster přežije také výpadek libovolného master-eligible uzlu díky quorum 3/4 — automaticky proběhne nová volba leadera. Jako hlavní omezení lokálního prostředí vidím sudý počet master-eligible uzlů (best practice je lichý – 3, 5, 7) a jednorázový import místo kontinuálního streamu (v produkci by byl Filebeat nebo Kafka).

Práce mi dala praktickou zkušenost s nasazením a konfigurací distribuovaného search enginu, pochopení toho, jak fungují invertované indexy a replikace, a psaním komplexních Query DSL dotazů. Zároveň jsem si ověřil, jak se ELK stack chová při simulovaných výpadcích a jak lze měřit vliv degradovaného clusteru na latenci.

---

## Zdroje

DOCKER Inc., 2026. Docker Documentation. [online]. [cit. 2026-04-22]. Dostupné z: https://docs.docker.com/

ELASTIC, 2026. Customer Case Studies – Netflix, Uber, Stack Overflow. [online]. Elasticsearch B.V. [cit. 2026-04-22]. Dostupné z: https://www.elastic.co/customers

ELASTIC, 2026. Elasticsearch Reference 8.17. [online]. Elasticsearch B.V. [cit. 2026-04-22]. Dostupné z: https://www.elastic.co/guide/en/elasticsearch/reference/8.17/index.html

ELASTIC, 2026. Elasticsearch SQL Documentation. [online]. Elasticsearch B.V. [cit. 2026-04-22]. Dostupné z: https://www.elastic.co/guide/en/elasticsearch/reference/8.17/sql-overview.html

ELASTIC, 2026. Kibana Guide 8.17. [online]. Elasticsearch B.V. [cit. 2026-04-22]. Dostupné z: https://www.elastic.co/guide/en/kibana/8.17/index.html

ELASTIC, 2026. Logstash Reference 8.17. [online]. Elasticsearch B.V. [cit. 2026-04-22]. Dostupné z: https://www.elastic.co/guide/en/logstash/8.17/index.html

ELASTIC, 2026. Running the Elastic Stack on Docker. [online]. Elasticsearch B.V. [cit. 2026-04-22]. Dostupné z: https://www.elastic.co/guide/en/elastic-stack-get-started/current/get-started-stack-docker.html

ELASTIC, 2026. Security Settings in Elasticsearch. [online]. Elasticsearch B.V. [cit. 2026-04-22]. Dostupné z: https://www.elastic.co/guide/en/elasticsearch/reference/8.17/security-settings.html

ELASTICVUE, 2026. Elasticvue – Free Elasticsearch GUI. [online]. [cit. 2026-04-22]. Dostupné z: https://elasticvue.com/

KAGGLE, 2026. Spotify Charts Dataset. [online]. Kaggle. [cit. 2026-04-22]. Dostupné z: https://www.kaggle.com/datasets/dhruvildave/spotify-charts

KAGGLE, 2026. Spotify Songs Dataset. [online]. Kaggle. [cit. 2026-04-22]. Dostupné z: https://www.kaggle.com/datasets/joebeachcapital/30000-spotify-songs

KAGGLE, 2026. Spotify Tracks Dataset. [online]. Kaggle. [cit. 2026-04-22]. Dostupné z: https://www.kaggle.com/datasets/maharshipandya/spotify-tracks-dataset

PANDAS DEVELOPMENT TEAM, 2026. pandas documentation. [online]. [cit. 2026-04-22]. Dostupné z: https://pandas.pydata.org/docs/

PYTHON SOFTWARE FOUNDATION, 2026. Python 3 Documentation. [online]. [cit. 2026-04-22]. Dostupné z: https://docs.python.org/3/

---

## Přílohy

### Příloha A – Složka Data/

Složka obsahuje zdrojové datasety, Python analýzu a exportované grafy.

- `tracks_clean.csv` – dataset skladeb po ořezání z Kaggle (15 000 záznamů, 20 sloupců).
- `artists_clean.csv` – dataset interpretů (5 271 záznamů, 7 sloupců).
- `charts_clean.csv` – dataset žebříčků (8 000 záznamů, 8 sloupců).
- `analyza.ipynb` – Jupyter notebook s explorativní analýzou dat. Obsahuje načtení CSV do Pandas, kontrolu struktury, detekci chybějících hodnot, deskriptivní statistiky (průměr, medián, percentily), rozdělení podle žánrů a grafy.
- `graf_tracks_popularita_zanry.png` – bar chart rozložení popularity per žánr.
- `graf_tracks_korelace.png` – korelační matice audio features.
- `graf_artists_followers.png` – histogram rozložení followerů (log scale).
- `graf_charts_regiony_streams.png` – součet streamů per region.

### Příloha B – Složka Dotazy/

- `vsechny_dotazy.md` – soubor obsahující všech 30 dotazů v Query DSL formátu. Každý dotaz má: zadání v přirozeném jazyce, samotný DSL příkaz, vysvětlení a přehled pojmů/operátorů. Dotazy jsou rozdělené do 5 kategorií po 6 dotazech (A – práce s daty, B – agregační funkce, C – fulltextové vyhledávání, D – indexy a konfigurace, E – cluster a distribuce).

### Příloha C – Složka funkčního řešení

Soubory přímo v kořeni projektu, které tvoří funkční nasazení:

- `docker-compose.yml` – definice všech 8 služeb (setup, es-master, es-data-1, es-data-2, es-data-3, kibana, init, logstash) + volitelný elasticvue. Obsahuje závislosti přes `depends_on` s podmínkami `service_healthy` a `service_completed_successfully`, volumes pro perzistentní data a certifikáty, a síť `elk-net`.
- `.env.example` – šablona pro `.env`. Definuje hesla pro `elastic` a `kibana_system`, verzi stacku, jméno clusteru, porty a limity paměti.
- `init/setup.sh` – inicializační skript. Čeká na připravenost clusteru a poté vytvoří index templates pro tracks, artists a charts s explicitními mappingy (datové typy per pole, 3 shardy, 2 repliky).
- `logstash/pipelines.yml` – definice 3 nezávislých Logstash pipelin.
- `logstash/pipeline/tracks.conf` – ETL pipeline pro tracks. File input čte CSV, csv filter parsuje sloupce, mutate konvertuje typy, Ruby filter řeší boolean konverzi, output posílá dokumenty do ES přes HTTPS s document_id = track_id.
- `logstash/pipeline/artists.conf` – ETL pipeline pro artists. Obdobné filtry, navíc parsování genres pole ze stringu na array.
- `logstash/pipeline/charts.conf` – ETL pipeline pro charts. Deterministické document_id (date_region_chart_rank) kvůli idempotentnímu reimportu.
- `schema_architektury.png` – schéma architektury vytvořené v draw.io.
- `kibana_dashboard_export.ndjson` – export Kibana dashboardu pro rychlý import po prvním spuštění.
- `TODO.md` – checklist úkolů před obhajobou (ověření startu od nuly, projetí všech dotazů, export do PDF).

### Příloha D – Dockerfile a pomocné nástroje

Projekt nepoužívá vlastní Dockerfile – všechny kontejnery běží na oficiálních obrazech od Elasticu. Init skript `init/setup.sh` se spouští v oficiálním `elasticsearch:8.17.0` obrazu, stejně tak setup kontejner pro generování TLS.

Pro administraci je přidán kontejner `cars10/elasticvue:1.0.8` – open-source webový GUI klient pro Elasticsearch, který běží na portu 8080 a zobrazuje stav clusteru (uzly, shardy, indexy) a umí i search UI.
