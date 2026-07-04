# terraform/

Reserved for shared root-level Terraform configuration that doesn't belong
to a specific reusable module: for example, a top-level provider version
matrix or backend configuration shared by reference across
`environments/`.

**Status: Planned.** Nothing is wired here yet. Reusable, versioned logic
lives in [`modules/`](../modules); concrete deployable stacks that consume
those modules live in [`environments/`](../environments). This directory
stays empty until there's a real cross-environment concern that doesn't
fit either of those.
