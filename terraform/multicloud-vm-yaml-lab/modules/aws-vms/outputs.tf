output "instances" {
  value = {
    for name, vm in aws_instance.vm :
    name => {
      id         = vm.id
      private_ip = vm.private_ip
      public_ip  = vm.public_ip
    }
  }
}