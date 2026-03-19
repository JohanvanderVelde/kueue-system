# Kueue Queue Management

Dit project bevat twee manieren om Kueue queues in te richten, elk voor een andere use case.

---

## Use Case 1: Team-queues via ConfigMap (Kyverno-generated)

**Directory:** `scoped_cq/`

Teams kunnen zelf een **ClusterQueue** en **LocalQueue** aanmaken door een ConfigMap met het label `kueue.x-k8s.io/queue-config: "true"` in hun namespace te plaatsen. Kyverno genereert automatisch de bijbehorende resources.

Jobs die via deze queues lopen vallen **binnen de eigen ResourceQuota** van de namespace — er is geen speciale PriorityClass nodig.

### Hoe werkt het?

1. Een team maakt een ConfigMap aan in hun namespace met de gewenste quota-instellingen
2. Kyverno detecteert de ConfigMap (op basis van het label)
3. Er wordt automatisch een **ClusterQueue** `cq-<queueName>` aangemaakt
4. Er wordt een **LocalQueue** `lq-<queueName>` aangemaakt in de namespace
5. Met `synchronize: true` worden wijzigingen in de ConfigMap automatisch doorgevoerd

### ConfigMap velden

| Veld                 | Verplicht | Default          | Beschrijving                                       |
|----------------------|-----------|------------------|----------------------------------------------------|
| `queueName`          | Nee       | namespace naam   | Naam voor de queues (cq-/lq- prefix wordt toegevoegd) |
| `queueingStrategy`   | Nee       | `BestEffortFIFO` | `BestEffortFIFO` of `StrictFIFO`                   |
| `resourceFlavorName` | Nee       | `default-flavor` | Naam van de ResourceFlavor                         |
| `quota`              | Ja        | —                | YAML string met resource quota's (cpu, memory etc) |

### Voorbeeld ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kueue-queue-config
  namespace: team-ml
  labels:
    kueue.x-k8s.io/queue-config: "true"
data:
  queueName: "team-ml"
  quota: |
    cpu: "4"
    memory: "6Gi"
```

### Voorbeeld Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-training-job
  namespace: team-ml
  labels:
    kueue.x-k8s.io/queue-name: lq-team-ml
spec:
  template:
    spec:
      containers:
        - name: train
          image: my-image:latest
          resources:
            requests:
              cpu: "2"
              memory: "4Gi"
      restartPolicy: Never
```

### Toepassen

```bash
kubectl apply -f example-resource-flavor.yaml   # ResourceFlavor (eenmalig)
kubectl apply -f kyverno-rbac.yaml               # RBAC voor Kyverno
kubectl apply -f kyverno-policy.yaml             # Generate-policy
kubectl apply -f example-configmap.yaml          # Voorbeeld ConfigMap
```

---

## Use Case 2: MIG Sharing via Cohort (handmatige CQ's)

**Directory:** `share/`

Voor GPU MIG-resources is er een **gedeelde pool** (`cq-migs-to-share`) waaruit teams kunnen lenen via een **cohort**. Teams krijgen een eigen ClusterQueue met `nominalQuota: 0` en een `borrowingLimit` — ze hebben geen eigen GPU-quota maar mogen lenen uit de shared pool.

### PriorityClass `kueue-workload`

Jobs die MIG-resources gebruiken moeten de PriorityClass `kueue-workload` gebruiken. Deze PriorityClass is zo ingericht dat jobs **buiten de Kubernetes ResourceQuota** vallen — Kueue is volledig in de lead voor quota-management.

Een Kyverno **validation policy** zorgt ervoor dat alleen Jobs die een LocalQueue gebruiken waarvan de ClusterQueue in het `mig-sharing` cohort zit, deze PriorityClass mogen gebruiken. Dit is dynamisch: nieuwe teams worden automatisch toegestaan zodra hun CQ in het juiste cohort zit.

### Architectuur

```
Cohort: mig-sharing
├── cq-migs-to-share    (gedeelde pool: cpu 16, mem 48Gi, 4x mig-1g, 4x mig-2g)
├── cq-team-a           (nominalQuota 0, leent uit shared pool)
│   └── lq-team-a       (namespace: team-a)
└── cq-team-b           (nominalQuota 0, leent uit shared pool)
    └── lq-team-b       (namespace: team-b)
```

### BorrowingLimits per team-CQ

| Resource                  | nominalQuota | borrowingLimit |
|---------------------------|--------------|----------------|
| cpu                       | 0            | 4              |
| memory                    | 0            | 12Gi           |
| nvidia.com/mig-1g.5gb    | 0            | 2              |
| nvidia.com/mig-2g.10gb   | 0            | 2              |

### Voorbeeld Job (MIG sharing)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-gpu-job
  namespace: team-a
  labels:
    kueue.x-k8s.io/queue-name: lq-team-a
spec:
  template:
    spec:
      priorityClassName: kueue-workload
      containers:
        - name: gpu-task
          image: my-gpu-image:latest
          resources:
            requests:
              cpu: "2"
              memory: "8Gi"
              nvidia.com/mig-1g.5gb: "1"
      restartPolicy: Never
```

### Toepassen

```bash
kubectl apply -f share/cohort-mig-sharing.yaml            # Cohort
kubectl apply -f share/cq-migs-to-share.yaml              # Shared pool CQ
kubectl apply -f share/cq-team-a.yaml                     # Team-A CQ + LQ
kubectl apply -f share/cq-team-b.yaml                     # Team-B CQ + LQ
kubectl apply -f share/policy-restrict-priorityclass.yaml  # Kyverno validation policy
```

### Nieuw team toevoegen

1. Maak een nieuwe CQ + LQ aan (kopieer `cq-team-a.yaml` als template)
2. Zet `cohortName: mig-sharing` in de CQ spec
3. Pas `namespaceSelector` aan naar de juiste namespace
4. Dat is alles — de Kyverno policy herkent automatisch dat de CQ in het `mig-sharing` cohort zit

---

## Voorwaarden

- **Kyverno** moet geïnstalleerd zijn op het cluster
- **Kueue** moet geïnstalleerd zijn (CRDs aanwezig)
- De **ResourceFlavor** `default-flavor` moet bestaan (zie `example-resource-flavor.yaml`)
- De **PriorityClass** `kueue-workload` moet bestaan en uitgesloten zijn van ResourceQuota

## Verwijderen

- **Use Case 1:** Wanneer de ConfigMap wordt verwijderd, verwijdert Kyverno automatisch de CQ en LQ (`synchronize: true`)
- **Use Case 2:** Handmatig verwijderen met `kubectl delete -f share/`
