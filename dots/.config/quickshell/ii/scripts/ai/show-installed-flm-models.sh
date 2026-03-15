#!/usr/bin/env bash

# 1. Get the list
# 2. Grep for the checkmark emoji (verified/downloaded)
# 3. Extract the second column ($2) to get the model name
model_names=$(flm list 2>/dev/null | grep "✅" | awk '{print $2}')

# Build a properly escaped JSON array using jq
if [ -z "$model_names" ]; then
    echo "[]"
    exit 0
fi

echo "$model_names" | jq -Rsc 'split("\n") | map(select(length > 0))'
