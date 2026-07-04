# Security

The security posture of the production modules (`vpc`, `iam`, `eks`) and
what's still a gap because the module implementing it is Planned, not
built.

## Identity: IRSA over static credentials

No controller running on the EKS cluster (AWS Load Balancer Controller,
Cluster Autoscaler, external-dns) uses the node's IAM role or a static
access key. Each gets its own IAM role, scoped to its own trust policy
via IRSA. See [ADR-004](adr/ADR-004-why-irsa.md). If a future workload
needs AWS access, the answer is "add another IRSA role scoped to that
workload's service account," never "add a permission to the shared node
role."

## Least privilege, checked at review time

Every IAM policy in the `iam` module is written for the specific actions
its role needs, not `Action: "*"` or a managed policy broader than
necessary because it was convenient. A reviewer looking at an IAM policy
change should be able to answer "why does this role need this action"
from the module README's documented examples (External DNS, AWS Load
Balancer Controller, Cluster Autoscaler). If the answer isn't
documented, that's a gap in the PR, not just in the docs.

## Network security

- Security groups are scoped per workload/tier, not shared broadly. See
  [networking.md](networking.md#security-groups-vs-network-acls).
- Database subnets have no default route to the internet at all. This
  isn't a security group blocking it, it's an actual absence of route
  (see [ADR-005](adr/ADR-005-why-multi-az-networking.md)). A
  misconfigured security group in that tier still can't reach the
  internet, because there's no path there to begin with.
- NACLs provide a subnet-level backstop but are not the primary control.
  Relying on stateless NACL rules as the main defense tends to produce
  rules nobody can reason about.

## Encryption

- EKS control plane logging and node group EBS volumes are expected to
  use encryption at rest by default in the `eks` module (see that
  module's README once implemented for the exact KMS key configuration).
- Customer-managed KMS keys for workload-level encryption (as opposed to
  AWS-managed defaults) are tracked as the Planned `kms` module. Until
  it ships, modules that need a KMS key argument accept a caller-supplied
  key ARN rather than assuming AWS-managed keys are sufficient for every
  use case.

## Secrets

There is no secrets-handling story shipped in this repository yet. The
`secrets-manager` module is Planned, not implemented. This is stated
explicitly rather than left implicit, because "where do application
secrets go" is exactly the kind of question a security review should
never have to guess the answer to. Until that module ships, do not treat
any environment built from this repository as ready to hold real
application secrets.

## Terraform state security

State files can contain sensitive values (ARNs, sometimes secrets passed
as plain variables instead of marked `sensitive`). This repository's
remote-state backend (S3 plus DynamoDB locking, encrypted, versioned) is
tracked as the Planned `s3-remote-state` module. Until it exists, no
environment in this repository should run with local state, and no
`.tfvars` file should ever be committed (`.gitignore` already excludes
`*.tfvars` for this reason).

## CI-enforced scanning

`tfsec` and `checkov` run on every pull request touching Terraform (see
`.github/workflows/terraform-ci.yml`) and are not soft-fail. A finding
blocks merge, not just a warning in the PR conversation. If a finding is
a deliberate, reviewed exception (rare, and should stay rare), it's
suppressed inline with a comment explaining why, not by disabling the
check repository-wide.

## Reporting a vulnerability

See [SECURITY.md](../SECURITY.md) at the repository root for the private
disclosure process. In short: not a public issue.
