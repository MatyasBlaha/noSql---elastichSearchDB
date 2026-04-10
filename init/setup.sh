#!/bin/bash
# Init skript – bezi jednou po startu clusteru, PRED Logstash importem.
# Vytvori index templates s explicitnimi mappingy pro vsechny indexy.
set -e

ES_URL="https://es-data-1:9200"
CA_CERT="/usr/share/elasticsearch/config/certs/ca/ca.crt"
AUTH="elastic:${ELASTIC_PASSWORD}"

echo "Waiting for Elasticsearch cluster to be ready..."
until curl -s --cacert "$CA_CERT" -u "$AUTH" "$ES_URL/_cluster/health" | grep -qE '"status":"(green|yellow)"'; do
  echo "  Cluster not ready yet, retrying in 5s..."
  sleep 5
done
echo "Cluster is ready."

# --- TRACKS index template ---
echo "Creating index template for tracks..."
curl -s -X PUT --cacert "$CA_CERT" -u "$AUTH" \
  -H "Content-Type: application/json" \
  "$ES_URL/_index_template/spotify-tracks" \
  -d '{
    "index_patterns": ["tracks"],
    "template": {
      "settings": {
        "number_of_shards": 3,
        "number_of_replicas": 1
      },
      "mappings": {
        "properties": {
          "track_id":          { "type": "keyword" },
          "track_name":        { "type": "text", "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } } },
          "artists":           { "type": "text", "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } } },
          "album_name":        { "type": "text", "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } } },
          "popularity":        { "type": "integer" },
          "duration_ms":       { "type": "integer" },
          "explicit":          { "type": "boolean" },
          "danceability":      { "type": "float" },
          "energy":            { "type": "float" },
          "key":               { "type": "integer" },
          "loudness":          { "type": "float" },
          "mode":              { "type": "integer" },
          "speechiness":       { "type": "float" },
          "acousticness":      { "type": "float" },
          "instrumentalness":  { "type": "float" },
          "liveness":          { "type": "float" },
          "valence":           { "type": "float" },
          "tempo":             { "type": "float" },
          "time_signature":    { "type": "integer" },
          "track_genre":       { "type": "keyword" }
        }
      }
    },
    "priority": 100
  }'
echo ""

# --- ARTISTS index template ---
echo "Creating index template for artists..."
curl -s -X PUT --cacert "$CA_CERT" -u "$AUTH" \
  -H "Content-Type: application/json" \
  "$ES_URL/_index_template/spotify-artists" \
  -d '{
    "index_patterns": ["artists"],
    "template": {
      "settings": {
        "number_of_shards": 3,
        "number_of_replicas": 1
      },
      "mappings": {
        "properties": {
          "artist_id":             { "type": "keyword" },
          "name":                  { "type": "text", "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } } },
          "followers":             { "type": "long" },
          "genres":                { "type": "keyword" },
          "popularity":            { "type": "integer" },
          "related_artists_count": { "type": "integer" },
          "related_artists_ids":   { "type": "keyword" }
        }
      }
    },
    "priority": 100
  }'
echo ""

# --- CHARTS index template ---
echo "Creating index template for charts..."
curl -s -X PUT --cacert "$CA_CERT" -u "$AUTH" \
  -H "Content-Type: application/json" \
  "$ES_URL/_index_template/spotify-charts" \
  -d '{
    "index_patterns": ["charts"],
    "template": {
      "settings": {
        "number_of_shards": 3,
        "number_of_replicas": 1
      },
      "mappings": {
        "properties": {
          "title":   { "type": "text", "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } } },
          "rank":    { "type": "integer" },
          "date":    { "type": "date" },
          "artist":  { "type": "text", "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } } },
          "region":  { "type": "keyword" },
          "chart":   { "type": "keyword" },
          "trend":   { "type": "keyword" },
          "streams": { "type": "long" }
        }
      }
    },
    "priority": 100
  }'
echo ""

# --- Overeni ---
echo "Verifying templates..."
for tmpl in spotify-tracks spotify-artists spotify-charts; do
  curl -s --cacert "$CA_CERT" -u "$AUTH" "$ES_URL/_index_template/$tmpl" | grep -q "$tmpl" \
    && echo "  $tmpl OK" \
    || echo "  $tmpl FAILED"
done
echo "Index templates created successfully."
