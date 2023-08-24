#!/usr/bin/sh
set -x
while getopts v:t:h:r: flag
do
    case "${flag}" in
        v) k8s_version=${OPTARG};;       
        t) authtoken=${OPTARG};;
        h) hostname=${OPTARG};;
        r) role=${OPTARG};;
    esac
done


install_basics() {
    sudo dnf update --disablerepo=* --enablerepo='*microsoft*' -y
}

main(){
  apt-get update
  apt-get install -y apt-transport-https curl
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y docker.io kubeadm=${k8s_version}-00 kubelet=${k8s_version}-00 kubectl=${k8s_version}-00 --allow-downgrades

  mkdir -p /etc/containerd
  containerd config default >/etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl restart containerd
}

install_master(){
  echo "## Running Master Installer ##"
  kubeadm init --token "${authtoken}" --token-ttl 15m 
  export kubehome=/home/$SUDO_USER/.kube
  mkdir -p $kubehome && cp /etc/kubernetes/admin.conf $kubehome/config
  chown -R $SUDO_UID:$SUDO_UID $kubehome
  kubectl config set-cluster kubernetes --server https://${hostname}:6443
  sudo -u $SUDO_USER kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
}

install_worker(){
  echo "## Running Worker Installer ##"
  sleep 30
  kubeadm join ${hostname}:6443 --token "${authtoken}" --discovery-token-unsafe-skip-ca-verification
}

install_basics
main
if [ "$role" = "master" ]; then
  install_master
else
  install_worker
fi