#!/usr/bin/env bash
#
# Setup post provisioning

export KUBECONFIG=/vagrant/configs/config

# Install Ingress Nginx

echo "Installing Nginx Ingress controller"
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
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace -f custom-ingress-value.yaml --version $INGRESS_NGINX_VERSION
rm -f custom-ingress-value.yaml

kubectl -n ingress-nginx wait --for=condition=Ready pods -l app.kubernetes.io/name=ingress-nginx --timeout=60s


# Install nfs-provisioner

echo "Installing CSI Driver for NFS"
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set externalSnapshotter.enabled=true \
  --version $NFS_DRIVER_VERSION

kubectl -n kube-system wait --for=condition=Ready pods -l app.kubernetes.io/instance=csi-driver-nfs --timeout=60s

# Deploy storageclasss and volumesnapshotclass

echo "Deploying storage class"
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

echo "Deploying volume snapshot class"
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: nfs-csi
  # labels:
  #   velero.io/csi-volumesnapshot-class: "true"
driver: nfs.csi.k8s.io
parameters:
  server: master-node
  share: /var/nfs/k8s_pvs
deletionPolicy: Delete
EOF

kubectl apply -f /home/vagrant/sample-app.yaml

echo
echo "Spinup completed."
echo "You can access sample application on your browser at 'http://$MASTER_IP/sampleapp'"
echo