# Define the VPC and subnet
resource "aws_vpc" "my_vpc" {
  tags = {
    Name = var.project
  }
  cidr_block = "10.0.0.0/16"
}

data "aws_availability_zones" "current" {}

resource "aws_subnet" "my_subnet" {
  count = length(data.aws_availability_zones.current.names)

  tags = {
    Name = "${var.project}-${data.aws_availability_zones.current.names[count.index]}"
  }
  availability_zone = data.aws_availability_zones.current.names[count.index]
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
}

resource "aws_route_table_association" "my_subnet" {
  count = length(data.aws_availability_zones.current.names)

  subnet_id      = aws_subnet.my_subnet[count.index].id
  route_table_id = aws_route_table.my_route_table.id
}

# Define the security group
resource "aws_security_group" "my_security_group" {
  name        = var.project
  description = "Security group for ${var.project}"
  vpc_id      = aws_vpc.my_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "my_gateway" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = var.project,
  }
}

resource "aws_route" "my_gateway" {
  route_table_id         = aws_route_table.my_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_gateway.id
}
