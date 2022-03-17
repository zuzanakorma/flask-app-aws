#!/bin/bash

# This script is to be used with AWS EC2 user-data
# where the commands are run as root user, reason
# for not using sudo and also changing directories
# and files ownership to ec2-user (this demo uses AWS Linux)


# ====
# This section install git (missing in AWS Linux), clone the 
# application repo in the ec2-user home directory (security, we
# don't want apps running as root user), creates a virtualenv for
# Python to keep dependencies tracked, install the requirements once
# the environment is activated, and create an empty database with the
# schema. It's important to deactivate the environment because further
# in the script when installing Nginx, if the environment is activated,
# the command 'amazon-linux-extras' fails due to system Python dependencies

yum install -y git

cd /home/ec2-user/
git clone https://github.com/zuzanakorma/flask-app-aws.git

cd flask-app-aws/
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt 

python -c 'import app;app.db.create_all()'
deactivate
# ====

# ====
# This is to address the ownsership of files/directories when
# using AWS EC2 user-data. We want to make sure to set the right
# owner for our application
cd ..
chown -R ec2-user:ec2-user flask-app-aws/
# ====

# ====
# This section makes sure the application is installed as a 
# service in the Linux machine, so in case of an outage in the
# AWS instance, such as restart, the application starts automatically
# when the instance is back. 

# create multiline file for flaskapp.service
tee /etc/systemd/system/flaskapp.service <<EOF
[Unit]
Description=Gunicorn instance for a simple flask app
After=network.target
[Service]
User=ec2-user
Group=ec2-user
WorkingDirectory=/home/ec2-user/flask-app-aws
ExecStart=/home/ec2-user/flask-app-aws/venv/bin/gunicorn -b localhost:8080 app:app
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Every time you create a new service file in Systemd, you have to reload
# the daemon to detect the file
systemctl daemon-reload
systemctl start flaskapp
systemctl enable flaskapp
systemctl status flaskapp
# ====

# ====
# This section installs Nginx using 'amazon-linux-extras'
# because it is not available in 'yum' for AWS Linux. The
# reason for using Nginx is because we want to secure our 
# application that uses gunicorn as the WSGI, which is listening
# in localhost and port 8080. In that way, we place on front of it
# the Nginx server to act as a reverse proxy where later on
# we can add additional configuration such as SSL certificates for 
# HTTPS, or create more complex redirection logic for 'locations'

amazon-linux-extras install -y nginx1
# create multiline file for nginx configuration
tee /etc/nginx/conf.d/flaskapp.conf <<EOF
upstream flaskapp {
  server 127.0.0.1:8080;
}
EOF

tee /etc/nginx/default.d/flaskapp.conf <<EOF
location / {
  # pass requests to the Flask host
  proxy_pass http://flaskapp;
}
EOF

systemctl start nginx
systemctl enable nginx
systemctl status nginx
# ====