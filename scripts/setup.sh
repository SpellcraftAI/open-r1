#!/usr/bin/env bash

set -euo pipefail

# The name of your unmanaged instance group
INSTANCE_GROUP="open-r1-2x"
# The zone that the instance group is in
GROUP_ZONE="us-central1-c"

echo "Fetching instance names from unmanaged instance group: $INSTANCE_GROUP (zone: $GROUP_ZONE)"
instance_names_raw=$(gcloud compute instance-groups unmanaged list-instances "$INSTANCE_GROUP" \
  --zone="$GROUP_ZONE" \
  --format="value(NAME)" \
)

# Convert the multiline list of instance names into a Bash array.
IFS=$'\n' read -r -d '' -a instance_names <<< "$instance_names_raw" || true

# If you want to see them, you can debug-print here:
echo "Found ${#instance_names[@]} instances in group $INSTANCE_GROUP:"
printf " - %s\n" "${instance_names[@]}"
echo ""

rank=0
master_ip=""

# Loop over each instance in the array, in the order listed
for instance_name in "${instance_names[@]}"; do
  echo "==> Processing instance: $instance_name"

  # Grab the internal IP and zone of this specific instance.
  # We filter by NAME to get exactly that instance.
  ip_zone=$(gcloud compute instances list \
    --filter="name=($instance_name)" \
    --format="value(INTERNAL_IP,ZONE)"
  )

  # Parse out the internal IP and the zone.
  internal_ip=$(echo "$ip_zone" | awk '{print $1}')
  zone=$(echo "$ip_zone" | awk '{print $2}')

  # If this is the first instance (rank=0), it's the master
  if [ "$rank" -eq 0 ]; then
    master_ip="$internal_ip"
    echo "   -> Marking as MASTER (rank 0), IP: $master_ip"
  else
    echo "   -> Rank $rank"
  fi

  echo "   -> Zone: $zone"

  # SSH into the instance:
  #  1) Pull latest code in ~/open-r1
  #  2) Update machine_rank and main_process_ip lines in ~/open-r1/recipes/accelerate_configs/*.yml
  gcloud compute ssh "$instance_name" --zone="$zone" --command "
    echo 'Running git pull in ~/open-r1...'
    cd ~/open-r1 && git reset HEAD --hard && git pull --no-rebase && \
    echo 'Updating machine_rank=$rank, main_process_ip=$master_ip in configs...' && \
    sed -i 's|^machine_rank: .*|machine_rank: $rank|'  ~/open-r1/recipes/accelerate_configs/* && \
    sed -i 's|^main_process_ip: .*|main_process_ip: $master_ip|'  ~/open-r1/recipes/accelerate_configs/*
  "

  rank=$((rank + 1))
  echo ""
done

echo "All done!"
