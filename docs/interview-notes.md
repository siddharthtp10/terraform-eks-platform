# Interview notes

Plain-language Q&A per stage. Read the answers out loud until they sound natural.

## Stage 1 - Repo skeleton, .gitignore, pre-commit

**Q1. Why split into `bootstrap/` and `envs/dev/` instead of one folder?**
Terraform needs somewhere to store state, but the bucket for state must itself be
created by something. `bootstrap/` creates the bucket using local state once;
`envs/dev/` then uses that bucket as its remote backend. Separate folders also
mean separate state files, so a mistake in the platform can't touch the bucket.

**Q2. What must never be committed to git, and why?**
`*.tfstate` (contains resource details and often secrets in plaintext),
`*.tfvars` (environment-specific values), `.terraform/` (downloaded plugins,
huge and reproducible) and kubeconfigs (cluster credentials).

**Q3. Should `.terraform.lock.hcl` be committed?**
Yes. It records exact provider versions and checksums, so CI and every laptop
download identical plugins. Ignoring it is a common mistake.

**Q4. What do `fmt`, `validate` and `tflint` each catch?**
`fmt` = style only. `validate` = syntax and internal consistency (a reference to
an undeclared variable). `tflint` = deeper lint and provider-aware rules (unused
variables, invalid instance types, missing version constraints). None of them
talk to AWS or prove the plan will succeed; only `plan` does.

**Q5. How does this differ from your CloudFormation workflow?**
CloudFormation stores state for you inside the service (the stack). Terraform
makes *you* own state: where it lives, who can read it, how it is locked. In
return you get one tool across clouds, a real `plan` diff before every change,
and a module/registry ecosystem. The repo structure is also my choice rather
than "one template per stack".

### Commonly breaks at this stage
`terraform_validate` fails in pre-commit with *"Module not installed"* or
*"Missing required provider"* because nothing has been `init`-ed yet.
Debug: run `terraform init -backend=false` in the failing directory, then re-run
`pre-commit run --all-files`; read the hook output, which names the directory.

## Stage 2 - Remote state bootstrap

**Q1. Why use remote state instead of the default local `terraform.tfstate`?**
State is Terraform's record of what it built. On a laptop it is a single copy
that one person owns: lose the laptop and Terraform forgets your infrastructure;
a teammate (or the CI pipeline) can't run it at all. Remote state in S3 is shared,
backed up, encrypted and access-controlled, which is the prerequisite for CI/CD.

**Q2. What does state locking prevent?**
Two runs writing state at the same time. Without a lock, two `apply`s each read
the same starting state, make different changes, and the last writer silently
overwrites the first, leaving real resources that Terraform no longer knows about
(orphans) or thinks exist when they don't. With locking the second run fails fast
with "Error acquiring the state lock" and shows who holds it.

**Q3. S3 native locking vs a DynamoDB lock table?**
Before Terraform 1.10 the S3 backend needed a separate DynamoDB table for locks.
Now `use_lockfile = true` makes Terraform write a `<key>.tflock` object next to
the state using an S3 conditional write ("create only if it doesn't exist"), so
only one writer can succeed. Fewer resources, no extra table to pay for or give
IAM permissions on. (The DynamoDB method is deprecated.) The CI role later needs
S3 permission on that `.tflock` object too, not just on the state file.

**Q4. Why turn on versioning and encryption for the state bucket?**
Versioning is the undo button: if state is corrupted or a bad run overwrites it,
restore the previous version. Encryption (plus blocking public access and denying
non-TLS requests) matters because state routinely contains secrets such as
passwords and keys in plaintext, so it is one of the most sensitive files you own.

**Q5. What happens if the bootstrap's own local state is lost?**
The bucket and the platform state inside it are untouched; only Terraform's
bookkeeping for the *bucket* is gone. Recovery is to re-run bootstrap with the
same variables and `terraform import` the existing bucket and its sub-resources
(versioning, encryption, public access block, policy, lifecycle) so Terraform
adopts them rather than trying to create duplicates. That is why this config is
tiny, why the bucket has `prevent_destroy`, and why the bucket name is recorded
somewhere safe. A common alternative is to migrate bootstrap's state into the
bucket afterwards; the trade-off is a slightly circular dependency.

