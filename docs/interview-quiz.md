# Interview quiz

A self-test for [interview-notes.md](interview-notes.md). **58 questions, 8 sections.**

## How to use it

1. **Don't open the notes or the answer key.** Answer cold, in your own words, ideally out loud first and then in a
   line or two under each question (replace the `Your answer:` text).
2. When a whole section is done, check it against the **Answer key** at the very bottom. Mark each question
   `[x]` (solid), `[~]` (partly) or `[ ]` (missed).
3. For every `[~]` or `[ ]`, read the matching note in `interview-notes.md` (the key tells you which Q number), then
   close it and answer again the next day.
4. Section 8 has no right answer: practise it out loud until it sounds natural.

**Scoring:** count `[x]` as 1 and `[~]` as 0.5. Above 45: you can hold a Terraform conversation. 35-45: re-drill the
weak sections. Below 35: do the sections again after re-reading the notes.

Question types: **(MC)** multiple choice, **(T/F)** true or false, **(Short)** answer in 2-4 sentences,
**(Scenario)** diagnose and say what you would run.

---

## Section 1. Core Terraform

**1. (Short)** What is Terraform state, and what happens during `plan` and `apply`?
Your answer:

**2. (Scenario)** A teammate's run was killed and your `apply` fails with "Error acquiring the state lock". What do you do,
in order?
Your answer:

**3. (MC)** You build 4 subnets with `count` from a list and then remove the *first* item from the list. What does
`plan` show?
- A. Only the first subnet is destroyed
- B. Items after the first shift position, so several are destroyed and recreated
- C. Nothing, `count` tracks resources by ID
- D. An error: lists can't be shortened

Your answer:

**4. (Short)** Providers are pinned with `~> 6.67` and modules with `version = "6.7.3"`. Why the different styles, and
what does `.terraform.lock.hcl` add?
Your answer:

**5. (Scenario)** Someone changed a security group in the AWS console. How do you detect it, and what are your two choices
for dealing with it? Which command shows *only* drift?
Your answer:

**6. (Short)** Give an example from this repo of `depends_on` and one of a `lifecycle` rule, and say why each exists.
Your answer:

**7. (Short)** Workspaces or one directory per environment? Which does this repo use and why?
Your answer:

**8. (T/F)** Marking a variable `sensitive = true` keeps its value out of the state file.
Your answer:

---

## Section 2. Remote state and the bootstrap (Stages 1-2)

**9. (Short)** Why is the state bucket created by a separate `bootstrap/` config with *local* state, and why must it
outlive the platform you destroy?
Your answer:

**10. (Short)** What is a *partial* backend configuration, and why use it in a public repo instead of hard-coding the bucket?
Your answer:

**11. (Short)** How does S3 native locking (`use_lockfile = true`) work, what object does it create, and what does that
mean for the IAM permissions of a CI role?
Your answer:

**12. (Short)** Name four protections on the state bucket and what each one prevents.
Your answer:

**13. (Scenario)** The laptop that holds `bootstrap/terraform.tfstate` is lost. What is lost, what is *not*, and how do you
recover?
Your answer:

**14. (T/F)** `.terraform.lock.hcl` should be added to `.gitignore`.
Your answer:

**15. (Short)** What do `terraform fmt`, `validate` and `tflint` each catch, and what can none of them tell you?
Your answer:

---

## Section 3. The VPC (Stage 3)

**16. (Short)** What actually makes a subnet "public"? Is there a flag on the subnet?
Your answer:

**17. (Short)** Evaluate by hand (no tools):
- a) `cidrsubnet("10.0.0.0/16", 4, 2)`
- b) `cidrsubnet("10.0.0.0/16", 8, 241)`
- c) `cidrsubnet("10.0.0.0/16", 8, 3)`

Your answer:

**18. (Short)** Why do the nodes need a NAT gateway, how is it billed, and what is the trade-off between one NAT gateway
and one per AZ?
Your answer:

