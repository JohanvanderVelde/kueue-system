# install kind cluster
kind create cluster --name localdev

# install cert-manager
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.19.2 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

# install prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 82.2.1 \
  --namespace monitoring \
  --create-namespace \
  -f ./monitoring-values.yaml \
  --wait --timeout 300s

# install argocd
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --wait --timeout 300s

# install kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update kyverno
helm install kyverno kyverno/kyverno \
  --version 3.7.1 \
  --namespace kyverno \
  --create-namespace \
  --wait --timeout 300s

# install kueue
helm install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --version=0.16.1 \
  --namespace kueue-system \
  -f ./values.yaml \
  --wait --timeout 300s