NUM_VMS = 4
IP_NTW = "10.10.1."
IP_START = 1

Vagrant.configure("2") do |config|
  config.vm.box = "defanator/ubuntu-24.04"
  config.vm.box_version = "24.04.3-20251227.1"

  (1..NUM_VMS).each do |i|
    config.vm.define "vm#{i}" do |node|
      node.vm.provider "vmware" do |v|
        v.vmx["memsize"] = "2048"
        v.vmx["numvcpus"] = "2"
      end

      node.vm.hostname = "vm#{i}"
      node.vm.network "private_network", ip: IP_NTW + "#{IP_START + i}"
      node.vm.network "forwarded_port", guest: 22, host: "#{2200 + i}", id: "ssh", auto_correct: true

      node.vm.provision "shell", name: "base-setup", keep_color: true, preserve_order: true, path: "infra/base_setup.sh"

      case i
      when 1
        node.vm.provision "shell", name: "vm1-setup", keep_color: true, preserve_order: true, path: "infra/vm1_setup.sh"
      when 2
        node.vm.provision "shell", name: "vm2-setup", keep_color: true, preserve_order: true, path: "infra/vm2_setup.sh"
      when 3
        node.vm.provision "shell", name: "vm3-setup", keep_color: true, preserve_order: true, path: "infra/vm3_setup.sh"
      when 4
        node.vm.provision "shell", name: "vm4-setup", keep_color: true, preserve_order: true, path: "infra/vm4_setup.sh"
      end
    end
  end
end

# config.vm.base_address (string) - The IP address to be assigned to the default NAT interface on the guest. Support for this option is provider dependent.

# config.vm.hostname (string) - The hostname the machine should have. Defaults to nil. If nil, Vagrant will not manage the hostname.
# If set to a string, the hostname will be set on boot. If set, Vagrant will update /etc/hosts on the guest with the configured hostname.

# config.vm.network - Configures networks on the machine. Please see the networking page for more information.
# config.vm.network "public_network", bridge: "Intel(R) 82579LM Gigabit Network Connection"