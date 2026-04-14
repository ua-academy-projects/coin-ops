provider "aws" {
  region = var.region

}
resource "aws_instance" "db_server" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.my_sg.id]

  tags = {
    Name  = "db"
    Ovner = "Valik"
  }
}
resource "aws_instance" "web_server" {
  depends_on    = [aws_instance.db_server]
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.my_sg.id]

  tags = {
    Name  = "web"
    Ovner = "Valik"
  }
}
resource "aws_instance" "app_server" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.my_sg.id]

  tags = {
    Name  = "app"
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
  ingress {
    description = "SSH"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  ingress {
    description = "SSH"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  ingress {
    description = "SSH"
    from_port   = 5432
    to_port     = 5432
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

resource "local_file" "ansible_inventory" {
  content = <<EOT
[db]
${aws_instance.db_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/home/valentyn/key.aws/valik.pem

[webserver]
${aws_instance.web_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/home/valentyn/key.aws/valik.pem

[application]
${aws_instance.app_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=/home/valentyn/key.aws/valik.pem
  EOT

  filename = "../ansible/hosts-aws.ini"

}

resource "null_resource" "postgres" {
  depends_on = [
    aws_instance.db_server,
    aws_instance.app_server,
    aws_instance.web_server,
    aws_security_group.my_sg
  ]


  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ../ansible/hosts-aws.ini /home/valentyn/Project_coin/aws_app/ansible/install_postgres.yml --extra-vars rabbitmq_host=${aws_instance.app_server.public_ip}"


  }
}

resource "null_resource" "nginx" {
  depends_on = [
    aws_instance.db_server,
    aws_instance.app_server,
    aws_instance.web_server,
    aws_security_group.my_sg,
    null_resource.postgres,
    null_resource.app
  ]


  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ../ansible/hosts-aws.ini /home/valentyn/Project_coin/aws_app/ansible/install_nginx.yml --extra-vars postgres_host=${aws_instance.db_server.public_ip} --extra-vars public_ip=${aws_instance.web_server.public_ip}"


  }
}
resource "null_resource" "app" {
  depends_on = [
    aws_instance.db_server,
    aws_instance.app_server,
    aws_instance.web_server,
    aws_security_group.my_sg,
    null_resource.postgres
  ]


  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ../ansible/hosts-aws.ini /home/valentyn/Project_coin/aws_app/ansible/install_app.yml --extra-vars cloud=true  --extra-vars app_user=root"


  }
}


