#!/usr/bin/env bash
# Test pagination selection logic
set -euo pipefail

echo "Testing select menu with pagination option..."
echo

# Simulate the menu
items=("Model 1" "Model 2" "Model 3" "── Show more ──" "Quit")

echo "Simulating: User selects option 4 (── Show more ──)"
echo

PS3="Enter number: "
select choice in "${items[@]}"; do
  echo "Selected: [$choice]"
  
  if [[ "$choice" == "── Show more ──" ]]; then
    echo "SUCCESS: Show more was selected!"
    exit 0
  elif [[ "$choice" == "Quit" ]]; then
    echo "Quit selected"
    exit 0
  elif [[ -n "$choice" ]]; then
    echo "Model selected: $choice"
    exit 0
  else
    echo "Invalid"
  fi
done << EOF
4
EOF
