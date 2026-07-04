# ADR-003: Why GitOps-Ready (Not GitOps-Included)

## Status

Accepted

## Problem

Once workloads run on the EKS cluster this platform provisions, they need
a deployment mechanism that's auditable (who deployed what, when), can
detect and correct drift, and doesn't require direct cluster credentials
in a CI pipeline. At the same time, this repository's scope is the
platform *foundation* (networking, identity, cluster), not the workload
deployment tooling on top of it.

## Decision

Design this platform to be **GitOps-ready** rather than shipping a GitOps
controller as part of it. Concretely: IAM/IRSA roles are structured so a
future GitOps controller (Argo CD or Flux) can be granted a scoped role
the same way any other controller in this repository is (see
[ADR-004](ADR-004-why-irsa.md)), and module/environment layout keeps
"infrastructure" and "workload" concerns separated so a GitOps controller
reconciling the latter doesn't need to reconcile the former.

Installing and configuring an actual GitOps controller is marked
**Planned**. It belongs either in `examples/` as a reference composition
once the EKS module exists, or in its own repository, not fabricated here
as if it were already running.

## Trade-offs

- **Not shipping a GitOps controller means the platform isn't
  "complete" for someone who wants deploy-workloads-on-day-one.** That's
  an intentional scope boundary, not an oversight. See the repository
  goal of honest module status over appearing feature-complete.
- **GitOps itself has real costs when it does get added:** a sync
  controller running in-cluster, secrets that can't simply live in a git
  repo in plaintext (needs SOPS/Sealed Secrets/External Secrets Operator),
  and a promotion model (branches or directories per environment) that
  has to be designed, not assumed.

## Alternatives Considered

- **Direct push deploys from CI** (`kubectl apply` / `helm upgrade` from a
  pipeline): simpler to stand up initially, no in-cluster controller
  required, but no reconciliation loop. If something changes the cluster
  state outside the pipeline, nothing notices or corrects it. Rollback is
  "re-run the last good pipeline" rather than "revert a commit and let the
  controller converge."
- **Manual `kubectl` from an operator's laptop**: fine for a learning
  cluster, unacceptable for anything this repository calls production.
  No audit trail of who ran what, credentials on individual machines
  instead of scoped to a controller identity.

## Production Considerations

- When a GitOps controller is added, its cluster-side identity should use
  IRSA the same way the AWS Load Balancer Controller and Cluster
  Autoscaler do. No static AWS credentials in a Secret.
- Environment promotion (dev to staging to prod) should map to the
  `environments/` directory structure already established in this
  repository, so "which environment does this manifest target" has one
  answer, not two competing sources of truth (Terraform environment
  layout vs. GitOps directory layout).
- See [gitops.md](../gitops.md) for the fuller reasoning on what's
  actually required before a GitOps controller can be safely added, and
  [cost-optimization.md](../cost-optimization.md) for the operational
  cost of running a sync controller continuously.
