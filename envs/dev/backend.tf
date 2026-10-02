# PARTIAL backend configuration.
#
# Backend blocks cannot use variables or locals (Terraform needs the backend
# before it evaluates anything else). So we leave bucket/key/region OUT of the
# committed code and supply them at init time:
#
#   terraform init -backend-config=backend.hcl
#
# WHY NOT HARD-CODE THE BUCKET NAME? This is a public repo. A hard-coded bucket
# name advertises where your state lives (and ties the code to ONE person's
# bucket, so nobody else could use it without editing source). backend.hcl is
# gitignored; backend.hcl.example shows its shape. The same code can then point
# at any bucket/account/key with no code change, which is also how you'd run
# dev/stage/prod with different state keys.
terraform {
  backend "s3" {
    # S3 native locking (Terraform >= 1.10): while plan/apply runs, Terraform
    # writes "<key>.tflock" using an S3 conditional write (create only if the
    # object doesn't exist). A second run fails instead of corrupting state.
    # Replaces the old DynamoDB lock table.
    use_lockfile = true

    # Encrypt the state object at rest (the bucket also enforces default
    # encryption; this makes the client request it explicitly).
    encrypt = true
  }
}
