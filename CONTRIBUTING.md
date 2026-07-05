# Contributing

This repository follows a standard Terraform module contribution workflow.
It is maintained as a portfolio project, but is structured the same way an
internal platform team would run it: changes go through review, CI, and
documentation updates before merge.

## Before you start

- Read [docs/terraform-standards.md](docs/terraform-standards.md) and
  [docs/repository-standards.md](docs/repository-standards.md) first. Pull
  requests that don't follow the naming, tagging, and module conventions
  described there will be asked to change before review.
- Check `docs/adr/` for existing architecture decisions. If your change
  contradicts one, open an ADR proposing the change instead of silently
  diverging from it.
- Modules under `modules/*` that are marked **Planned** in the README are
  intentionally unimplemented interfaces. If you want to move one to
  production-ready, say so in the PR description. That's a bigger review
  than a bug fix.

## Branching strategy

- `main` is always deployable documentation/reference state. There is no
  long-lived `develop` branch.
- Branch names: `feat/<short-description>`, `fix/<short-description>`,
  `docs/<short-description>`, `chore/<short-description>`.
- Rebase onto `main` before opening a PR; avoid merge commits in feature
  branches.

## Commit messages

Conventional Commits are used so `CHANGELOG.md` can eventually be generated
from history:

```text
feat(vpc): add configurable NAT gateway strategy
fix(eks): correct IRSA trust policy condition
docs(adr): add ADR-006 for state locking
```

## Local checks before opening a PR

```bash
terraform fmt -recursive
terraform validate
tflint --recursive
tfsec .
checkov -d .
markdownlint '**/*.md'
```

Or simply:

```bash
pre-commit run --all-files
```

All of the above run in CI (see `.github/workflows/`) and will block merge
on failure. Running them locally first saves a review round trip.

## Module changes

Every module change must keep `main.tf`, `variables.tf`, `outputs.tf`, and
`README.md` in sync. If you add a variable, document it. If you change a
default that affects cost or security posture (e.g. NAT strategy, subnet
CIDR sizing, IAM policy scope), call it out explicitly in the PR
description. These are exactly the kind of changes a reviewer needs to
reason about, not just diff.

## Pull request review

- At least one review from a CODEOWNER is required (see `CODEOWNERS`).
- CI must be green: `terraform fmt`, `terraform validate`, `tflint`,
  `tfsec`, `checkov`, `markdownlint`.
- Squash-merge is preferred to keep `main` history readable.

## Reporting issues

Use the issue templates under `.github/ISSUE_TEMPLATE/`. Security issues
should **not** go through public issues. See [SECURITY.md](SECURITY.md).
