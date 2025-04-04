# scripts/collect-metrics.sh
#!/bin/bash
set -e

METRICS_DIR=$(mktemp -d)
trap 'rm -rf "$METRICS_DIR"' EXIT

echo "📊 Collecting resource metrics from Prometheus..."

# Forward Prometheus port
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
PF_PID=$!
trap 'kill $PF_PID; rm -rf "$METRICS_DIR"' EXIT
sleep 3

# Collect CPU metrics for both services
curl -s "http://localhost:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total{pod=~\"foo-deployment.*|bar-deployment.*\"}[1m])" | jq . > "$METRICS_DIR/cpu.json"

# Collect memory metrics for both services
curl -s "http://localhost:9090/api/v1/query?query=container_memory_working_set_bytes{pod=~\"foo-deployment.*|bar-deployment.*\"}" | jq . > "$METRICS_DIR/memory.json"

# Generate resource report
echo "=============================================="
echo "🖥️  RESOURCE UTILIZATION DURING LOAD TEST"
echo "=============================================="
echo ""

# Extract and format CPU metrics
echo "CPU USAGE (cores)"
echo "----------------"
jq -r '.data.result[] | select(.metric.container_name != "POD") | "- " + (.metric.pod // "unknown") + ": " + (.value[1] | tonumber * 1000 | round / 1000 | tostring) + " cores"' "$METRICS_DIR/cpu.json" || echo "- No CPU metrics available"
echo ""

# Extract and format memory metrics
echo "MEMORY USAGE"
echo "------------"
jq -r '.data.result[] | select(.metric.container_name != "POD") | "- " + (.metric.pod // "unknown") + ": " + (.value[1] | tonumber / (1024*1024) | round | tostring) + " MB"' "$METRICS_DIR/memory.json" || echo "- No memory metrics available"
echo ""

echo "=============================================="

# Kill port-forward
kill $PF_PID
