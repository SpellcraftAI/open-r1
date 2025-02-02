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

# Start a new tmux session using the first instance.
first_instance="${instance_names[0]}"
tmux new-session -d -s "$SESSION" -n "$WINDOW" \
  "gcloud compute ssh \"${first_instance}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"

# Keep track of the “left” pane for the current row.
# We assume the session’s first (and only) pane is our current row’s left pane.
row_left_pane="$(tmux display-message -p -t ${SESSION}:$WINDOW '#{pane_id}')"

# Process the remaining instances.
# We'll loop over instance_names[1..n-1] and for each row, add a partner (if available) via horizontal split.
# Then if more instances remain, start a new row by vertically splitting the left pane of the current row.
for (( i=1; i<num_instances; i++ )); do
  # For even i (i.e. odd-numbered instance, second in the row) add a horizontal split.
  if (( i % 2 == 1 )); then
    # Split horizontally in the current row.
    tmux select-pane -t "$row_left_pane"
    tmux split-window -h -t "$row_left_pane" \
      "gcloud compute ssh \"${instance_names[i]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'"
  else
    # For even-numbered pane positions (starting a new row):
    # Split vertically from the left pane of the previous row.
    tmux select-pane -t "$row_left_pane"
    # The -P flag makes tmux print the new pane id; -F formats the output.
    new_left=$(tmux split-window -v -P -F "#{pane_id}" -t "$row_left_pane" \
      "gcloud compute ssh \"${instance_names[i]}\" --zone=\"$GROUP_ZONE\" -- -t '$ssh_command'")
    # Update the row_left_pane variable for the new row.
    row_left_pane="$new_left"
  fi
done

# Tidy up the layout. The "tiled" layout will re-arrange panes nicely.
tmux select-layout -t "${SESSION}:${WINDOW}" tiled

# Attach to the tmux session.
tmux attach-session -t "$SESSION"
