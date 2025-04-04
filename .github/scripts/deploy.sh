#!/bin/bash
set -e

echo "📋 Starting deployment process..."

# Set error handling
handle_error() {
  echo "❌ Error occurred at line $1"
  exit 1
}
trap 'handle_error $LINENO' ERR

# Create namespace for our applications
echo "👉 Creating default namespace if it doesn't exist..."
kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -

# Install NGINX Ingress Controller for KinD
echo "👉 Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "👉 Waiting for NGINX Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || {
    echo "❌ Timed out waiting for Ingress controller to be ready"
    kubectl get pods -n ingress-nginx
    kubectl describe pods -n ingress-nginx -l app.kubernetes.io/component=controller
    exit 1
  }

# Deploy foo application
echo "👉 Deploying foo application..."
kubectl apply -f .github/k8s/foo-deployment.yaml

# Deploy bar application
echo "👉 Deploying bar application..."
kubectl apply -f .github/k8s/bar-deployment.yaml

# Deploy ingress
echo "👉 Deploying ingress rules..."
kubectl apply -f .github/k8s/ingress.yaml

# Optional: Deploy Prometheus for monitoring
if [ "${DEPLOY_MONITORING:-false}" == "true" ]; then
  echo "👉 Deploying Prometheus monitoring stack..."
  kubectl apply -f .github/k8s/monitoring/prometheus.yaml
fi

# Wait for deployments to be ready
echo "👉 Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/foo-deployment || {
  echo "❌ Foo deployment failed to become ready"
  kubectl describe deployment foo-deployment
  exit 1
}

kubectl wait --for=condition=available --timeout=60s deployment/bar-deployment || {
  echo "❌ Bar deployment failed to become ready"
  kubectl describe deployment bar-deployment
  exit 1
}

# Add hosts to /etc/hosts for local testing
echo "👉 Setting up local DNS for testing..."
echo "127.0.0.1 foo.localhost bar.localhost" | sudo tee -a /etc/hosts

echo "✅ Deployment completed successfully!"
