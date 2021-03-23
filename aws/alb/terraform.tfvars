region = "eu-central-1" # Frankfurt

vpc_cidr = "10.0.0.0/16"

subnets = [
  {
    cidr = "10.0.1.0/24"
    name = "subnet_1"
    az   = "eu-central-1a"
  },
  {
    cidr = "10.0.2.0/24"
    name = "subnet_2"
    az   = "eu-central-1b"
  }
]

instances = [
  {
    private_ip = "10.0.1.51"
    az         = "eu-central-1a"
    name       = "ubuntu_1a_alb"
  },
  {
    private_ip = "10.0.2.51"
    az         = "eu-central-1b"
    name       = "ubuntu_1b_alb"
  }
]

