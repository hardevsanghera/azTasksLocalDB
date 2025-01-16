#!/bin/bash
#set -x
#steps to deploy django for prod use - the target Ubuntu VM has previously setup in Azure cloud, including userids and required s/w packages
#In addition the target ubuntu VM (which is the webserver too) has an ssh tunnel back to the MSSQL server which is the database engine for the Django App.
#Notes
#env:DJANGO_SETTINGS_MODULE='tut.settings.dev'
#env:DJANGO_SETTINGS_MODULE='tut.settings.prod'
#
#hardev@nutanix.com Jan '25'

#logged in as webadmin (a sudoer) on target Ubuntu VM
cd ~

#Variables
djangoProject="prodTasksProj"
djangoApp="prodTaskApp"
djangoBaseDir="djangoProjects"
djangoSecretKey="" #EDIT this
dbNAME="tasks",
dbUSER="SA",
dbPASSWORD="abcdefghij", #EDIT this
dbHOST="127.0.0.1",
dbPORT="8888",
mainSettings="settings.py"
localSettings="local_settings.py"
gunicornSocketFile="/etc/systemd/system/gunicorn.socket"
gunicornServiceFile="/etc/systemd/system/gunicorn.service"
nginxSitesFile="/etc/nginx/sites-available/$djangoProject"
gitrepo="https://github.com/hardevsanghera/prodTasksProj.git" #This is where the Django Tasks Application is
webadmin="webadmin"
group="www-data"
staticFiles="/var/www/django/static"
staticFilesRoot="/var/www/django"

#MSFT odbc driver for SQL Server install from: 
# https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server?view=sql-server-ver15&tabs=ubuntu18-install%2Cubuntu17-install%2Cdebian8-install%2Credhat7-13-install%2Crhel7-offline
if ! [[ "18.04 20.04 22.04 23.04 24.04" == *"$(lsb_release -rs)"* ]];
then
    echo "Ubuntu $(lsb_release -rs) is not currently supported.";
    exit;
fi
# Add the signature to trust the Microsoft repo
# For Ubuntu versions < 24.04 
curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
# For Ubuntu versions >= 24.04
curl https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
# Add repo to apt sources
curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
#disable interactive panel for "Daemons using outdated libraries" restart, just accept restarts
sudo sed -i "s/\#\$nrconf{restart} = 'i'/\$nrconf{restart} = 'a'/" /etc/needrestart/needrestart.conf
# Install the driver
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
# optional: for bcp and sqlcmd
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18
echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
source ~/.bashrc
# optional: for unixODBC development headers
#sudo apt-get install -y unixodbc-dev

#Add webadmin to nginx group, fix permissions on the static files folders
sudo usermod -a -G $group $webadmin
sudo mkdir -p $staticFiles
sudo chown -R $webadmin:$group $staticFilesRoot

#venv for the project
mkdir $djangoBaseDir
cd $djangoBaseDir

#Get the django Project/App
git clone $gitrepo
cd $djangoProject

#Setup virtual environment
python3 -m venv ./venv
source venv/bin/activate

#Install pip modules from requirements.txt
pip install -r requirements.txt

#Go to the django project directory
cd $djangoProject/$djangoProject

#add to settings.py
cat >> $mainSettings <<EOF
try:
  from .local_settings import *
except ImportError:
  pass
EOF

# SECURITY WARNING: keep the secret key used in production secret!
echo "SECRET_KEY = '$djangoSecretKey'" >> $localSettings

# SECURITY WARNING: don't run with debug turned on in production!
echo "DEBUG = False" >> $localSettings

myIP=`curl ident.me` #This is the public IP of the Ubuntu VM
echo "ALLOWED_HOSTS = ['$myIP']" >> $localSettings


# Database settings for MSSQL - there is a reverse ssh tunnel to the bakend MSSQL Server
cat >> $localSettings <<EOF

DATABASES = {
    'default': {
        'ENGINE': 'mssql' ,
        'NAME': '${dbNAME}' ,
        'USER': '${dbUSER}' ,
        'PASSWORD': '${dbPASSWORD}' ,
        'HOST': '${dbHOST}' ,
        'PORT': '${dbPORT}' ,
        'OPTIONS': {
            'driver': 'ODBC Driver 18 for SQL Server',
            'extra_params': "Encrypt=no" #TrustServerCertificate=no
        },
    },
}
EOF

#Fix weird insertion of extra "," in expanded variables
sed -i  "s/,'/'/g" $localSettings

echo "STATIC_URL = '/static/'" >> $localSettings

echo "STATIC_ROOT = '$staticFiles'" >> $localSettings

#Run migration/home/webadmin/djangoProj/prodTasksProj/prodTasksProjs
cd ..
python3 manage.py makemigrations
python3 manage.py migrate

#Create super user - get a "successfully created" but userid/pw doesn't work - the tasks application works OK.
DJANGO_SUPERUSER_PASSWORD=$dbPASSWORD python3 manage.py createsuperuser --username $webadmin --email webadmin@email.com --noinput

#Can now test the site at IP:8000/tasks
#python manage.py runserver 0.0.0.0:8000

#Collect static files
python manage.py collectstatic --no-input

#deactivate venv
deactivate

#add to this file
#/etc/systemd/system/gunicorn.socket
sudo bash -c "cat > $gunicornSocketFile" <<EOF
[Unit]
Description=gunicorn socket

[Socket]
ListenStream=/run/gunicorn.sock

[Install]
WantedBy=sockets.target
EOF

#Gunicorn service setup
#vi /etc/systemd/system/gunicorn.service
sudo bash -c "cat > $gunicornServiceFile" <<EOF
[Unit]
Description=gunicorn daemon
Requires=gunicorn.socket
After=network.target

[Service]
User=$webadmin
Group=$group
WorkingDirectory=/home/$webadmin/djangoProjects/$djangoProject/$djangoProject
ExecStart=/home/$webadmin/djangoProjects/$djangoProject/venv/bin/gunicorn --access-logfile - --workers 3  --bind unix:/run/gunicorn.sock  $djangoProject.wsgi:application         

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl start gunicorn.socket
sudo systemctl enable gunicorn.socket
sudo systemctl status gunicorn.socket
file /run/gunicorn.sock

#nginx setup
#sudo vi /etc/nginx/sites-available/prodTasksProj
sudo bash -c "cat > $nginxSitesFile" <<EOF
server {
    listen 80;
EOF
echo "server_name $myIP;" | sudo tee -a $nginxSitesFile
sudo bash -c "cat >> $nginxSitesFile" <<EOF
    location = /favicon.ico { access_log off; log_not_found off; }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/gunicorn.sock;
    }

    location /static/ {
        root $staticFilesRoot;
    }

}


EOF

#link
sudo ln -s /etc/nginx/sites-available/$djangoProject /etc/nginx/sites-enabled

#sudo systemctl restart nginx
sudo ufw delete allow 8000
sudo ufw allow 'Nginx Full'
sudo systemctl restart nginx

echo "====== Done, status of componenets ====="
systemctl status nginx
systemctl status gunicorn
systemctl status gunicorn.socket
file /run/gunicorn.sock
echo "====== Done ====="
