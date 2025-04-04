#!/bin/bash
set -e

echo "🔍 Starting verification checks..."

# Function to check endpoint
check_endpoint() {
  local host=$1
  local expected=$2
  local max_retries=5
  local retry=0
  local success=false

  echo "🔍 Checking endpoint: $host"
  
  while [ $retry -lt $max_retries ] && [ "$success" = false ]; do
    response=$(curl -s -H "Host: $host" http://localhost)
    if echo "$response" | grep -q "$expected"; then
      echo "✅ Endpoint $host successfully returned '$expected'"
      success=true
    else
      retry=$((retry+1))
      echo "⚠️ Attempt $retry: Endpoint $host did not return expected output, retrying in 5s..."
      sleep 5
    fi
  done
  
  if [ "$success" = false ]; then
    echo "❌ Endpoint $host failed validation after $max_retries attempts"
    echo "Got: $response"
    echo "Expected to contain: $expected"
    
    # Diagnostic information
    echo "📊 Diagnostic information:"
    kubectl get pods
    kubectl get services
    kubectl get ingress
    kubectl get events --sort-by='.lastTimestamp'
    
    exit 1
  fi
}

# Show cluster status
echo "📊 Current cluster status:"
kubectl get nodes
kubectl get pods -A
kubectl get services
kubectl get ingress

# Check that foo endpoint works
check_endpoint "foo.localhost" "foo"

# Check that bar endpoint works
check_endpoint "bar.localhost" "bar"

echo "✅ All verification checks passed successfully!"
