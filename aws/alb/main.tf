terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

variable "credentials" {
  type = object({
    access_key = string
    secret_key = string
  })
}

variable "keypair" {
  type = string
}

variable "region" {
  type = string
}

# Configure the AWS Provider
provider "aws" {
  region     = var.region
  access_key = var.credentials.access_key
  secret_key = var.credentials.secret_key
}

variable "vpc_cidr" {
  type = string
}

resource "aws_vpc" "vpc1" {
  cidr_block = var.vpc_cidr
  tags = {
    "Name" = "vpc_1"
  }
}

resource "aws_internet_gateway" "gw1" {
  vpc_id = aws_vpc.vpc1.id
  tags = {
    Name = "gw_1"
  }
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw1.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw1.id
  }

  tags = {
    Name = "route_table_1"
  }
}

variable "subnets" {
  type = list(object({
    cidr = string
    name = string
    az   = string
  }))
}

resource "aws_subnet" "subnets" {
  for_each          = { for i, val in var.subnets : i => val }
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags = {
    "Name" = each.value.name
  }
}

resource "aws_route_table_association" "a" {
  for_each       = { for i, val in var.subnets : i => val }
  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.r.id
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg_1"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb1" {
  name            = "terraform-alb1"
  subnets         = [for subnet in aws_subnet.subnets : subnet.id]
  security_groups = [aws_security_group.alb_sg.id]

  tags = {
    Name = "terraform-alb1"
  }
}

output "alb1_dns" {
  value = aws_lb.alb1.dns_name
}

resource "aws_lb_target_group" "web_tg" {
  name     = "tf-example-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc1.id

  health_check {
    interval            = 5
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    timeout             = 2
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.alb1.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_security_group" "web" {
  name        = "alb_ec2_sg_1"
  description = "Allow inbound traffic from alb1"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description     = "HTTP"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "sg_1"
  }
}

variable "instances" {
  type = list(object({
    private_ip = string
    name       = string
    az         = string
  }))
}

resource "aws_network_interface" "nic" {
  for_each        = { for i, val in var.instances : i => val }
  subnet_id       = aws_subnet.subnets[each.key].id
  private_ips     = [each.value.private_ip]
  security_groups = [aws_security_group.web.id]

}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "project1_ec2" {
  for_each          = { for i, val in var.instances : i => val }
  ami               = data.aws_ami.ubuntu.id
  instance_type     = "t2.micro"
  availability_zone = each.value.az
  key_name          = var.keypair

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.nic[each.key].id
  }

  user_data = <<-EOF
    #!/bin/bash
    apt update -y
    apt -y install nginx
    systemctl start nginx
    echo "Hello World from $(hostname -f)" > /var/www/html/index.html
  EOF

  tags = {
    Name = each.value.name
  }
}

resource "aws_lb_target_group_attachment" "test" {
  for_each         = aws_instance.project1_ec2
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = each.value.id
  port             = 80
}

# Elastic IP for debug
resource "aws_eip" "eip" {
  for_each          = { for i, val in var.instances : i => val }
  network_interface = aws_network_interface.nic[each.key].id
}
