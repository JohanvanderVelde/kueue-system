# Kueue System - Beheer

## Installatie

### v0.12.4 (met KueueViz)

```bash
helm install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --version=0.12.4 \
  --namespace kueue-system \
  -f ./values-0.12.4.yaml \
  --create-namespace --wait --timeout 300s
```

### v0.16.1

```bash
helm install kueue oci://registry.k8s.io/kueue/charts/kueue \
  --version=0.16.1 \
  --namespace kueue-system \
  -f ./values.yaml \
  --create-namespace --wait --timeout 300s
```

## KueueViz (port-forward)

KueueViz frontend maakt via de browser een WebSocket-verbinding naar de backend.
Bij port-forward moet de `REACT_APP_WEBSOCKET_URL` naar localhost wijzen.

```bash
# Patch de frontend env var
kubectl set env deployment/kueue-kueueviz-frontend \
  -n kueue-system \
  REACT_APP_WEBSOCKET_URL=ws://localhost:8081

# Wacht tot rollout klaar is
kubectl rollout status deployment/kueue-kueueviz-frontend -n kueue-system

# Start port-forwards
kubectl port-forward svc/kueue-kueueviz-backend -n kueue-system 8081:8080 &
kubectl port-forward svc/kueue-kueueviz-frontend -n kueue-system 8080:8080 &
```

Open http://localhost:8080

## Verwijderen

```bash
./remove-kueue.sh
```

Het script doorloopt de volgende stappen (met bevestiging per stap):

1. **ArgoCD Application** verwijderen (stopt auto-sync)
2. **Kyverno policies** verwijderen (voorkomt hergeneratie van CRs)
3. **Kueue custom resources** opruimen (in dependency-volgorde, met wait)
4. **Webhooks, APIServices, namespace resources** verwijderen (webhooks eerst)
5. **CRDs** verwijderen
6. **Namespace** verwijderen
