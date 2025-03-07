# main.tf

provider "aws" {
  region = "us-east-1"  # Adjust this to your preferred region
}

# Enable AWS Security Hub
resource "aws_securityhub_account" "this" {}

# Enable GuardDuty
resource "aws_guardduty_detector" "this" {
  enable = true
}

# Enable AWS Config
resource "aws_config_configuration_recorder" "this" {
  name     = "config-recorder"
  role_arn = aws_iam_role.config_role.arn
  recording_group {
    all_supported = true
  }
}

resource "aws_iam_role" "config_role" {
  name = "aws_config_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Principal = {
          Service = "config.amazonaws.com"
        },
        Effect    = "Allow",
        Sid       = ""
      }
    ]
  })
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect    = "Allow",
        Sid       = ""
      }
    ]
  })
}

# Attach policies to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Cloud Security Role (for EC2)
resource "aws_iam_role" "cloud_security_role" {
  name = "cloud-security-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect    = "Allow",
        Sid       = ""
      }
    ]
  })
}

# Attach the ReadOnlyAccess policy to the cloud security role
resource "aws_iam_role_policy_attachment" "cloud_security_role_attachment" {
  role       = aws_iam_role.cloud_security_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Lambda function for remediation
resource "aws_lambda_function" "security_remediation" {
  function_name = "security-remediation"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  filename      = "lambda/security_remediation.zip"  # Make sure this file exists and contains Lambda code
}

# CloudWatch Event Rule to trigger the Lambda function on GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_event" {
  name        = "guardduty-threat-detected"
  description = "Trigger Lambda on GuardDuty threat"
  event_pattern = jsonencode({
    source = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

# CloudWatch Event Target to link GuardDuty findings to Lambda function
resource "aws_cloudwatch_event_target" "remediation_target" {
  rule = aws_cloudwatch_event_rule.guardduty_event.name
  arn  = aws_lambda_function.security_remediation.arn
}