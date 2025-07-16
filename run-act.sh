#!/bin/bash
act --verbose 2>&1 | while read line; do 
  echo "$(date '+%Y-%m-%d %H:%M:%S') $line" 
done | tee act-timestamped.log