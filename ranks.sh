instances=$(gcloud compute instances list \
           --format="value(NAME)")

rank=0
for instance in $instances; do
  echo "Assigning machine_rank=$rank to instance $instance"
  # We SSH into the instance and run sed in-place on all configs.
  # Make sure you handle shell-escaping properly in the command string.
  gcloud compute ssh "$instance" --command \
    "sed -i 's/^machine_rank: .*/machine_rank: $rank/' ~/open-r1/configs/*.yaml"

  rank=$((rank + 1))
done