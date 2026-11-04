terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}



#--------------------------------------modules-----------------------------------------------

module "vpc" {
  source   = "./modules/vpc"
  name     = "lesson"
  vpc_cidr = var.vpc_cidr
  az_count = var.az_count
}

#-------------------------------------moved--------------------------------------------------



moved {
  from = aws_vpc.main
  to   = module.vpc.aws_vpc.main
}

moved {
  from = aws_subnet.public
  to   = module.vpc.aws_subnet.public
}


moved {
  from = aws_subnet.private
  to   = module.vpc.aws_subnet.private
}

moved {
  from = aws_internet_gateway.main
  to   = module.vpc.aws_internet_gateway.main
}

moved {
  from = aws_route_table.public
  to   = module.vpc.aws_route_table.public
}
moved {
  from = aws_route_table_association.public
  to   = module.vpc.aws_route_table_association.public
}

moved {
  from = aws_route_table.private
  to   = module.vpc.aws_route_table.private
}

moved {
  from = aws_route_table_association.private
  to   = module.vpc.aws_route_table_association.private
}
