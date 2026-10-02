variable "aws_region" {
  description = "AWS region for the dev platform. Must match the region you intend to deploy into (and normally the state bucket's region)."
  type        = string
  default     = "ap-south-1"
}
