# Title
This "project" is a fail2ban action and some supporting configs, which allow to use fail2ban when docker-mailserver runs in Kubernetes container behing nginx-ingress TCP proxy, using HAPROXY mode.

# About
I've got my own installation of  **super-easy-to-use** mail-server-in-a-box [Docker Mailserver](https://docker-mailserver.github.io/docker-mailserver/edge/). It runs in public cloud, behind the load balancer with nginx-ingress in a Kubernetes container. Basic description of this configuration is [here](https://docker-mailserver.github.io/docker-mailserver/edge/config/advanced/kubernetes/).

This configuration doesn't allow to use built-in fail2ban with iptables action, because DMS container does't see real IP addresses at TCP level (DMS works in HAPROXY mode). So, one of the way to block annoying IPs - use nginx-ingress resource.

This script manages nginx-ingress configmap data - [stream-snippet](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#stream-snippet) key. Nginx-ingress will reload configmap changes "on-the-fly". You can add/delete/list deny records in this section of ingress configmap. Adding "deny" record to this snippet, block IP address from TCP proxing **for all ports!** with 403 error in nginx-ingress logs.

# Installation
All steps below concerning **DMS installation** (with nginx-ingress proxy). But it could be used as a regular fail2ban action in k8s container ("in-cluster" config) and as CLI command (using standard kubeconfig).

Defaults for all configs in repo **(change to your actual values!)**:
* DMS namespace: **mail**
* DMS kubernetes service account: **default**
* DMS configuration mounted to **/tmp/docker-mailserver** and contains required fail2ban action files:
  * **nginx-ingress-configmap.conf**
  * **nginx-ingress-configmap**
* nginx-ingress namespace: **ingress-nginx-public**
* nginx-ingress configmap name: **ingress-public-ingress-nginx-controller**

## 1. Allow access from DMS container to nginx-ingress configmap
Create following role and role binding in Kubernetes cluster **(check your own object names and namespaces!)**:

```
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nginx-update-cm
  namespace: ingress-nginx-public
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["ingress-public-ingress-nginx-controller"]
  verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nginx-update-cm
  namespace: ingress-nginx-public
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: nginx-update-cm
subjects:
- kind: ServiceAccount
  name: default
  namespace: mail
```

## 2. Update **nginx-ingress-configmap.conf** with your actual data
At least check variable **configmap_path** with your values and values above:

```
[Init]
# Path to action script
program = /usr/local/bin/nginx-ingress-configmap

# NGINX ingess controller configmap in format: <namespace>/<name>
configmap_path = ingress-nginx-public/ingress-public-ingress-nginx-controller

[Definition]
# Uncomment if you don't want "unban all" on DMS restart
# actionflush = true

actionban   = [ -x "<program>" ] && <program> <configmap_path> add <ip>
actionunban = [ -x "<program>" ] && <program> <configmap_path> delete <ip>
```

Place this file along with script **nginx-ingress-configmap** to DMS container configration volume aka **"/tmp/docker-mailserver/"**. I don't know which approach you use to handle DMS configuration folder. I use persistent volume for it, so, I just place files on that volume using copy.

## Update user-patches.sh
Install **pip** apt-package, and **kubernetes** pip-package into DMS container. Copy action script to **/usr/local/bin/**, action config to **/etc/fail2ban/action.d/**:

```
echo "[   USR   ]  Adding fail2ban nginx-ingress-configmap action"
cd /tmp/docker-mailserver
apt-get update &>/dev/null
apt-get --yes install python3-pip &>/dev/null
pip3 install --no-input --no-cache-dir kubernetes==25.3.0 &>/dev/null
cp nginx-ingress-configmap /usr/local/bin && chmod +x /usr/local/bin/nginx-ingress-configmap
cp nginx-ingress-configmap.conf /etc/fail2ban/action.d
```

## 3. Configure fail2ban
Use built-in DMS configuration files to tune [fail2ban config](https://docker-mailserver.github.io/docker-mailserver/edge/config/security/fail2ban/). To activate this action, edit **fail2ban-jail.cf** in **/tmp/docker-mailserver/** with:

```
[DEFAULT]
banaction = nginx-ingress-configmap
```

## 4. Don't forget to tell DMS to use fail2ban:
Add environment variable ENABLE_FAIL2BAN="1" to DMS container!

## 5. That's all
Finnaly, restart DMS container, and enjoy nginx-ingress pod(s) logs like:

```
$ kubectl logs -n ingress-nginx-public ingress-public-ingress-nginx-controller-mhsp2 | grep "TCP 403"
[45.XX.YYY.156] [05/Feb/2023:18:39:24 +0000] TCP 403 0 0 0.000
[45.XX.YYY.154] [05/Feb/2023:18:55:30 +0000] TCP 403 0 0 0.000
[45.XX.YYY.162] [05/Feb/2023:19:05:33 +0000] TCP 403 0 0 0.000
[45.XX.YYY.160] [05/Feb/2023:19:32:19 +0000] TCP 403 0 0 0.000
...

$ nginx-ingress-configmap ingress-nginx-public/ingress-public-ingress-nginx-controller list
45.XX.YYY.154
45.XX.YYY.156
45.XX.YYY.162
45.XX.YYY.160
```

# Troubleshoting
You may try:
1. Check DMS container logs
1. Run **nginx-ingress-configmap** "out-cluster" with appropriate kubeconfig in ~/.kube and check results/errors
1. Comment *"&>/dev/null"* from **user-patches.sh** to find possible package installation errors
1. Exec to DMS container, run **nginx-ingress-configmap** in-cluster manually and check results/errors
1. Check **/var/log/fail2ban.log**
1. Check actual nginx-ingress configmap, using kubectl

# Disclaimer
I just share this piece of code "as is", and don't provide any guarantee or support. You can use it, correct it, modify it and also don't use it. Do it on your own risk!

# Thanks
Thanks to all DMS Team for a really easy and reliable mail-server-in-a-box! Especially, for ARM image support...