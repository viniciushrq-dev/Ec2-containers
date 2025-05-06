provider "aws" {
  region = "sa-east-1"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "meu-vpc"
  cidr = "10.0.0.0/16"

  azs = ["sa-east-1a", "sa-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = false
  enable_dns_hostnames = true
}

module "security_groups" {
  source = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  name        = "meu-sg"
  description = "SG para EC2 e RDS"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port = 80
      to_port = 80
      protocol = "tcp"
    cidr_blocks = "0.0.0.0/0"
    }
  ]
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

resource "aws_instance" "app_server" {
  ami =  "ami-093ebc571ac829cca"# AMI válida para Amazon Linux 2 em sa-east-1
  instance_type     = "t3.micro"
  subnet_id         = module.vpc.public_subnets[0]
  vpc_security_group_ids = [module.security_groups.security_group_id]

  associate_public_ip_address = true

  tags = {
    Name = "Servidor-API"
  }
}

resource "aws_db_instance" "meu_banco" {
  allocated_storage = 20
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  username          = "meuadmin" # Alterado para evitar erro de nome reservado
  password          = "senha1234"
  parameter_group_name = "default.postgres15"

  vpc_security_group_ids = [module.security_groups.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet.id

  skip_final_snapshot = true
}

resource "aws_db_subnet_group" "rds_subnet" {
  name = "rds-subnet"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "RDS subnet group"
  }
}

variable "region" {
  default = "sa-east-1"
}

output "ec2_public_ip" {
  value = aws_instance.app_server.public_ip
}

resource "aws_ecr_repository" "nginx_repo" {
  name = "nginx-container"
  
}

resource "aws_ecs_cluster" "meu_cluster" {
  name = "meu-cluster"  
}

resource "aws_ecs_task_definition" "nginx_task" {
  family = "nginx-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = "256" # 0.25 vCPU
  memory = "512" # 512MB
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name = "nginx"
      image = "nginx:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol = "tcp"
        }
      ]
    }
  ])
  
}
resource "aws_ecs_service" "nginx_service" {
  name = "nginx-service"
  cluster = aws_ecs_cluster.meu_cluster.id
  task_definition = aws_ecs_task_definition.nginx_task.arn
  launch_type = "FARGATE"
  desired_count = 1

  network_configuration {
    subnets = module.vpc.public_subnets
    assign_public_ip = true
    security_groups = [module.security_groups.security_group_id]
  }
  depends_on = [ aws_iam_role_policy_attachment.ecs_task_execution_role_policy ]
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
          Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  
}