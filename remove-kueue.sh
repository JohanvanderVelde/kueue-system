#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="kueue-system"
ARGOCD_NS="argocd"
APP_NAME="kueue"

confirm() {
  echo -e "${YELLOW}$1${NC}"
  read -r -p "Doorgaan? (j/n): " response
  [[ "$response" =~ ^[jJyY]$ ]] || { echo "Afgebroken."; exit 1; }
}

echo -e "${YELLOW}=== Kueue Verwijder Script ===${NC}"
echo ""

# ─── Stap 0: Pre-flight checks ───
echo -e "${GREEN}[0/6] Pre-flight checks...${NC}"
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}Geen verbinding met het cluster. Controleer je kubeconfig.${NC}"
  exit 1
fi
echo "Cluster bereikbaar."

# ─── Stap 1: ArgoCD Application verwijderen ───
echo ""
echo -e "${GREEN}[1/6] ArgoCD Application verwijderen...${NC}"
if kubectl get application "$APP_NAME" -n "$ARGOCD_NS" &>/dev/null; then
  confirm "  ArgoCD Application '$APP_NAME' gevonden. Dit stopt de auto-sync (resources blijven bestaan)."
  kubectl delete application "$APP_NAME" -n "$ARGOCD_NS"
  echo -e "  ${GREEN}✓ ArgoCD Application verwijderd.${NC}"
else
  echo "  Geen ArgoCD Application '$APP_NAME' gevonden, overgeslagen."
fi

# ─── Stap 2: Kyverno policies gerelateerd aan Kueue verwijderen ───
echo ""
echo -e "${GREEN}[2/6] Kyverno policies gerelateerd aan Kueue verwijderen...${NC}"
echo "(Moet vóór CR-verwijdering, anders hergenereren policies de resources)"

KUEUE_POLICIES=$(kubectl get clusterpolicy -o name 2>/dev/null | grep -i "kueue\|clusterqueue\|localqueue" || true)
if [[ -n "$KUEUE_POLICIES" ]]; then
  echo "  Gevonden policies:"
  echo "$KUEUE_POLICIES"
  confirm "Bovenstaande Kyverno policies verwijderen?"
  echo "$KUEUE_POLICIES" | xargs kubectl delete 2>/dev/null || true
  echo -e "${GREEN}Kyverno policies verwijderd.${NC}"
else
  echo "Geen Kueue-gerelateerde Kyverno policies gevonden."
fi

# ─── Stap 3: Kueue custom resources opruimen ───
echo ""
echo -e "${GREEN}[3/6] Kueue custom resources opruimen (workloads, queues, etc.)...${NC}"

# Volgorde is belangrijk: eerst dependents, dan parents
# workloads → localqueues → clusterqueues → (wacht tot weg) → cohorts → resourceflavors
KUEUE_RESOURCES=(
  "workloads"
  "localqueues"
  "admissionchecks"
  "workloadpriorityclasses"
  "multikueueclusters"
  "multikueueconfigs"
  "provisioningrequestconfigs"
  "clusterqueues"
  "cohorts"
  "resourceflavors"
)

wait_for_deletion() {
  local resource=$1
  local timeout=60
  local elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    count=$(kubectl get "$resource" -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" -eq 0 ]] && return 0
    echo "  Wachten op verwijdering van $resource ($count resterend)..."
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo -e "${RED}Timeout: $resource niet volledig verwijderd na ${timeout}s${NC}"
  return 1
}

for resource in "${KUEUE_RESOURCES[@]}"; do
  if kubectl api-resources --api-group=kueue.x-k8s.io -o name 2>/dev/null | grep -q "$resource"; then
    count=$(kubectl get "$resource" -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      echo "Verwijderen: $resource ($count gevonden)..."
      kubectl delete "$resource" --all -A --timeout=60s 2>/dev/null || true
      wait_for_deletion "$resource"
    else
      echo "Geen $resource gevonden."
    fi
  fi
done
echo -e "${GREEN}Custom resources opgeruimd.${NC}"

# ─── Stap 4: Kueue resources in namespace verwijderen ───
echo ""
echo -e "${GREEN}[4/6] Alle resources in namespace '$NAMESPACE' verwijderen...${NC}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  confirm "Alle resources (webhooks, apiservices, deployments, services, RBAC, etc.) in '$NAMESPACE' verwijderen?"
  # Webhooks en APIServices EERST verwijderen om API-blokkades te voorkomen
  kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/name=kueue --timeout=60s 2>/dev/null || true
  kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/name=kueue --timeout=60s 2>/dev/null || true
  kubectl delete apiservices -l app.kubernetes.io/name=kueue --timeout=60s 2>/dev/null || true
  # Fallback: verwijder op naam als het label ontbreekt
  kubectl delete apiservices v1beta1.visibility.kueue.x-k8s.io v1beta2.visibility.kueue.x-k8s.io --timeout=60s 2>/dev/null || true
  # Daarna de rest (met label selector om alleen Kueue-resources te raken)
  kubectl delete all -l app.kubernetes.io/name=kueue -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
  kubectl delete configmaps -l app.kubernetes.io/name=kueue -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
  kubectl delete secrets -l app.kubernetes.io/name=kueue -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
  # Cert-manager secrets (hebben eigen label, worden opgeruimd bij namespace delete)
  kubectl delete secrets -l controller.cert-manager.io/fao=true -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
  kubectl delete serviceaccounts -l app.kubernetes.io/name=kueue -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
  kubectl delete roles -l app.kubernetes.io/name=kueue -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
  kubectl delete rolebindings -l app.kubernetes.io/name=kueue -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
  kubectl delete clusterroles -l app.kubernetes.io/name=kueue --timeout=60s 2>/dev/null || true
  kubectl delete clusterrolebindings -l app.kubernetes.io/name=kueue --timeout=60s 2>/dev/null || true
  # Kueue visibility rolebinding in kube-system (wordt niet meegenomen door namespace-scoped deletes)
  kubectl delete rolebinding kueue-visibility-server-auth-reader -n kube-system --timeout=60s 2>/dev/null || true
  echo -e "${GREEN}Kueue resources verwijderd.${NC}"
else
  echo "Namespace '$NAMESPACE' bestaat niet, overgeslagen."
fi

# ─── Stap 5: CRDs verwijderen ───
echo ""
echo -e "${GREEN}[5/6] Kueue CRDs verwijderen...${NC}"
KUEUE_CRDS=$(kubectl get crds -l app.kubernetes.io/name=kueue -o name 2>/dev/null || true)
if [[ -n "$KUEUE_CRDS" ]]; then
  echo "Gevonden CRDs:"
  echo "$KUEUE_CRDS"
  confirm "Bovenstaande CRDs verwijderen?"
  echo "$KUEUE_CRDS" | xargs kubectl delete --timeout=60s
  echo -e "${GREEN}CRDs verwijderd.${NC}"
else
  echo "Geen Kueue CRDs gevonden."
fi

# ─── Stap 6: Namespace opruimen ───
echo ""
echo -e "${GREEN}[6/6] Namespace '$NAMESPACE' verwijderen...${NC}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  confirm "Namespace '$NAMESPACE' verwijderen?"
  kubectl delete namespace "$NAMESPACE" --timeout=120s
  echo -e "${GREEN}Namespace verwijderd.${NC}"
else
  echo "Namespace '$NAMESPACE' bestaat niet meer."
fi

echo ""
echo -e "${GREEN}=== Kueue volledig verwijderd ===${NC}"
echo ""
