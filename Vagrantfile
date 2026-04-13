Vagrant.configure("2") do |config|
    config.vm.box = "bento/ubuntu-24.04"

    config.vm.define "devops-ui" do |ui|
        ui.vm.hostname = "devops-ui"
        ui.vm.network "private_network", ip: "192.168.56.11"
        ui.vm.network "forwarded_port", guest: 22, host: 2222

        ui.vm.provider "virtualbox" do |vb|
            vb.name = "devops-ui"
            vb.memory = 1024
            vb.cpus = 2
        end 
    end

    config.vm.define "devops-proxy" do |proxy|
        proxy.vm.hostname = "devops-proxy"
        proxy.vm.network "private_network", ip: "192.168.56.12"
        proxy.vm.network "forwarded_port", guest: 22, host: 2223


        proxy.vm.provider "virtualbox" do |vb|
            vb.name = "devops-proxy"
            vb.memory = 1024
            vb.cpus = 2
         end
    end


    config.vm.define "devops-history" do |history|
        history.vm.hostname = "devops-history"
        history.vm.network "private_network", ip: "192.168.56.13"
        history.vm.network "forwarded_port", guest: 22, host: 2224

        history.vm.provider "virtualbox" do |vb|
            vb.name = "devops-history"
            vb.memory = 1024
            vb.cpus = 2

        end
    end

    config.vm.define "devops-data" do |data|
        data.vm.hostname = "devops-data"
        data.vm.network "private_network", ip: "192.168.56.14"
        data.vm.network "forwarded_port", guest: 22, host: 2225

        data.vm.provider "virtualbox" do |vb|
            vb.name = "devops-data"
            vb.memory = 1024
            vb.cpus = 2
    
        end
    end

end