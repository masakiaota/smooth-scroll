#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/memory
swiftc -O -whole-module-optimization Settings.swift Interface.swift scripts/MemoryBenchmark.swift -o .build/MemoryBenchmark
benchmark_pid=
trap 'if [ -n "$benchmark_pid" ]; then kill "$benchmark_pid" 2>/dev/null || :; fi' EXIT HUP INT TERM
for mode in retained isolated; do
    for run in 1 2 3; do
        report=".build/memory/$mode-$run"
        .build/MemoryBenchmark "$mode" > "$report.log" 2>&1 &
        benchmark_pid=$!
        # A bounded wait; the benchmark checks its helper has exited first.
        attempt=0
        until rg -q '^ready:' "$report.log"; do
            kill -0 "$benchmark_pid"
            attempt=$((attempt + 1))
            [ "$attempt" -lt 100 ] || exit 1
            sleep 0.1
        done
        vmmap -summary "$benchmark_pid" > "$report.txt"
        printf '%s run %s: ' "$mode" "$run"
        rg '^Physical footprint:' "$report.txt"
        wait "$benchmark_pid"
        benchmark_pid=
    done
done
