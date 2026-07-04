# ADR-004: Why IRSA

## Status

Accepted

## Problem

Controllers running on EKS (AWS Load Balancer Controller, Cluster
Autoscaler, external-dns) need to call AWS APIs: create ALBs, resize
Auto Scaling Groups, write Route53 records. The node's IAM role is the
easiest thing to grant those permissions to, but every pod scheduled on
that node inherits whatever the node role allows. On a shared node group,
that means a compromised or misconfigured pod for workload A can call any
AWS API workload B's controller was granted, because permissions live at
the node level, not the workload level.

## Decision

Use **IAM Roles for Service Accounts (IRSA)**: an OIDC identity provider
tied to the EKS cluster, with per-controller IAM roles whose trust policy
is scoped to a specific Kubernetes namespace plus service account (via
the `sub` claim). Each controller assumes only its own role via
`sts:AssumeRoleWithWebIdentity`. The node role stays scoped to what the
kubelet itself needs (ECR pull, CNI, CloudWatch Logs agent), nothing more.

## Trade-offs

- **More IAM surface area to manage.** Instead of one node role, there's
  one role per controller (ALB controller, Cluster Autoscaler,
  external-dns, and any future workload needing AWS access), each with
  its own trust policy and permission policy. That's more resources to
  read and review, in exchange for each one being individually scoped and
  auditable.
- **Requires an OIDC provider per cluster.** This is a one-time piece of
  setup per EKS cluster (see the `eks` module), not a per-workload cost,
  but it is a prerequisite that has to exist before any IRSA role can
  trust it.
- **Trust policy correctness matters.** A trust policy scoped to the
  wrong namespace/service-account (or missing the `aud`/`sub` condition
  entirely) can silently grant a broader set of pods access than
  intended. This is exactly the kind of change [security.md](../security.md)
  expects a reviewer to read closely, not rubber-stamp.

## Alternatives Considered

- **Shared node instance profile**: simplest to set up, but violates
  least privilege by design. Every pod on the node can call every AWS API
  the node role allows, regardless of whether that pod's workload needs
  it. Rejected for anything beyond a throwaway sandbox.
- **kube2iam / kiam**: third-party projects that intercept the EC2
  metadata endpoint to hand out per-pod credentials. They predate IRSA,
  require running an additional privileged daemonset (itself a security
  surface), and are effectively superseded by IRSA being a first-class
  EKS/IAM feature. Not worth the added moving part today.
- **EKS Pod Identity**: AWS's newer alternative to IRSA-via-OIDC, with a
  simpler trust relationship (no manual OIDC provider/thumbprint
  management). It's a reasonable candidate for a future ADR superseding
  this one once third-party Helm charts (AWS Load Balancer Controller,
  Cluster Autoscaler) have universally caught up to supporting it. As of
  this design, IRSA has broader out-of-the-box support across those
  charts, so it's the safer default.

## Production Considerations

- Every IRSA role's trust policy is conditioned on both `aud` (must be
  `sts.amazonaws.com`) and `sub` (namespace plus service account). An
  unconditioned trust policy defeats the purpose.
- Role names and the service accounts that assume them are documented per
  controller in the `iam` module's README (External DNS, AWS Load
  Balancer Controller, Cluster Autoscaler examples), so there's one place
  to check "what can this controller actually do."
- No long-lived AWS access keys exist anywhere in this repository or its
  CI. `terraform-plan.yml` uses GitHub OIDC to assume an AWS role for
  the same reason workloads use IRSA: short-lived, scoped, auditable
  credentials instead of static ones.
