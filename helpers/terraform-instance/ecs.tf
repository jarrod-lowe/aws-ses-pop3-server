resource "aws_ecs_cluster" "container" {
  name = var.project
}

resource "aws_cloudwatch_log_group" "container" {
  name              = var.project
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "container" {
  family = var.project
  runtime_platform {
    cpu_architecture        = upper(var.architecture)
    operating_system_family = "LINUX"
  }
  network_mode             = "awsvpc"
  memory                   = 512 # MB
  cpu                      = 256 # /1024 vCPU
  task_role_arn            = aws_iam_role.ec2_role.arn
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  requires_compatibilities = ["FARGATE"]

  container_definitions = jsonencode([
    {
      name      = var.project,
      image     = "${aws_ecr_repository.container.repository_url}:latest"
      essential = true,
      environment = [
        {
          Name  = "POP3_HOST"
          Value = "0.0.0.0"
        },
        {
          Name  = "POP3_PORT"
          Value = tostring(var.port)
        },
        {
          Name  = "POP3_VERBOSE"
          Value = "false"
        },
        {
          Name  = "POP3_LAMBDA_INVOKE_FUNCTION"
          Value = aws_lambda_function.auth_proxy.function_name
        },
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.container.id,
          awslogs-region        = data.aws_region.current.name,
          awslogs-stream-prefix = var.project,
        },
      },
      portMappings = [
        { "containerPort" : var.port, "hostPort" : var.port },
      ],
      networkMode = "awsvpc",
      memory      = 512, # MB
      cpu         = 256, # /1024 vCPU
    }
  ])
}

resource "aws_ecs_service" "container" {
  name                 = var.project
  cluster              = aws_ecs_cluster.container.arn
  task_definition      = aws_ecs_task_definition.container.arn
  scheduling_strategy  = "REPLICA"
  force_new_deployment = true
  desired_count        = 1

  launch_type = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.my_security_group.id]
    subnets          = [for sn in aws_subnet.my_subnet : sn.id]
    assign_public_ip = true
  }
}

resource "aws_ecr_repository" "container" {
  name = var.project
}

resource "aws_ecr_repository_policy" "container" {
  repository = aws_ecr_repository.container.name
  policy     = data.aws_iam_policy_document.container_repository.json
}

data "aws_iam_policy_document" "container_repository" {
  statement {
    actions = ["ecr:*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "null_resource" "container" {
  triggers = {
    change_counter = 1
  }
  provisioner "local-exec" {
    command     = <<EOF
      ( cd ../.. ; docker buildx build --platform=linux/${var.architecture} . -t ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.${data.aws_partition.current.dns_suffix}/${var.project}:latest )
      aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.${data.aws_partition.current.dns_suffix}
      docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.${data.aws_partition.current.dns_suffix}/${var.project}:latest
    EOF
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [aws_ecr_repository_policy.container]
}
