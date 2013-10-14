#!/bin/bash

# Author: Rovanion Luckey
# App Version: 6.2
version=6.2
# This script installs Gitlab 6.2 on a Debian 7 against MySQL and Nginx.

# Bail out if there are any errors
set -e

if [ "$USER" != "root" ]; then
  sudo -u "root" -H $0 "$@"; exit;
fi


###
# Read flags and arguments
###
# For all arguments
for opt in $@; do
  case $opt in
    # Reading $2 grabs the value, shift 2 to get past both the flag and value.
    -u) user=$2 ; shift 2 ;;     # The gitlab username
    -p) password=$2 ; shift 2 ;; # Password for the gitlab user
    -f) folder=$2 ; shift 2 ;;   # The folder in which all is put
    -d) domain=$2 ; shift 2 ;;   # The domain at which the server runs
    -r) rootDBPassword=$2 ; shift 2 ;; # The password for the MySQL DB
    -a) auto=0 ; shift 1 ;;      # Take no input
    -h) echo "This script installs Gitlab $version on a Debian 7"
	echo "Usage: $0 [option]"
	echo "Options:"
	echo -e "\t -u \t User to run GitLab under, git by default."
	echo -e "\t -p \t Password for the user Gitlab runs as, random by default."
	echo -e "\t -f \t Folder to install GitLab in, /home/$user by default."
	echo -e "\t -d \t Domain name of the GitLab server, e.g. git.domain.com."
 	echo -e "\t -r \t Password for the root user of the MySQL database."
	echo -e "\t -a \t Do everything automatically without input, at least -d must be specified."
	exit;;
  esac
done


###
# User input
###
if [[ $auto ]]; then
    if [[ -z $domain  ]]; then
	# If rootDBPassword is unset and mysql is already installed.
	if [[ -z $rootDBPassword ]] && dpkg -s mysql-server &>/dev/null; then
	    echo "The domain name with -d and MySQL root password with -r must be specified for automatic installs if MySQL is already installed; which it is on this machine."
	else
	    echo "The domain name must be specified with the -d flag for automatic installs."
	fi
	exit 1
    fi
else
    # If the variables are unset, ask for them.
    if [[ -z $user ]]; then
	echo -n "Type the user you want GitLab to run as followed by [ENTER]. If none is given the default is 'git': "
	read user
	if [[ "$user" == "" || -z $user ]]; then
	    user="git"
	fi
    fi
    if [[ -z $password ]]; then
	echo -n "Type the new password for user '$user' followed by [ENTER]. If none is given the default is random: "
	read password
    fi
    if [[ -z $folder ]]; then
	echo -n "Type the folder you want GitLab installed in followed by [ENTER]. Please don't include a trailing '/'. If none is given /home/$user: "
	read folder
    fi
    if [[ -z $domain ]]; then
	echo -n "Type the domain name at which GitLab will be running, e.g. git.domain.com, followed by [ENTER]: "
	read domain
    fi
    if [[ -z $rootDBPassword ]]; then
	echo -n "Type the Password for the root user of the MySQL database followed by [ENTER]: "
	read -s rootDBPassword
    fi
fi


###
# Default values
###
if [[ "$user" == "" || -z $user ]]; then
    user="git"
fi
if [[ "$password" == "" || -z $password ]]; then
    password=$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM
fi
if [[ "$folder" == "" || -z $folder ]]; then
    folder="/home/$appUser"
fi
if [[ "$domain" == "" || -z $domain ]]; then
    echo "The domain name at which the server runs must be specified."
    exit 1;
fi
if [[ "$rootDBPassword" == "" || -z $rootDBPassword ]]; then
    if dpkg -s mysql-server &>/dev/null; then
	echo "The password for the root MySQL user must be specified because MySQL is already installed."
	exit 1;
    else
	rootDBPassword=$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM
    fi
fi

# Adding the user according to http://www.debian-administration.org/articles/668
useradd --home "$folder" -p $(echo "$password" | openssl passwd -1 -stdin) "$user"
cd "$folder"
echo $folder