**19. (Short)** Which two subnet tags does this repo set for load balancers, and what reads them? What error do you see
if they are missing?
Your answer:

**20. (Short)** Why does the free S3 gateway endpoint save money? Why didn't we also add interface endpoints for ECR?
Your answer:

**21. (Short)** Why does EKS need `enable_dns_support` and `enable_dns_hostnames`?
Your answer:

---

## Section 4. EKS (Stage 4)

**22. (Short)** Access entries vs the `aws-auth` ConfigMap: what is the difference, and what did we set to use only the
new method?
Your answer:

**23. (Short)** In IRSA, what does the role's *trust policy* check? What would go wrong if the `sub` condition were left out?
Your answer:

**24. (Short)** IRSA vs EKS Pod Identity. When would you choose each?
Your answer:

**25. (Short)** Managed vs self-managed node groups: what does AWS do for you in the managed case?
Your answer:

**26. (Short)** The node is a `t3.medium`, not a `t3.small`. Why? (Include the rough pod numbers.)
Your answer:

**27. (Scenario)** The API's public endpoint is restricted to your IP. If you turned the *private* endpoint off but kept
that restriction, what would break and why?
Your answer:

**28. (Short)** Why is `enable_cluster_creator_admin_permissions` set to `false`, with an explicit access entry instead?
Your answer:

**29. (Short)** The add-ons use `most_recent = true`. What is the convenience, and what is the risk?
Your answer:

**30. (Short)** Give three differences between building this in Terraform and your CloudFormation experience.
Your answer:

---

## Section 5. CI/CD, OIDC and scanning (Stage 5)

**31. (Short)** How does OIDC avoid long-lived keys? Walk through what happens from the workflow job to AWS credentials.
Your answer:

**32. (Short)** Write the `sub` claim a pull-request job presents, and the one the apply job presents. (Use `OWNER/REPO`.)
Which one is the apply role's trust policy pinned to?
Your answer:

**33. (Short)** Why two roles (plan and apply) instead of one?
Your answer:

**34. (Short)** The PR plan runs with `-lock=false`. Why is that safe here, and what does it let us do?
Your answer:

**35. (Short)** Why are actions pinned to a commit SHA instead of a tag like `@v4`?
Your answer:

**36. (Short)** On a *public* repo, what two precautions are taken with the plan output, and why?
Your answer:

**37. (Short)** What did Trivy flag in this repo? How was it handled, and why not simply lower the severity threshold?
Your answer:

**38. (Scenario)** An AWS access key was pushed to a public repo. List your steps in order, and say why deleting the commit is
not enough.
Your answer:

**39. (Short)** Why isn't apply triggered automatically on merge? How could a real team allow auto-apply safely?
Your answer:

**40. (Short)** The workflow has three jobs. Why is the job that posts the PR comment separate from the job that talks to AWS?
Your answer:

---

## Section 6. Flux and GitOps (Stage 6)

**41. (Short)** Push vs pull deployment: what is the difference and what is the security benefit of pull?
Your answer:

**42. (Short)** What does `flux bootstrap` create in Git and in the cluster? Is the GitHub token stored in the cluster?
Your answer:

**43. (Short)** Explain how Flux reconciles. What do `prune`, `wait`, `interval` and `dependsOn` do?
Your answer:

**44. (Scenario)** You run `kubectl scale deploy podinfo --replicas=5`, but Git says 2. What happens, how long does it take, and
how would you change it properly?
Your answer:

**45. (Short)** Flux vs Argo CD: how would you choose?
Your answer:

**46. (Short)** How do you handle secrets in GitOps? What would you use in production?
Your answer:

**47. (Short)** Why is the GitOps content in a separate repo, and why must Flux and apps be torn down *before*
`terraform destroy`?
Your answer:

---

## Section 7. Debugging scenarios

**48. (Scenario)** `terraform apply` succeeded, but `kubectl get nodes` says `You must be logged in to the server
(Unauthorized)`. What do you check?
Your answer:

