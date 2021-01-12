#! /bin/bash

# Override existing DNS Settings using netplan, but don't do it for Terraform builds
if ! curl -s 169.254.169.254 --connect-timeout 2 >/dev/null; then
  echo -e "    eth1:\n      dhcp4: true\n      nameservers:\n        addresses: [8.8.8.8,8.8.4.4]" >>/etc/netplan/01-netcfg.yaml
  netplan apply
fi
sed -i 's/nameserver 127.0.0.53/nameserver 8.8.8.8/g' /etc/resolv.conf && chattr +i /etc/resolv.conf

# Get a free Maxmind license here: https://www.maxmind.com/en/geolite2/signup
# Required for the ASNgen app to work: https://splunkbase.splunk.com/app/3531/
export MAXMIND_LICENSE=
if [ -n "$MAXMIND_LICENSE" ]; then
  echo "Note: You have not entered a MaxMind license key on line 5 of bootstrap.sh, so the ASNgen Splunk app may not work correctly."
  echo "However, it is not required and everything else should function correctly."
fi

export DEBIAN_FRONTEND=noninteractive
echo "apt-fast apt-fast/maxdownloads string 10" | debconf-set-selections
echo "apt-fast apt-fast/dlflag boolean true" | debconf-set-selections

sed -i "2ideb mirror://mirrors.ubuntu.com/mirrors.txt focal main restricted universe multiverse\ndeb mirror://mirrors.ubuntu.com/mirrors.txt focal-updates main restricted universe multiverse\ndeb mirror://mirrors.ubuntu.com/mirrors.txt focal-backports main restricted universe multiverse\ndeb mirror://mirrors.ubuntu.com/mirrors.txt focal-security main restricted universe multiverse" /etc/apt/sources.list

apt_install_prerequisites() {
  echo "[$(date +%H:%M:%S)]: Adding apt repositories..."
  # Add repository for apt-fast
  add-apt-repository -y ppa:apt-fast/stable
  # Add repository for yq
  add-apt-repository -y ppa:rmescandon/yq
  # Install prerequisites and useful tools
  echo "[$(date +%H:%M:%S)]: Running apt-get clean..."
  apt-get clean
  echo "[$(date +%H:%M:%S)]: Running apt-get update..."
  apt-get -qq update
  apt-get -qq install -y apt-fast
  echo "[$(date +%H:%M:%S)]: Running apt-fast install..."
  apt-fast -qq install -y jq whois git unzip htop yq python3-pip cmake make gcc g++ flex bison libpcap-dev libssl-dev python-dev swig zlib1g-dev emacs
}

modify_motd() {
  echo "[$(date +%H:%M:%S)]: Updating the MOTD..."
  # Force color terminal
  sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' /root/.bashrc
  sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' /home/vagrant/.bashrc
  # Remove some stock Ubuntu MOTD content
  chmod -x /etc/update-motd.d/10-help-text
  # Copy the DetectionLab MOTD
  cp /vagrant/resources/logger/20-detectionlab /etc/update-motd.d/
  chmod +x /etc/update-motd.d/20-detectionlab
}

test_prerequisites() {
  for package in jq whois build-essential git unzip yq python-pip; do
    echo "[$(date +%H:%M:%S)]: [TEST] Validating that $package is correctly installed..."
    # Loop through each package using dpkg
    if ! dpkg -S $package >/dev/null; then
      # If which returns a non-zero return code, try to re-install the package
      echo "[-] $package was not found. Attempting to reinstall."
      apt-get -qq update && apt-get install -y $package
      if ! which $package >/dev/null; then
        # If the reinstall fails, give up
        echo "[X] Unable to install $package even after a retry. Exiting."
        exit 1
      fi
    else
      echo "[+] $package was successfully installed!"
    fi
  done
}

