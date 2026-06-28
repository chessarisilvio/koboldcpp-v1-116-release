#!/usr/bin/env bash
# koboldcpp manual GPU benchmark script
# Usage: ./test_manuali.sh [build_indices...]
#   If no arguments, tests all available builds.
#   Example: ./test_manuali.sh 0 1

set -euo pipefail

# Configuration
PROMPT="Explain the theory of relativity in detail."
TOKENS_TO_GENERATE=128
SERVER_START_TIMEOUT=30  # seconds
REQUEST_TIMEOUT=60       # seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}
print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}
print_error() {
    echo -e "${RED}[-]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local deps=("nvidia-smi" "curl" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "Dependency '$dep' not found. Please install it."
            exit 1
        fi
    done
}

# Find available builds (directories build_* containing koboldcpp binary)
find_builds() {
    local builds=()
    # Look for directories named build_* in current directory
    while IFS= read -r -d '' dir; do
        if [[ -x "$dir/koboldcpp" ]]; then
            builds+=("$dir")
        fi
    done < <(find . -maxdepth 1 -type d -name "build_*" -print0)

    if [[ ${#builds[@]} -eq 0 ]]; then
        print_error "No builds found. Please run build_koboldcpp.sh first."
        exit 1
    fi

    echo "${builds[@]}"
}

# Extract GPU index from build directory name (e.g., build_0 -> 0)
get_gpu_index() {
    local dir="$1"
    # Remove './build_' prefix and get the number
    basename "$dir" | sed -E 's/build_([0-9]+)/\1/'
}

# Get GPU name from nvidia-smi for a given index
get_gpu_name() {
    local index="$1"
    nvidia-smi --query-gpu=name --format=csv,noheader,nounits -i "$index" | head -n1
}

# Start koboldcpp server in background
start_server() {
    local build_dir="$1"
    local port="$2"
    local log_file="$3"

    print_status "Starting server on port $port (logging to $log_file)"
    "$build_dir/koboldcpp" --port "$port" --host 127.0.0.1 --ctx-size 2048 --n-gpu-layers 99 > "$log_file" 2>&1 &
    local server_pid=$!

    # Wait for server to be ready
    local start_time=$(date +%s)
    while true; do
        if curl -s "http://127.0.0.1:$port/health" > /dev/null 2>&1; then
            break
        fi
        local now=$(date +%s)
        if [[ $((now - start_time)) -ge $SERVER_START_TIMEOUT ]]; then
            print_error "Server failed to start within $SERVER_START_TIMEOUT seconds"
            kill $server_pid 2>/dev/null || true
            return 1
        fi
        sleep 1
    done

    echo "$server_pid"
}

# Stop koboldcpp server
stop_server() {
    local pid="$1"
    if [[ -n "$pid" && "$(ps -p $pid -o pid=)" ]]; then
        print_status "Stopping server (PID: $pid)"
        kill $pid
        wait $pid 2>/dev/null || true
    fi
}

# Run benchmark for a specific build
run_benchmark() {
    local build_dir="$1"
    local gpu_index="$2"
    local gpu_name
    gpu_name=$(get_gpu_name "$gpu_index")

    print_status "Testing GPU $gpu_index: $gpu_name (build: $build_dir)"

    # Choose a port (avoid conflicts: 8080 + gpu_index)
    local port=$((8080 + gpu_index))
    local log_file="./koboldcpp_server_${gpu_index}.log"
    local server_pid=""

    # Start server
    server_pid=$(start_server "$build_dir" "$port" "$log_file") || {
        print_error "Failed to start server for GPU $gpu_index"
        return 1
    }

    # Prepare request data
    local request_data=$(cat <<EOF
{
    "prompt": "$PROMPT",
    "max_tokens": $TOKENS_TO_GENERATE,
    "temperature": 0.7,
    "top_p": 0.9,
    "stream": false
}
EOF
)

    # Measure time and VRAM
    print_status "Sending benchmark request (generating $TOKENS_TO_GENERATE tokens)..."
    local start_time=$(date +%s%N)  # nanoseconds

    # Start VRAM monitoring in background
    local vram_log="./vram_${gpu_index}.log"
    : > "$vram_log"  # clear file
    local vram_pid=""
    (
        while [[ -d /proc/$server_pid ]]; do
            nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i "$gpu_index" >> "$vram_log"
            sleep 0.5
        done
    ) &
    vram_pid=$!

    # Send request
    local response
    response=$(curl -s -X POST "http://127.0.0.1:$port/v1/completions" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        --max-time $REQUEST_TIMEOUT) || {
        print_error "Request failed or timed out"
        stop_server "$server_pid"
        kill $vram_pid 2>/dev/null || true
        return 1
    }

    local end_time=$(date +%s%N)
    stop_server "$server_pid"
    kill $vram_pid 2>/dev/null || true
    wait $vram_pid 2>/dev/null || true

    # Calculate time taken
    local time_taken_ms=$(( (end_time - start_time) / 1000000 ))  # convert to milliseconds
    local time_taken_sec=$(echo "scale=3; $time_taken_ms / 1000" | bc)

    # Extract tokens generated from response
    local tokens_generated
    tokens_generated=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
    if [[ "$tokens_generated" == "null" || -z "$tokens_generated" ]]; then
        tokens_generated=0
    fi

    # Calculate tokens per second
    local tps
    if [[ "$time_taken_sec" > 0 && "$tokens_generated" -gt 0 ]]; then
        tps=$(echo "scale=2; $tokens_generated / $time_taken_sec" | bc)
    else
        tps=0
    fi

    # Get max VRAM used during test
    local max_vram_mb=0
    if [[ -f "$vram_log" && -s "$vram_log" ]]; then
        max_vram_mb=$(sort -n "$vram_log" | tail -n1)
    fi

    # Clean up temporary files
    rm -f "$log_file" "$vram_log"

    # Output results
    echo "=== Benchmark Results for GPU $gpu_index: $gpu_name ==="
    echo "Prompt: \"$PROMPT\""
    echo "Tokens requested: $TOKENS_TO_GENERATE"
    echo "Tokens generated: $tokens_generated"
    echo "Time taken: ${time_taken_sec}s"
    echo "Tokens per second: $tps"
    echo "Max VRAM used: ${max_vram_mb} MB"
    echo ""

    # Return results as JSON for potential further processing
    # echo "{\"gpu_index\":$gpu_index,\"gpu_name\":\"$gpu_name\",\"tokens_per_second\":$tps,\"max_vram_mb\":$max_vram_mb,\"time_taken_sec\":$time_taken_sec}"
}

# Main execution
main() {
    check_dependencies

    # Determine which builds to test
    local all_builds
    all_builds=($(find_builds))

    local builds_to_test=()
    if [[ $# -eq 0 ]]; then
        # No arguments: test all builds
        builds_to_test=("${all_builds[@]}")
        print_status "Testing all available builds: ${#builds_to_test[@]}"
    else
        # Arguments provided: treat as build indices or directory names
        for arg in "$@"; do
            if [[ "$arg" == "all" ]]; then
                builds_to_test=("${all_builds[@]}")
                break
            fi
            # Check if arg is a number (index) or matches build_* pattern
            if [[ "$arg" =~ ^[0-9]+$ ]]; then
                local dir="./build_$arg"
                if [[ -d "$dir" && -x "$dir/koboldcpp" ]]; then
                    builds_to_test+=("$dir")
                else
                    print_warning "Build directory '$dir' not found or missing koboldcpp binary"
                fi
            elif [[ -d "$arg" && -x "$arg/koboldcpp" ]]; then
                builds_to_test+=("$arg")
            else
                print_warning "Invalid build specification: '$arg'"
            fi
        done

        # Remove duplicates
        builds_to_test=($(printf "%s\n" "${builds_to_test[@]}" | sort -u))
    fi

    if [[ ${#builds_to_test[@]} -eq 0 ]]; then
        print_error "No valid builds selected for testing"
        exit 1
    fi

    print_status "Found ${#builds_to_test[@]} build(s) to test"

    # Run benchmark for each selected build
    for build_dir in "${builds_to_test[@]}"; do
        local gpu_index
        gpu_index=$(get_gpu_index "$build_dir")
        run_benchmark "$build_dir" "$gpu_index"
    done

    print_status "Benchmark completed"
}

# Make bc available if not present (it's usually installed)
if ! command -v bc &> /dev/null; then
    print_error "bc (basic calculator) not found. Please install it."
    exit 1
fi

main "$@"