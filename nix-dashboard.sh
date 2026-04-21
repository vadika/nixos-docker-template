#!/usr/bin/env bash
# nix-dashboard.sh — Builder/cache health dashboard for the nixos-dev container
set -euo pipefail

# --- Config ---
STATS_DIR="${NIX_DASHBOARD_DIR:-/home/dev/.nix-dashboard}"
STATS_LOG="$STATS_DIR/build-log.jsonl"
CACHE_URL="${NIX_CACHE_URL:-http://artemis2:5000}"
REMOTE_BUILDERS=("artemis2")

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

mkdir -p "$STATS_DIR"

# --- Helpers ---
human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "$bytes / 1073741824" | bc -l 2>/dev/null || awk "BEGIN{printf \"%.1f\", $bytes/1073741824}")"
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" "$(echo "$bytes / 1048576" | bc -l 2>/dev/null || awk "BEGIN{printf \"%.1f\", $bytes/1048576}")"
    else
        printf "%d KB" $(( bytes / 1024 ))
    fi
}

check_mark() {
    if [ "$1" = "ok" ]; then
        printf "${GREEN}[OK]${RESET}"
    else
        printf "${RED}[FAIL]${RESET}"
    fi
}

# --- Commands ---

cmd_status() {
    echo -e "${BOLD}=== Nix Builder Dashboard ===${RESET}"
    echo -e "${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo

    # Nix store stats
    echo -e "${CYAN}--- Nix Store ---${RESET}"
    if command -v nix &>/dev/null; then
        local store_paths
        store_paths=$(nix path-info --all 2>/dev/null | wc -l)
        echo "  Store paths:  $store_paths"

        # Get store size from df on /nix
        local nix_usage
        nix_usage=$(df -B1 /nix 2>/dev/null | tail -1 | awk '{print $3}')
        if [ -n "$nix_usage" ]; then
            echo "  Store size:   $(human_size "$nix_usage")"
        fi

        local nix_avail
        nix_avail=$(df -B1 /nix 2>/dev/null | tail -1 | awk '{print $4}')
        if [ -n "$nix_avail" ]; then
            echo "  Available:    $(human_size "$nix_avail")"
        fi

        local nix_pct
        nix_pct=$(df /nix 2>/dev/null | tail -1 | awk '{print $5}')
        if [ -n "$nix_pct" ]; then
            echo "  Disk usage:   $nix_pct"
        fi
    else
        echo "  (nix not found)"
    fi
    echo

    # Binary cache health
    echo -e "${CYAN}--- Binary Cache ($CACHE_URL) ---${RESET}"
    local cache_info
    cache_info=$(wget -qO- --timeout=10 "$CACHE_URL/nix-cache-info" 2>/dev/null) && {
        echo -e "  Status:       $(check_mark ok) reachable"
        local store_dir priority
        store_dir=$(echo "$cache_info" | grep "^StoreDir:" | awk '{print $2}')
        priority=$(echo "$cache_info" | grep "^Priority:" | awk '{print $2}')
        [ -n "$store_dir" ] && echo "  Store dir:    $store_dir"
        [ -n "$priority" ] && echo "  Priority:     $priority"
    } || {
        echo -e "  Status:       $(check_mark fail) unreachable"
    }
    echo

    # Remote builders
    echo -e "${CYAN}--- Remote Builders ---${RESET}"
    for builder in "${REMOTE_BUILDERS[@]}"; do
        if ssh -o ConnectTimeout=3 -o BatchMode=yes "vadikas@$builder" true &>/dev/null; then
            local load
            load=$(ssh -o ConnectTimeout=3 -o BatchMode=yes "vadikas@$builder" "cat /proc/loadavg" 2>/dev/null | awk '{print $1, $2, $3}')
            echo -e "  $builder:  $(check_mark ok) load: ${load:-unknown}"
        else
            echo -e "  $builder:  $(check_mark fail) unreachable"
        fi
    done
    echo

    # Recent build stats summary
    echo -e "${CYAN}--- Recent Build Stats ---${RESET}"
    if [ -f "$STATS_LOG" ] && [ -s "$STATS_LOG" ]; then
        local total_builds total_built total_substituted total_fetched
        # Last 20 builds
        local recent
        recent=$(tail -20 "$STATS_LOG")
        total_builds=$(echo "$recent" | wc -l)
        total_built=$(echo "$recent" | jq -s '[.[].built] | add // 0')
        total_substituted=$(echo "$recent" | jq -s '[.[].substituted] | add // 0')
        total_fetched=$(echo "$recent" | jq -s '[.[].fetched_mb] | add // 0 | . * 10 | round / 10')

        local total_derivations=$(( total_built + total_substituted ))
        local cache_rate=0
        if (( total_derivations > 0 )); then
            cache_rate=$(awk "BEGIN{printf \"%.1f\", $total_substituted * 100.0 / $total_derivations}")
        fi

        echo "  Last $total_builds builds:"
        echo -e "    Built locally:  ${YELLOW}$total_built${RESET} derivations"
        echo -e "    From cache:     ${GREEN}$total_substituted${RESET} derivations"
        echo -e "    Cache hit rate: ${BOLD}${cache_rate}%${RESET}"
        echo -e "    Downloaded:     ${total_fetched} MB"
        echo
        echo -e "  ${DIM}Latest build:${RESET}"
        local latest
        latest=$(tail -1 "$STATS_LOG")
        local l_target l_built l_sub l_time l_date
        l_target=$(echo "$latest" | jq -r '.target // "unknown"')
        l_built=$(echo "$latest" | jq -r '.built')
        l_sub=$(echo "$latest" | jq -r '.substituted')
        l_time=$(echo "$latest" | jq -r '.duration_sec // "?"')
        l_date=$(echo "$latest" | jq -r '.timestamp')
        echo "    $l_date  $l_target"
        echo "    built: $l_built  cached: $l_sub  time: ${l_time}s"
    else
        echo -e "  ${DIM}No build data yet. Run: nix-dashboard build <nix-args>${RESET}"
    fi
    echo
}

