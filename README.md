
# RKE2 Rancher with CNI Cilium, Ingress Controller Traefik and Metallb for VIP


```
mkdir $HOME/.kube
sudo cp -i /etc/rancher/rke2/rke2.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
sudo ln -s /var/lib/rancher/rke2/data/v1*/bin/kubectl /usr/local/bin/kubectl
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
echo "alias k=kubectl" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo "complete -o default -F __start_kubectl k" >> ~/.bashrc
echo "export KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
```

### Helm

#### Install Helm
```
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```
#### Repos Helm
```
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo add rke2-charts https://rke2-charts.rancher.io
```

### MASTER-1
```
mkdir -p /etc/rancher/rke2/
cat << EOF >> /etc/rancher/rke2/config.yaml
node-name: master-1
token: RancherManagerTeste
write-kubeconfig-mode: 600
#disable-kube-proxy: true #DESABILITADO PARA PERMITIR SEGUIR A INSTALAÇÃO INICIAL, DEPOIS DESCOMENTE A LINHA
etcd-expose-metrics: true
cni:
- cilium
tls-san:
  - rke2-teste.sesp.mt.gov.br
  - 172.16.118.48 #VIP RANCHER
  - 172.16.118.49 #VIP KUBERNETES
ingress-controller: traefik
disable:
  - rke2-ingress-nginx
EOF
curl -sfL https://get.rke2.io | sh - && \
systemctl enable --now rke2-server.service
```

#### Observe a finalização da instalação:
```
kubectl get pod -A -w
kubectl get node
```
#### Descomente "disable-kube-proxy" e reinicie o rke2-server
```
sed -i 's/^#//' /etc/rancher/rke2/config.yaml && \
systemctl restart rke2-server
```
### Cilium

Após finalizado, editar /etc/rancher/rke2/config.yaml e descomentar 'disable-kube-proxy' e reiniciar o rke2-server.

Finalizado, aplique os ajustes de configuração no rke2-cilium. Pegue o values do rke2-cilium instalado:

helm get values rke2-cilium -n kube-system > cilium-values.yaml

Aplique no 'cilium-values.yaml', na ultima linha:
```
cat << EOF >> ~/cilium-values.yaml
cluster:
  id: 1
  name: cluster-teste
kubeProxyReplacement: true
encryption:
  enabled: true
  type: wireguard
l2announcements:
  enabled: true
externalIPs:
  enabled: true
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
EOF
```
#### Aplique as configurações:
```
helm upgrade rke2-cilium -n kube-system rke2-charts/rke2-cilium -f cilium-values.yaml
```
Verifique a instalação dos novos pods cilium. Finalizado, siga com o procedimento. Configurar o VIP do API do Kubernetes para seguir com a instalação dos Masters 2 e 3.

### METALLB as VIP

#### Install metallb
```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```
#### Configurar IP ADDRESS POOL dos VIPS
```
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: rancher-vip
  namespace: metallb-system
spec:
  addresses:
    - 172.16.118.48/32
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kubernetes-vip
  namespace: metallb-system
spec:
  addresses:
    - 172.16.118.49/32
  serviceAllocation:
    priority: 100
    namespaces:
      - default
EOF
```
#### ADVERTISEMENT DOS VIPS
```
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ippool-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - rancher-vip
  - kubernetes-vip
EOF
```
Após aplicados, configure SERVICE para o VIP do KUBERNETES-API
```
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-vip
  namespace: default
spec:
  ports:
  - name: rke2-api
    port: 9345
    protocol: TCP
    targetPort: 9345
  - name: k8s-api
    port: 6443
    protocol: TCP
    targetPort: 6443
  type: LoadBalancer
EOF
```
### Endpoint Copier Operator 

Cria uma cópia do serviço e endpoint 'kubernetes-vip' para mantê-los sincronizados. O operador endpoint-copier-operator implanta duas réplicas, uma será a líder e a outra assumirá a função de líder se necessário.
```
helm repo add suse-edge https://suse-edge.github.io/charts

helm install endpoint-copier-operator suse-edge/endpoint-copier-operator \
--create-namespace \
-n endpoint-copier-operator
```
Or
```
helm install \
endpoint-copier-operator oci://registry.suse.com/edge/charts/endpoint-copier-operator \
--namespace endpoint-copier-operator \
--create-namespace
```
### Verifique se o serviço kubernetes-vip tem o endereço IP correto:
```
kubectl get service kubernetes-vip -n default \
 -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
```
### MASTER-2/3
```
mkdir -p /etc/rancher/rke2/
cat << EOF >> /etc/rancher/rke2/config.yaml
server: https://172.17.125.18:9345
node-name: master-3
token: RancherTeste
write-kubeconfig-mode: 600
#disable-kube-proxy: true
etcd-expose-metrics: true
cni:
- cilium
tls-san:
  - rke2.seguranca.local
  - 172.17.125.17 #VIP RANCHER
  - 172.17.125.18 #VIP KUBERNETES
ingress-controller: traefik
disable:
  - rke2-ingress-nginx
EOF
curl -sfL https://get.rke2.io | sh - && \
systemctl enable --now rke2-server.service
```
Descomente 'disable-kube-proxy" e reinicie o rke2-server
```
sed -i 's/^#//' /etc/rancher/rke2/config.yaml && \
systemctl restart rke2-server
```
### VIP do RANCHER

O service do rke2-traefik é por padrão ClusterIP. Deve-se alterar para LoadBalancer. Ajuste o value e aplique:

#### Pegar o value padrão:
```
helm get values rke2-traefik -n kube-system > traefik-values.yaml
```
Aplique no traefik-values.yaml
```
cat << EOF >> ~/traefik-values.yaml
service:
  type: LoadBalancer
providers:
  kubernetesGateway:
    enabled: true
EOF
```

### Atualize Traefik
```
helm upgrade rke2-traefik -n kube-system rke2-charts/rke2-traefik -f traefik-values.yaml

kubectl get service rke2-traefik -n kube-system \
 -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### RANCHER

#### Cert-Manager
```
helm upgrade -i cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--set crds.enabled=true
```
Aguarde a finalização dos pods.

#### Rancher 
```
helm upgrade -i rancher rancher-latest/rancher \
--namespace cattle-system \
--create-namespace \
--set hostname=rke2.mydomain.local \
--set replicas=3 \
--set ingress.ingressClassName=traefik \
--set bootstrapPassword=rancheradmin \
--wait
```
Aguarde a finalização dos pods.
