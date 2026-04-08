# Resource/MIG Sharing Strategieën
De beschikbare resources zijn beperkt. Het idee is om een MIG pool te creeren die door iedereen gebruikt kan worden, zonder dat hiervoor eerst een aanvraag bij team ICE gedaan hoeft te worden en die dus ook niet in de resourceQuota zit. Door de beschikbare resources kan het voorkomen dat de vraag naar MIGs meer is dan de MIG pool bedraagt, hierdoor ontkom je niet aan queuing. Deze oplossing is dus alleen geschikt voor jobs die gescheduled kunnen worden.

Hierin zijn de volgende oplossingen mogelijk. Hierbij zouden we nog teams meer prioriteit kunnen geven en / of met activeDeadlineSeconds de duur van jobs kunnen beperken.

## 1. Enkele CQ + meerdere LQs

Eén ClusterQueue met de volledige MIG pool, elk team een LocalQueue.

| Voordelen | Nadelen |
|---|---|
| Simpelste opzet | Geen per-team limiet |
| Minimaal beheer | First-come-first-served, geen eerlijkheid |
| Maximale benutting | 1 team kan alles opsnoepen |

## 2. Multi-CQ met borrowingLimit (`share/`)

Per team een CQ met `nominalQuota: 0` en een lage `borrowingLimit` (bijv. 2).

| Voordelen | Nadelen |
|---|---|
| Per-team limiet op MIG-gebruik | Ongebruikte MIGs niet benuttbaar boven cap |
| Lopende workloads nooit gepreempt | In rustige tijden begrensde capaciteit per team |
| Eenvoudig, voorspelbaar gedrag | Verspilling bij lage bezetting |

## 3. Fair Sharing alleen (`fairsharing/`, geen borrowingLimit)

Per team een CQ met `nominalQuota: 0`, geen `borrowingLimit`, Fair Sharing enabled.

| Voordelen | Nadelen |
|---|---|
| Maximale benutting: 1 team kan alles pakken in rustige tijd | Lopende workloads worden gepreempt (disruptief) |
| Eerlijke verdeling bij contention via DRS | Bij veel teams + weinig MIGs: constante preempties |
| Geen verspilling | Workloads moeten idempotent/herstartbaar zijn |
| | Complexer om te begrijpen voor teams |

## 4. Combinatie: Fair Sharing + hoge borrowingLimit

Per team een CQ met `nominalQuota: 0` en een **hoge** `borrowingLimit`, Fair Sharing enabled.

| Voordelen | Nadelen |
|---|---|
| Burst in rustige tijd (tot borrowingLimit) | Nog steeds preemptie mogelijk (maar minder dan optie 3) |
| BorrowingLimit voorkomt totale monopolie | Workloads moeten herstartbaar zijn |
| Minder preempties dan pure Fair Sharing | Iets complexer qua configuratie |
| Eerlijke verdeling bij meer vraag dan aanbod | borrowingLimit moet bewust gekozen worden |
| Voorspelbaarder dan optie 3 | |

