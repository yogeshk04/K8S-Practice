sudo -i

yum update -y

swapoff -a
# The Kubernetes scheduler determines the best available node on which to deploy newly created pods. If memory swapping is allowed to occur on a host system, this can lead ot performance and stability issues withn Kubernetes.

setenforce 0
# Disabling the SElinux makes all containers can easily access host filesystems

yum install docker -y

systemctl enable docker
systemctl start docker

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF


cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

yum install -y kubeadm-1.21.3 kubelet-1.21.3 kubectl-1.21.3 --disableexcludes=kubernetes


systemctl enable kubelet
systemctl start kubelet








****************************************************************************************************************************************************************************
********************************************
Only on Master Node
********************************************

# sudo kubeadm init --prod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=ALL

# sudo kubeadm init --apiserver-advertise-address=172.31.39.190 --pod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=NumCPU --ignore-preflight-errors=Mem

sudo kubeadm init --apiserver-advertise-address=172.31.2.202 --pod-network-cidr=192.168.0.0/16 --ignore-preflight-errors=NumCPU --ignore-preflight-errors=Mem


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


#export KUBECONFIG=/etc/kubernetes/kubelet.conf

sudo kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml

sudo kubectl apply -f https://docs.projectcalico.org/v3.8/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml

#kubectl get pods -all-namespaces

****************************************************************************************************************************************************************************

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
********************************************
Only on Worker Node
********************************************

kubeadm join 172.31.2.202:6443 --token 547jfa.po4mxuiddodu3aob \
        --discovery-token-ca-cert-hash sha256:9953297bd47826e07af7e088d6d7b97b4dd66a201b3e307cd78b5991043317a1


kubeadm join 172.31.2.202:6443 --token 547jfa.po4mxuiddodu3aob --discovery-token-ca-cert-hash sha256:9953297bd47826e07af7e088d6d7b97b4dd66a201b3e307cd78b5991043317a1
		
		
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
