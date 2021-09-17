# Lambda function configuration module.
# Creates the following resources on the target environment:
# - lambda function
# - lambda function layer (optional)
# - IAM role for lambda function
# 
# IAM policies can be assigned to the lambda function in the following ways:
# - as policy attachments, works well for managed policies (tuple "lambda.policy-attachments")
# - as lambda permissions (tuple "lambda.permissions")
# - as role policies (tuple "lambda.policies")

# Lambda structure format:
# lambda {
#   name = ... <- the name of your lambda function
#   zip = ... <- zip file with the source code
#   handler = ... <- name of the function inside source code acting as a lambda handler
#   runtime = ... <- one of the AWS-supported lambda runtimes, e.g. "python3.8" for example
#   subnet-ids = [...] <- array of subnets where lambda runs (for VPC lambda only)
#   sg-ids = [...] <- array of security groups (for VPC lambda only)
#   env = { ... } <- map of environment variables for lambda
#   policies = {} <- map of the IAM policies added as inline policies to the lambda IAM role
#   policy-attachments = [] <- map of the IAM policies attached to the lambda IAM role 
#   permissions = {} <- map of IAM permissions for lambda (excluding S3 permissions)
#   s3-permission = { source-arn } <- specify the S3 bucket where lambda has access permissions
#   memsize = ... <- memory size for lambda function execution (or default)
#   timeout = ... <- lambda execution timeout (or default)
# }
# layer = { <- definition of lambda layer
#   zip = ... <- zip file with packaged lambda dependencies
#   name = ... <- name of the lambda layer
#   compatible-runtimes = [...] <- list of compatible AWS-supported runtimes for the lambda layer
# }


locals {
  name   = var.arg.name
  tags   = var.arg.tags
  region = var.arg.region

  managed-policies = {
    vpc = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
    basic = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  }

  is-vpc-lambda = (length(local.lambda.subnet-ids) + length(local.lambda.sg-ids)) > 0

  lambda = lookup(var.arg, "lambda", {
    policy-attachments = []
    permissions        = {}
    policies           = {}
    env                = null
    s3-permission      = {}
  })

  env  = local.lambda.env == null ? [] : local.lambda.env[*]
  role = lookup(local.lambda, "role", aws_iam_role.lambda)

  layer = lookup(var.arg, "layer", null)
  logs  = lookup(var.arg, "logs", {})

  default-policy = {
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = {
        Service = [
          "lambda.amazonaws.com",
        ]
      }
    }]
  }
}

resource "aws_lambda_function" "lambda" {
  function_name    = "${local.name}-${local.lambda.name}"
  filename         = local.lambda.zip
  source_code_hash = filebase64sha256(local.lambda.zip)
  layers           = local.layer == null ? [] : [aws_lambda_layer_version.layer[0].arn]

  handler          = local.lambda.handler # "index.handler"
  role             = local.role.arn

  memory_size      = lookup(local.lambda, "memsize", "512")
  runtime          = lookup(local.lambda, "runtime", "nodejs10.x")
  timeout          = lookup(local.lambda, "timeout", 900)

  description      = lookup(local.lambda, "description", "")
  publish          = lookup(local.lambda, "track-versions", false)

  vpc_config {
    subnet_ids         = local.lambda.subnet-ids
    security_group_ids = local.lambda.sg-ids
  }

  dynamic "environment" {
    for_each = local.env
    content {
      variables = environment.value
    }
  }
}

resource "aws_lambda_layer_version" "layer" {
  count               = local.layer == null ? 0 : 1
  filename            = local.layer.zip
  layer_name          = local.layer.name
  source_code_hash    = filebase64sha256(local.layer.zip)
  compatible_runtimes = local.layer.compatible-runtimes
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-${local.lambda.name}-role"
  assume_role_policy = jsonencode(lookup(local.lambda, "policy", local.default-policy))
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = local.role.name
  policy_arn = local.is-vpc-lambda ? local.managed-policies.vpc : local.managed-policies.basic
}

resource "aws_iam_role_policy_attachment" "policy-attachments" {
  for_each   = toset(lookup(local.lambda, "policy-attachments", []))
  role       = local.role.name
  policy_arn = each.key
}

data "aws_caller_identity" "this" {}

resource "aws_lambda_permission" "permissions" {
  for_each      = lookup(local.lambda, "permissions", {})
  function_name = aws_lambda_function.lambda.function_name

  principal  = try(local.lambda.permissions[each.key]["principal"], "sns.amazonaws.com")
  action     = try(local.lambda.permissions[each.key]["action"], "lambda:InvokeFunction")
  source_arn = try(local.lambda.permissions[each.key]["source-arn"], aws_lambda_function.lambda.arn)
}

resource "aws_lambda_permission" "s3-permission" {
  count          = can(local.lambda.s3-permission.source-arn) ? 1 : 0
  function_name  = aws_lambda_function.lambda.function_name
  source_account = data.aws_caller_identity.this.account_id

  action     = try(local.lambda.s3-permission.action, "lambda:InvokeFunction")
  principal  = try(local.lambda.s3-permission.principal, "s3.amazonaws.com")
  source_arn = try(local.lambda.s3-permission.source-arn, aws_lambda_function.lambda.arn)
}

resource "aws_iam_role_policy" "policies" {
  for_each = lookup(local.lambda, "policies", {})
  policy   = local.lambda.policies[each.key]
  role     = local.role.id
}
