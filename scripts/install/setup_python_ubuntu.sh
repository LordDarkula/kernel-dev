#!/bin/sh

sudo apt install -y python3
sudo apt install -y python3-pip
sudo apt install -y python3-venv

python3 -m venv venv
source venv/bin/activate

pip install -e .
