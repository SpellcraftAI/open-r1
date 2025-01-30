#!/usr/bin/env bash

set -euo pipefail

# Capture all instances in a variable
instances=$(gcloud compute instances list --format="value(NAME,INTERNAL_IP,ZONE)")

# Convert the multi-line string to an array
IFS=$'\n' read -r -d '' -a lines <<< "$instances" || true

rank=0
master_ip=""

# Loop over the array
for line in "${lines[@]}"; do
  instance_name=$(echo "$line" | awk '{print $1}')
  internal_ip=$(echo "$line" | awk '{print $2}')
  zone=$(echo "$line" | awk '{print $3}')

  if [ "$rank" -eq 0 ]; then
    master_ip="$internal_ip"
    echo "Found MASTER instance: $instance_name (rank 0) with IP $master_ip"
  fi

  echo "Updating $instance_name (zone: $zone):"
  echo "  -> machine_rank: $rank"
  echo "  -> main_process_ip: $master_ip"

  gcloud compute ssh "$instance_name" --zone="$zone" --command "
    cd ~/open-r1 && git pull && \
    sed -i 's|^machine_rank: .*|machine_rank: $rank|'  ~/open-r1/configs/* && \
    sed -i 's|^main_process_ip: .*|main_process_ip: $master_ip|'  ~/open-r1/configs/*
  "

  rank=$((rank + 1))
done