cmd_build() {
    if [ $# -eq 0 ]; then
        echo "Usage: nix-dashboard build [nix build args...]"
        echo "Example: nix-dashboard build .#packages.x86_64-linux.foo"
        exit 1
    fi

    local target="${*}"
    local tmp_log dry_log
    tmp_log=$(mktemp)
    dry_log=$(mktemp)
    trap "rm -f $tmp_log $dry_log" EXIT

    echo -e "${BOLD}=== Building: $target ===${RESET}"
    echo

    # Dry-run first to get accurate build-vs-fetch counts
    echo -e "${DIM}Evaluating...${RESET}"
    nix build $@ --dry-run 2>"$dry_log" || true

    local built_count substituted_count fetched_mib
    local dry_out
    dry_out=$(cat "$dry_log")

    built_count=$(echo "$dry_out" | grep -oP 'these \K\d+(?= derivations will be built)' 2>/dev/null || true)
    if [ -z "$built_count" ]; then
        echo "$dry_out" | grep -q "this derivation will be built" 2>/dev/null && built_count=1 || built_count=0
    fi

    substituted_count=$(echo "$dry_out" | grep -oP 'these \K\d+(?= paths will be fetched)' 2>/dev/null || true)
    if [ -z "$substituted_count" ]; then
        echo "$dry_out" | grep -q "this path will be fetched" 2>/dev/null && substituted_count=1 || substituted_count=0
    fi

    fetched_mib=$(echo "$dry_out" | grep -oP '\(\K[\d.]+(?= MiB download)' 2>/dev/null || echo "0.0")

    # Sanitize
    built_count=$(echo "$built_count" | tr -dc '0-9'); built_count=${built_count:-0}
    substituted_count=$(echo "$substituted_count" | tr -dc '0-9'); substituted_count=${substituted_count:-0}
    fetched_mib=$(echo "$fetched_mib" | tr -d '[:space:]'); fetched_mib=${fetched_mib:-0.0}

    echo -e "${DIM}Will build $built_count, fetch $substituted_count ($fetched_mib MiB)${RESET}"
    echo

    local start_time
    start_time=$(date +%s)

    local exit_code=0
    nix build $@ -L 2>&1 | tee "$tmp_log" || exit_code=$?

    local end_time
    end_time=$(date +%s)
    local duration=$(( end_time - start_time ))

    echo
    echo -e "${BOLD}=== Build Summary ===${RESET}"
    echo -e "  Duration:    ${duration}s"

    local total_derivations=$(( built_count + substituted_count ))
    local cache_rate=0
    if (( total_derivations > 0 )); then
        cache_rate=$(awk "BEGIN{printf \"%.1f\", $substituted_count * 100.0 / $total_derivations}")
    fi

    echo -e "  Built:       ${YELLOW}$built_count${RESET} derivations"
    echo -e "  From cache:  ${GREEN}$substituted_count${RESET} derivations"
    echo -e "  Cache rate:  ${BOLD}${cache_rate}%${RESET}"
    [ "$fetched_mib" != "0.0" ] && echo -e "  Downloaded:  ${fetched_mib} MiB"

    if [ $exit_code -ne 0 ]; then
        echo -e "  Result:      ${RED}FAILED${RESET} (exit code: $exit_code)"
    else
        echo -e "  Result:      ${GREEN}SUCCESS${RESET}"
    fi
    echo

    # Save to stats log
    local record
    record=$(jq -nc \
        --arg ts "$(date -Iseconds)" \
        --arg target "$target" \
        --argjson built "$built_count" \
        --argjson substituted "$substituted_count" \
        --argjson duration "$duration" \
        --argjson fetched_mb "$(awk "BEGIN{printf \"%.1f\", $fetched_mib}")" \
        --argjson success "$([ $exit_code -eq 0 ] && echo true || echo false)" \
        '{timestamp: $ts, target: $target, built: $built, substituted: $substituted, duration_sec: $duration, fetched_mb: $fetched_mb, success: $success}')
    echo "$record" >> "$STATS_LOG"

    return $exit_code
}

cmd_history() {
    if [ ! -f "$STATS_LOG" ] || [ ! -s "$STATS_LOG" ]; then
        echo "No build history yet. Run: nix-dashboard build <nix-args>"
        exit 0
    fi

    local count="${1:-20}"

    echo -e "${BOLD}=== Build History (last $count) ===${RESET}"
    echo
    printf "  ${DIM}%-20s  %-6s %-6s %-7s %-7s %s${RESET}\n" "TIMESTAMP" "BUILT" "CACHED" "RATE" "TIME" "TARGET"
    printf "  ${DIM}%-20s  %-6s %-6s %-7s %-7s %s${RESET}\n" "---" "---" "---" "---" "---" "---"

    tail -"$count" "$STATS_LOG" | while IFS= read -r line; do
        local ts built sub dur target success rate
        ts=$(echo "$line" | jq -r '.timestamp' | cut -c1-19 | sed 's/T/ /')
        built=$(echo "$line" | jq -r '.built')
        sub=$(echo "$line" | jq -r '.substituted')
        dur=$(echo "$line" | jq -r '.duration_sec // "?"')
        target=$(echo "$line" | jq -r '.target // "?"' | head -c 40)
        success=$(echo "$line" | jq -r '.success')

        local total=$(( built + sub ))
        if (( total > 0 )); then
            rate=$(awk "BEGIN{printf \"%.0f%%\", $sub * 100.0 / $total}")
        else
            rate="-"
        fi

        local dur_fmt="${dur}s"
        local color=""
        if [ "$success" = "false" ]; then
            color="${RED}"
        fi

        printf "  ${color}%-20s  %-6s %-6s %-7s %-7s %s${RESET}\n" "$ts" "$built" "$sub" "$rate" "$dur_fmt" "$target"
    done
    echo

    # Overall stats
    echo -e "${BOLD}=== Overall Stats ===${RESET}"
    local total_builds total_built total_sub total_dur
    total_builds=$(wc -l < "$STATS_LOG")
    total_built=$(jq -s '[.[].built] | add // 0' "$STATS_LOG")
    total_sub=$(jq -s '[.[].substituted] | add // 0' "$STATS_LOG")
    total_dur=$(jq -s '[.[].duration_sec] | add // 0' "$STATS_LOG")

    local overall_total=$(( total_built + total_sub ))
    local overall_rate=0
    if (( overall_total > 0 )); then
        overall_rate=$(awk "BEGIN{printf \"%.1f\", $total_sub * 100.0 / $overall_total}")
    fi

    echo "  Total builds:     $total_builds"
    echo "  Total built:      $total_built derivations"
    echo "  Total cached:     $total_sub derivations"
    echo "  Overall hit rate: ${overall_rate}%"
    echo "  Total build time: ${total_dur}s"
    echo
}

cmd_dry_run() {
    if [ $# -eq 0 ]; then
        echo "Usage: nix-dashboard dry-run [nix build args...]"
        echo "Shows what will be built vs substituted without building."
        exit 1
    fi

    echo -e "${BOLD}=== Dry Run: $* ===${RESET}"
    echo

    local tmp_log
    tmp_log=$(mktemp)
    trap "rm -f $tmp_log" EXIT

    nix build "$@" --dry-run 2>&1 | tee "$tmp_log"

    echo
    echo -e "${BOLD}=== Prediction ===${RESET}"

    # Parse "these N derivations will be built:" and "these N paths will be fetched:"
    local will_build will_fetch
    will_build=$(grep -oP 'these (\d+) derivations will be built' "$tmp_log" | grep -oP '\d+' || echo 0)
    will_fetch=$(grep -oP 'these (\d+) paths will be fetched' "$tmp_log" | grep -oP '\d+' || echo 0)
    # Also handle "this derivation will be built:" (singular)
    if grep -q "this derivation will be built" "$tmp_log" 2>/dev/null; then
        will_build=$(( will_build + 1 ))
    fi
    if grep -q "this path will be fetched" "$tmp_log" 2>/dev/null; then
        will_fetch=$(( will_fetch + 1 ))
    fi

    local fetch_size
    fetch_size=$(grep -oP '[\d.]+ [A-Za-z]+B' "$tmp_log" | tail -1 || echo "unknown")

    local total=$(( will_build + will_fetch ))
    local rate=0
    if (( total > 0 )); then
        rate=$(awk "BEGIN{printf \"%.1f\", $will_fetch * 100.0 / $total}")
    fi

    echo -e "  Will build:   ${YELLOW}$will_build${RESET} derivations"
    echo -e "  Will fetch:   ${GREEN}$will_fetch${RESET} paths"
    [ -n "$fetch_size" ] && echo -e "  Download:     ~$fetch_size"
    echo -e "  Cache rate:   ${BOLD}${rate}%${RESET}"
    echo
}

# --- Main ---
case "${1:-status}" in
    status|s)
        cmd_status
        ;;
    build|b)
        shift
        cmd_build "$@"
        ;;
    history|h)
        shift
        cmd_history "${1:-20}"
        ;;
    dry-run|dry|d)
        shift
        cmd_dry_run "$@"
        ;;
    help|--help|-h)
        echo "nix-dashboard — Builder/cache health dashboard"
        echo
        echo "Usage:"
        echo "  nix-dashboard [status]             Show store, cache, and builder health"
        echo "  nix-dashboard build <nix-args>      Build with metrics tracking"
        echo "  nix-dashboard dry-run <nix-args>    Preview what will build vs fetch"
        echo "  nix-dashboard history [N]            Show last N builds (default: 20)"
        echo "  nix-dashboard help                   This help"
        echo
        echo "Environment:"
        echo "  NIX_DASHBOARD_DIR   Stats directory (default: /home/dev/.nix-dashboard)"
        echo "  NIX_CACHE_URL       Binary cache URL (default: http://artemis2:5000)"
        ;;
    *)
        echo "Unknown command: $1 (try 'nix-dashboard help')"
        exit 1
        ;;
esac
