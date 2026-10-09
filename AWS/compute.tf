resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/aws/ecs/${var.project_name}-inference"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_ecs_task_definition" "inference" {
  family                   = "${var.project_name}-inference"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "inference"
    image     = "${aws_ecr_repository.inference.repository_url}:${var.inference_image_tag}"
    essential = true
    environment = [
      { name = "DATA_BUCKET", value = aws_s3_bucket.data.bucket },
      { name = "MODEL_S3_PREFIX", value = "models/" },
      { name = "INPUT_S3_PREFIX", value = "imagery/" },
      { name = "OUTPUT_S3_PREFIX", value = "detections/" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "inference"
      }
    }
  }])
}

resource "aws_ecs_service" "optional_http_inference" {
  count           = var.create_demo_ecs_service ? 1 : 0
  name            = "${var.project_name}-inference-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.inference.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
  lifecycle { ignore_changes = [desired_count] }
}
