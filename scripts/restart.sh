#!/usr/bin/env bash
set -euo pipefail

INSTANCE_GROUP="cuda-121"
GROUP_ZONE="us-central1-c"

echo "Fetching instance names from unmanaged instance group '$INSTANCE_GROUP' in zone '$GROUP_ZONE'..."
instances=$(gcloud compute instance-groups unmanaged list-instances "$INSTANCE_GROUP" \
  --zone="$GROUP_ZONE" \
  --format="value(NAME)")

# Convert the multiline list of instance names into a Bash array.
IFS=$'\n' read -r -d '' -a instance_names <<< "$instances" || true

echo "Found ${#instance_names[@]} instances:"
printf "  %s\n" "${instance_names[@]}"
echo ""

# We'll keep track of background PIDs in this array.
pids=()

# Define a cleanup function that kills all background jobs when we Ctrl+C.
cleanup() {
  echo "Caught Ctrl+C (or SIGTERM). Killing all SSH sessions..."
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  # Wait for all background jobs to exit.
  wait
  echo "All background jobs terminated."
}

# Trap SIGINT (Ctrl+C) and SIGTERM and run 'cleanup'.
trap cleanup INT TERM

# Start each SSH job in the background.
for instance_name in "${instance_names[@]}"; do
  # If all are in the same zone, you can skip this next lookup.
  # But here's how to confirm the zone for each instance:
  zone=$(gcloud compute instances list \
    --filter="name=($instance_name)" \
    --format="value(ZONE)")

  echo "Restarting $instance_name (zone: $zone)..."

  # Run the SSH command in a sub-shell in the background (&).
  # - The remote process will stop if SSH is killed (which happens if we Ctrl+C).
  (
     gcloud compute ssh "$instance_name" --zone="$zone" --command "sudo reboot now"
  ) &

  # Capture the PID of this background job.
  pids+=($!)
done

# Wait for all background jobs to finish (or until we Ctrl+C).
wait

echo "All done!"
