# Terraform Module Relationships

Which modules consume which, and where the Production-Ready / Planned
boundary sits. This is the dependency graph an `environments/*` stack
composes. See [environment-layout.md](environment-layout.md) for how
that composition actually happens per environment.

```mermaid
flowchart TD
    VPC["vpc\nProduction-Ready"]
    IAM["iam\nProduction-Ready"]
    EKS["eks\nProduction-Ready"]

    VPC --> IAM
    VPC --> EKS
    IAM --> EKS

    subgraph PlannedModules["Planned (interface + docs only)"]
        ACM[acm]
        R53[route53]
        SM[secrets-manager]
        CW[cloudwatch]
        KMS[kms]
        ECR[ecr]
        WAF[waf]
        EB[eventbridge]
        SNS[sns]
        SQS[sqs]
        S3S[s3-remote-state]
    end

    EKS -.would consume.-> ACM
    EKS -.would consume.-> R53
    EKS -.would consume.-> SM
    EKS -.would consume.-> CW
    IAM -.would reference.-> KMS
    S3S -.backend for all state, including this repo's own.-> VPC
```

## Reading this diagram

- `vpc` has no dependencies on other modules in this repository. It's
  the foundation everything else consumes.
- `iam` depends on `vpc` only for the EKS OIDC provider association (once
  a cluster exists); its IRSA role definitions themselves are
  cluster-agnostic.
- `eks` consumes both `vpc` (subnets, security groups) and `iam` (node
  role, IRSA roles for cluster add-ons).
- Every edge into `PlannedModules` is dotted because nothing consumes
  them yet. They're documented interfaces, not wired dependencies. When
  `acm` ships, for example, the edge from `eks` (or more likely an
  ingress/ALB configuration in `examples/`) becomes solid.
- `s3-remote-state` is architecturally "underneath" every other module
  (it's what backs their state files), which is why it's drawn as a
  foundation concern rather than a peer of `acm`/`route53`/etc. It's
  still Planned, though, so this repository's own modules don't yet
  assume a remote backend exists.
