#!/usr/bin/env bash
set -euo pipefail

INSTANCE_GROUP="open-r1-2x"
GROUP_ZONE="us-central1-c"

echo "Fetching instance names from unmanaged instance group '$INSTANCE_GROUP' in zone '$GROUP_ZONE'..."
instances=$(gcloud compute instance-groups unmanaged list-instances "$INSTANCE_GROUP" \
  --zone="$GROUP_ZONE" \
  --format="value(NAME)")

# Convert the multiline list of instance names into a Bash array.
IFS=$'\n' read -r -d '' -a instance_names <<< "$instances" || true

num_instances=${#instance_names[@]}
if [[ $num_instances -eq 0 ]]; then
  echo "ERROR: No instances found."
  exit 1
fi

echo "Found $num_instances instance(s):"
printf "  %s\n" "${instance_names[@]}"
echo ""

# A cleanup function to kill the tmux session on Ctrl+C / SIGTERM.
cleanup() {
  echo "Caught interrupt. Killing tmux session..."
  tmux kill-session -t nvidia || true
  echo "Session killed. Exiting..."
  exit 0
}
trap cleanup INT TERM

# The command each pane will run.
ssh_command="killall nvidia-smi 2> /dev/null; watch -n 1 nvidia-smi"

SESSION="nvidia"
WINDOW="gpu-monitor"

# Determine how many instances go to row1.
# We round up so that row1 gets the extra pane if the total is odd.
half_count=$(( (num_instances + 1) / 2 ))

# === Row 1: Create a new tmux session with the first instance. ===
tmux new-session -d -s "$SESSION" -n "$WINDOW" \
  "gcloud compute ssh \"${instance_names[0]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"

# For the remaining instances that belong in row1.
for (( i=1; i<half_count; i++ )); do
  tmux split-window -h -t "${SESSION}:${WINDOW}" \
    "gcloud compute ssh \"${instance_names[i]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"
done

# === Row 2: If any instances remain, create a second horizontal row. ===
if (( num_instances > half_count )); then
  # Split the leftmost pane of row1 vertically to start row2.
  # Capture the new pane id so we know where to add further splits.
  row2_left=$(tmux split-window -v -P -F "#{pane_id}" -t "${SESSION}:${WINDOW}.0" \
    "gcloud compute ssh \"${instance_names[half_count]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'")
  
  # For any additional instances in row2, add them with horizontal splits.
  for (( i=half_count+1; i<num_instances; i++ )); do
    tmux split-window -h -t "$row2_left" \
      "gcloud compute ssh \"${instance_names[i]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"
  done
fi

# Rearrange panes into a neat tiled layout.
tmux select-layout -t "${SESSION}:${WINDOW}" tiled

# Attach to the tmux session.
tmux attach-session -t "$SESSION"
