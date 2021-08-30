locals {
  lambda-cf-edge-s3-dir  = "cf-edge-s3"
  lambda-cf-edge-s3-name = "cloudfront-edge-s3"
  lambda-cf-edge-s3-path = "${path.module}/${local.lambda-cf-edge-s3-dir}"
}

module "lambda-cf-edge-s3" {
  source = "./lambda"

  arg = {
    # General variables
    name   = local.env
    tags   = { Name : "${local.lambda-cf-edge-s3-name}-${local.env}" }
    region = local.region

    # Full lambda function configuration
    lambda = {
      name        = local.lambda-cf-edge-s3-name
      description = "Lambda@Edge: Authenticates CloudFront requests to S3 bucket containing maintenance web pages."

      zip     = "${local.lambda-cf-edge-s3-path}/index.js.zip"
      handler = "index.handler"
      runtime = "nodejs12.x"
      memsize = "512"
      timeout = 30

      # Lambda versioning is needed for cloudfront association
      track-versions = true

      # Not a VPC function, so subnets and security groups are empty
      subnet-ids = []
      sg-ids     = []

      env = null

      policy-attachments = [
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
      ]

      policy = {
        Version = "2012-10-17",
        Statement = [{
          Effect = "Allow",
          Action = "sts:AssumeRole",
          Principal = {
            Service = [
              "lambda.amazonaws.com",
              "edgelambda.amazonaws.com"
            ]
          }
        }]
      }
    }
  }
}
