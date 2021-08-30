output "out" {
  value = {
    arn           = aws_lambda_function.lambda.arn
    version       = aws_lambda_function.lambda.version
    qualified-arn = aws_lambda_function.lambda.qualified_arn
    function-name = aws_lambda_function.lambda.function_name
    role-arn      = aws_iam_role.lambda.arn
    log-groups = [
      aws_cloudwatch_log_group.lambda
    ]
  }
}
