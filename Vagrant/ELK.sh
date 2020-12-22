#! /usr/bin/env bash

# Functions

DATE() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Variables

# Get IP
IP=`ip -o addr show up primary scope global | while read -r num dev fam addr rest; do echo [$(DATE)] [Info] [System] ${addr%/*}; done`
# Set package version
VERSION="7.10.1"
# Set provision folder
PROVISION_FOLDER="/tmp"

# Let's go

# Update & Upgrade System
echo "[$(DATE)] [Info] [System] Updating & Upgrading System..."
apt update &> /dev/null
apt -y upgrade &> /dev/null

# Install Java
if [ $(dpkg-query -W -f='${Status}' openjdk-8-jdk 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
  echo "[$(DATE)] [Info] [Java] Installing Java..."
  add-apt-repository -y ppa:openjdk-r/ppa &> /dev/null
  apt update &> /dev/null
  apt -y install openjdk-8-jdk &> /dev/null
fi

# Install Elastic Repository
if ! grep -q "^deb .*7.x" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo "[$(DATE)] [Info] [System] Installing Elastic Repository..."
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add - &> /dev/null
    apt -y install apt-transport-https &> /dev/null
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list &> /dev/null
    apt update &> /dev/null
fi

# ------------------------------- Elasticsearch --------------------------------
# Install Elasticsearch
echo "[$(DATE)] [Info] [Elasticsearch] Installing Elasticsearch..."
apt -y install elasticsearch=$VERSION &> /dev/null

# Specify system limits via systemd (see https://www.elastic.co/guide/en/elasticsearch/reference/master/setting-system-settings.html)
mkdir /etc/systemd/system/elasticsearch.service.d/
cat >/etc/systemd/system/elasticsearch.service.d/override.conf <<EOF
[Service]
LimitMEMLOCK=infinity
EOF

# Copy config, reload daemon and restart Elasticsearch
echo "[$(DATE)] [Info] [Elasticsearch] Copy config, reload daemon and restart Elasticsearch..."
cp -R $PROVISION_FOLDER/elasticsearch/* /etc/elasticsearch/ &> /dev/null
systemctl daemon-reload &> /dev/null
systemctl enable elasticsearch  &> /dev/null
service elasticsearch restart  &> /dev/null

# Generate randmoly-generated passwords and store them in variables for later use
# elasticsearch has to be running before this can be ran
echo "[$(DATE)] [Info] [Elasticsearch] Generate passwords..."
mkdir /opt/kibana/
yes | /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto >> /opt/kibana/kibana_passwords.txt
mkdir -p /vagrant/resources/kibana
cp /opt/kibana/kibana_passwords.txt /vagrant/resources/kibana/

KIBANA_SYS_PASS="$(grep -E "kibana_system \S .*" /opt/kibana/kibana_passwords.txt)"
ELASTIC_PASS="$(grep -E "elastic \S .*" /vagrant/resources/kibana/kibana_passwords.txt)"
KIBANA_UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# ----------------------------------- Kibana -----------------------------------
# Install Kibana
echo "[$(DATE)] [Info] [Kibana] Installing Kibana..."
apt -y install kibana=$VERSION &> /dev/null
chown -R kibana:kibana /usr/share/kibana

# Create file where Kibana stores log output
touch /var/log/kibana.log
chown kibana:kibana /var/log/kibana.log

# Copy config
echo "[$(DATE)] [Info] [Kibana] Copy config"
cp -R $PROVISION_FOLDER/kibana/* /etc/kibana &> /dev/null

# Add Kibana security requirements
echo "[$(DATE)] [Info] [Kibana] Add Kibana security requirements"
printf 'elasticsearch.password: \"' >>/etc/kibana/kibana.yml
printf %s  ${KIBANA_SYS_PASS##*=}\" >>/etc/kibana/kibana.yml
printf '\nxpack.encryptedSavedObjects.encryptionKey: \"' >>/etc/kibana/kibana.yml
printf %s  ${KIBANA_UUID}\" >>/etc/kibana/kibana.yml

# Reload daemon and restart Kibana
echo "[$(DATE)] [Info] [Kibana] Reload daemon and restart Kibana..."
systemctl daemon-reload &> /dev/null
systemctl enable kibana &> /dev/null
service kibana restart &> /dev/null

# --------------------------------- Logstash -----------------------------------
# Install Logstash
echo "[$(DATE)] [Info] [Logstash] Installing Logstash..."
apt -y install logstash=1:$VERSION-1 &> /dev/null
systemctl enable logstash &> /dev/null

# ------------------------------ Beats Family ----------------------------------
# Install Filebeat
echo "[$(DATE)] [Info] [Filebeat] Installing Filebeat..."
apt -y install filebeat=$VERSION &> /dev/null
#ToDo Filebeat config
# Install Packetbeat
#echo "[$(DATE)] [Info] [Packetbeat] Installing Packetbeat..."
apt -y install libpcap0.8 &> /dev/null
apt -y install packetbeat=$VERSION &> /dev/null
# Install Metricbeat
echo "[$(DATE)] [Info] [Metricbeat] Installing Metricbeat..."
apt -y install metricbeat=$VERSION &> /dev/null
# Install Heartbeat
echo "[$(DATE)] [Info] [Heartbeat] Installing Heartbeat..."
apt -y install heartbeat-elastic=$VERSION &> /dev/null
# Install Auditbeat
echo "[$(DATE)] [Info] [Auditbeat] Installing Auditbeat..."
apt -y install auditbeat=$VERSION &> /dev/null

# ------------------------------- Tidying Up -----------------------------------
# Clean unneeded packages
echo "[$(DATE)] [Info] [System] Cleaning unneeded packages..."
apt -y autoremove &> /dev/null
# Update file search cache
echo "[$(DATE)] [Info] [System] Updating file search cache..."
updatedb &> /dev/null
# Prevent package upgrade
echo "[$(DATE)] [Info] [System] Prevent package upgrade..."
apt-mark hold elasticsearch kibana logstash filebeat packetbeat metricbeat heartbeat-elastic auditbeat &> /dev/null
# Clear Disk Cache
echo "[$(DATE)] [Info] [System] Clear disk cache..."
sync; echo 1 > /proc/sys/vm/drop_caches
# Show IPs
echo "[$(DATE)] [Info] [System] IP Address on the machine..."
echo -e "$IP"
echo "[$(DATE)] [Info] [System] Login to Kibana via http://192.168.38.105:5601 and use the elastic password found in /opt/kibana/kibana_passwords.txt"
echo "[$(DATE)] [Info] [System] Enjoy it! :)"