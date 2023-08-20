#!/usr/bin/env bash
#
# Setup post provisioning

export KUBECONFIG=/vagrant/configs/config

# Install Ingress Nginx

cat <<EOF > custom-ingress-value.yaml
controller:
  service:
    nodePorts:
      http: 30080
      https: 30443
    type: NodePort
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    effect: NoSchedule
  nodeSelector:
    kubernetes.io/os: linux
    kubernetes.io/hostname: master-node
EOF

echo "Install Ingress Nginx"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace -f custom-ingress-value.yaml
rm -f custom-ingress-value.yaml

# Install nfs-provisioner

helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system --version v4.2.0
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs.csi.k8s.io
parameters:
  server: master-node
  share: /var/nfs/k8s_pvs
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
mountOptions:
  - nfsvers=4.1
EOF