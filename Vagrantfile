
require "yaml"
settings = YAML.load_file "settings.yaml"

IP_SECTIONS = settings["network"]["control_ip"].match(/^([0-9.]+\.)([^.]+)$/)
# First 3 octets including the trailing dot:
IP_NW = IP_SECTIONS.captures[0]
# Last octet excluding all dots:
IP_START = Integer(IP_SECTIONS.captures[1])
NUM_WORKER_NODES = settings["nodes"]["workers"]["count"]

Vagrant.configure("2") do |config|
  config.vm.provision "shell", env: { "IP_NW" => IP_NW, "IP_START" => IP_START, "NUM_WORKER_NODES" => NUM_WORKER_NODES }, inline: <<-SHELL
      # apt-get update -y
      echo "$IP_NW$((IP_START)) master-node" >> /etc/hosts
      for i in `seq 1 ${NUM_WORKER_NODES}`; do
        echo "$IP_NW$((IP_START+i)) worker-node0${i}" >> /etc/hosts
      done
  SHELL

  if `uname -m`.strip == "aarch64"
    config.vm.box = settings["software"]["box"] + "-arm64"
  else
    config.vm.box = settings["software"]["box"]
  end
  config.vm.box_check_update = true

  config.vm.define "master" do |master|
    master.vm.hostname = "master-node"
    master.vm.network "private_network", ip: settings["network"]["control_ip"]
    master.vm.network "forwarded_port", guest: 22, host: 2220, id: "ssh"

    if settings["shared_folders"]
      settings["shared_folders"].each do |shared_folder|
        master.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
      end
    end
    master.vm.provider "virtualbox" do |vb|
        vb.cpus = settings["nodes"]["control"]["cpu"]
        vb.memory = settings["nodes"]["control"]["memory"]
        if settings["cluster_name"] and settings["cluster_name"] != ""
          vb.customize ["modifyvm", :id, "--groups", ("/" + settings["cluster_name"])]
        end
        if settings["host_os"] == "windows"
          vb.gui = true # Vagrant does not work in headless mode in Windows 10 and 11 host
        end
    end
    master.vm.provision "shell",
      env: {
        "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
        "ENVIRONMENT" => settings["environment"],
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
        "UBUNTU_VERSION" => settings["software"]["box"],
        "RUNTIME" => settings["runtime"],
        "HELM_VERSION" => settings["software"]["helm"]
      },
      path: "scripts/common.sh"
    master.vm.provision "shell",
      env: {
        "CALICO_VERSION" => settings["software"]["calico"],
        "CONTROL_IP" => settings["network"]["control_ip"],
        "POD_CIDR" => settings["network"]["pod_cidr"],
        "SERVICE_CIDR" => settings["network"]["service_cidr"],
        "INGRESS_NGINX_VERSION" => settings["software"]["ingress_nginx"],
        "NFS_DRIVER_VERSION" => settings["software"]["csi_driver_nfs"]
      },
      path: "scripts/master.sh"
  end

  (1..NUM_WORKER_NODES).each do |i|

    config.vm.define "node0#{i}" do |node|
      node.vm.hostname = "worker-node0#{i}"
      node.vm.network "private_network", ip: IP_NW + "#{IP_START + i}"
      node.vm.network "forwarded_port", guest: 22, host: "222#{i}", id: "ssh"
      if settings["shared_folders"]
        settings["shared_folders"].each do |shared_folder|
          node.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
        end
      end
      node.vm.provider "virtualbox" do |vb|
          vb.cpus = settings["nodes"]["workers"]["cpu"]
          vb.memory = settings["nodes"]["workers"]["memory"]
          if settings["cluster_name"] and settings["cluster_name"] != ""
            vb.customize ["modifyvm", :id, "--groups", ("/" + settings["cluster_name"])]
          end
          if settings["host_os"] == "windows"
            vb.gui = true # Vagrant does not work in headless mode in Windows 10 and 11 host
          end
      end
      node.vm.provision "shell",
        env: {
          "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
          "ENVIRONMENT" => settings["environment"],
          "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
          "UBUNTU_VERSION" => settings["software"]["box"],
          "RUNTIME" => settings["runtime"],
          "HELM_VERSION" => settings["software"]["helm"]
        },
        path: "scripts/common.sh"
      node.vm.provision "shell", env: {
        "NFS_DRIVER_VERSION" => settings["software"]["csi_driver_nfs"]
      }, path: "scripts/node.sh"

      # Only install the dashboard after provisioning the last worker (and when enabled).
      if i == NUM_WORKER_NODES and settings["software"]["dashboard"] and settings["software"]["dashboard"] != ""
        node.vm.provision "shell", path: "scripts/dashboard.sh"
      end
      if i == NUM_WORKER_NODES
        node.vm.provision "file", source: "./sample-app/sample-app-non-pvc.yaml", destination: "sample-app-non-pvc.yaml"
        node.vm.provision "file", source: "./sample-app/sample-app-ing.yaml", destination: "sample-app-ing.yaml"
        node.vm.provision "file", source: "./sample-app/sample-app-pvc.yaml", destination: "sample-app-pvc.yaml"
        node.vm.provision "shell", env: {
          "INGRESS_NGINX_VERSION" => settings["software"]["ingress_nginx"],
          "NFS_DRIVER_VERSION" => settings["software"]["csi_driver_nfs"],
          "MASTER_IP" => settings["network"]["control_ip"]
        }, 
        path: "scripts/post-provision.sh"
      end
    end
  end
end 