### Commonly breaks at this stage
`apply` fails with `BucketAlreadyExists` (the name is taken by someone else) or
`BucketAlreadyOwnedByYou` (you made it earlier), or init fails with `Invalid
security token` / region errors.
Debug: `aws sts get-caller-identity` (confirm which account/identity you are),
check `aws_region` in tfvars equals `region` in backend.hcl, and pick a more
unique bucket name. Re-run `terraform plan`; S3 names are global, not per-account.

## Stage 3 - VPC (terraform-aws-modules/vpc)

**Q1. What makes a subnet "public" vs "private", and how does a route table do it?**
There is no "public" flag on a subnet. A subnet is public if its route table has a
route `0.0.0.0/0 -> Internet Gateway`; it is private if it doesn't (its default
route points at a NAT gateway instead, or nowhere). The route table decides where
packets go, and that is the whole difference. Instances in a public subnet also
need a public IP to be reachable; ours don't get one automatically.

**Q2. Why do we need a NAT gateway, and what does it cost?**
Worker nodes live in private subnets with no public IPs, but they must still pull
container images and call AWS APIs. A NAT gateway sits in a public subnet and
lets private resources start outbound connections while blocking unsolicited
inbound ones. It is one of the pricier "idle" resources: you pay per hour it
exists regardless of traffic, plus per GB processed (see the README Cost note).
That's why the S3 gateway endpoint matters: it is free and sends S3 traffic
(including ECR image layers) around the NAT.

**Q3. Why does EKS need specific tags on subnets?**
Kubernetes doesn't know which subnets to use for load balancers; it finds them
by tag. `kubernetes.io/role/elb=1` marks subnets for internet-facing load
balancers, `kubernetes.io/role/internal-elb=1` marks internal ones, and
`kubernetes.io/cluster/<name>=shared` ties them to the cluster. The AWS Load
Balancer Controller reads these tags. Without them, a Service of type
LoadBalancer or an Ingress fails with "unable to find suitable subnets".

**Q4. One NAT gateway vs one per AZ?**
One is cheaper (you pay the fixed hourly cost once), but it's a single point of
failure: if its AZ goes down, nodes in the other AZ lose outbound internet, and
cross-AZ traffic to reach it is billed. One per AZ costs more but each AZ is
independent and traffic stays local. I use one for a destroy-after-use demo
(`single_nat_gateway = true`) and would use one per AZ in production. It is a
single variable, which is the point of using a module.

**Q5. How does `cidrsubnet()` work?**
`cidrsubnet(prefix, newbits, netnum)` splits a network into smaller ones.
`newbits` is how many bits are added to the prefix length and `netnum` picks which
of the resulting 2^newbits blocks you want. `cidrsubnet("10.0.0.0/16", 4, 1)` gives
`10.0.16.0/20`: /16 + 4 bits = /20, and block number 1 starts 4,096 addresses in.
Deriving subnets from the VPC CIDR avoids typos and overlaps, and it scales
with `azs_count`. (CloudFormation has `Fn::Cidr`, but Terraform lets you loop
and compute with ordinary expressions.)

