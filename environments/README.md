# environments/

Concrete, deployable stacks (e.g. `dev`, `staging`, `prod`) that consume
the modules in [`modules/`](../modules) with environment-specific
variables and remote state configuration.

**Status: Planned.** The `vpc`, `iam`, and `eks` modules are now
production-ready; this directory gets populated in the milestone that
wires them together. See the root [README.md](../README.md) roadmap for
sequencing.
