#!/bin/bash

for limit in /sys/class/powercap/intel-rapl*/*_power_limit_uw; do
    # Derive the corresponding max-power filename
    maxf="${limit%_power_limit_uw}_max_power_uw"
    if [[ -r "$maxf" && -w "$limit" ]]; then
        cat "$maxf" > "$limit"
    fi
done

