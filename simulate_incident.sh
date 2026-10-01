#!/usr/bin/env bash
set -e

BACKEND_URL="${1:-http://localhost:8000}"
REQUEST_COUNT=1500

echo "========================================================================"
echo " SIT753 7.3HD DevOps - Live Incident Simulation (Traffic Surge / DoS)  "
echo " Target Endpoint: $BACKEND_URL/health"
echo " Total Requests:  $REQUEST_COUNT asynchronous requests"
echo "========================================================================"
echo ">> Dispatching traffic surge to trigger CPU & Network telemetry spikes..."

START_TIME=$(date +%s)
for i in $(seq 1 $REQUEST_COUNT); do
    curl -s -o /dev/null "$BACKEND_URL/health" &
    if [ $((i % 500)) -eq 0 ]; then
        echo "  [+] Dispatched $i / $REQUEST_COUNT requests..."
    fi
done
wait
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "------------------------------------------------------------------------"
echo "[SUCCESS] Traffic surge incident completed in ${DURATION}s."
echo ">> Real-time telemetry spikes are now observable in monitoring tools:"
echo "   - cAdvisor:   http://localhost:8085/containers/"
echo "   - Prometheus: http://localhost:9090 (Query: rate(container_cpu_usage_seconds_total[1m]))"
echo "   - Grafana:    http://localhost:3001"
echo "========================================================================"
