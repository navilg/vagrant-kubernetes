#!/bin/bash
#
# Setup for Control Plane (Master) servers

set -euxo pipefail

NODENAME=$(hostname -s)

sudo kubeadm config images pull

echo "Preflight Check Passed: Downloaded All Required Images"

sudo kubeadm init --apiserver-advertise-address=$CONTROL_IP --apiserver-cert-extra-sans=$CONTROL_IP --pod-network-cidr=$POD_CIDR --service-cidr=$SERVICE_CIDR --node-name "$NODENAME" --ignore-preflight-errors Swap

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Save Configs to shared /Vagrant location

# For Vagrant re-runs, check if there is existing configs in the location and delete it for saving new configuration.

config_path="/vagrant/configs"

if [ -d $config_path ]; then
  rm -f $config_path/*
else
  mkdir -p $config_path
fi

cp -i /etc/kubernetes/admin.conf $config_path/config
touch $config_path/join.sh
chmod +x $config_path/join.sh

kubeadm token create --print-join-command > $config_path/join.sh

sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp -i $config_path/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
sudo chmod 700 /home/vagrant/.kube/config
EOF

helm repo add projectcalico https://docs.tigera.io/calico/charts
helm install calico projectcalico/tigera-operator --version v${CALICO_VERSION} --namespace tigera-operator --create-namespace

# Install Metrics Server

kubectl apply -f https://raw.githubusercontent.com/techiescamp/kubeadm-scripts/main/manifests/metrics-server.yaml

if [ -n "$NFS_DRIVER_VERSION" ]; then
  # Setup NFS server
  sudo apt install nfs-kernel-server -y
  mkdir -p /var/nfs/k8s_pvs
  sudo chown nobody:nogroup /var/nfs/k8s_pvs
  sudo chmod 777 /var/nfs/k8s_pvs
  echo '/var/nfs/k8s_pvs worker-node0*(rw,sync,no_root_squash,no_subtree_check) master-node(rw,sync,no_root_squash,no_subtree_check)' | sudo tee -a /etc/exports
  sudo systemctl restart nfs-kernel-server

  # Mount NFS on client
  sleep 3
  mkdir /home/vagrant/k8s_pvs
  echo 'master-node:/var/nfs/k8s_pvs /home/vagrant/k8s_pvs/ nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0' | sudo tee -a /etc/fstab
  sudo mount /home/vagrant/k8s_pvs/
fi

if [ -n "$INGRESS_NGINX_VERSION" ]; then
  # Setup Loadbalancer on master noode which will reverse proxy traffic to ingress controller.

  sudo apt install nginx -y
  sudo systemctl enable nginx
  cat > /etc/nginx/conf.d/loadbalancer.conf <<EOF
  server {
    listen 80; 

    location / {
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_pass http://localhost:30080;
    }
  }
EOF
  rm -f /etc/nginx/sites-enabled/default
  sudo nginx -s reload
fi