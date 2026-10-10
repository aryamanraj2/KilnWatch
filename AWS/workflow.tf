resource "aws_sfn_state_machine" "inference" {
  name     = "${var.project_name}-inference-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "KilnWatch starter inference workflow. Replace container command/input mapping with the actual inference contract."
    StartAt = "RunInferenceTask"
    States = {
      RunInferenceTask = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = aws_ecs_cluster.main.arn
          TaskDefinition = aws_ecs_task_definition.inference.arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = aws_subnet.public[*].id
              SecurityGroups = [aws_security_group.ecs.id]
              AssignPublicIp = "ENABLED"
            }
          }
        }
        End = true
      }
    }
  })
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${var.project_name}-api-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda API errors exceeded threshold."
  dimensions          = { FunctionName = aws_lambda_function.api.function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}


# API read proof has no StartExecution permission; jobs remain 501.
