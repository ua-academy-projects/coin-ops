NUM_VMS = 5
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

      node.vm.synced_folder ".", "/vagrant"
      node.vm.synced_folder "services/", "/home/vagrant/shared_folder"

      node.vm.provision "ansible_local" do |ansible|
        ansible.playbook = "infra/playbook.yml"
        ansible.galaxy_role_file = "infra/requirements.yml"
        ansible.galaxy_command = "ansible-galaxy collection install -r %{role_file}"
      end
    end
  end
end