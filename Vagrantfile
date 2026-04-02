Vagrant.configure("2") do |config|
  # Общие настройки для всех серверов
  config.ssh.insert_key = false

  # Сервер 1
  config.vm.define "db" do |server|
    server.vm.box = "bento/ubuntu-22.04"
    server.vm.hostname = "db"
    server.vm.network "private_network", ip: "192.168.56.11"
    server.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "/vagrant/ansible/install_postgres.yml"
    end
    server.vm.provider "virtualbox" do |vb|
      vb.name = "db"
      vb.memory = 1024
      vb.cpus = 1
    end
  end

  # Сервер 2
  config.vm.define "webserver" do |server|
    server.vm.box = "bento/ubuntu-22.04"
    server.vm.hostname = "webserver"
    server.vm.network "private_network", ip: "192.168.56.12"
    server.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "/vagrant/ansible/install_nginx.yml"
    end
    server.vm.provider "virtualbox" do |vb|
      vb.name = "webserver"
      vb.memory = 1024
      vb.cpus = 1
    end
  end

  # Сервер 3
  config.vm.define "aplication" do |server|
    server.vm.box = "bento/ubuntu-22.04"
    server.vm.hostname = "aplication"
    server.vm.network "private_network", ip: "192.168.56.13"
    server.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "/vagrant/ansible/install_app.yml"
    end
     server.vm.provider "virtualbox" do |vb|
      vb.name = "aplication"
      vb.memory = 1024
      vb.cpus = 1
    end
  end
end
