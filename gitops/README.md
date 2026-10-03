# GitOps repository (Flux)

This folder is the **entire contents of a separate GitOps repository**
(suggested name: `terraform-eks-platform-gitops`). It lives here so it can be reviewed and
scanned alongside the platform code; see the main README for how it is published.

```
clusters/dev/            what THIS cluster runs: Flux Kustomizations (+ flux-system/ added by bootstrap)
infrastructure/{base,dev}/  cluster-wide prerequisites (namespaces)
apps/base/podinfo/       the app, environment-neutral
apps/dev/                dev overlay (replicas, message)
```

Flow: `flux-system` (created by bootstrap) watches `clusters/dev` -> finds `infrastructure.yaml`
and `apps.yaml` -> `infrastructure` applies first, then `apps` (it `dependsOn` infrastructure).

Validate locally without a cluster:

```bash
kustomize build apps/dev
kustomize build infrastructure/dev
```
