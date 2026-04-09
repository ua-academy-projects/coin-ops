provider "aws" {
  region = var.region

}
resource "aws_instance" "my_server" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.my_sg.id]

  tags = {
    Name  = "my_aws_server"
    Ovner = "Valik"
  }
}

resource "aws_security_group" "my_sg" {
  name = "my_security-group"

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


