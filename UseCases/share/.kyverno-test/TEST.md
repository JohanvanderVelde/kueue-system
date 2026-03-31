# Kyverno Policy Test Beperkingen

## 1. `kyverno-policy-fixed.yaml` — Generate Shared Kueue Queues

**Status:** Test niet aanwezig in `.kyverno-test/`

**Reden:** De kyverno CLI kent de Kueue CRDs (`ClusterQueue`, `LocalQueue`) niet in offline modus. Daardoor neemt de CLI aan dat `ClusterQueue` een namespaced resource is en eist een `namespace` veld in de generate rule — terwijl `ClusterQueue` cluster-scoped is. De CLI voert de generate rule niet uit en vergelijkt dus niet met de expected output.

**Workaround:** Alleen in-cluster testbaar met Kueue CRDs geïnstalleerd.

## 2. `policy-restrict-priorityclass.yaml` — Restrict kueue-workload PriorityClass

**Status:** Niet lokaal testbaar.

**Reden:** De policy gebruikt `apiCall` met `urlPath` om live LocalQueue en ClusterQueue objecten op te halen uit de cluster API. De kyverno CLI kan deze API-calls niet simuleren in offline modus.

**Workaround:** Alleen testbaar met `kyverno apply --cluster` tegen een draaiend cluster met Kueue.
