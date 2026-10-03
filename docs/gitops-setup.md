# GitOps with Flux

## Where the GitOps content lives (and why a separate repo)

The `gitops/` folder in this repo is the full content of a **separate repository**,
`terraform-eks-platform-gitops`. Reasons:

1. `flux bootstrap` and Flux itself push commits straight to the branch they watch. This
   repo's `main` is protected (pull requests only), so Flux could not write to it.
2. Platform changes (Terraform, needs review + cost control) and app delivery (frequent,
   automated) have different approvers and cadence.
3. Flux commits never trigger or pollute the Terraform CI.

A single repo with a `gitops/` path is fine for a small team that doesn't protect `main`;
in that case point `--path=gitops/clusters/dev` at it.

## Run order (you run all of these)

Prerequisite: the Stage 4 cluster is up and `kubectl get nodes` shows the node `Ready`.

```bash
# 0. Flux CLI (v2.9.6 was the latest when written; supports Kubernetes 1.36)
brew install fluxcd/tap/flux          # or: curl -s https://fluxcd.io/install.sh | sudo bash
flux check --pre                      # verifies cluster access + version compatibility

# 1. Create an EMPTY public repo named terraform-eks-platform-gitops (no README/license)
#    in the GitHub UI, or:  gh repo create <OWNER>/terraform-eks-platform-gitops --public

# 2. Seed it from the gitops/ folder (preserves history, one command)
cd terraform-eks-platform
git subtree split --prefix=gitops -b gitops-seed
git push https://github.com/<OWNER>/terraform-eks-platform-gitops.git gitops-seed:main
git branch -D gitops-seed

# 3. Create a fine-grained personal access token (GitHub > Settings > Developer settings):
#    - Repository access: ONLY terraform-eks-platform-gitops
#    - Permissions: Administration = Read and write (to add the deploy key),
#                   Contents = Read and write, Metadata = Read-only
#    - Expiry: 7 days. It is only needed during bootstrap.

# 4. Give the token to the shell WITHOUT writing it to any file or to shell history
read -rs GITHUB_TOKEN && export GITHUB_TOKEN      # paste the token, press Enter (nothing is echoed)

# 5. Bootstrap
flux bootstrap github \
  --owner=<OWNER> \
  --repository=terraform-eks-platform-gitops \
  --branch=main \
  --path=clusters/dev \
  --personal \
  --private=false \
  --components=source-controller,kustomize-controller

unset GITHUB_TOKEN
```

`--components` installs only the two controllers we use (no Helm, no notifications), saving
pods on the single small node. Revoke the token in GitHub afterwards if you like: the cluster
does not keep it (see below).

### What bootstrap creates

**In Git** (a commit to `clusters/dev/flux-system/` in the GitOps repo):
`gotk-components.yaml` (all Flux controllers, CRDs, RBAC), `gotk-sync.yaml` (a `GitRepository`
pointing at the repo and a `Kustomization` named `flux-system` that applies `clusters/dev`),
and a `kustomization.yaml`.

**In the cluster:** the `flux-system` namespace, the controllers, the CRDs, and a Secret holding
an SSH **deploy key** (read-only by default). The deploy key's public half is registered on the
repo. The PAT is used once to do all this and is **not** stored in the cluster. Flux "manages
itself": the controllers' own manifests live in Git, so upgrading Flux is a commit.

## Verify

```bash
flux check
flux get sources git                    # flux-system   READY True, a revision (commit)
flux get kustomizations                 # flux-system, infrastructure, apps: all READY True
kubectl get pods -n flux-system         # 2 controllers Running
kubectl -n podinfo get deploy,pods,svc  # podinfo 2/2, 2 pods Running
kubectl -n podinfo port-forward svc/podinfo 9898:9898 &
curl -s localhost:9898 | head -20       # JSON incl. "message": "Hello from dev, delivered by Flux"
kill %1
```

## Demonstrate drift correction

Flux compares the cluster to Git every `interval` (1m here) and reverts differences.

```bash
kubectl -n podinfo get deploy podinfo               # READY 2/2 (the overlay says 2)
kubectl -n podinfo scale deploy podinfo --replicas=5   # change the cluster by hand
kubectl -n podinfo get deploy podinfo -w             # watch it go back to 2 within ~1 minute
# don't want to wait?  flux reconcile kustomization apps --with-source
```

Also try deleting the Service (`kubectl -n podinfo delete svc podinfo`): Flux recreates it.
Then do it the GitOps way: change `replicas: count` in `apps/dev/kustomization.yaml` in the GitOps
repo, commit, and `flux get kustomizations --watch` shows the new value roll out, with no
`kubectl` involved.

## Teardown order (do this BEFORE terraform destroy)

```bash
flux suspend kustomization flux-system        # 1. stop Flux recreating what we delete
flux delete kustomization apps --silent       # 2. prune: removes podinfo
flux delete kustomization infrastructure --silent   # 3. prune: removes the namespace
kubectl get ns podinfo                        #    wait until NotFound
flux uninstall --silent                       # 4. remove Flux, its CRDs and namespace
cd envs/dev && terraform destroy              # 5. only now destroy the cluster + VPC
```

Why this order: anything Kubernetes created in AWS (a LoadBalancer Service's load balancer, EBS
volumes from PVCs) is NOT in Terraform state. If the cluster is destroyed first, those orphans keep
running, cost money, and block VPC deletion (`DependencyViolation`). podinfo here is ClusterIP only,
so nothing leaks, but the habit matters. Re-bootstrapping later against the same repo recreates
everything on a fresh cluster.

If you are finished for good: delete the deploy key and (optionally) the GitOps repo.
