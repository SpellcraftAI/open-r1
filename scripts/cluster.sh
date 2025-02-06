#!/usr/bin/env bash
set -euo pipefail

INSTANCE_GROUP="cuda-121"
GROUP_ZONE="us-central1-c"

instances=$(gcloud compute instance-groups unmanaged list-instances "$INSTANCE_GROUP" \
  --zone="$GROUP_ZONE" \
  --format="value(NAME) ")

# Convert the whitespace-separated list of instance names into a Bash array.
read -r -a instance_names <<< ${instances[@]}

echo "Found ${#instance_names[@]} instances:"
printf "  %s\n" "${instance_names[@]}"
echo ""

# We'll use a parallel array for instance IP addresses.
instance_ips=()

echo "Fetching IP addresses for each instance using 'gcloud compute instances list'..."
for instance in "${instance_names[@]}"; do
  # Using a filter on the instance name and zone to get the external IP.
  ip=$(gcloud compute instances list \
         --filter="name=(${instance}) AND zone:(${GROUP_ZONE})" \
         --format="value(INTERNAL_IP)")
  instance_ips+=( "$ip" )
  echo "  $instance => $ip"
done

echo ""
echo "Summary of instances with their IP addresses:"
# Loop over the array indices to print corresponding entries.
for i in "${!instance_names[@]}"; do
  printf "  %s: %s\n" "${instance_names[$i]}" "${instance_ips[$i]}"
done

# We'll keep track of background PIDs in this array.
pids=()

# Define a cleanup function that kills all background jobs when we Ctrl+C.
cleanup() {
  echo "Caught Ctrl+C (or SIGTERM). Killing all SSH sessions..."
  for pid in "${pids[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
  # Wait for all background jobs to exit.
  wait
  echo "All background jobs terminated."
}

# Trap SIGINT (Ctrl+C) and SIGTERM and run 'cleanup'.
trap cleanup INT TERM

rank=0
num_nodes=${#instance_names[@]}
gpus_available=$(($num_nodes * 8- 1))

echo "RANK $rank | NODES $num_nodes | GPUS $gpus_available | LLVM 1"

# Start each SSH job in the background.
for instance_name in "${instance_names[@]}"; do
  # If all are in the same zone, you can skip this next lookup.
  # But here's how to confirm the zone for each instance:
  zone=$(gcloud compute instances list \
    --filter="name=($instance_name)" \
    --format="value(ZONE)")

  echo "Starting train.sh on $instance_name (zone: $zone)..."

  # Run the SSH command in a sub-shell in the background (&).
  # - The remote process will stop if SSH is killed (which happens if we Ctrl+C).
  #  add NCCL_DEBUG=INFO for debug
  (
  gcloud compute ssh "$instance_name" \
    --zone="$zone" \
    --command "source /etc/profile.d/env.sh &&
      killall -9 accelerate || true &&
      ulimit -n 10000 &&
      cd ~/open-r1 &&
      ./scripts/train.sh
        --machine_rank=$rank
        --num_machines=$num_nodes
        --num_processes=$gpus_available
        --main_process_ip=${instance_ips[0]}
        --main_process_port=6969"
  ) &

  # Capture the PID of this background job.
  pids+=($!)
  rank=$((rank + 1))
done

# Wait for all background jobs to finish (or until we Ctrl+C).
wait

echo "All done!"
