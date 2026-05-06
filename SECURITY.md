# Security Policy

## Reporting a Vulnerability

If you discover a security issue in this repository, please **do not**
open a public GitHub issue. Instead, use GitHub's private vulnerability
reporting:

- https://github.com/melorga/eks-microservices-demo/security/advisories/new

We aim to acknowledge new reports within 5 business days and to ship
a fix or mitigation within 30 days for High/Critical findings.

## Supported Versions

This repository is a reference architecture; only the `main` branch is
actively maintained. Older commits will not receive backported fixes.

## Scope

In scope:

- Terraform under `infrastructure/`
- Kubernetes manifests under `kubernetes/`
- GitHub Actions workflows under `.github/workflows/`

Out of scope:

- Third-party Helm charts, container images, or AWS managed services -
  please report those upstream.
