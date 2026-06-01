output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = {
    public_a = aws_subnet.subnets["public-a"].id
    public_b = aws_subnet.subnets["public-b"].id
  }
}

output "private_subnet_ids" {
  value = {
    private_a = aws_subnet.subnets["private-a"].id
    private_b = aws_subnet.subnets["private-b"].id
  }
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "cluster_private_ips" {
  value = {
    for name, instance in aws_instance.nodes : name => instance.private_ip
  }
}

output "load_balancer_dns_name" {
  value = aws_lb.ingress.dns_name
}

output "load_balancer_zone_id" {
  value = aws_lb.ingress.zone_id
}

output "ingress_http_nodeport" {
  value = var.ingress_http_nodeport
}

output "ingress_https_nodeport" {
  value = var.ingress_https_nodeport
}

output "headlamp_nodeport" {
  value = var.headlamp_nodeport
}

output "kubespray_inventory_ini" {
  value = <<-EOT
    [all]
    cp-1 ansible_host=${aws_instance.nodes["cp-1"].private_ip} ip=${aws_instance.nodes["cp-1"].private_ip} access_ip=${aws_instance.nodes["cp-1"].private_ip}
    cp-2 ansible_host=${aws_instance.nodes["cp-2"].private_ip} ip=${aws_instance.nodes["cp-2"].private_ip} access_ip=${aws_instance.nodes["cp-2"].private_ip}
    cp-3 ansible_host=${aws_instance.nodes["cp-3"].private_ip} ip=${aws_instance.nodes["cp-3"].private_ip} access_ip=${aws_instance.nodes["cp-3"].private_ip}

    [kube_control_plane]
    cp-1
    cp-2
    cp-3

    [etcd]
    cp-1
    cp-2
    cp-3

    [kube_node]
    cp-1
    cp-2
    cp-3

    [k8s_cluster:children]
    kube_control_plane
    kube_node

    [calico_rr]

    [all:vars]
    ansible_user=${var.ssh_user}
    ansible_ssh_private_key_file=~/.ssh/id_rsa
    ansible_ssh_common_args='-o ProxyJump=${var.ssh_user}@${aws_instance.bastion.public_ip}'
  EOT
}

output "kubespray_inventory_yaml" {
  value = yamlencode({
    all = {
      hosts = {
        cp-1 = {
          ansible_host = aws_instance.nodes["cp-1"].private_ip
          ip           = aws_instance.nodes["cp-1"].private_ip
          access_ip    = aws_instance.nodes["cp-1"].private_ip
        }
        cp-2 = {
          ansible_host = aws_instance.nodes["cp-2"].private_ip
          ip           = aws_instance.nodes["cp-2"].private_ip
          access_ip    = aws_instance.nodes["cp-2"].private_ip
        }
        cp-3 = {
          ansible_host = aws_instance.nodes["cp-3"].private_ip
          ip           = aws_instance.nodes["cp-3"].private_ip
          access_ip    = aws_instance.nodes["cp-3"].private_ip
        }
      }
      children = {
        kube_control_plane = {
          hosts = {
            cp-1 = {}
            cp-2 = {}
            cp-3 = {}
          }
        }
        etcd = {
          hosts = {
            cp-1 = {}
            cp-2 = {}
            cp-3 = {}
          }
        }
        kube_node = {
          hosts = {
            cp-1 = {}
            cp-2 = {}
            cp-3 = {}
          }
        }
        k8s_cluster = {
          children = {
            kube_control_plane = {}
            kube_node          = {}
          }
        }
        calico_rr = {
          hosts = {}
        }
      }
      vars = {
        ansible_user                 = var.ssh_user
        ansible_ssh_private_key_file = "~/.ssh/id_rsa"
        ansible_ssh_common_args      = "-o ProxyJump=${var.ssh_user}@${aws_instance.bastion.public_ip}"
      }
    }
  })
}

output "ingress_nginx_helm_command" {
  value = "helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.type=NodePort --set controller.service.nodePorts.http=${var.ingress_http_nodeport} --set controller.service.nodePorts.https=${var.ingress_https_nodeport}"
}

output "kubectl_tunnel_command" {
  value = "ssh -J ${var.ssh_user}@${aws_instance.bastion.public_ip} -i ~/.ssh/id_rsa -N -L 6443:127.0.0.1:6443 ${var.ssh_user}@${aws_instance.nodes["cp-1"].private_ip}"
}

output "headlamp_tunnel_command" {
  value = "ssh -i ~/.ssh/id_rsa -N -L 30082:${aws_instance.nodes["cp-1"].private_ip}:${var.headlamp_nodeport} ${var.ssh_user}@${aws_instance.bastion.public_ip}"
}
