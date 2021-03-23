region = "eu-central-1" # Frankfurt

vpc_cidr = "10.0.0.0/16"

subnet = {
  cidr = "10.0.1.0/24"
  name = "subnet_1"
  az   = "eu-central-1a"
}


instances = [
  {
    private_ip = "10.0.1.51"
    az         = "eu-central-1a"
    name       = "ubuntu_1_clb"
  },
  {
    private_ip = "10.0.1.51"
    az         = "eu-central-1a"
    name       = "ubuntu_2_clb"
  }
]
