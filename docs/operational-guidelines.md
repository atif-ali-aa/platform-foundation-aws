# Operational Guidelines

How to make and apply changes to infrastructure built from this
repository without surprising yourself in production. This is written
for whoever operates an environment built from these modules. It assumes
the reader has already read
[repository-standards.md](repository-standards.md) for the process a
change goes through before it gets here.

## Before running `terraform apply`

- Read the **plan**, not just the PR diff. A one-line variable change
  (a CIDR, a NAT strategy flag, a node group's `desired_size`) can
  produce a plan that replaces a subnet or drains a node group. The diff
  won't tell you that; the plan will.
- Confirm you're targeting the environment you think you are. Because
  each `environments/*` stack has its own state file and backend key
  (see [repository-standards.md](repository-standards.md#state-management--remote-backend-strategy)),
  running `apply` from the wrong directory applies to the wrong
  environment's state. There's no shared state to accidentally protect
  you from this, only directory discipline.
- Anything the plan shows as **destroy and recreate** (not just update)
  on a stateful resource (a database subnet's underlying resource, an
  EKS node group with a name that changed) is worth a second look before
  approving, even if CI is green. CI validates syntax and known security
  patterns, not "does this specific replacement matter for this specific
  environment right now."

## Drift

Terraform doesn't watch for drift continuously. It only tells you at the
next `plan`. Practically, that means:

- Don't hand-edit resources this repository manages in the AWS console,
  even "just to test something." The `ManagedBy = terraform` tag (see
  [repository-standards.md](repository-standards.md#tagging-strategy))
  is there so it's obvious in the console that a resource shouldn't be
  edited directly, not as a suggestion.
- If drift happens anyway (someone else's emergency change, an AWS-side
  automatic update), the next `plan` will show it as a diff even though
  no Terraform file changed. Reconcile it deliberately: either update
  Terraform to match reality, or apply to revert reality to match
  Terraform. Don't let a plan with unexplained changes get approved on
  autopilot.

## Rollback

Since `apply` is a manual, human-triggered step (see
[deployment-flow.md](../architecture/deployment-flow.md)), rollback is:
revert the merged commit, open a new PR, get it reviewed like any other
change, and `apply` the reverting plan. There's no separate rollback
mechanism to maintain. The same review-then-apply flow that ships a
change ships its reversal.

## Node group changes

Because worker capacity uses managed node groups (see
[ADR-002](adr/ADR-002-why-amazon-eks.md)), AWS handles node draining
during updates. But a change that forces node group replacement (AMI
change, subnet change, instance type change on some update strategies)
still means every pod on that node group gets rescheduled. Applying that
kind of change during a low-traffic window is still the operator's
responsibility. Managed node groups make the mechanics safer, not the
timing automatic.

## What this repository does not yet give you operationally

Being honest about gaps matters more here than anywhere else in this
repository:

- No centralized alerting on Terraform drift or failed applies. That's
  tooling built on top of this repository, not shipped by it.
- No automated rollback on a bad `apply`. See Rollback above; it's a
  manual re-run of the review flow, not a one-click revert.
- No runbook for a specific incident, because there's no running
  production system behind this portfolio repository to have had one.
  What's documented here is the operating discipline the modules are
  designed to support, for whoever deploys them for real.
