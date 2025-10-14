#!/usr/bin/env bash
set -e

sudo yum update -y
sudo yum install -y iperf3 curl httpd tc

# Enable ECN + DCTCP
sudo sysctl -w net.ipv4.tcp_ecn=1
sudo modprobe tcp_dctcp

# HTTP content
mkdir -p /var/www/html
dd if=/dev/zero of=/var/www/html/big.bin bs=1M count=200
for i in $(seq 1 20); do
  dd if=/dev/zero of=/var/www/html/seg${i}.ts bs=1M count=2
done

sudo systemctl enable httpd
sudo systemctl start httpd

# Iperf server
nohup iperf3 -s -p 5201 &
