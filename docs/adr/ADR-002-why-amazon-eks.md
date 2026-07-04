# ADR-002: Why Amazon EKS

## Status

Accepted

## Problem

The platform needs a Kubernetes control plane that a small platform team
can operate without taking on full control-plane ownership (etcd backups,
API server HA, version upgrades, CVE patching on control-plane nodes).
It also needs to interoperate cleanly with the CNCF ecosystem (AWS Load
Balancer Controller, Cluster Autoscaler, external-dns, and eventually a
GitOps controller) rather than a more limited scheduler abstraction.

## Decision

Use Amazon EKS with managed node groups for worker capacity. The control
plane is fully managed by AWS; this repository is responsible for the
VPC/subnets it runs in, the IAM/IRSA wiring for workloads, the node
groups, and cluster add-ons layered on top (AWS Load Balancer Controller,
Cluster Autoscaler).

## Trade-offs

- **Flat control-plane cost plus data-plane cost.** EKS charges per
  cluster-hour regardless of size, on top of the EC2/EBS cost of node
  groups. For a single small cluster this is a real, non-trivial fixed
  cost compared to a self-managed control plane on already-provisioned
  instances.
- **AWS controls the upgrade cadence.** EKS supports a rolling window of
  Kubernetes minor versions and deprecates old ones on AWS's schedule, not
  ours. Falling behind means a forced upgrade path later instead of one
  chosen on our own timeline.
- **Some abstractions are less flexible than raw `kubeadm`.** Control
  plane logging, API server flags, and admission configuration are
  exposed through EKS's API, not arbitrary control-plane configuration.
  For this platform's needs (a standard workload cluster, not a
  Kubernetes distribution testbed) that ceiling hasn't been a problem.

## Alternatives Considered

- **Self-managed Kubernetes (kubeadm / kOps on EC2)**: full control over
  every control-plane component, no per-cluster-hour fee, but the team
  now owns etcd backup/restore, API server HA, control-plane node
  patching, and version upgrade orchestration. For a platform foundation
  meant to be maintained by a small team (or one person, as in this
  repository), that operational burden isn't justified by the control it
  buys.
- **ECS / Fargate**: simpler mental model, no control plane to reason
  about at all, but it forfeits the Kubernetes ecosystem this platform is
  explicitly built around (IRSA-based CNCF controllers, Helm charts, a
  GitOps controller consuming standard Kubernetes manifests). Workloads
  that only need "run a container" are a better fit for ECS; a platform
  foundation meant to host varied, ecosystem-integrated workloads is not.
- **GKE / AKS**: both are strong managed Kubernetes offerings, but this
  repository is explicitly scoped as an AWS platform foundation. Running
  Kubernetes on a different cloud than the rest of the AWS estate
  (networking, IAM, planned services) would fragment identity and
  networking design rather than reuse it.

## Production Considerations

- Worker capacity uses **managed node groups**, not self-managed
  Auto Scaling Groups directly. AWS handles node draining on updates and
  keeps the node's Kubernetes version compatible with the control plane.
- Pod-level AWS access goes through **IRSA**, not the node IAM role. See
  [ADR-004](ADR-004-why-irsa.md). The node role is scoped to what a
  kubelet actually needs (ECR pull, CNI, CloudWatch logs), not to what any
  workload on the node might need.
- Control plane logging (API server, audit, authenticator) is enabled to
  CloudWatch Logs. See [security.md](../security.md) for retention and
  access expectations.
- **Karpenter is explicitly out of scope for this module.** Cluster
  Autoscaler is the production-ready autoscaling path here. Karpenter is
  a materially different node-provisioning model (direct EC2 fleet
  management, no ASGs) that deserves its own repository and its own
  design decisions rather than being bolted onto this module as an
  afterthought.
