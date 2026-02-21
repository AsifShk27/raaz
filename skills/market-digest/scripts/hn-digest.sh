#!/usr/bin/env bash

# Hacker News Digest Fetcher (Shell-based)
# Usage: ./hn-digest.sh [count] [topic] [offset]

count="${1:-5}"
topic="${2:-tech}"
offset="${3:-0}"

HN_API="https://hacker-news.firebaseio.com/v0"

# Get story IDs
top_ids_raw=$(curl -s "$HN_API/topstories.json")

# Convert JSON array to space-separated IDs
ids=($(echo "$top_ids_raw" | tr ',' '\n' | head -500 | sed 's/\[//; s/\]//; s/ //g' | grep -v '^$'))

# Topic keywords
case "$topic" in
  health)
    keywords=("health" "medical" "doctor" "hospital" "medicine" "drug" "cancer" "covid")
    ;;
  hacking)
    keywords=("hack" "security" "vulnerability" "exploit" "cyber" "malware" "ransomware")
    ;;
  life)
    keywords=("life" "productivity" "habit" "mindful" "happiness" "relationship")
    ;;
  *)
    keywords=("tech" "software" "programming" "ai" "ml" "code" "developer")
    ;;
esac

result=""
matched=0
skipped=0

for id in "${ids[@]}"; do
  (( skipped < offset )) && ((skipped++)) && continue
  
  story=$(curl -s "$HN_API/item/$id.json" 2>/dev/null || continue)
  
  title=$(echo "$story" | jq -r '.title' 2>/dev/null || continue)
  [[ -z "$title" || "$title" == "null" ]] && continue
  
  url=$(echo "$story" | jq -r '.url')
  score=$(echo "$story" | jq -r '.score')
  time=$(echo "$story" | jq -r '.time')
  descendants=$(echo "$story" | jq -r '.descendants')
  
  # Skip Ask HN, Show HN
  echo "$title" | grep -qiE "Ask HN|Show HN" && continue
  
  # Exclude crypto
  echo "$title" | grep -qiE "crypto|bitcoin|ethereum|solana|nft|blockchain" && continue
  
  # Age
  age_seconds=$(( $(date +%s) - time ))
  if (( age_seconds < 3600 )); then
    age="$(( age_seconds / 60 ))m ago"
  elif (( age_seconds < 86400 )); then
    age="$(( age_seconds / 3600 ))h ago"
  else
    age="$(( age_seconds / 86400 ))d ago"
  fi
  
  # Topic boost
  score_boost=0
  for kw in "${keywords[@]}"; do
    if echo "$title" | grep -qi "$kw"; then
      ((score_boost += 50))
    fi
  done
  
  final_score=$(( score + score_boost ))
  
  # Output directly
  echo "{\"title\": \"${title//\"/\\\"}\", \"age\": \"$age\", \"comments\": $descendants, \"url\": \"${url//\"/\\\"}\"}"
  
  ((matched++))
  (( matched >= count )) && break
done
