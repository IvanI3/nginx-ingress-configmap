echo "[   USR   ]  Adding fail2ban nginx-ingress-configmap action"
cd /tmp/docker-mailserver
apt-get update &>/dev/null
apt-get --yes install python3-pip &>/dev/null
apt-get clean &>/dev/null
pip3 install --no-input --no-cache-dir kubernetes==25.3.0 &>/dev/null
cp nginx-ingress-configmap /usr/local/bin && chmod +x /usr/local/bin/nginx-ingress-configmap
cp nginx-ingress-configmap.conf /etc/fail2ban/action.d
