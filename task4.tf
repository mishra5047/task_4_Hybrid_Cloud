provider "aws" {
  version = "~> 2.0"
  region  = "ap-south-1"
  profile = "default"
}

# Creating VPC 

resource "aws_vpc" "task_vpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "Task-4"
  }
}

# Creating Public Subnet 

resource "aws_subnet" "public_subnet" {
  depends_on = [ aws_vpc.task_vpc]
  
  vpc_id     = aws_vpc.task_vpc.id
  cidr_block = "192.168.3.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "public_subnet"
  }
}

# Creating Private Subnet

resource "aws_subnet" "private_subnet" {
  depends_on = [ aws_vpc.task_vpc]
  
  vpc_id     = aws_vpc.task_vpc.id
  cidr_block = "192.168.2.0/24"
  availability_zone = "ap-south-1b"
  
  tags = {
    Name = "private_subnet"
  }
}

# Creating Internet Gateway

resource "aws_internet_gateway" "task_ig" {
  depends_on = [ aws_vpc.task_vpc ]

  vpc_id = aws_vpc.task_vpc.id
  tags = {
    Name = "task_ig"
  }
}

# Routing Table for IG
resource "aws_route_table" "router" {
  
  depends_on = [ aws_internet_gateway.task_ig ]
  
  vpc_id = aws_vpc.task_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.task_ig.id
  }

  tags = {
      Name = "router_task"
  }
} 

resource "aws_route_table_association" "router-association" {
  
  depends_on = [ aws_route_table.router ]

  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.router.id
}

# Elastic IP for NAT Gateway

resource "aws_eip" "task_ip" {
  vpc      = true
  depends_on = [aws_internet_gateway.task_ig]
}

# Creating NAT Gateway

resource "aws_nat_gateway" "task_nat" {
  allocation_id = aws_eip.task_ip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "task NAT"
  }
}

# Routing Table for NAT Gateway

resource "aws_route_table" "nat_route" {
  depends_on = [aws_nat_gateway.task_nat]
  vpc_id = aws_vpc.task_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.task_nat.id
  }
  tags = {
    Name = "NAT_RouteTable"
  }
}

resource "aws_route_table_association" "NAT_assocation" {
  depends_on = [aws_subnet.private_subnet, aws_route_table.nat_route]
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.nat_route.id
}

# Security Group For MySQL

resource "aws_security_group" "MySQL_SG" {
  depends_on = [aws_security_group.Bastion_Host_SG]
  name        = "SG_MySQL"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.task_vpc.id

  ingress{
    description = "SSH"
    from_port = 22
    to_port = 22
    security_groups =[ aws_security_group.Bastion_Host_SG.id]
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MySQL redirection"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "MySQL_SG"
  }
}

# Creating Instance for MySQL 

resource "aws_instance" "MySQL" {
  depends_on = [aws_security_group.MySQL_SG, tls_private_key.task_key]
  ami           = "ami-04ca6b22ca88bdbea"
  instance_type = "t2.micro"
  key_name = "task_key"
  vpc_security_group_ids = [ aws_security_group.MySQL_SG.id ]
  subnet_id = aws_subnet.private_subnet.id
  user_data = <<-EOF
        #!/bin/bash
        
        sudo docker run -dit -p 8080:3306 --name mysql -e MYSQL_ROOT_PASSWORD=master -e MYSQL_DATABASE=Task-4-db -e MYSQL_USER=abhishek -e MYSQL_PASSWORD=redhat mysql:5.6
  EOF

  tags = {
    Name = "MySQL-OS"
  }
}

# Creating key
resource "tls_private_key" "task_key" {
  algorithm   = "RSA"
}

# Saving to local system 
resource "local_file" "save_key" {
    depends_on = [ tls_private_key.task_key]
    content   = tls_private_key.task_key.private_key_pem
    filename  = "task_key.pem"
}

# Sending public key to aws 
resource "aws_key_pair" "public_key" {
    depends_on = [local_file.save_key]
    key_name = "task_key"
    public_key = tls_private_key.task_key.public_key_openssh
}

# Creating Security Group for WordPress

resource "aws_security_group" "WP_SG" {
  depends_on = [aws_security_group.Bastion_Host_SG]
  name        = "WordPress_SG"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.task_vpc.id
  
  ingress{
    description = "SSH"
    from_port = 22
    to_port = 22
    security_groups =[ aws_security_group.Bastion_Host_SG.id]
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Http port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Http redirection"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "WordPress_SG"
  }
}

# Launching Instance for WordPress

resource "aws_instance" "WordPress" {
  depends_on = [tls_private_key.task_key, aws_security_group.WP_SG]
  ami           = "ami-04ca6b22ca88bdbea"
  instance_type = "t2.micro"
  associate_public_ip_address = true
  vpc_security_group_ids = [ aws_security_group.WP_SG.id ]
  subnet_id = aws_subnet.public_subnet.id
  key_name = "task_key"
  user_data = <<-EOF
        #!/bin/bash
        
        sudo docker run -dit -p 8000:80 --name wp wordpress:4.8-apache
  EOF

  tags = {
    Name = "WordPress-OS"
  }
}

# Creating bastion Host Security Group

resource "aws_security_group" "Bastion_Host_SG" {
  depends_on = [aws_vpc.task_vpc]
  name        = "Bastion-Host-SG"
  description = "SSH For Bastion Host"
  vpc_id      = aws_vpc.task_vpc.id


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


  tags = {
    Name = "Bastion-Host-SG"
  }
}

# Launching Bastion Host

resource "aws_instance" "Bastion_Host" {
ami = "ami-0732b62d310b80e97"
instance_type = "t2.micro"
associate_public_ip_address = true
key_name = "task_key"
availability_zone = "ap-south-1a"
subnet_id = aws_subnet.public_subnet.id
security_groups = [ aws_security_group.Bastion_Host_SG.id]


tags = {
Name = "Bastion-Host"
    }
}


output "Bastion-Host-public-ip" {
    value = aws_instance.Bastion_Host.public_ip
}