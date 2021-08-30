variable "arg" {}

variable "env" {
  type        = string
  default     = "put-name-of-your-env-here"
  description = "Name of the target environment"
}

variable "dns" {
  type = map(any)

  default = {
    domain          = "put-your-domain-name-here"
    zone-id         = "your-domain-zone-id"
    certificate-arn = "put-your-ACM-ssl-certificate-arn-here"
  }

  description = "DNS configuration for the CloudFront distribution"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for Lambda@Edge deployment"
}
