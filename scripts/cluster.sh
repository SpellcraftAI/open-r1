#!/usr/bin/env bash

# Exit on any error, treat unset variables as errors, and fail on pipe errors
set -euo pipefail

# Change these to match your unmanaged instance group
INSTANCE_GROUP="open-r1-2x"
GROUP_ZONE="us-central1-c"

echo "Gathering instance names from group '$INSTANCE_GROUP' in zone '$GROUP_ZONE'..."
instances=$(gcloud compute instance-groups unmanaged list-instances "$INSTANCE_GROUP" \
  --zone="$GROUP_ZONE" \
  --format="value(NAME)"
)

# Convert the multiline output into a Bash array
IFS=$'\n' read -r -d '' -a instance_names <<< "$instances" || true

echo "Found ${#instance_names[@]} instances in the group:"
printf "  %s\n" "${instance_names[@]}"
echo ""

for instance_name in "${instance_names[@]}"; do
  echo "==> Sending 'Hello world' to $instance_name ..."
  
  # If all instances are in the same zone (GROUP_ZONE), you can skip this extra lookup.
  # But let's confirm we have the correct zone for each instance:
  zone=$(gcloud compute instances list \
    --filter="name=($instance_name)" \
    --format="value(ZONE)"
  )

  # Use SSH to run a simple command
  gcloud compute ssh "$instance_name" --zone="$zone" --command "cd ~/open-r1 && ./scripts/train.sh"

  echo ""
done

echo "All done!"
