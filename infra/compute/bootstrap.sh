#!/bin/bash
set -euo pipefail

# increase limit for open files
cat >> /etc/sysctl.d/99-k3d.conf <<EOF
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 1048576
EOF
sysctl --system

# install docker
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

# install k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# install and setup kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
ln -sf /usr/local/bin/kubectl /usr/local/bin/k
rm kubectl

# wait for nodes 
wait_for_nodes() {
  local expected=$1
  local timeout=180
  local elapsed=0
  until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ')" -ge "$expected" ]; do
    sleep 5
    elapsed=$((elapsed + 5))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "Timed out waiting for $expected ready nodes"
      exit 1
    fi
  done
}

# set home
export HOME=/root

# create the server (control plane)
k3d cluster create openbao-platform --servers 3 --agents 0 -p "443:443@loadbalancer" --wait
wait_for_nodes 3

# create db agents (database workers)
k3d node create db --cluster openbao-platform --role agent --replicas 3 --wait
wait_for_nodes 6

# create the app agents (app worker)
k3d node create app --cluster openbao-platform --role agent --replicas 5 --wait
wait_for_nodes 11

# set proper labels for the worker nodes
kubectl label node k3d-db-0 k3d-db-1 k3d-db-2 node-role.kubernetes.io/database=
kubectl label node k3d-app-0 k3d-app-1 k3d-app-2 k3d-app-3 k3d-app-4 node-role.kubernetes.io/worker=

# taint the nodes
kubectl taint node k3d-openbao-platform-server-0 k3d-openbao-platform-server-1 k3d-openbao-platform-server-2 \
  node-role.kubernetes.io/control-plane=:NoSchedule
kubectl taint node k3d-db-0 k3d-db-1 k3d-db-2 workload=database:NoSchedule

# install and setup flux
curl -s https://fluxcd.io/install.sh | bash

export GITHUB_TOKEN="${github_token}"
flux bootstrap github \
  --owner=yawnartey \
  --repository=ikim-devops-coding-challenge \
  --branch=main \
  --path=clusters/openbao-platform \
  --personal