**49. (Scenario)** The CI step `configure-aws-credentials` fails with "Not authorized to perform
sts:AssumeRoleWithWebIdentity". List four things you check.
Your answer:

**50. (Scenario)** `terraform destroy` on the VPC hangs, then fails with `DependencyViolation` on a subnet or security
group. What is the likely cause and how do you find and fix it?
Your answer:

**51. (Scenario)** `flux get kustomizations` shows `apps` as not Ready with "dependency 'flux-system/infrastructure' is
not ready". What do you do?
Your answer:

**52. (Scenario)** A PR plan in CI says it will create all 58 resources, but the cluster is running. What are the likely causes?
Your answer:

**53. (Scenario)** A new pod stays `Pending` on the one-node cluster. Give two or three reasons and the command that shows
which applies.
Your answer:

**54. (Scenario)** You are surprised by a ~$150 AWS bill at the end of the month. What was probably left running, and how do
you check?
Your answer:

**55. (Scenario)** `terraform plan` fails in CI with `AccessDenied` on one specific API call (for example
`ec2:CreateLaunchTemplate`). Do you add `*:*`? What do you do instead?
Your answer:

---

## Section 8. Say it out loud (no answer key)

**56.** Give the 60-second pitch of this project.

**57.** What is the biggest cost-versus-resilience trade-off you made, and how would the design change for production?
Name three things you would do differently.

**58.** Walk through exactly what happens, step by step, from `git push` of a branch with a Terraform change to a plan
comment appearing on the pull request, including how the job gets AWS access.

---

---

# STOP. Answer key below

Don't scroll past here until you have answered a section. "Note Q" refers to the question number in
`interview-notes.md`.

## Section 1. Core Terraform

**1.** State maps config to the real resources Terraform created (IDs, attributes). `plan`: read config, refresh state against
reality, build the dependency graph, show the diff. `apply`: execute that diff in dependency order, write results to state.
Without state it couldn't know what already exists. *(Note Q1)*

**2.** Don't force it blindly. (1) Read the error: it shows the lock ID, who and when. (2) Confirm nobody is actually running
`apply` (teammate, CI). (3) Only then `terraform force-unlock <LOCK_ID>`. With S3 native locking the lock is the
`<key>.tflock` object. Never edit state by hand; if the state is damaged restore the previous object version from the
versioned bucket. *(Note Q2)*

**3. B.** `count` indexes by position, so removing the first item shifts the rest and Terraform wants to destroy/recreate
them. `for_each` keys by a stable string, so only the removed key is affected. *(Note Q3)*

**4.** Providers: `~> 6.67` accepts minor/patch but never a new major; the lock file freezes the *exact* version and
checksums chosen at `init`, so laptop and CI install identical plugins (commit it). Modules have no lock file, so pin an
exact version for reproducibility; upgrade deliberately by PR. *(Note Q4)*

**5.** `terraform plan` refreshes and shows the change back to config; `terraform plan -refresh-only` shows *only* drift. Then
either re-apply to revert it, or update the config to accept it. A scheduled CI `plan` detects drift early. `import` brings
existing resources under Terraform. *(Note Q5)*

**6.** `depends_on`: the bucket policy waits for the public-access block (S3 can reject racing changes; Terraform can't see
a reference-based dependency). `lifecycle`: `prevent_destroy = true` on the state bucket so any plan that would delete it
fails. Others: `create_before_destroy`, `ignore_changes`. *(Note Q6)*

**7.** Workspaces share code and directory with several state files, and the active workspace is invisible. One directory
per environment (`envs/dev`, later `envs/prod`) with its own state key makes each environment explicit in the tree, in review
and in CI. This repo uses directories. *(Note Q8)*

**8. False.** `sensitive` only hides the value in CLI output; it is still stored in plaintext in state, which is why the state
bucket is locked down. *(Note Q7)*

## Section 2. Remote state and the bootstrap

