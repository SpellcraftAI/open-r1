#!/usr/bin/env bash
set -euo pipefail

killall tmux 2> /dev/null || true

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

# A cleanup function to kill the tmux session on Ctrl+C / SIGTERM
cleanup() {
  echo "Caught interrupt. Killing tmux session..."
  tmux kill-session -t nvidia || true
  echo "Session killed. Exiting..."
  exit 0
}
trap cleanup INT TERM

# This is the command each pane will run: first kill any existing nvidia-smi, then watch.
ssh_command="killall nvidia-smi 2> /dev/null; watch -n 1 nvidia-smi"

SESSION="nvidia"
WINDOW="gpu-monitor"

# Calculate how many panes per row.
# We want exactly 2 rows, so the first row gets ceil(n/2) panes.
row1_count=$(( (num_instances + 1) / 2 ))
row2_count=$(( num_instances - row1_count ))

echo "Using 2 rows: $row1_count pane(s) in the first row and $row2_count pane(s) in the second row."

# --- Create first row ---
# Start a new tmux session with the first instance in the first pane.
tmux new-session -d -s "$SESSION" -n "$WINDOW" \
  "gcloud compute ssh \"${instance_names[0]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"

# For remaining instances in row 1, split horizontally.
for (( i=1; i<row1_count; i++ )); do
  tmux split-window -h -t "${SESSION}:${WINDOW}" \
    "gcloud compute ssh \"${instance_names[i]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"
done

# Now, ensure the layout of the first row is even.
tmux select-layout -t "${SESSION}:${WINDOW}" even-horizontal

# --- Create second row (if any) ---
if (( row2_count > 0 )); then
  # Split vertically from the left-most pane of the first row to create the first pane of row 2.
  tmux select-pane -t "${SESSION}:${WINDOW}.0"
  tmux split-window -v -t "${SESSION}:${WINDOW}.0" \
    "gcloud compute ssh \"${instance_names[row1_count]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"

  # For the remaining instances in row 2, add horizontally.
  for (( i = row1_count + 1; i < num_instances; i++ )); do
    # Always add to the most-recent pane in row 2. We can locate it by finding the pane at the bottom row.
    # For simplicity, assume the bottom row's left-most pane has index row1_count (the newly created pane).
    tmux select-pane -t "${SESSION}:${WINDOW}.${row1_count}"
    tmux split-window -h -t "${SESSION}:${WINDOW}.${row1_count}" \
      "gcloud compute ssh \"${instance_names[i]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"
  done

  # Tidy up the layout for the second row.
  # We can reapply the tiled layout over the whole window to achieve an even split.
  tmux select-layout -t "${SESSION}:${WINDOW}" tiled
fi

# Attach to the tmux session.
tmux attach-session -t "$SESSION"
