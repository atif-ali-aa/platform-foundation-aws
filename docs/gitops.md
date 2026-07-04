# GitOps

What "GitOps-ready" actually means for this repository, since no GitOps
controller ships here. See [ADR-003](adr/ADR-003-why-gitops.md) for the
full reasoning behind that scope boundary.

## What this repository provides

- **A clean separation between infrastructure and workload concerns.**
  `modules/` and `environments/` provision the platform (VPC, IAM, EKS).
  Nothing in this repository deploys application workloads onto it. A
  GitOps controller reconciling workload manifests never needs to touch
  Terraform state, and Terraform never needs to know what's running
  inside the cluster.
- **An IRSA pattern a GitOps controller's own identity can reuse.**
  Whichever controller gets adopted (Argo CD, Flux) needs AWS access for
  things like pulling from ECR or reading Secrets Manager on behalf of
  the workloads it deploys. It gets that the same way the AWS Load
  Balancer Controller does: a scoped IRSA role, not a shared credential.
  See [ADR-004](adr/ADR-004-why-irsa.md).
- **An environment layout GitOps promotion can map onto.** `dev`,
  `staging`, and `prod` already exist as the Terraform environment
  boundary (see [environment-layout.md](../architecture/environment-layout.md)).
  A GitOps promotion model (branches or directories per environment)
  should reuse that boundary rather than invent a second, competing
  notion of "environment."

## What this repository does not provide yet

- No Argo CD or Flux installation. Installing one is real work: sizing
  its own resource footprint, deciding sync policy (automated vs.
  manual), and deciding how it authenticates to a container registry.
  It belongs in `examples/` as a reference composition once the `eks`
  module exists, not fabricated here ahead of that.
- No secrets-in-git story. GitOps typically implies secrets end up
  referenced from git somehow (even if encrypted). That needs the
  Planned `secrets-manager` module (or SOPS/Sealed Secrets/External
  Secrets Operator layered on top) decided first. See
  [security.md](security.md#secrets).
- No promotion pipeline definition (what triggers dev to staging to
  prod). That's a workload-deployment decision, not a
  platform-foundation one, and is explicitly out of this repository's
  scope per [ADR-003](adr/ADR-003-why-gitops.md).

## Why this split instead of shipping a GitOps stack now

A platform foundation that's actually reusable shouldn't force a specific
GitOps controller or promotion model on every consumer. Someone adopting
`vpc`/`iam`/`eks` from this repository might already run Argo CD, might
prefer Flux, or might not be ready for GitOps at all yet. Keeping the
foundation controller-agnostic, but designed so adding one later doesn't
require re-architecting IAM or networking, is the more durable choice
than picking one now and baking it in.