fix_eth1_static_ip() {
  USING_KVM=$(sudo lsmod | grep kvm)
  if [ -n "$USING_KVM" ]; then
    echo "[*] Using KVM, no need to fix DHCP for eth1 iface"
    return 0
  fi
  if [ -f /sys/class/net/eth2/address ]; then
    if [ "$(cat /sys/class/net/eth2/address)" == "00:50:56:a3:b1:c4" ]; then
      echo "[*] Using ESXi, no need to change anything"
      return 0
    fi
  fi
  # There's a fun issue where dhclient keeps messing with eth1 despite the fact
  # that eth1 has a static IP set. We workaround this by setting a static DHCP lease.
  echo -e 'interface "eth1" {
    send host-name = gethostname();
    send dhcp-requested-address 192.168.38.105;
  }' >>/etc/dhcp/dhclient.conf
  netplan apply
  # Fix eth1 if the IP isn't set correctly
  ETH1_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
  if [ "$ETH1_IP" != "192.168.38.105" ]; then
    echo "Incorrect IP Address settings detected. Attempting to fix."
    ifdown eth1
    ip addr flush dev eth1
    ifup eth1
    ETH1_IP=$(ifconfig eth1 | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1)
    if [ "$ETH1_IP" == "192.168.38.105" ]; then
      echo "[$(date +%H:%M:%S)]: The static IP has been fixed and set to 192.168.38.105"
    else
      echo "[$(date +%H:%M:%S)]: Failed to fix the broken static IP for eth1. Exiting because this will cause problems with other VMs."
      exit 1
    fi
  fi

  # Make sure we do have a DNS resolution
  while true; do
    if [ "$(dig +short @8.8.8.8 github.com)" ]; then break; fi
    sleep 1
  done
}

