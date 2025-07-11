
# Provider configuration
provider "aws" {
  region = "us-west-1"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# VPC and Subnets
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "3-tier-vpc"
  }
}

# Public Subnets (Web   )
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = element(["us-west-1a", "us-west-1b"], count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# Private Subnets (App)
resource "aws_subnet" "private_app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 3}.0/24"
  availability_zone = element(["us-west-1a", "us-west-1b"], count.index)
  tags = {
    Name = "private-app-subnet-${count.index + 1}"
  }
}

# Private Subnets (DB )
resource "aws_subnet" "private_db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 5}.0/24"
  availability_zone = element(["us-west-1a", "us-west-1b"], count.index)
  tags = {
    Name = "private-db-subnet-${count.index + 1}"
  }
}

# Internet Gateway for Public Subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "3-tier-igw"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

# Associate Public Subnets with Route Table
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway for Private Subnets (Application Tier)
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name = "3-tier-nat"
  }
}

# Route Table for Private Subnets (Application Tier)
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "private-app-route-table"
  }
}

# Associate Private App Subnets with Route Table
resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# Security Group for Web Tier (Allow HTTP/HTTPS)
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow HTTP/HTTPS traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

# Security Group for Application Tier (Allow traffic from Web Tier)
resource "aws_security_group" "app" {
  name        = "app-sg"
  description = "Allow traffic from Web Tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for Database Tier (Allow traffic from Application Tier)
resource "aws_security_group" "db" {
  name        = "db-sg"
  description = "Allow traffic from Application Tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS Database (Database Tier)
resource "aws_db_subnet_group" "db" {
  name       = "db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id
}

resource "aws_db_instance" "prod_db" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0.35"      # Updated to a supported version
  instance_class         = "db.t3.micro" # Updated instance class
  db_name                = "mydb"
  username               = "admin"
  password               = "!password1234!" # Replace with a secure password
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  availability_zone      = "us-west-1a"
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
}

# EC2 Instance for Web Tier ( Web Server)
resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              echo "<html><body><h1>Welcome to My Web Server</h1></body></html>" > /var/www/html/index.html
              EOF
  tags = {
    Name = "web-server"
  }
}

# Output the Public IP of the Web Server
output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}
# Output AMI
output "ami_4prod" {
  description = "ID of AMI used for prod instance"
  value       = data.aws_ami.amazon_linux.id
}