# EKS Microservices Demo

[![AWS](https://img.shields.io/badge/AWS-EKS%20%7C%20Fargate%20%7C%20NLB-FF9900?style=for-the-badge&logo=amazon-aws)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.33-326CE5?style=for-the-badge&logo=kubernetes)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-1.9%2B-7B42BC?style=for-the-badge&logo=terraform)](https://terraform.io/)

> **Status: reference architecture.** A single hardened nginx Deployment
> behind an NLB on EKS 1.33 (Fargate). It is intentionally small. The
> sections labelled "Roadmap (not implemented)" below describe components
> that are *not* in this repo.

## What this repo deploys

- **VPC** (`terraform-aws-modules/vpc/aws ~> 5.0`) with three private + three
  public subnets, NAT gateway, and the standard EKS subnet tags.
- **EKS cluster** (`terraform-aws-modules/eks/aws ~> 21.0`):
  - Kubernetes **1.33** (1.29 reached extended-support EOL on
    2026-03-23 and is not supported here).
  - `authentication_mode = "API"` with an EKS Access Entry granting
    cluster-admin to the caller IAM principal (no `aws-auth` ConfigMap).
  - Public endpoint **restricted by `var.allowed_admin_cidrs`**
    (defaults to `0.0.0.0/0` for first bring-up; **set this to your
    office / VPN CIDRs** before treating the cluster as anything but
    a sandbox).
  - All control-plane log types enabled
    (`api, audit, authenticator, controllerManager, scheduler`).
  - Cluster secrets envelope-encrypted with a customer-managed KMS key
    (rotation enabled).
  - Fargate profile for `default`, `kube-system`, and `monitoring`.
  - Optional managed node group on AL2023 (`var.enable_managed_nodes`).
- **EKS Addons** with version-pinned defaults: `coredns`, `kube-proxy`,
  `vpc-cni`, `aws-ebs-csi-driver` (with a dedicated IRSA role).
- **AWS Load Balancer Controller** (Helm chart 1.10.0) with the
  upstream IAM policy from
  `kubernetes-sigs/aws-load-balancer-controller`
  (committed at `infrastructure/policies/aws-lb-controller.json`).
- **gp3 default StorageClass** via `ebs.csi.aws.com`, encrypted.
- **metrics-server** (Helm chart 3.12.x) and an *optional*
  **cluster-autoscaler** (9.43.x; consider Karpenter instead for
  greenfield clusters).
- **Frontend workload** (`kubernetes/applications/frontend.yaml`):
  one nginx Deployment + ConfigMap + NLB Service +
  HorizontalPodAutoscaler + PodDisruptionBudget + NetworkPolicy, all
  running under the `restricted` Pod Security profile (non-root,
  read-only root FS, dropped capabilities, RuntimeDefault seccomp).

## Prerequisites

- AWS CLI v2 configured against the account where the cluster will live.
- `terraform` >= 1.9 (< 2.0).
- `kubectl` >= 1.33.
- `helm` >= 3.14.

## Deploy

```bash
git clone https://github.com/melorga/eks-microservices-demo.git
cd eks-microservices-demo

# 1. Edit infrastructure/backend.tf - replace the REPLACE-ME bucket /
#    table names with your S3 bucket + DynamoDB lock table.
# 2. Edit infrastructure/variables.tf (or supply a tfvars) and at minimum
#    set var.allowed_admin_cidrs to your real source CIDRs.

cd infrastructure
terraform init
terraform plan
terraform apply

# Wire kubectl up to the new cluster
aws eks update-kubeconfig --region us-east-1 --name dev-eks-cluster

cd ../kubernetes
kubectl apply -f monitoring/
kubectl apply -f applications/

# Find the NLB
kubectl get svc frontend-service
```

## Repository layout

```
infrastructure/
  versions.tf           Terraform / provider version constraints
  backend.tf            S3 + DynamoDB remote state (placeholders)
  variables.tf          Inputs (kubernetes_version, addon versions, ...)
  main.tf               VPC, EKS, IRSA roles, KMS, addons, Helm releases
  outputs.tf            Cluster + IRSA outputs
  policies/
    aws-lb-controller.json   Vendored upstream IAM policy
kubernetes/
  applications/
    frontend.yaml              Deployment, ConfigMap, NLB Service, HPA
    frontend-policies.yaml     PDB + NetworkPolicy
  monitoring/
    namespace.yaml             monitoring namespace (PSA: restricted)
  namespaces/
    monitoring.yaml            (legacy duplicate; kept for compat)
.github/
  workflows/ci.yml             Terraform + kubeconform + trivy CI
  dependabot.yml               Weekly tf / actions / docker bumps
  CODEOWNERS
SECURITY.md
```

## Security checklist (read before treating this as more than a demo)

- [ ] `var.allowed_admin_cidrs` is restricted to known CIDRs (not
      `0.0.0.0/0`).
- [ ] Backend S3 bucket has versioning + Object Lock + SSE-KMS, and the
      DynamoDB lock table exists.
- [ ] The caller IAM principal that gets cluster-admin via the access
      entry is a role you actually own, not a long-lived user.
- [ ] You ran `aws eks describe-addon-versions` and bumped the addon
      versions in `variables.tf` to the current latest for your region.
- [ ] You replaced the `nginx:1.27-alpine` tag with a digest pin.

## CI

`.github/workflows/ci.yml` runs:

1. **Terraform** via the reusable workflow at
   `melorga/gha-workflows/.github/workflows/terraform.yml` using OIDC
   (no long-lived AWS keys; reads `secrets.AWS_OIDC_ROLE_ARN`).
2. **kubeconform** lint of `kubernetes/`.
3. **Trivy** filesystem scan of the repo, results uploaded as SARIF.
4. **Trivy config** scan of `infrastructure/` for IaC misconfigurations.

Concurrency is keyed on workflow + ref so duplicate pushes don't kick
off parallel applies.

## Roadmap (not implemented)

These are deliberately *not* in the repo today; they are listed so it is
clear what would be needed to turn this into a production platform:

- **GitOps:** ArgoCD or Flux for app-of-apps reconciliation.
- **Service mesh:** Istio or Linkerd for mTLS / traffic shaping.
- **Progressive delivery:** Flagger or Argo Rollouts.
- **Runtime security:** Falco + Falcosidekick.
- **Observability:** kube-prometheus-stack (Prometheus, Grafana,
  Alertmanager); OTel collector + AWS X-Ray; Loki/CloudWatch for logs.
- **Secrets:** External Secrets Operator + AWS Secrets Manager.
- **Policy:** OPA Gatekeeper or Kyverno.
- **Data:** RDS/ElastiCache modules and the corresponding application
  microservices (Go API, Python workers, etc.).

## License

MIT - see [LICENSE](LICENSE).
