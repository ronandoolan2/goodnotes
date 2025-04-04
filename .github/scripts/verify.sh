#!/bin/bash
set -e

echo "🔍 Starting verification checks..."

# Function to check endpoint
check_endpoint() {
  local host=$1
  local expected=$2
  local max_retries=10  # Increased from 5 to 10
  local retry=0
  local success=false

  echo "🔍 Checking endpoint: $host"
  
  while [ $retry -lt $max_retries ] && [ "$success" = false ]; do
    # Add more verbose output for debugging
    echo "  - Attempt $((retry+1))/$max_retries: curl -s -H \"Host: $host\" http://localhost"
    
    # Use timeout to prevent hanging
    response=$(timeout 5s curl -s -H "Host: $host" http://localhost)
    if [ $? -ne 0 ]; then
      echo "  ⚠️ Curl command failed or timed out"
      retry=$((retry+1))
      echo "  ⏳ Waiting 10s before retry..."
      sleep 10  # Increased wait time between retries
      continue
    fi
    
    if echo "$response" | grep -q "$expected"; then
      echo "  ✅ Endpoint $host successfully returned '$expected'"
      success=true
    else
      echo "  ⚠️ Response didn't match expected content: \"$response\""
      retry=$((retry+1))
      echo "  ⏳ Waiting 10s before retry..."
      sleep 10
    fi
  done
  
  if [ "$success" = false ]; then
    echo "❌ Endpoint $host failed validation after $max_retries attempts"
    
    # More verbose diagnostics
    echo "📊 Current network status:"
    kubectl get nodes -o wide
    kubectl get pods -A -o wide
    kubectl get services -o wide
    kubectl get ingress -o wide
    
    # Check ingress controller logs
    echo "📊 Ingress controller logs:"
    kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
    
    # Check port forwarding status
    echo "📊 Port status on localhost:"
    netstat -tuln | grep 80
    
    # Check DNS resolution
    echo "📊 DNS resolution for localhost:"
    cat /etc/hosts | grep localhost
    
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
