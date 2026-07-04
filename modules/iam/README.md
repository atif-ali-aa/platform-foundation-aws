# iam

IAM OIDC provider and IRSA role patterns: least-privilege, per-controller
IAM roles that Kubernetes service accounts assume via
`sts:AssumeRoleWithWebIdentity`, instead of inheriting permissions from a
shared node role.

Design reasoning lives in
[ADR-004](../../docs/adr/ADR-004-why-irsa.md) and
[docs/security.md](../../docs/security.md). This README covers the
module's actual inputs, outputs, and usage.

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  environment = "prod"

  # From the eks module's cluster_oidc_issuer_url output (see modules/eks,
  # shipping in the next milestone). The iam module doesn't create the EKS
  # cluster itself. It's deliberately decoupled so it can wire IRSA for
  # any OIDC issuer, not only one this repository's own eks module created.
  oidc_provider_issuer_url = module.eks.cluster_oidc_issuer_url

  enable_external_dns_role             = true
  external_dns_hosted_zone_arns        = ["arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"]

  enable_load_balancer_controller_role = true

  enable_cluster_autoscaler_role       = true
  cluster_autoscaler_cluster_name      = "prod-eks"

  tags = {
    CostCenter = "platform"
  }
}
```

Adding a role this module doesn't ship as a named example:

```hcl
module "iam" {
  source = "../../modules/iam"
  # ...

  irsa_roles = {
    my_controller = {
      namespace       = "my-namespace"
      service_account = "my-controller"
      policy_json     = data.aws_iam_policy_document.my_controller.json
    }
  }
}
```

## Design decisions

- **The module doesn't create the EKS cluster it's wiring IRSA for.** It
  takes `oidc_provider_issuer_url` as an input rather than depending on
  the `eks` module directly. See
  [terraform-module-relationships.md](../../architecture/terraform-module-relationships.md).
  This keeps `iam` reusable for any OIDC issuer, and lets Terraform's own
  dependency graph (via the reference in the example above) handle
  ordering instead of a hardcoded module dependency.
- **One AWS account, one OIDC provider per issuer.** `create_oidc_provider`
  defaults to `true`. Set it to `false` and supply
  `existing_oidc_provider_arn` if a provider for this issuer already
  exists (AWS rejects creating a second one for the same URL).
- **Every IRSA role's trust policy is conditioned on both `sub` and
  `aud`**, not just `sub`. An unconditioned or partially-conditioned
  trust policy is exactly the kind of subtle IAM mistake
  [docs/security.md](../../docs/security.md) expects a reviewer to catch,
  not something this module leaves to chance.
- **`external_dns_hosted_zone_arns` has no wildcard fallback.** If you
  enable the External DNS role, you must supply the specific hosted zone
  ARNs it's allowed to modify. Most tutorials default this to
  `arn:aws:route53:::hostedzone/*`. This module doesn't, because a
  portfolio repository claiming "least privilege" shouldn't ship a
  wildcard by default.
- **The AWS Load Balancer Controller policy is modeled on, not copied
  from, the upstream policy.** The real
  [kubernetes-sigs/aws-load-balancer-controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/#iam-permissions)
  IAM policy changes across controller versions. This module's policy
  mirrors its structure (broad read-only `Describe`/`List` calls,
  mutating actions scoped by the `elbv2.k8s.aws/cluster` resource tag the
  controller itself applies) but should be diffed against the policy
  published for whatever controller version you actually deploy before
  using this in a real account. See the comment above
  `data.aws_iam_policy_document.load_balancer_controller` in `main.tf`.
- **Cluster Autoscaler's mutating actions are tag-scoped**
  (`autoscaling:SetDesiredCapacity`,
  `autoscaling:TerminateInstanceInAutoScalingGroup`) to Auto Scaling
  Groups tagged `k8s.io/cluster-autoscaler/<cluster_name> = owned`. The
  read-only `Describe*` calls are necessarily account-wide, since the
  Auto Scaling API doesn't support resource-level scoping for them.
- **`irsa_roles` is the generic escape hatch.** External DNS, the AWS
  Load Balancer Controller, and Cluster Autoscaler are the three named
  examples this module ships because they're what almost every EKS
  cluster needs. Anything else gets the same trust-policy treatment via
  `irsa_roles` without needing its own dedicated variables and resources.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `environment` | Deployment environment name (`dev`, `staging`, `prod`). | `string` | n/a | yes |
| `oidc_provider_issuer_url` | OIDC issuer URL from the EKS cluster. | `string` | n/a | yes |
| `create_oidc_provider` | Whether to create the IAM OIDC provider. | `bool` | `true` | no |
| `existing_oidc_provider_arn` | Existing OIDC provider ARN, required if `create_oidc_provider` is `false`. | `string` | `null` | no |
| `oidc_provider_client_id_list` | Audience values accepted by the OIDC provider. | `list(string)` | `["sts.amazonaws.com"]` | no |
| `irsa_roles` | Additional IRSA roles beyond the built-in examples. | `map(object)` | `{}` | no |
| `enable_external_dns_role` | Create the External DNS IRSA role. | `bool` | `false` | no |
| `external_dns_service_account` | Namespace/name external-dns runs as. | `object({namespace,name})` | `kube-system` / `external-dns` | no |
| `external_dns_hosted_zone_arns` | Hosted zone ARNs external-dns may modify. Required (non-empty) if enabled. | `list(string)` | `[]` | no |
| `enable_load_balancer_controller_role` | Create the AWS Load Balancer Controller IRSA role. | `bool` | `false` | no |
| `load_balancer_controller_service_account` | Namespace/name the controller runs as. | `object({namespace,name})` | `kube-system` / `aws-load-balancer-controller` | no |
| `enable_cluster_autoscaler_role` | Create the Cluster Autoscaler IRSA role. | `bool` | `false` | no |
| `cluster_autoscaler_service_account` | Namespace/name Cluster Autoscaler runs as. | `object({namespace,name})` | `kube-system` / `cluster-autoscaler` | no |
| `cluster_autoscaler_cluster_name` | Cluster name used to scope Cluster Autoscaler's mutating actions. Required if enabled. | `string` | `null` | no |
| `tags` | Additional tags merged into every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| --- | --- |
| `oidc_provider_arn` | ARN of the OIDC provider in use. |
| `oidc_provider_url` | OIDC issuer URL (no scheme), for reference. |
| `irsa_role_arns` | Map of role key to IAM role ARN, for every enabled role. |
| `irsa_role_names` | Map of role key to IAM role name, for every enabled role. |
| `external_dns_role_arn` | Convenience output; `null` if not enabled. |
| `load_balancer_controller_role_arn` | Convenience output; `null` if not enabled. |
| `cluster_autoscaler_role_arn` | Convenience output; `null` if not enabled. |

## What this module deliberately does not do

- No EKS node IAM role. That's tightly coupled to node group
  configuration and lives in the `eks` module instead (see
  [ADR-002](../../docs/adr/ADR-002-why-amazon-eks.md)).
- No Kubernetes-side wiring (no `ServiceAccount` manifest, no Helm
  release for the controllers themselves). This module produces the AWS
  side of IRSA. Annotating the matching `ServiceAccount` with
  `eks.amazonaws.com/role-arn` is a workload-deployment concern. See
  [docs/gitops.md](../../docs/gitops.md).
