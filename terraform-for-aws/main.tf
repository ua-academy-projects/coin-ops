# Create Network Resources
resource "aws_vpc" "vpc" {
  cidr_block = "10.10.0.0/16"
  tags       = {
    Name = "my-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "my-igw"
  }
}

resource "aws_subnet" "internal_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "${var.region}a"

  tags              = {
    Name = "internal-subnet"
  }
  
}

resource "aws_subnet" "external_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags                    = {
      Name = "external-subnet"
  }
  
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.external_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for Jump Host
resource "aws_security_group" "jump_host_sg" {
  name        = "jump-host-sg"
  description = "Allow SSH access to jumphost"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH access from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jump-host-sg"
  }
}

# Security Group for internal resources
resource "aws_security_group" "internal_sg" {
  name        = "internal-sg"
  description = "Allow traffic from jump host to internal resources"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "Allow SSH from jump host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jump_host_sg.id]
  }
  
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "internal-sg"
  }
}

# Search for the latest Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Create SSH Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "terraform-aws-key"
  public_key = file("~/.ssh/aws_ec2_key.pub")
}

# Create Jump Host in the external subnet
resource "aws_instance" "jump_host" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"

  subnet_id              = aws_subnet.external_subnet.id
  vpc_security_group_ids = [aws_security_group.jump_host_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  tags                   = {
    Name = "jump-host"
  }
}

# Create an internal instance in the internal subnet
resource "aws_instance" "internal_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"

  subnet_id              = aws_subnet.internal_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  tags             = {
    Name = "internal-instance"
  }
}