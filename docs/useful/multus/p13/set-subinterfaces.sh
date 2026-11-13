#!/bin/bash

ssh k8s-worker1 ip link add link e2 name e2.1000 type vlan id 1000
ssh k8s-worker1 ip link add link e2 name e2.1001 type vlan id 1001
ssh k8s-worker2 ip link add link e2 name e2.1000 type vlan id 1000
ssh k8s-worker2 ip link add link e2 name e2.1001 type vlan id 1001
ssh k8s-worker1 ip link set e2.1000 up
ssh k8s-worker1 ip link set e2.1001 up
ssh k8s-worker2 ip link set e2.1000 up
ssh k8s-worker2 ip link set e2.1001 up
