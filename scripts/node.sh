#!/bin/bash
#
# Setup for Node servers

set -euxo pipefail

config_path="/vagrant/configs"

/bin/bash $config_path/join.sh -v

sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp -i $config_path/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
NODENAME=$(hostname -s)
kubectl label node $(hostname -s) node-role.kubernetes.io/worker=worker --overwrite
EOF

# Setup NFS client
sudo apt install nfs-common -y
mkdir /home/vagrant/k8s_persistent_vol/
echo 'master-node:/var/nfs/k8s_persistent_volumes /home/vagrant/k8s_persistent_vol/ nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0' | sudo tee -a /etc/fstab
sudo mount /home/vagrant/k8s_persistent_vol/