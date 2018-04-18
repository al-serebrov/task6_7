#!/bin/bash

# Exporting environmental variables from the config file
source vm1.config

# Initial configuration
HOST_NAME="VM1"
APACHE_VLAN_IP="${APACHE_VLAN_IP//\/*/}"
SSL_PATH="/etc/ssl/certs"
VM2_INT_IP="`grep ^INT_IP= vm2.config | sed 's/^INT_IP=\(.*\)\/.*$/\1/g'`"

#Configuring DHCP if needed
if [ "$EXT_IP" == "DHCP" ]; then
    dhclient $EXTERNAL_IF
else
    ifconfig $EXTERNAL_IF $EXT_IP up
    # Add default gateway
    route add default gw `echo ${EXT_GW//\/*/}`
fi

# Add nameserver
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Get external interface IP address
EXT_IP_ADDR=`ip address show $EXTERNAL_IF | grep "inet " | awk '{print $2}' | tr '\n' ' ' | sed 's/\/.*$//g'`

# Setup internet connection for VM2
ifconfig $INTERNAL_IF $INT_IP up

# Install needed dependencies
apt-get -y install vlan ssh openssh-server openssl

# Create VLAN on INTERNAL_IF
vconfig add $INTERNAL_IF $VLAN
ifconfig $INTERNAL_IF.$VLAN $VLAN_IP up

# Add routing for VM2
sysctl net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s $VM2_INT_IP -o $EXTERNAL_IF -j MASQUERADE

# Edit hosts
cat <<EOF > /etc/hosts
$EXT_IP_ADDR       $HOST_NAME
127.0.0.1       localhost
127.0.1.1       $HOST_NAME
EOF

# Install "nginx" and "curl"
apt-get -y install nginx curl

# Add default nginx configuration for HOST_NAME
cat <<EOF > /etc/nginx/sites-available/$HOST_NAME
server {

    listen $NGINX_PORT;
    server_name vm1;

    ssl_certificate           $SSL_PATH/web.pem;
    ssl_certificate_key       $SSL_PATH/web.key;

    ssl on;
    ssl_session_cache  builtin:1000  shared:SSL:10m;
    ssl_protocols  TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;

    access_log            /var/log/nginx/vm1.access.log;

    location / {

      proxy_set_header        Host \$host;
      proxy_set_header        X-Real-IP \$remote_addr;
      proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header        X-Forwarded-Proto \$scheme;

      # Fix the "It appears that your reverse proxy set up is broken" error.
      proxy_pass          http://$APACHE_VLAN_IP:80;

    }
}
EOF

# Remove default nginx configuration
rm -f /etc/nginx/sites-enabled/default

# Create a link between sites-enabled conf and sites-available conf
ln -s /etc/nginx/sites-available/$HOST_NAME /etc/nginx/sites-enabled/$HOST_NAME

# Make a folder for SSL cert
mkdir -p $SSL_PATH

# Generate root CA key inside SSL_PATH
openssl genrsa -out $SSL_PATH/root-ca.key 4096

# Generate full chain
openssl req -x509 -new -nodes -key $SSL_PATH/root-ca.key -sha256 -days 365 \
    -out $SSL_PATH/root-ca.crt \
    -subj "/C=UA/ST=Kharkov/L=Kharkov/O=Task6_7/OU=web/CN=root_cert/"

# Generate key for nginx
openssl genrsa -out $SSL_PATH/web.key 2048

# Generate full chain for nginx
openssl req -new -out $SSL_PATH/web.csr -key $SSL_PATH/web.key \
    -subj "/C=UA/ST=Kharkov/L=Kharkov/O=Task6_7/OU=web/CN=$HOST_NAME/"

# Sign nginx CSR with the certificate
openssl x509 -req -in $SSL_PATH/web.csr -CA \
    $SSL_PATH/root-ca.crt \
    -CAkey $SSL_PATH/root-ca.key \
    -CAcreateserial \
    -out $SSL_PATH/web.crt -days 365 -sha256 \
    -extfile <(echo -e "authorityKeyIdentifier=keyid,issuer\nbasicConstraints=CA:FALSE\nkeyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment\nsubjectAltName = @alt_names\n[ alt_names ]\nDNS.1 = $HOST_NAME\nDNS.2 = $EXT_IP_ADDR\nIP.1 = $EXT_IP_ADDR")

# Create pem file with web and root certificates in it
cat $SSL_PATH/web.crt $SSL_PATH/root-ca.crt > $SSL_PATH/web.pem

# Restart nginx to apply changes
service nginx restart

exit 0
