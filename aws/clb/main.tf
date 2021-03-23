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

variable "subnet" {
  type = object({
    cidr = string
    name = string
    az   = string
  })
}

resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = var.subnet.cidr
  availability_zone = var.subnet.az
  tags = {
    "Name" = var.subnet.name
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.r.id
}

resource "aws_security_group" "clb_sg" {
  name        = "clb_sg_1"
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

resource "aws_elb" "clb1" {
  name            = "terraform-clb1"
  subnets         = [aws_subnet.subnet1.id]
  security_groups = [aws_security_group.clb_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "terraform-clb1"
  }
}

output "clb1_dns" {
  value = aws_elb.clb1.dns_name
}

resource "aws_security_group" "web" {
  name        = "clb_ec2_sg_1"
  description = "Allow inbound traffic from clb1"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description     = "HTTP"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_elb.clb1.source_security_group_id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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

variable "instances" {
  type = object({
    private_ip = string
    az         = string
    name       = string
  })
}

resource "aws_network_interface" "nic" {
  for_each        = { for i, val in var.instances : i => val }
  subnet_id       = aws_subnet.subnet1.id
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

resource "aws_elb_attachment" "elb_attach" {
  for_each = aws_instance.project1_ec2
  elb      = aws_elb.clb1.id
  instance = each.value.id
}

# Elastic IP for debug
resource "aws_eip" "eip" {
  for_each          = { for i, val in var.instances : i => val }
  network_interface = aws_network_interface.nic[each.key].id
}
