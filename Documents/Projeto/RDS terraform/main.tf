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
