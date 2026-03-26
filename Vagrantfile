Vagrant.configure("2") do |config|
    config.vm.box = "bento/ubuntu-24.04"

    config.vm.define "devops-flask" do |flask|
        flask.vm.hostname = "devops-flask"
        flask.vm.network "private_network", ip: "192.168.56.11"
        flask.vm.network "forwarded_port", guest: 22, host: 2222

        flask.vm.provider "virtualbox" do |vb|
            vb.name = "devops-flask"
            vb.memory = "512"   
            vb.cpus = 2
        end 
    end

    config.vm.define "ansible" do |ansible|
        ansible.vm.hostname = "devops-ansible"
        ansible.vm.network "private_network", ip: "192.168.56.12"
        ansible.vm.network "forwarded_port", guest: 22, host: 2223

        ansible.vm.provider "virtualbox" do |vb|
            vb.name = "devops-ansible"
            vb.memory = 2048
            vb.cpus = 2
         end
    end

    
    config.vm.define "devops-rabbitmq" do |rabbit|
        rabbit.vm.hostname = "devops-rabbitmq"
        rabbit.vm.network "private_network", ip: "192.168.56.13"
        rabbit.vm.network "forwarded_port", guest: 22, host: 2224

        rabbit.vm.provider "virtualbox" do |vb|
        vb.name = "devops-rabbitmq"
        vb.memory = 2048
        vb.cpus = 2

        end
    end


    config.vm.define "devops-postgres" do |db|
        db.vm.hostname = "devops-postgres"
        db.vm.network "private_network", ip: "192.168.56.14"
        db.vm.network "forwarded_port", guest: 22, host: 2225

        db.vm.provider "virtualbox" do |vb|
        vb.name = "devops-postgres"
        vb.memory = 2048
        vb.cpus = 2

        end
    end
end

