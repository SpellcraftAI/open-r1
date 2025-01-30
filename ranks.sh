#!/usr/bin/env bash

set -euo pipefail

# Gather instance NAME, INTERNAL_IP, and ZONE.
# You can also add a filter if you only want certain instances:
# e.g., --filter="name ~ '^open-r1-2x-.*'"
instances=$(gcloud compute instances list \
  --format="value(NAME,INTERNAL_IP,ZONE)" \
)

rank=0
master_ip=""

while IFS= read -r line; do
  # Extract fields from the line
  instance_name=$(echo "$line" | awk '{print $1}')
  internal_ip=$(echo "$line" | awk '{print $2}')
  zone=$(echo "$line" | awk '{print $3}')

  # First machine is master
  if [ "$rank" -eq 0 ]; then
    master_ip="$internal_ip"
    echo "Found MASTER instance: $instance_name (rank 0) with IP $master_ip"
  fi

  echo "Updating $instance_name (zone: $zone):"
  echo "  -> machine_rank: $rank"
  echo "  -> main_process_ip: $master_ip (from the master)"
  
  # SSH in: do a git pull, then sed replacement of machine_rank and main_process_ip
  gcloud compute ssh "$instance_name" --zone="$zone" --command "
    cd ~/open-r1 && git pull && \
    sed -i 's|^machine_rank: .*|machine_rank: $rank|'  ~/open-r1/configs/*.yml && \
    sed -i 's|^main_process_ip: .*|main_process_ip: $master_ip|'  ~/open-r1/configs/*.yml
  "

  rank=$((rank + 1))
done <<< "$instances"
