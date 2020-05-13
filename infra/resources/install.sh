#!/usr/bin/env bash

set -eEuo pipefail

export PATH=$PATH:/snap/bin
#export DEBIAN_FRONTEND=noninteractive
# sudo -E apt update -y
# sudo -E apt install -y python3-pip docker.io

sudo -E yum install -y python3-pip git curl vim

# ensure docker is absent before installing it from convinient script
sudo -E yum remove -y docker \
     docker-client \
     docker-client-latest \
     docker-common \
     docker-latest \
     docker-latest-logrotate \
     docker-logrotate \
     docker-engine || echo ok

# issue on centos: manual install containerd first
sudo yum install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm
curl -fsSL "https://get.docker.com" -o /tmp/get-docker.sh
sudo sh /tmp/get-docker.sh
sudo systemctl start docker

sudo -E yum install -y python3-pip git curl
sudo -E pip3 install python-openstackclient python-ironicclient
sudo usermod -aG docker $USER

microk8s status --wait-ready
microk8s enable rbac
microk8s enable dns
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv ./kustomize /usr/local/bin


if [[ ! -d $HOME/ironic-image ]]; then
	  (cd $HOME && git clone -b ovh/train https://github.com/yanndegat/ironic-image/)
    (cd $HOME/ironic-image && docker build -t ironic-base:latest -f Dockerfile.base .)
    (cd $HOME/ironic-image && docker build -t ovh-ironic:local -f Dockerfile .)
    docker save ovh-ironic:local > /tmp/myimage.tar && microk8s ctr image import /tmp/myimage.tar
fi


if [[ ! -d $HOME/ironic ]]; then
	  (cd $HOME && git clone https://github.com/yanndegat/ironic/)
    (cd $HOME/ironic/ && git checkout ovh/train)
fi

if [[ ! -d $HOME/baremetal-operator ]]; then
	  (cd $HOME && git clone https://github.com/yanndegat/baremetal-operator/)
    (cd $HOME/baremetal-operator && docker build -f build/Dockerfile -t ovh-bmo:local .)
    docker save ovh-bmo:local > /tmp/myimage.tar && microk8s ctr image import /tmp/myimage.tar
    cp -f $HOME/resources/ironic_bmo_configmap.env $HOME/baremetal-operator/deploy/ovh/
fi

sudo mkdir -p "$HOME/shared/html/images"
(cd "$HOME/shared/html/images" && sudo curl -LO https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img)

cat >> $HOME/.bash_history <<EOF
docker build -t ovh-ironic:local -f Dockerfile .
docker save ovh-ironic:local > /tmp/myimage.tar && microk8s ctr image import /tmp/myimage.tar
microk8s kubectl -n metal3 delete baremetalhost  node-0
kustomize build ~/baremetal-operator/deploy/ovh/ | microk8s kubectl delete -f -
kustomize build ~/baremetal-operator/deploy/ovh/ | microk8s kubectl apply -f -
microk8s kubectl -n metal3 edit baremetalhost  node-0
microk8s kubectl -n metal3 logs deployment/metal3-baremetal-operator -c ironic-conductor -f
cat ~/bm0.yml | microk8s kubectl apply -f -
cat ~/resources/ns3171929.ip-51-195-6.eu.yaml | microk8s kubectl apply -f -
microk8s kubectl -n metal3 logs deployment/metal3-baremetal-operator -c ironic-conductor -f
microk8s kubectl -n metal3 delete baremetalhost  node-0
git fetch origin && git reset --hard origin/ovh/train
watch microk8s kubectl -n metal3 get pods
microk8s kubectl -n metal3 exec -it deployment/metal3-baremetal-operator -c ironic-conductor -- bash
OS_CLOUD=metal3 openstack baremetal node list
EOF

