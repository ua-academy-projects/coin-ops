output "instance_ips" {
  value = {
    for name, vm in google_compute_instance.vm : name => {
      private_ip = vm.network_interface[0].network_ip
      public_ip  = try(vm.network_interface[0].access_config[0].nat_ip, null)
    }
  }
}