**9.** The bucket can't store its own state (chicken-and-egg), so it's applied once with local state. The platform is
destroyed after every session; `destroy` needs state, so state must live somewhere that isn't destroyed. Hence a separate
config, `prevent_destroy`, `force_destroy = false`. *(Note Q9, Q18)*

**10.** `backend "s3" {}` with only `use_lockfile` and `encrypt` in code; bucket/key/region supplied at init via
`-backend-config=backend.hcl` (gitignored; `.example` committed). Backend blocks can't use variables. Benefit: the bucket
name isn't published in a public repo and the same code works for any bucket/env. *(see the comment in `envs/dev/backend.tf`)*

**11.** Terraform writes `<key>.tflock` using an S3 conditional write (create only if it doesn't exist), so only one writer wins;
it replaces the DynamoDB lock table. The CI role therefore needs `s3:GetObject/PutObject/DeleteObject` on the `.tflock` object
too, not just the state file (a read-only plan role avoids this by using `-lock=false`). *(Note Q16)*

**12.** Versioning: undo for corrupted/overwritten state. Encryption: state holds secrets in plaintext. Public-access block:
never public even if a bad policy is attached. Deny non-TLS: no cleartext transfer. Also: `prevent_destroy` and
`force_destroy = false` against accidental deletion; lifecycle expiry of old versions after 90 days. *(Note Q17)*

**13.** Lost: Terraform's bookkeeping for the *bucket* only. Not lost: the bucket and every platform state inside it. Recover
by re-running bootstrap with the same variables and `terraform import`-ing the bucket and its sub-resources (versioning,
encryption, public access block, policy, lifecycle). *(Note Q18)*

**14. False.** Commit it: it pins exact provider versions and checksums for everyone. *(Note Q11)*

**15.** `fmt`: style. `validate`: syntax and internal consistency offline. `tflint`: lint plus provider-aware rules (unused
variables, bad instance types). None call AWS or prove the plan will succeed: only `plan`/`apply` against the real account
does. *(Note Q12)*

## Section 3. The VPC

**16.** The route table. A subnet is public if its route table has `0.0.0.0/0 -> internet gateway`; private if its default
route goes to a NAT gateway (or nowhere). There is no "public" flag on the subnet. *(Note Q19)*

**17.** a) `10.0.32.0/20` (/20 blocks are 4,096 addresses = 16 in the third octet, so index 2 starts at 32).
b) `10.0.241.0/24`. c) `10.0.3.0/24`. *(Note Q23)*

**18.** Nodes in private subnets have no public IPs but must pull images and call AWS APIs outbound; a NAT gateway (in a public
subnet) allows outbound-initiated traffic and blocks unsolicited inbound. Billed per hour *while it exists* plus per GB
processed (and the EIP). One NAT is cheaper but a single point of failure: if its AZ dies, the other AZ loses egress, and
cross-AZ traffic is billed. Production: one per AZ. *(Note Q20, Q22)*

**19.** `kubernetes.io/role/elb = 1` on public subnets (internet-facing LBs) and `kubernetes.io/role/internal-elb = 1` on private
subnets (internal LBs), plus the `kubernetes.io/cluster/<name> = shared` tag. Read by the AWS cloud provider / AWS Load Balancer
Controller. Missing: "unable to find suitable subnets" when creating a LoadBalancer Service or Ingress. *(Note Q21)*

**20.** Gateway endpoints are free and route S3 traffic privately instead of through the NAT, which charges per GB; ECR image
layers are served from S3, so big image pulls skip the NAT charge. Interface endpoints (ECR API, etc.) cost an hourly fee per AZ,
which isn't worth it for a one-node demo. *(Note Q20 + vpc.tf comment)*

**21.** The VPC resolver (`enable_dns_support`) and instance DNS names (`enable_dns_hostnames`) let nodes resolve the cluster's
private API endpoint and AWS service endpoints; the EKS control plane expects them on. *(vpc.tf comment)*

## Section 4. EKS

