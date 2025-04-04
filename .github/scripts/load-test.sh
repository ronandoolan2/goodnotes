#!/bin/bash
set -e

# Create k6 load test script
cat > load-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

// Custom metrics
const fooRequestDuration = new Trend('foo_request_duration');
const barRequestDuration = new Trend('bar_request_duration');
const failRate = new Rate('failed_requests');
const requestCount = new Counter('requests');

export const options = {
  scenarios: {
    constant_load: {
      executor: 'constant-vus',
      vus: 10,
      duration: '30s',
    },
  },
  thresholds: {
    'failed_requests': ['rate<0.1'], // Less than 10% of requests should fail
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
  requestCount.add(1);
  
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    [`response body contains "${target}"`]: (r) => r.body.includes(target),
  });
  
  if (!success) {
    failRate.add(1);
  }
  
  if (target === 'foo') {
    fooRequestDuration.add(res.timings.duration);
  } else {
    barRequestDuration.add(res.timings.duration);
  }
  
  sleep(0.1);
}
EOF

# Run load test
echo "Running load test..."
k6 run load-test.js --summary-export=load-test-summary.json

# Generate a human-readable report from the JSON output
echo "# Load Test Results Summary"
echo ""
echo "## Overall Statistics"
echo "- Total Requests: $(jq '.metrics.requests.count' load-test-summary.json)"
echo "- Failed Requests: $(jq '.metrics.failed_requests.rate * 100' load-test-summary.json)%"
echo ""
echo "## Foo Endpoint Performance"
echo "- Avg Duration: $(jq '.metrics.foo_request_duration.avg' load-test-summary.json) ms"
echo "- Min Duration: $(jq '.metrics.foo_request_duration.min' load-test-summary.json) ms"
echo "- Max Duration: $(jq '.metrics.foo_request_duration.max' load-test-summary.json) ms"
echo "- p90 Duration: $(jq '.metrics.foo_request_duration["p(90)"]' load-test-summary.json) ms"
echo "- p95 Duration: $(jq '.metrics.foo_request_duration["p(95)"]' load-test-summary.json) ms"
echo ""
echo "## Bar Endpoint Performance"
echo "- Avg Duration: $(jq '.metrics.bar_request_duration.avg' load-test-summary.json) ms"
echo "- Min Duration: $(jq '.metrics.bar_request_duration.min' load-test-summary.json) ms"
echo "- Max Duration: $(jq '.metrics.bar_request_duration.max' load-test-summary.json) ms"
echo "- p90 Duration: $(jq '.metrics.bar_request_duration["p(90)"]' load-test-summary.json) ms"
echo "- p95 Duration: $(jq '.metrics.bar_request_duration["p(95)"]' load-test-summary.json) ms"
echo ""
echo "## Requests per Second"
echo "- Requests/sec: $(jq '.metrics.iterations.rate' load-test-summary.json)"
