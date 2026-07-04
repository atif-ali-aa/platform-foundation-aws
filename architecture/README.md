# architecture/

Mermaid diagrams describing the platform's target design. These render
directly on GitHub, stay in plain text so they diff like code, and are
kept in sync with the modules as they're built. A diagram here should
never describe a shape the Terraform doesn't actually produce.

| Diagram | Describes |
| --- | --- |
| [high-level-platform-architecture.md](high-level-platform-architecture.md) | How the modules in this repository compose into a platform, and where planned services attach |
| [aws-networking.md](aws-networking.md) | VPC subnet tiers, AZ layout, and traffic paths (public/private/database) |
| [terraform-module-relationships.md](terraform-module-relationships.md) | Which modules consume which, and the Production-Ready vs. Planned boundary |
| [environment-layout.md](environment-layout.md) | How `environments/` composes modules per environment with isolated state |
| [deployment-flow.md](deployment-flow.md) | The path from a pull request to an applied change |
