variable "region" {
  default = "eu-west-2"
}

variable "lambda_function_name" {
  default = "rfping"
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

provider "aws" {
   region = var.region
}

resource "aws_s3_bucket" "rfping-bucket" {
  bucket = "rfping-lambda-storag3"
  acl    = "private"

  tags = {
    Name        = "Lambda storage"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_object" "file_upload" {
  bucket = aws_s3_bucket.rfping-bucket.id
  key    = "lambda"
  source = "/tmp/main.zip"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}


resource "aws_dynamodb_table" "rftable" {
  name             = "Clients"
  hash_key         = "Uuid"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  attribute {
    name = "Uuid"
    type = "S"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.role_for_LDC.id

  policy = <<EOF
{  
  "Version": "2012-10-17",
  "Statement":[{
    "Effect": "Allow",
    "Action": [
     "dynamodb:BatchGetItem",
     "dynamodb:GetItem",
     "dynamodb:Query",
     "dynamodb:Scan",
     "dynamodb:BatchWriteItem",
     "dynamodb:PutItem",
     "dynamodb:UpdateItem"
    ],
    "Resource": "${aws_dynamodb_table.rftable.arn}"
   }
  ]
}
EOF
}

resource "aws_iam_role" "role_for_LDC" {
  name = "rfping-role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
}
EOF
}

resource "aws_lambda_function" "rfping-lambda" {

  function_name = var.lambda_function_name
  s3_bucket     = "rfping-lambda-storag3" 
  s3_key        = "lambda"
  role          = aws_iam_role.role_for_LDC.arn
  handler       = "main"
  runtime       = "go1.x"

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_log_group,
    aws_s3_bucket_object.file_upload,
  ]

  environment {
    variables = {
      region = var.region
    }
  }

}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.role_for_LDC.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_api_gateway_rest_api" "rfping-apigw" {
  name        = "RFPingAPI"
  description = "API Gateway for RFPing lambda"
}

resource "aws_api_gateway_resource" "proxy" {
   rest_api_id = aws_api_gateway_rest_api.rfping-apigw.id
   parent_id   = aws_api_gateway_rest_api.rfping-apigw.root_resource_id
   path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
   rest_api_id   = aws_api_gateway_rest_api.rfping-apigw.id
   resource_id   = aws_api_gateway_resource.proxy.id
   http_method   = "ANY"
   authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
   rest_api_id = aws_api_gateway_rest_api.rfping-apigw.id
   resource_id = aws_api_gateway_method.proxy.resource_id
   http_method = aws_api_gateway_method.proxy.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.rfping-lambda.invoke_arn
}

resource "aws_api_gateway_method" "proxy_root" {
   rest_api_id   = aws_api_gateway_rest_api.rfping-apigw.id
   resource_id   = aws_api_gateway_rest_api.rfping-apigw.root_resource_id
   http_method   = "ANY"
   authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
   rest_api_id = aws_api_gateway_rest_api.rfping-apigw.id
   resource_id = aws_api_gateway_method.proxy_root.resource_id
   http_method = aws_api_gateway_method.proxy_root.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.rfping-lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "rfping-depl" {
   depends_on = [
     aws_api_gateway_integration.lambda,
     aws_api_gateway_integration.lambda_root,
   ]

   rest_api_id = aws_api_gateway_rest_api.rfping-apigw.id
   lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "rfping-stage" {
  deployment_id = aws_api_gateway_deployment.rfping-depl.id
  rest_api_id   = aws_api_gateway_rest_api.rfping-apigw.id
  stage_name    = "rfping"
}


resource "aws_lambda_permission" "apigw" {
   statement_id  = "AllowAPIGatewayInvoke"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.rfping-lambda.function_name
   principal     = "apigateway.amazonaws.com"

   source_arn = "${aws_api_gateway_rest_api.rfping-apigw.execution_arn}/*/*"
}

resource "aws_wafregional_ipset" "ipset" {
  name = "tfIPSet"

  ip_set_descriptor {
    type  = "IPV4"
    value = "${chomp(data.http.myip.body)}/32"
  }
}

resource "aws_wafregional_regex_match_set" "methregmatch" {
  name = "methregmatch"

  regex_match_tuple {
    field_to_match {
      type = "METHOD"
    }

    regex_pattern_set_id = aws_wafregional_regex_pattern_set.methpatt.id
    text_transformation  = "NONE"
  }
}

resource "aws_wafregional_regex_pattern_set" "methpatt" {
  name                  = "methpatt"
  regex_pattern_strings = ["OPTIONS"]
}

resource "aws_wafregional_rule" "wafrule_public" {
  depends_on  = [aws_wafregional_ipset.ipset, aws_wafregional_regex_match_set.methregmatch]
  name        = "tfWAFRule"
  metric_name = "tfWAFRule"

  predicate {
    data_id = aws_wafregional_ipset.ipset.id
    negated = true
    type    = "IPMatch"
  }
  predicate {
    data_id = aws_wafregional_regex_match_set.methregmatch.id
    negated = false
    type    = "RegexMatch"
  }

}

resource "aws_wafregional_web_acl" "waf_acl" {
  depends_on = [
    aws_wafregional_ipset.ipset,
    aws_wafregional_regex_match_set.methregmatch,
    aws_wafregional_regex_pattern_set.methpatt,
    aws_wafregional_rule.wafrule_public,
  ]
  name        = "tfWebACL"
  metric_name = "tfWebACL"

  default_action {
    type = "ALLOW"
  }

  rule {
    action {
      type = "BLOCK"
    }

    priority = 1
    rule_id  = aws_wafregional_rule.wafrule_public.id
    type     = "REGULAR"
  }
}


resource "aws_wafregional_web_acl_association" "waf_assoc" {
  resource_arn = aws_api_gateway_stage.rfping-stage.arn
  web_acl_id   = aws_wafregional_web_acl.waf_acl.id
}

output "base_url" {
  value = aws_api_gateway_stage.rfping-stage.invoke_url
}
