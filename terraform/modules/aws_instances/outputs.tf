output "instance_ips" {
  value = {
    for name, vm in aws_instance.vm : name => {
      private_ip = vm.private_ip
      public_ip  = vm.public_ip
    }
  }
}
