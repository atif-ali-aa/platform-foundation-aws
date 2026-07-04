# Architecture

This document is the narrative version of the diagrams in
[`architecture/`](../architecture). Read it alongside
[high-level-platform-architecture.md](../architecture/high-level-platform-architecture.md)
rather than instead of it.

## Layering

The repository is built in three layers, and each layer only depends on
the one below it:

1. **Modules** (`modules/`): reusable, versioned Terraform. A module
   knows nothing about which environment consumes it. `vpc`, `iam`, and
   `eks` are the production-ready layer today; everything else is a
   documented interface waiting for an implementation (see
   [Module Status](../README.md#module-status)).
2. **Environments** (`environments/`): concrete Terraform roots that pin
   module versions, supply environment-specific variables, and own their
   own state file. See
   [environment-layout.md](../architecture/environment-layout.md).
3. **Workloads**: what actually runs on the EKS cluster. Out of scope for
   this repository by design; see [gitops.md](gitops.md) for why
   workload deployment is deliberately a separate concern from platform
   provisioning.

A change to a module is reviewed once and consumed by every environment
that pins that version. A change to an environment's `.tfvars` affects
only that environment. This is the whole reason the two are separate
directories instead of one big root module with `count`/conditionals
branching on environment name.

## Why only three production modules

`vpc`, `iam`, and `eks` are the minimum set that makes "here is a
platform" true: networking to run things in, identity to let controllers
act on AWS on the platform's behalf, and compute to actually schedule
workloads. Everything else in the Planned list (DNS, secrets, logging
aggregation beyond what EKS emits, encryption keys, container registry,
edge protection, eventing) is a real production need, but bolting on a
shallow implementation of eleven more services to look complete would
violate the one rule this repository is built around: don't fake it.
Each planned module has a real interface and real documentation for what
it will do. See [repository-standards.md](repository-standards.md) for
what "Planned" is allowed to mean.

## How the production modules fit together

- `vpc` has no dependency on the other two modules. It's pure networking
  and is usable by itself.
- `iam` defines the OIDC provider association and IRSA role patterns. It
  needs an EKS cluster's OIDC issuer URL to wire trust policies
  correctly, so in practice it's applied alongside or after `eks`, even
  though its Terraform doesn't hard-depend on the `eks` module's state.
- `eks` consumes `vpc` (for subnets and security group placement) and
  `iam` (for the node role and IRSA roles the cluster's add-ons need).

See [terraform-module-relationships.md](../architecture/terraform-module-relationships.md)
for the exact dependency graph, including where the Planned modules would
attach once they exist.

## What this document is not

It's not a claim that a running cluster exists somewhere. `vpc`, `iam`,
and `eks` are implemented in Terraform and pass `fmt`/`validate` locally,
but none of them have been applied against a real AWS account as part of
building this repository. This document describes the target shape the
implementation is built to match, not a system observed running in
production.
