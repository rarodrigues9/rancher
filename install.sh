#!/bin/bash

sudo curl https://releases.rancher.com/install-docker/20.10.sh | sh
sudo usermod -aG docker vagrant
sudo apt install git -y
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose