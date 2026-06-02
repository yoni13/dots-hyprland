#!/usr/bin/env bash

frames=(
  "AGENTS IS RUNNING"
  "AGENTS IS RUNNING_"
  "// AGENTS IS RUNNING //"
  "!! AGENTS IS RUNNING !!"
  "[ AGENTS IS RUNNING ]"
  "AGENTS IS RUNNING"
)

now_ms=$(date +%s%3N)
idx=$(((now_ms / 125) % ${#frames[@]}))
printf '%s\n' "${frames[$idx]}"