**22.** `aws-auth` was a hand-edited YAML ConfigMap mapping IAM roles to Kubernetes groups: a typo could lock everyone out.
Access entries move that mapping into the EKS API (entry + AWS-managed access policy, cluster- or namespace-scoped), auditable
in CloudTrail and manageable in Terraform. We set `authentication_mode = "API"`. *(Note Q25)*

**23.** It accepts only tokens from the cluster's OIDC provider whose `aud` is `sts.amazonaws.com` and whose `sub` is exactly
`system:serviceaccount:<namespace>:<name>`. Without the `sub` condition, any pod in the cluster (or any service account) could
assume the role. *(Note Q24)*

**24.** IRSA: OIDC provider in IAM + annotation on the service account; trust policy embeds the cluster's OIDC URL (per-cluster
edits, size limits); works everywhere incl. Fargate. Pod Identity: an EKS-API association (cluster+namespace+SA -> role), role
trusts the fixed `pods.eks.amazonaws.com` principal, an agent on the node vends credentials; easier to reuse across clusters.
Choose Pod Identity for new multi-cluster setups; IRSA where it's required or you want the explicit mechanics. *(Note Q24)*

**25.** AWS creates and manages the Auto Scaling group and EKS-optimised AMI, and does rolling updates with cordon/drain.
Self-managed: you own AMI, patching and bootstrap, for more control and more toil. *(Note Q26)*

**26.** `t3.small` caps at about 11 pods (ENI/IP limits); `t3.medium` allows about 17. kube-system alone is about 7 pods
(coredns x2, aws-node, kube-proxy, EBS CSI x3), plus Flux and podinfo, which would exceed 11. *(variables.tf comment)*

**27.** Nodes would then reach the API through the NAT gateway's public IP, which isn't in the allow-list, so nodes fail to join
or lose the API (`NodeCreationFailure` / NotReady). Keeping the private endpoint on lets in-VPC traffic use private IPs
regardless of the allow-list. *(eks.tf comment)*

**28.** That option silently grants admin to whoever ran `apply`, and would collide with the explicit access entry when it's
the same person. Explicit access is visible in code and review. *(eks.tf comment)*

**29.** Convenience: always the newest compatible add-on version at plan time. Risk: a later plan can show an add-on upgrade
nobody reviewed; production pins `addon_version` and upgrades deliberately. *(eks.tf comment)*

**30.** Any three of: community module/tested building block vs template copy; `plan` shows an exact diff (change sets are
optional and coarser); you own state (S3, locking) instead of the stack owning it; plain references between configs instead of
exports/imports; failure leaves a partial result in state instead of an automatic rollback; one tool/language across providers.
*(Note Q28)*

## Section 5. CI/CD, OIDC and scanning

**31.** The job requests a short-lived signed JWT from GitHub (needs `id-token: write`), sends it to AWS STS with
`AssumeRoleWithWebIdentity`; STS verifies the signature against the IAM OIDC provider and checks the role's trust-policy
conditions (`aud`, `sub`); if they match it returns temporary credentials (about 1 hour). Nothing long-lived is stored, so
nothing to leak or rotate. *(Note Q29)*

**32.** PR job: `repo:OWNER/REPO:pull_request`. Apply job (running in the environment): `repo:OWNER/REPO:environment:dev-apply`.
The apply role is pinned to the environment one, so only a job in the approval-gated environment can assume it. *(Note Q30)*

**33.** Different power and different gates: plan is read-only and reachable from any same-repo PR; apply can write and is
reachable only from the protected environment (reviewer approval, main branch only). A malicious or buggy PR can never write
infrastructure. *(ci-access/oidc.tf comment)*

**34.** The plan role is read-only on the bucket, so it can't write the lock file. Plans don't change state, so concurrent PR
plans are harmless. It lets us give the PR role no write access to state at all. *(workflow comment)*

**35.** A tag is a movable pointer: if an action's repo is compromised the attacker can re-point the tag at malicious code that
then runs with the job's secrets and OIDC token. A SHA is immutable. (Keep current with Dependabot/Renovate.) *(see the header comment in `terraform-pr.yml`)*