###
# Dependencies
###
dependencies="build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl git-core openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev python python-docutils postfix mysql-server mysql-client libmysqlclient-dev nginx"
apt-get update
if [[ $auto ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -y upgrade
    apt-get -y install $dependencies
    mysqladmin -u root password "$rootDBPassword"
else
    apt-get upgrade
    apt-get install $dependencies
fi

###
# Remove old Ruby and install 2.0
###
echo -e "\n\nThe following steps will remove Ruby 1.8 if installed then compile and install Ruby 2.0 instead. Note that this may or may not break existing applications installed on this server. Proceed with caution."
if [[ $auto ]]; then
    apt-get remove -y ruby1.8
else
    echo -n "Are you sure you want to compile and install Ruby 2.0? Answer y or n followed by [ENTER]: "
    read answer
    if [[ "$answer" != "y" || "$answer" != "Y" ]]; then
	exit
    fi
    apt-get remove ruby1.8
fi

curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p247.tar.gz | tar xz
cd ruby-2.0.0-p247
./configure
make
sudo make install
cd "$folder"

# Install the ruby gem bundler
gem install bundler --no-ri --no-rdoc


###
# Gitlab Shell
###
sudo -u "$user" -H git clone https://github.com/gitlabhq/gitlab-shell.git
cd gitlab-shell
sudo -u "$user" -H git checkout v1.7.1
mv config.yml config.yml.old 2>/dev/null
# Automatically edit the config according to the arguments given. "|" is used instead of "/".
sudo -u "$user" -H sed -r -e "s|user: git|user: $user|" config.yml.example | sed -r -e "s|/home/git|$folder|" >> config.yml
sudo -u "$user" -H ./bin/install


###
# MySQL
###
mysql -u root -p"$dbPassword" -Bse "CREATE USER '$user'@'localhost' IDENTIFIED BY '$password'; 
CREATE DATABASE IF NOT EXISTS `gitlabhq_production` DEFAULT CHARACTER SET `utf8` COLLATE `utf8_unicode_ci`; 
GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON `gitlabhq_production`.* TO '$user'@'localhost';"

# Test the mysql connection with the new user
if ! sudo -u "$user" -H mysql -u "$user" -p="$password" -D gitlabhq_production ; then
    echo "Failed to login as '$user'@'localhost'. Something went wrong with the MySQL setup."
fi


###
# GitLab and Configuration
###
cd "$folder/gitlab"
sudo -u "$user" -H git clone https://github.com/gitlabhq/gitlabhq.git gitlab && git checkout 6-2-stable
sudo -u "$user" -H sed -r -e "s|localhost|$domain|" config/gitlab.yml.example | sed -r -e "s|# user: git|user: $user|" | sed -r -e "s|/home/git|$folder|" >> gitlab.yml

chown -R "$user" log/
chown -R "$user" tmp/
chmod -R u+rwX  log/
chmod -R u+rwX  tmp/
sudo -u "$user" -H mkdir gitlab-satellites
sudo -u "$user" -H mkdir tmp/pids
sudo -u "$user" -H mkdir tmp/sockets
sudo -u "$user" -H mkdir public/uploads
chmod -R u+rwX  tmp/pids/
chmod -R u+rwX  tmp/sockets/
chmod -R u+rwX  public/uploads/

# Unicorn config
sudo -u "$user" -H sed -r -e "s|/home/git|$folder|" config/unicorn.rb.example | sed -r -e "s|# user: git|user: $user|" >> unicorn.rb

# Enable DDOS middleware Rack Attack
sudo -u "$user" -H cp config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb
sudo -u "$user" -H sed -i "s|# config.middleware.use Rack::Attack|config.middleware.use Rack::Attack|" config/application.rb

# Git Config
sudo -u "$user" -H git config --global user.name "$user"
sudo -u "$user" -H git config --global user.email "$user@$domain"
sudo -u "$user" -H git config --global core.autocrlf input

# Database config
sudo -u "$user" -H sed -r -e "s|username: gitlab|username: $user|" config/database.yml.mysql | sed -r -e "s|password: \"secure password\"|password: $password|" >> config/database.yml
sudo -u "$user" -H chmod o-rwx config/database.yml


###
# Finilizing install
###
gem install charlock_holmes --version '0.6.9.4'
sudo -u "$user" -H bundle install --deployment --without development test postgres aws

if [[ $auto ]]; then
    sudo -u "$user" -H yes yes | bundle exec rake gitlab:setup RAILS_ENV=production
else
    sudo -u "$user" -H bundle exec rake gitlab:setup RAILS_ENV=production
fi


###
# Init Script
###
cp lib/support/init.d/gitlab /etc/init.d/gitlab
chmod +x /etc/init.d/gitlab
update-rc.d gitlab defaults 21
echo -e "app_user=$user \napp_root=$folder \n" >> /etc/default/gitlab
lib/support/logrotate/gitlab /etc/logrotate.d/gitlab


###
# Check and start GitLab
###
sudo -u "$user" -H bundle exec rake gitlab:env:info RAILS_ENV=production
service gitlab start
sudo -u "$user" -H bundle exec rake gitlab:check RAILS_ENV=production

###
# Nginx
###
sed "s|root /home/git/gitlab/public;|root $folder/public|" lib/support/nginx/gitlab | sed "s|server_name YOUR_SERVER_FQDN;|server_name $domain;|" >> /etc/nginx/sites-available/gitlab
ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
service nginx reload
