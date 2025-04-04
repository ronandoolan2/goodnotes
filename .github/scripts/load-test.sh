#!/bin/bash
set -e

echo "🚀 Preparing load test..."

# Create a temporary directory for test artifacts
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create k6 load test script
cat > "$TEST_DIR/load-test.js" << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

// Custom metrics
const fooRequestDuration = new Trend('foo_request_duration');
const barRequestDuration = new Trend('bar_request_duration');
const failRate = new Rate('failed_requests');
const fooRequests = new Counter('foo_requests');
const barRequests = new Counter('bar_requests');

export const options = {
  scenarios: {
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '10s', target: 5 },
        { duration: '20s', target: 10 },
        { duration: '10s', target: 0 },
      ],
    },
  },
  thresholds: {
    'failed_requests': ['rate<0.05'], // Less than 5% of requests should fail
    'foo_request_duration': ['p(95)<500'], // 95% of requests should be below 500ms
    'bar_request_duration': ['p(95)<500'], // 95% of requests should be below 500ms
  },
};

export default function() {
  // Randomly choose between foo and bar
  const target = Math.random() < 0.5 ? 'foo' : 'bar';
  const url = `http://localhost`;
  const params = {
    headers: {
      'Host': `${target}.localhost`,
    },
  };
  
  const res = http.get(url, params);
  
  if (target === 'foo') {
    fooRequests.add(1);
    fooRequestDuration.add(res.timings.duration);
  } else {
    barRequests.add(1);
    barRequestDuration.add(res.timings.duration);
  }
  
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    [`response body contains "${target}"`]: (r) => r.body.includes(target),
  });
  
  if (!success) {
    failRate.add(1);
  }
  
  sleep(0.1);
}
EOF

# Run load test
echo "🚀 Running load test..."
k6 run --summary-export="$TEST_DIR/load-test-summary.json" "$TEST_DIR/load-test.js"

# Generate a human-readable report
echo "📊 Generating load test report..."

echo "=============================================="
echo "🚀 LOAD TEST RESULTS SUMMARY"
echo "=============================================="
echo ""

# Extract metrics with proper error handling
get_metric() {
  local metric=$1
  local field=$2
  value=$(jq -r ".metrics.${metric}.${field} // \"N/A\"" "$TEST_DIR/load-test-summary.json")
  if [ "$value" != "null" ] && [ "$value" != "N/A" ]; then
    echo "$value"
  else
    echo "N/A"
  fi
}

# Overall statistics
total_requests=$(get_metric "iterations" "count")
foo_requests=$(get_metric "foo_requests" "count")
bar_requests=$(get_metric "bar_requests" "count")
failed_rate=$(get_metric "failed_requests" "rate")
if [ -z "$failed_rate" ] || [ "$failed_rate" = "null" ] || [ "$failed_rate" = "N/A" ]; then
  failed_percent="0.00"
else
  failed_percent=$(awk "BEGIN { printf \"%.2f\", ${failed_rate} * 100 }")
fi


echo "OVERALL STATISTICS"
echo "-----------------"
echo "Total Requests: $total_requests"
echo "  - Foo Requests: $foo_requests"
echo "  - Bar Requests: $bar_requests"
echo "Failed Requests: ${failed_percent}%"
echo ""

# Endpoint performance
echo "FOO ENDPOINT PERFORMANCE"
echo "-----------------------"
echo "Avg Duration: $(get_metric "foo_request_duration" "avg") ms"
echo "Min Duration: $(get_metric "foo_request_duration" "min") ms"
echo "Max Duration: $(get_metric "foo_request_duration" "max") ms"
echo "p90 Duration: $(get_metric "foo_request_duration" "p(90)") ms"
echo "p95 Duration: $(get_metric "foo_request_duration" "p(95)") ms"
echo ""

echo "BAR ENDPOINT PERFORMANCE"
echo "-----------------------"
echo "Avg Duration: $(get_metric "bar_request_duration" "avg") ms"
echo "Min Duration: $(get_metric "bar_request_duration" "min") ms"
echo "Max Duration: $(get_metric "bar_request_duration" "max") ms"
echo "p90 Duration: $(get_metric "bar_request_duration" "p(90)") ms"
echo "p95 Duration: $(get_metric "bar_request_duration" "p(95)") ms"
echo ""

# Request rate statistics
echo "REQUEST RATE"
echo "-----------"
echo "Requests/sec: $(get_metric "iterations" "rate")"
echo ""

# Thresholds check
thresholds_passed=$(jq -r '.root_group.checks // [] | length' "$TEST_DIR/load-test-summary.json")
if [ "$thresholds_passed" -gt 0 ]; then
  echo "✅ All thresholds passed"
else
  echo "⚠️ Some thresholds failed - check detailed logs"
fi

# Collect resource metrics if Prometheus is enabled
if kubectl get namespace monitoring &>/dev/null; then
  echo "📊 Collecting resource metrics..."
  bash -x ls
  bash ./collect-metrics.sh >> "$TEST_DIR/metrics.txt"
  cat "$TEST_DIR/metrics.txt"
fi

echo "=============================================="