**36.** The plan comment is redacted (12-digit account IDs and IPv4 addresses removed, size capped) and IPs are masked in logs,
and the binary plan is never uploaded as an artifact, because logs/comments/artifacts of a public repo are readable by anyone
and plans can contain secrets. Fork PRs also get no secrets or OIDC token. *(see comments in the workflows)*

**37.** One HIGH finding: AWS-0132 (state bucket uses SSE-S3, not a customer-managed KMS key). It was a deliberate cost
trade-off, so it's suppressed in code (`#trivy:ignore`) next to the decision, scoped to that one resource, with a written reason
and an expiry date. Lowering the severity gate would hide *future* real findings; explicit, justified, time-boxed suppressions
keep the gate honest. We also proved the gate with a deliberately bad config. *(Note Q32)*

**38.** (1) Revoke/deactivate the key immediately. (2) Check CloudTrail for what it did. (3) Rotate anything it could reach.
(4) Remove it from history if needed (`git filter-repo`, force-push, purge caches). (5) Prevent recurrence: secret scanning/push
protection, pre-commit secret detection, and OIDC so there are no long-lived keys. Deleting the commit isn't enough because bots
scan and copy public pushes within seconds. *(Note Q33)*

**39.** EKS, NAT and the node bill by the hour, so a merge (even a README typo) must not silently start the meter: apply is
`workflow_dispatch` plus a reviewer-approved environment. A real team can auto-apply cheap/low-risk stacks on merge with path
filters and a separate role/environment, while keeping expensive or destructive stacks behind approval. *(Note Q31; comment in `terraform-apply.yml`)*

**40.** Least privilege per job: the AWS job has `id-token: write` and read-only contents; the comment job has only
`pull-requests: write` with no AWS access and no OIDC token. A compromise of the comment step can't touch AWS. *(workflow comment)*

## Section 6. Flux and GitOps

**41.** Push: CI runs `kubectl apply`/`helm upgrade`, so it needs cluster credentials, and manual cluster changes go unnoticed.
Pull: an agent inside the cluster watches Git and applies it, so only read access to Git is needed, no external system holds
cluster admin, and drift is corrected. Git is the audit log; rollback is `git revert`. *(Note Q34)*

**42.** In Git: a commit to `clusters/dev/flux-system/` with the controller manifests, a `GitRepository` and a `flux-system`
`Kustomization`. In the cluster: the `flux-system` namespace, controllers, CRDs and an SSH deploy-key Secret (read-only). The
PAT is used once to set this up (it registers the deploy key) and is **not** stored in the cluster. *(`docs/gitops-setup.md`)*

**43.** source-controller fetches the repo; kustomize-controller builds and server-side-applies the manifests at a path every
`interval`, correcting any difference between Git and the cluster. `prune: true` deletes what you removed from Git. `wait: true`
reports Ready only when applied resources are healthy. `dependsOn` orders Kustomizations (apps after infrastructure). *(Note Q35)*

**44.** Flux reverts it to 2 on its next reconcile, within the 1-minute interval (or immediately with
`flux reconcile kustomization apps --with-source`). To change it properly, edit `count` in `apps/dev/kustomization.yaml` in the
GitOps repo and commit. *(gitops-setup.md)*

**45.** Both pull from Git and correct drift. Flux: small controllers configured entirely by Kubernetes objects, Git-centric, good
for platform teams. Argo CD: one app with a strong UI, visual diff/sync, Application/ApplicationSet model, own RBAC/SSO, often
easier to adopt. Choose by team habits. *(Note Q36)*

**46.** Never plaintext in Git. Options: SOPS (with AWS KMS, native in Flux) or Sealed Secrets, or keep secrets out of Git and sync
them with the External Secrets Operator from AWS Secrets Manager. Production choice: External Secrets with Secrets Manager (Git
holds a reference, rotation in AWS, IAM-governed access). *(Note Q37)*

