#!/bin/bash
set -e

echo "Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "Waiting for ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

echo "Creating foo deployment..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: foo-deployment
  labels:
    app: foo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: foo
  template:
    metadata:
      labels:
        app: foo
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:latest
        args:
        - "-text=foo"
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: foo-service
spec:
  selector:
    app: foo
  ports:
  - port: 80
    targetPort: 5678
EOF

echo "Creating bar deployment..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bar-deployment
  labels:
    app: bar
spec:
  replicas: 2
  selector:
    matchLabels:
      app: bar
  template:
    metadata:
      labels:
        app: bar
    spec:
      containers:
      - name: http-echo
        image: hashicorp/http-echo:latest
        args:
        - "-text=bar"
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: bar-service
spec:
  selector:
    app: bar
  ports:
  - port: 80
    targetPort: 5678
EOF

echo "Creating ingress routes..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: foo.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: foo-service
            port:
              number: 80
  - host: bar.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: bar-service
            port:
              number: 80
EOF

echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=90s deployment/foo-deployment
kubectl wait --for=condition=available --timeout=90s deployment/bar-deployment

echo "Setting up local DNS for testing..."
echo "127.0.0.1 foo.localhost bar.localhost" | sudo tee -a /etc/hosts

echo "Verifying routes..."
curl -s -H "Host: foo.localhost" http://localhost | grep "foo"
curl -s -H "Host: bar.localhost" http://localhost | grep "bar"

echo "Deployment complete!"
