# Architecture Deep Dive

This document explains the reasoning behind every significant decision in the BakTrack EKS reference architecture.

---

## Network Design

### VPC Layout

```
10.10.0.0/16
├── Public subnets
│   ├── 10.10.101.0/24  (ap-south-1a)  ← ALB, NAT Gateway
│   └── 10.10.102.0/24  (ap-south-1b)  ← ALB
└── Private subnets
    ├── 10.10.1.0/24    (ap-south-1a)  ← EKS nodes
    └── 10.10.2.0/24    (ap-south-1b)  ← EKS nodes
```

**Why two AZs?** EKS requires subnets in at least two AZs to schedule pods with pod anti-affinity. It also gives the ALB controller two AZs to spread traffic across.

**Why a single NAT Gateway?** A second NAT in ap-south-1b would cost ~$32/month extra and provide resilience only if an entire AZ fails — unlikely for a portfolio project. In production, one NAT per AZ is the right call.

**Subnet tagging** is critical. EKS and the ALB controller discover subnets via these tags:
- `kubernetes.io/role/elb=1` on public subnets → ALB placement
- `kubernetes.io/role/internal-elb=1` on private subnets → internal NLB
- `karpenter.sh/discovery=baktrack-dev` on private subnets → Karpenter node launch

---

## Compute Strategy

### Two node groups, two purposes

| Node group | Type | Capacity | Purpose |
|---|---|---|---|
| `system` | t3.small | ON_DEMAND, min 1 | ArgoCD, Karpenter, ESO, cert-manager, kube-prometheus-stack |
| `app` | t3.small | SPOT, min 1 max 3 | notification-api, video-processor, ai-inference-stub |

System pods carry a `CriticalAddonsOnly:NoSchedule` taint. This prevents app workloads from evicting or crowding out the controllers that manage the cluster. Spot interruptions on the app node group are tolerable — Flask services are stateless and restart fast.

### Karpenter vs cluster-autoscaler

Cluster-autoscaler scales node groups — it's slow (1–2 min), coarse-grained, and requires pre-defined groups for each instance type. Karpenter watches pending pods directly and launches the cheapest matching EC2 instance within seconds. For a cost-sensitive portfolio project with unpredictable load, Karpenter is the right tool.

---

## IAM Design

### IRSA — No static keys anywhere

Every component that needs AWS access uses IRSA (IAM Roles for Service Accounts):

```
Pod (Kubernetes ServiceAccount)
  └─▶ OIDC token mounted by EKS
        └─▶ AWS STS AssumeRoleWithWebIdentity
              └─▶ IAM Role (scoped to exact permissions)
                    └─▶ AWS API call
```

| Component | IAM Role | Permissions |
|---|---|---|
| AWS LB Controller | `baktrack-dev-alb-controller` | `elasticloadbalancing:*`, `ec2:Describe*` |
| Karpenter | `baktrack-dev-karpenter` | `ec2:RunInstances`, `ec2:TerminateInstances`, SQS |
| GitHub Actions CI | `gha-ecr-push` | `ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:PutImage` |

The CI role uses **OIDC federation** — GitHub Actions workflows get a short-lived token from `token.actions.githubusercontent.com` and assume the role without any stored secret. The role trust policy is scoped to `repo:Yash-Rathod/*:*` so only repos in this GitHub account can assume it.

---

## GitOps Flow

```
Developer
  │
  ├─ git push to mock-services
  │     └─▶ GitHub Actions
  │           ├─ pytest (unit tests must pass)
  │           ├─ docker build
  │           ├─ ECR push (tag = first 7 chars of git SHA)
  │           └─ bump tag in apps-config (via PAT)
  │
  └─ git push to apps-config (by CI, or manually for platform changes)
        └─▶ ArgoCD detects diff (polls every 3 min)
              └─▶ helm upgrade with new values
                    └─▶ Kubernetes rolling update
                          └─▶ new pods become Ready
                                └─▶ old pods terminated
```

**Why separate repos?** Separating `infra-terraform`, `helm-charts`, `apps-config`, and `mock-services` mirrors how real GitOps shops operate — different teams own different repos, different approval processes, different change velocities. The infra repo changes once a month; the app repo changes dozens of times a day.

**Why not Flux?** ArgoCD has a UI that makes the sync state visible at a glance — essential for a portfolio where a hiring manager needs to see what's happening without running `kubectl`.

---

## Observability Stack

```
kube-prometheus-stack (one Helm chart installs everything)
├── prometheus-operator          # manages Prometheus CRDs
├── Prometheus                   # scrapes targets, stores time-series
│   └── ServiceMonitors          # per-app scrape configs (this repo)
│       ├── notification-api-dev (port 8080, /metrics, 30s)
│       ├── video-processor-dev  (port 8080, /metrics, 30s)
│       └── ai-inference-stub-dev(port 8080, /metrics, 30s)
├── Alertmanager                 # routes alerts
│   └── PrometheusRule: PodCrashLooping
├── Grafana                      # dashboards
│   ├── Dashboard: Kubernetes / Views / Global (ID 15757)
│   └── Dashboard: BakTrack services (flask_http_request_total)
├── kube-state-metrics           # cluster resource metrics
└── node-exporter                # per-node OS metrics (CPU, memory, disk)
```

**Why ServiceMonitor instead of pod annotations?** Both work, but `ServiceMonitor` is the operator-native pattern — it creates a CRD that Prometheus operator watches. Pod annotations require Prometheus to have a broad `scrape_configs` rule. ServiceMonitors are more explicit and easier to audit.

---

## Multi-Environment Strategy

Three environments exist in code; only `dev` is applied to save cost:

| Env | CIDR | Cluster name | Status |
|---|---|---|---|
| dev | 10.10.0.0/16 | baktrack-dev | Applied — live |
| staging | 10.20.0.0/16 | baktrack-staging | Code only |
| prod | 10.30.0.0/16 | baktrack-prod | Code only |

Each environment has its own:
- `terraform.tfstate` key in S3
- VPC CIDR (no overlap — peering-ready)
- `variables.tf` with env-specific defaults
- ArgoCD Application manifests in `apps-config/envs/<env>/`

To bring up staging: `cd envs/staging && terraform init && terraform apply`.

---

## ECR Lifecycle Policy

All three ECR repos enforce: **keep last 10 images, expire the rest**. Without this, ECR storage grows unboundedly. At $0.10/GB/month it's cheap but messy. Immutable tags (`IMAGE_TAG_MUTABILITY=IMMUTABLE`) prevent overwriting a deployed image — critical for rollback integrity.

---

## Cost Optimisation Decisions

| Decision | Saving |
|---|---|
| Spot instances for app node group | ~60% vs on-demand |
| Single NAT Gateway | ~$32/month vs dual-AZ NAT |
| `terraform destroy` after screenshots | ~$120/month avoided |
| t3.small instead of t3.medium for nodes | ~50% compute cost |
| ECR lifecycle policy | Negligible storage cost |
| Self-hosted Prometheus vs managed | ~$25/month vs Amazon Managed Grafana |
| No custom domain | $12/year Route53 + cert avoided |