**47.** Flux commits to the branch it watches and this repo's `main` is protected; app delivery and platform changes have different
cadence and approvers; it keeps Flux commits out of Terraform CI. Teardown order: things Kubernetes creates in AWS (load balancers,
EBS volumes) aren't in Terraform state, so destroying the cluster first orphans them, they keep billing and block VPC deletion.
*(gitops-setup.md)*

## Section 7. Debugging scenarios

**48.** The access entry principal doesn't match who you are. Compare `aws sts get-caller-identity` with
`aws eks list-access-entries --cluster-name eks-dev`; with SSO the entry needs the plain role ARN *without* the
`/aws-reserved/sso.amazonaws.com/...` path. Also check your IP is in `api_allowed_cidrs` (a timeout rather than Unauthorized).
*(Stage 4 "Commonly breaks" in the notes)*

**49.** (1) The job has `permissions: id-token: write`. (2) `github_owner` matches the repo owner's exact capitalisation (case-sensitive).
(3) For apply, the job declares `environment: dev-apply` and the name matches `apply_environment`. (4) It's not a fork PR; and the
branch/context matches the `sub` the trust policy expects. Confirm via CloudTrail or by decoding the token. *(Stage 5 "Commonly breaks" in the notes)*

**50.** Resources created by Kubernetes (a LoadBalancer Service's load balancer, ENIs, security groups, EBS volumes) still sit in the
VPC and aren't in Terraform state. Find them with `aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=<id>` and the
load balancer list; delete them (best: delete the Service/PVC with kubectl *before* destroying the cluster), then re-run destroy.
*(`docs/gitops-setup.md`)*

**51.** Work outside-in: `flux get all -A` to find the first non-Ready object, then `kubectl -n flux-system describe kustomization
infrastructure` and `flux logs --level=error`. `apps` is just waiting on `infrastructure`; fix that one (for example a Pod Security
rejection or a bad manifest), and `apps` follows. *(Stage 6 "Commonly breaks" in the notes)*

**52.** Terraform isn't looking at the right state: `-backend-config` omitted or pointing at a different bucket/key (a fresh local
state), the CI secret `TF_STATE_BUCKET` is wrong, the state was destroyed/emptied, or you're in the wrong directory/account. Check
`terraform state list` and the initialised backend (`.terraform/terraform.tfstate`).
*(Note Q1, Q2)*

**53.** (1) Pod-per-node limit reached (t3.medium about 17 pods). (2) Not enough CPU/memory requests free on the 2-vCPU node.
(3) A PersistentVolume/zone or taint/selector mismatch. `kubectl describe pod <name>` shows the scheduler event
("Too many pods" / "Insufficient cpu"). `kubectl describe node` shows allocatable vs allocated. *(variables.tf comment)*

**54.** The platform was left running: EKS control plane ($0.10/h), the node, the NAT gateway and its public IP are about
$0.21/hour, about $150/month. Check `aws eks list-clusters`, `aws ec2 describe-nat-gateways`, `aws ec2 describe-addresses`, and
Cost Explorer filtered by the `Project=terraform-eks-platform` tag. Prevent it with the destroy order in the README. *(README Cost)*

**55.** No. Read the denied action and resource in CloudTrail (or the error), then add exactly that one action to
`ci-access/permissions.tf`, scoped as tightly as possible, and re-apply `ci-access`. Granting `*:*` defeats the least-privilege
design. *(Stage 5 "Commonly breaks" in the notes)*

## Section 8. Say it out loud

Use the 60-second pitch at the top of `interview-notes.md` for **56**, the "Design decisions and trade-offs" and "What I would do
differently in production" sections of the README for **57**, and for **58** retrace the flow in
`.github/workflows/terraform-pr.yml`: PR opened -> `static` job (fmt, validate, tflint, Trivy) -> `plan` job (OIDC token ->
STS -> read-only role -> `terraform init/plan -lock=false` -> redacted text artifact) -> `comment` job (downloads the artifact, posts or
updates one sticky PR comment).
