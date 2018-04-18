#!/bin/bash

# Export environmental variables from the config file
source vm2.config

# Initial configuration
HOST_NAME="vm2"
HOST_IP=`echo "$APACHE_VLAN_IP" | sed 's/\/.*$//g'`
HOSTS_STR="$HOST_IP $HOST_NAME"

# Add routing, default gateway and needed resolver
ifconfig $INTERNAL_IF $INT_IP up
route add default gw `echo $GW_IP | sed 's/\/.*$//g'`
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Create VLAN on INTERNAL_IF
apt-get -y install vlan
vconfig add $INTERNAL_IF $VLAN
ifconfig $INTERNAL_IF.$VLAN $APACHE_VLAN_IP up

# Add HOSTS_STR to hosts file
sed -i -e "1 s/^/$HOSTS_STR\n/" /etc/hosts

# Install needed dependencies
apt-get -y install apache2 curl

# Configure Apach to listen only HOST_IP port 80 (http)
cat <<EOF > /etc/apache2/ports.conf
Listen $HOST_IP:80
EOF

# Add default Apache configuration for HOST_NAME
cat <<EOF > /etc/apache2/sites-available/$HOST_NAME.conf
<VirtualHost $HOST_IP:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html
#        ErrorLog \${APACHE_LOG_DIR}/error.log
#        CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Disable Apache default configuration
a2dissite 000-default

# Enable Apache configuration for HOST_NAME
a2ensite $HOST_NAME

# Restart Apache to apply changes
service apache2 restart

exit 0
