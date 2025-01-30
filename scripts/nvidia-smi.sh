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
echo "Found ${#instance_names[@]} instances:"
printf "  %s\n" "${instance_names[@]}"
echo ""

if [[ ${#instance_names[@]} -lt 4 ]]; then
  echo "ERROR: We need at least 4 instances for a 4-panel layout."
  exit 1
fi

# Take the first 4 instances
first_four=("${instance_names[@]:0:4}")
echo "Using these 4 instances for a 4-panel nvidia-smi:"
printf "  %s\n" "${first_four[@]}"
echo ""

# A cleanup function to kill the tmux session on Ctrl+C / SIGTERM
cleanup() {
  echo "Caught Ctrl+C (or SIGTERM). Killing tmux session..."
  tmux kill-session -t nvidia || true
  echo "Session killed. Exiting..."
  exit 0
}
trap cleanup INT TERM

# This is the command each pane will run: first kill any existing nvidia-smi, then watch.
ssh_command="killall nvidia-smi 2> /dev/null; watch -n 1 nvidia-smi"

# We do a simple 2x2 layout with a for-loop: 0..3
for i in {0..3}; do
  if [[ $i -eq 0 ]]; then
    # Create a new tmux session in detached mode for the first instance
    tmux new-session -d -s nvidia -n "gpu-monitor" \
      "gcloud compute ssh \"${first_four[$i]}\" \
         --zone=\"$GROUP_ZONE\" \
         -- -t '$ssh_command'"
  elif [[ $i -eq 1 ]]; then
    # Split horizontally for the second instance
    tmux split-window -h \
      "gcloud compute ssh \"${first_four[$i]}\" \
         --zone=\"$GROUP_ZONE\" \
         -- -t '$ssh_command'"
  elif [[ $i -eq 2 ]]; then
    # Split vertically for the third instance
    tmux split-window -v \
      "gcloud compute ssh \"${first_four[$i]}\" \
         --zone=\"$GROUP_ZONE\" \
         -- -t '$ssh_command'"
  else
    # i = 3: split the top-left pane again to get a 2x2 layout
    tmux select-pane -t 0
    tmux split-window -v \
      "gcloud compute ssh \"${first_four[$i]}\" \
         --zone=\"$GROUP_ZONE\" \
         -- -t '$ssh_command'"
  fi
done

# Attach to the newly created session (this blocks until you detach or exit tmux)
tmux select-layout -t nvidia:gpu-monitor tiled
tmux attach-session -t nvidia
