# Use Case: Scoped ClusterQueue (eigen ResourceQuota)

## Wanneer gebruiken?

- Teams willen een **queue-mechanisme** voor hun batch workloads
- Teams willen **gegarandeerde isolatie**: hun workloads worden nooit beïnvloed door andere teams
- De resources vallen binnen de reguliere **ResourceQuota** en hoeven niet buiten quota om beheerd te worden

## Overzicht

In deze opzet maakt elk team gebruik van een **eigen ClusterQueue** die gekoppeld is aan hun namespace. De resources in de ClusterQueue komen overeen met de resources die het team al tot zijn beschikking heeft via de Kubernetes **ResourceQuota**. Er is geen gedeelde pool en er wordt niet geleend van andere teams.

Het primaire voordeel van deze opzet is het **queue-mechanisme**: wanneer een team meer workloads indient dan er resources beschikbaar zijn, worden deze in een wachtrij geplaatst en automatisch gestart zodra er capaciteit vrijkomt — in plaats van dat ze falen of handmatig opnieuw ingediend moeten worden.

Elk team heeft zijn eigen, geïsoleerde queue-structuur. Er is geen cohort en geen interactie met queues van andere teams.

## Voordelen en nadelen

| Voordelen | Nadelen |
|---|---|
| Queue-mechanisme: workloads wachten automatisch op capaciteit | Geen mogelijkheid om ongebruikte resources van andere teams te benutten |
| Self-service: teams beheren hun eigen queue via een ConfigMap | Quota in ConfigMap moet synchroon blijven met ResourceQuota |
| Geen preemptie door andere teams: volledige isolatie | Geen resource-sharing: ongebruikte capaciteit blijft onbenut |
| Eenvoudig te begrijpen voor teams | Extra laag bovenop bestaande ResourceQuota |
| Prioritering binnen de queue mogelijk | |
| Wijzigingen in ConfigMap worden automatisch doorgevoerd | |
