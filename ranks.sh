#!/usr/bin/env bash

set -euo pipefail

# Get instance NAME and INTERNAL_IP in one pass.
# Adjust filters if needed (e.g., --filter="name ~ '^open-r1-2x-.*'").
instances=$(gcloud compute instances list \
  --format="value(NAME,INTERNAL_IP)" \
)

rank=0
master_ip=""

while IFS= read -r line; do
  # Extract the instance name and internal IP from the line.
  instance_name=$(echo "$line" | awk '{print $1}')
  internal_ip=$(echo "$line" | awk '{print $2}')

  # The first machine becomes the master.
  if [ "$rank" -eq 0 ]; then
    master_ip="$internal_ip"
    echo "Found MASTER instance: $instance_name (rank 0) with IP $master_ip"
  fi

  echo "Updating $instance_name:"
  echo "  -> machine_rank: $rank"
  echo "  -> main_process_ip: $master_ip (from the master)"
  
  # 1) Go into ~/open-r1 and do a git pull
  # 2) Update machine_rank and main_process_ip in YAML configs
  gcloud compute ssh "$instance_name" --command "
    cd ~/open-r1 && git pull && \
    sed -i 's|^machine_rank: .*|machine_rank: $rank|; s|^main_process_ip: .*|main_process_ip: $master_ip|' ~/open-r1/configs/*.yml
  "

  rank=$((rank + 1))
done <<< "$instances"
