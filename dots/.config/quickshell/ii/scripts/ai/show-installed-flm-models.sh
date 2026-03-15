#!/usr/bin/env bash

# Get the list of installed fastflowlm models, skip the header, extract first column
model_names=$(flm list 2>/dev/null | tail -n +2 | awk '{print $1}')

# Build a properly escaped JSON array using jq
if [ -z "$model_names" ]; then
    echo "[]"
    exit 0
fi

echo "$model_names" | jq -Rsc 'split("\n") | map(select(length > 0))'