### Commonly breaks at this stage
`apply` fails with `AddressLimitExceeded` (no free Elastic IPs for the NAT
gateway), or a subnet error such as `InvalidSubnet.Conflict` / CIDR overlap if
you changed `vpc_cidr` against an existing VPC, or `InvalidParameterValue` when
an AZ doesn't support the request.
Debug: read the failing resource address in the error (for example
`module.vpc.aws_eip.nat[0]`). For EIPs, check Service Quotas ("EC2-VPC Elastic
IPs", per region) and release unused addresses. For CIDRs, run
`terraform console` and evaluate `cidrsubnet("10.0.0.0/16", 4, 0)` to see
exactly what ranges your variables produce. For AZs, run
`aws ec2 describe-availability-zones --region ap-south-1`.

## Stage 4 - EKS (terraform-aws-modules/eks)

**Q1. IRSA vs EKS Pod Identity: what is the difference?**
Both give a pod short-lived AWS credentials without stored keys. With IRSA the
cluster has an OIDC identity provider in IAM; a pod's service account carries a
role-ARN annotation and the role's trust policy checks the token's `sub`
(namespace:serviceaccount) and `aud`. The catch: the trust policy embeds the
cluster's OIDC URL, so every cluster needs its own edit and there is a size limit
on trust policies. Pod Identity is newer: you create an "association" (cluster +
namespace + service account -> role) through the EKS API, the role trusts the
fixed `pods.eks.amazonaws.com` principal, and an agent on the node hands out
credentials. It's simpler to reuse across clusters. I used IRSA here because it
works everywhere (including Fargate and older setups) and shows the moving parts.

**Q2. Access entries vs the `aws-auth` ConfigMap?**
`aws-auth` was a YAML ConfigMap in `kube-system` mapping IAM roles to Kubernetes
groups. A typo could lock everyone out, and the only way to fix it was via the
cluster creator's hidden admin. Access entries move that mapping into the EKS API:
each IAM principal gets an entry plus AWS-managed access policies (for example
cluster-admin or read-only), scoped to the cluster or to namespaces. It's
auditable in CloudTrail, manageable in Terraform, and recoverable without
kubectl. I set `authentication_mode = "API"` so only access entries count.

**Q3. Managed node groups vs self-managed?**
In a managed node group AWS creates the Auto Scaling group, picks the EKS-optimised
AMI, and does rolling updates with cordon/drain for you. Self-managed nodes are
EC2/ASGs you build and patch yourself: more control (custom AMIs, odd kernels,
special bootstrap) and more toil. I use managed unless I have a hard requirement,
and would look at Karpenter or EKS Auto Mode for real scaling.

**Q4. Why put nodes in private subnets?**
Nodes have no public IP, so nothing on the internet can reach the kubelet or your
workloads directly; all inbound traffic must come through a load balancer you
chose to create in the public subnets. Outbound traffic (images, AWS APIs) goes
through the NAT gateway. It's a smaller attack surface for the price of the NAT.
Note the control-plane endpoint is a separate decision (public restricted to my IP
here, private endpoint also on for in-VPC traffic).

**Q5. How does this differ from your CloudFormation experience?**
The EKS resources are the same AWS APIs. The differences: a community module
gives me a tested, versioned building block where in CloudFormation I'd write or
copy a large template or nested stack; `terraform plan` shows an exact diff before
I touch anything (CloudFormation change sets are comparable but optional and
coarser); state is mine to manage (S3) instead of belonging to a stack; and I can
read values between configs (VPC outputs feeding EKS) with plain references
rather than exports/imports. Failure handling also differs: Terraform stops
and leaves the partial result in state, where CloudFormation rolls back.

### Commonly breaks at this stage
`kubectl` returns `error: You must be logged in to the server (Unauthorized)`, or
node group creation hangs and fails with `NodeCreationFailure`.
- Unauthorized: the access entry's `principal_arn` doesn't match the identity you
  call kubectl as. With AWS SSO the entry needs the plain role ARN
  `arn:aws:iam::<id>:role/AWSReservedSSO_<...>` WITHOUT the
  `/aws-reserved/sso.amazonaws.com/<region>/` path that `get-caller-identity`
  shows. Debug: `aws sts get-caller-identity`, compare with
  `aws eks list-access-entries --cluster-name eks-dev`, fix the variable, re-apply.
- Can't connect at all (timeout): your public IP changed or isn't in
  `api_allowed_cidrs`. Re-check `curl -s https://checkip.amazonaws.com` and re-apply.
- NodeCreationFailure: nodes can't reach the API or pull images. Check the NAT
  gateway and private route table from Stage 3, then
  `aws eks describe-nodegroup ... --query nodegroup.health`.

## Stage 5 - GitHub Actions, OIDC, scanning

**Q1. Why is OIDC better than storing AWS access keys in GitHub secrets?**
A stored key is long-lived: it works from anywhere until someone rotates it, and if
it leaks (a log, a compromised action, a former contributor) the attacker has
standing access. With OIDC each job asks GitHub for a signed token that is valid for
minutes, exchanges it with AWS STS for temporary credentials (1 hour), and those die
on their own. Nothing secret is stored in GitHub, so there is nothing to rotate or leak.
AWS decides whether to trust the job by checking the token signature and the role's
trust-policy conditions.

**Q2. How does the `sub` claim stop another repository from assuming your role?**
Every repo on GitHub gets valid tokens from the same issuer, so signature checking
alone proves nothing. The `sub` claim names the exact repo and context, for example
`repo:OWNER/REPO:pull_request`. The trust policy requires `sub` to equal that string
(plus `aud = sts.amazonaws.com`), so a token from `someone-else/repo` is rejected. The
apply role is stricter: it requires `...:environment:dev-apply`, so only a job running
in the protected environment (reviewer approval, main branch only) can get write
access. Leaving the `sub` condition off is the classic OIDC mistake.

**Q3. Plan on PR vs apply on merge: what is the reasoning, and why not auto-apply here?**
Plan on PR gives reviewers the exact diff before anything changes, and it runs with a
read-only role so a bad PR can't break anything. Apply after merge keeps `main` and
reality in sync, with an audit trail. For this repo I do NOT auto-apply: the EKS
stack costs money every hour, so apply is manual and needs an approver. For cheap or
low-risk stacks a real team would auto-apply on merge, filtered by path, with its own
role. Also, apply runs from a saved plan file so what is applied is what was planned.

**Q4. What did the security scanner catch?**
Trivy flagged one HIGH finding, AWS-0132, on the state bucket: it uses SSE-S3 rather
than a customer-managed KMS key. That was a deliberate cost trade-off, so I suppressed
it in code next to the decision, scoped to that one resource, with a written reason and
an expiry date, instead of lowering the severity gate. I also proved the gate works by
feeding it a deliberately bad config (SSH open to 0.0.0.0/0) and checking it fails the
build. The point I make in interviews: a scanner finding is a prompt to decide, and
every suppression should be explicit, justified and time-boxed.

**Q5. A secret was committed or leaked: what do you do?**
Revoke or rotate it FIRST (deactivate the key or credential in AWS/GitHub); deleting
the commit does not help because it's already been copied and scanned by bots. Then
check CloudTrail for what it was used for, remove it from history if needed
(`git filter-repo`, force-push, and ask GitHub support to purge caches), and add
prevention: pre-commit secret detection, GitHub secret scanning with push protection,
and OIDC so there are no long-lived keys to leak. The best answer to "leaked AWS key"
is that this pipeline has none.

### Commonly breaks at this stage
The `configure-aws-credentials` step fails with `Not authorized to perform
sts:AssumeRoleWithWebIdentity`.
Debug: the trust policy and the token disagree. Check, in order: (1) the job has
`permissions: id-token: write`; (2) `github_owner` in `ci-access` matches the repo
owner's exact capitalisation (the claim is case-sensitive); (3) for apply, the job
declares `environment: dev-apply` and the name equals `apply_environment`; (4) the
workflow is not running from a fork PR. To see the real claim, temporarily add a step
that decodes the token, or read the failed AssumeRoleWithWebIdentity event in
CloudTrail. A later `AccessDenied` on a specific API call (for example
`ec2:CreateLaunchTemplate`) means a missing permission: read the denied action in
CloudTrail and add exactly that action to `ci-access/permissions.tf`, then re-apply.