install_splunk() {
  # Check if Splunk is already installed
  if [ -f "/opt/splunk/bin/splunk" ]; then
    echo "[$(date +%H:%M:%S)]: Splunk is already installed"
  else
    echo "[$(date +%H:%M:%S)]: Installing Splunk..."
    # Get download.splunk.com into the DNS cache. Sometimes resolution randomly fails during wget below
    dig @8.8.8.8 download.splunk.com >/dev/null
    dig @8.8.8.8 splunk.com >/dev/null
    dig @8.8.8.8 www.splunk.com >/dev/null

    # Try to resolve the latest version of Splunk by parsing the HTML on the downloads page
    echo "[$(date +%H:%M:%S)]: Attempting to autoresolve the latest version of Splunk..."
    LATEST_SPLUNK=$(curl https://www.splunk.com/en_us/download/splunk-enterprise.html | grep -i deb | grep -Eo "data-link=\"................................................................................................................................" | cut -d '"' -f 2)
    # Sanity check what was returned from the auto-parse attempt
    if [[ "$(echo "$LATEST_SPLUNK" | grep -c "^https:")" -eq 1 ]] && [[ "$(echo "$LATEST_SPLUNK" | grep -c "\.deb$")" -eq 1 ]]; then
      echo "[$(date +%H:%M:%S)]: The URL to the latest Splunk version was automatically resolved as: $LATEST_SPLUNK"
      echo "[$(date +%H:%M:%S)]: Attempting to download..."
      wget --progress=bar:force -P /opt "$LATEST_SPLUNK"
    else
      echo "[$(date +%H:%M:%S)]: Unable to auto-resolve the latest Splunk version. Falling back to hardcoded URL..."
      # Download Hardcoded Splunk
      wget --progress=bar:force -O /opt/splunk-8.0.2-a7f645ddaf91-linux-2.6-amd64.deb 'https://download.splunk.com/products/splunk/releases/8.0.2/linux/splunk-8.0.2-a7f645ddaf91-linux-2.6-amd64.deb&wget=true'
    fi
    if ! ls /opt/splunk*.deb 1>/dev/null 2>&1; then
      echo "Something went wrong while trying to download Splunk. This script cannot continue. Exiting."
      exit 1
    fi
    if ! dpkg -i /opt/splunk*.deb >/dev/null; then
      echo "Something went wrong while trying to install Splunk. This script cannot continue. Exiting."
      exit 1
    fi

    /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd changeme
    /opt/splunk/bin/splunk add index zeek -auth 'admin:changeme'
    /opt/splunk/bin/splunk add index linux -auth 'admin:changeme'
    /opt/splunk/bin/splunk install app /vagrant/resources/splunk_server/splunk-add-on-for-zeek-aka-bro_400.tgz -auth 'admin:changeme'
    /opt/splunk/bin/splunk install app /vagrant/resources/splunk_server/splunk-add-on-for-unix-and-linux_820.tgz  -auth 'admin:changeme'

    # Add a Splunk TCP input on port 9997
    echo -e "[splunktcp://9997]\nconnection_host = ip" >/opt/splunk/etc/apps/search/local/inputs.conf
    # Add props.conf and transforms.conf
    cp /vagrant/resources/splunk_server/props.conf /opt/splunk/etc/apps/search/local/
    cp /vagrant/resources/splunk_server/transforms.conf /opt/splunk/etc/apps/search/local/
    cp /opt/splunk/etc/system/default/limits.conf /opt/splunk/etc/system/local/limits.conf
    # Bump the memtable limits to allow for the ASN lookup table
    sed -i.bak 's/max_memtable_bytes = 10000000/max_memtable_bytes = 30000000/g' /opt/splunk/etc/system/local/limits.conf

    # Skip Splunk Tour and Change Password Dialog
    echo "[$(date +%H:%M:%S)]: Disabling the Splunk tour prompt..."
    touch /opt/splunk/etc/.ui_login
    mkdir -p /opt/splunk/etc/users/admin/search/local
    echo -e "[search-tour]\nviewed = 1" >/opt/splunk/etc/system/local/ui-tour.conf
    # Source: https://answers.splunk.com/answers/660728/how-to-disable-the-modal-pop-up-help-us-to-improve.html
    if [ ! -d "/opt/splunk/etc/users/admin/user-prefs/local" ]; then
      mkdir -p "/opt/splunk/etc/users/admin/user-prefs/local"
    fi
    echo '[general]
render_version_messages = 1
dismissedInstrumentationOptInVersion = 4
notification_python_3_impact = false
display.page.home.dashboardId = /servicesNS/nobody/search/data/ui/views/logger_dashboard' >/opt/splunk/etc/users/admin/user-prefs/local/user-prefs.conf
    # Enable SSL Login for Splunk
    echo -e "[settings]\nenableSplunkWebSSL = true" >/opt/splunk/etc/system/local/web.conf
    # Copy over the Logger Dashboard
    if [ ! -d "/opt/splunk/etc/apps/search/local/data/ui/views" ]; then
      mkdir -p "/opt/splunk/etc/apps/search/local/data/ui/views"
    fi
    cp /vagrant/resources/splunk_server/logger_dashboard.xml /opt/splunk/etc/apps/search/local/data/ui/views || echo "Unable to find dashboard"
    # Reboot Splunk to make changes take effect
    /opt/splunk/bin/splunk restart
    /opt/splunk/bin/splunk enable boot-start
  fi
}

install_zeek() {
  echo "[$(date +%H:%M:%S)]: Installing Zeek..."
  # Environment variables
  NODECFG=/opt/zeek/etc/node.cfg


  ## custom download ######################

  cd ~
  wget https://download.zeek.org/zeek-3.1.3.tar.gz
  tar xzf zeek-3.1.3.tar.gz
  cd zeek-3.1.3
  ./configure --prefix=/opt/zeek/
  make -j4
  sudo make install
  # Update APT repositories
  apt-get -qq -ym update
  # Install crudini
  apt-get -qq -ym install crudini

  ##############################

  #   sh -c "echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_20.04/ /' > /etc/apt/sources.list.d/security:zeek.list"
  # wget -nv https://download.opensuse.org/repositories/security:zeek/xUbuntu_20.04/Release.key -O /tmp/Release.key
  # apt-key add - </tmp/Release.key &>/dev/null
  # # Update APT repositories
  # apt-get -qq -ym update
  # # Install tools to build and configure Zeek
  # apt-get -qq -ym install zeek crudini

  ##############################

  export PATH=$PATH:/opt/zeek/bin

  ln -s /home/vagrant/projects/zeek-agent-framework/zeek-agent /opt/zeek/share/zeek/site/zeek-agent

  pip3 install zkg==2.1.1
  zkg refresh
  zkg autoconfig
  zkg install --force salesforce/ja3

  # Load Zeek scripts
  echo '
  @load protocols/ftp/software
  @load protocols/smtp/software
  @load protocols/ssh/software
  @load protocols/http/software
  @load tuning/json-logs
  @load policy/integration/collective-intel
  @load policy/frameworks/intel/do_notice
  @load frameworks/intel/seen
  @load frameworks/intel/do_notice
  @load frameworks/files/hash-all-files
  @load base/protocols/smb
  @load policy/protocols/conn/vlan-logging
  @load policy/protocols/conn/mac-logging
  @load ja3
  @load zeek-agent
  @load zeek-agent/queries/auditd

  redef Intel::read_files += {
    "/opt/zeek/etc/intel.dat"
  };
  ' >>/opt/zeek/share/zeek/site/local.zeek

  # Configure Zeek
  crudini --del $NODECFG zeek
  crudini --set $NODECFG manager type manager
  crudini --set $NODECFG manager host localhost
  crudini --set $NODECFG proxy type proxy
  crudini --set $NODECFG proxy host localhost

  # Setup Zeek workers
  crudini --set $NODECFG worker-eth0 type worker
  crudini --set $NODECFG worker-eth0 host localhost
  crudini --set $NODECFG worker-eth0 interface eth0
  crudini --set $NODECFG worker-eth0 lb_method pf_ring
  crudini --set $NODECFG worker-eth0 lb_procs 1

  crudini --set $NODECFG worker-eth1 type worker
  crudini --set $NODECFG worker-eth1 host localhost
  crudini --set $NODECFG worker-eth1 interface eth1
  crudini --set $NODECFG worker-eth1 lb_method pf_ring
  crudini --set $NODECFG worker-eth1 lb_procs 1

  # Setup Zeek to run at boot
  cp /vagrant/resources/zeek/zeek.service /lib/systemd/system/zeek.service
  systemctl enable zeek
  systemctl start zeek

  # # Configure the Splunk inputs
  mkdir -p /opt/splunk/etc/apps/Splunk_TA_bro/local && touch /opt/splunk/etc/apps/Splunk_TA_bro/local/inputs.conf
  crudini --set /opt/splunk/etc/apps/Splunk_TA_bro/local/inputs.conf monitor:///opt/zeek/spool/manager index zeek
  crudini --set /opt/splunk/etc/apps/Splunk_TA_bro/local/inputs.conf monitor:///opt/zeek/spool/manager sourcetype bro:json
  crudini --set /opt/splunk/etc/apps/Splunk_TA_bro/local/inputs.conf monitor:///opt/zeek/spool/manager whitelist '.*\.log$'
  crudini --set /opt/splunk/etc/apps/Splunk_TA_bro/local/inputs.conf monitor:///opt/zeek/spool/manager blacklist '.*(communication|stderr)\.log$'
  crudini --set /opt/splunk/etc/apps/Splunk_TA_bro/local/inputs.conf monitor:///opt/zeek/spool/manager disabled 0

  # Ensure permissions are correct and restart splunk
  chown -R splunk:splunk /opt/splunk/etc/apps/Splunk_TA_bro
  /opt/splunk/bin/splunk restart

  # Verify that Zeek is running
  if ! pgrep -f zeek >/dev/null; then
    echo "Zeek attempted to start but is not running. Exiting"
    exit 1
  fi
}


install_zeek_agent_framework() {
  mkdir -p /home/vagrant/projects/
  cd /home/vagrant/projects/
  git clone https://github.com/Wajihulhassan/zeek-agent-framework.git
  cd zeek-agent-framework/
  git checkout state-final
  cd /home/vagrant/
  chown -R vagrant:vagrant projects
}


postinstall_tasks() {
  # Include Splunk and Zeek in the PATH
  echo export PATH="$PATH:/opt/zeek/bin" >>~/.bashrc
  echo "export SPLUNK_HOME=/opt/splunk" >>~/.bashrc
  # Include Zeekpath
  echo export ZEEKPATH="/home/vagrant/projects/zeek-agent-framework/:$(zeek-config --zeekpath)" >>~/.bashrc
  # Ping DetectionLab server for usage statistics
  curl -s -A "DetectionLab-logger" "https:/ping.detectionlab.network/logger" || echo "Unable to connect to ping.detectionlab.network"
}

main() {
  apt_install_prerequisites
  modify_motd
  test_prerequisites
  fix_eth1_static_ip
  #install_splunk
  install_zeek_agent_framework
  install_zeek
  postinstall_tasks
}

main
exit 0
