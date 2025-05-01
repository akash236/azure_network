#!/bin/bash

# Variables
RESOURCE_GROUP="network-rg"
LOCATION="australiaeast"
HUB_VNET_NAME="hub-vnet"
SPOKE_VNET_NAME="spoke-vnet"
HUB_VNET_ADDRESS="10.0.0.0/16"
SPOKE_VNET_ADDRESS="10.1.0.0/16"
FIREWALL_SUBNET="10.0.0.0/24"
HUB_SUBNET="10.0.1.0/24"
SPOKE_SUBNET="10.1.0.0/24"
FIREWALL_NAME="hub-firewall"
DESKTOP_IP="YOUR_DESKTOP_IP_HERE"  # Replace with your desktop's public IP address

# Create Resource Group
echo "Creating Resource Group..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Hub VNet with subnets
echo "Creating Hub VNet..."
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $HUB_VNET_NAME \
  --address-prefix $HUB_VNET_ADDRESS \
  --subnet-name DefaultSubnet \
  --subnet-prefix $HUB_SUBNET

# Create a dedicated subnet for Azure Firewall (must be named 'AzureFirewallSubnet')
echo "Creating Firewall Subnet..."
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $HUB_VNET_NAME \
  --name AzureFirewallSubnet \
  --address-prefix $FIREWALL_SUBNET

# Create Spoke VNet with subnet
echo "Creating Spoke VNet..."
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $SPOKE_VNET_NAME \
  --address-prefix $SPOKE_VNET_ADDRESS \
  --subnet-name DefaultSubnet \
  --subnet-prefix $SPOKE_SUBNET

# Peer Hub VNet to Spoke VNet
echo "Creating VNet Peering (Hub to Spoke)..."
az network vnet peering create \
  --resource-group $RESOURCE_GROUP \
  --name HubToSpoke \
  --vnet-name $HUB_VNET_NAME \
  --remote-vnet $SPOKE_VNET_NAME \
  --allow-vnet-access \
  --allow-forwarded-traffic

# Peer Spoke VNet to Hub VNet
echo "Creating VNet Peering (Spoke to Hub)..."
az network vnet peering create \
  --resource-group $RESOURCE_GROUP \
  --name SpokeToHub \
  --vnet-name $SPOKE_VNET_NAME \
  --remote-vnet $HUB_VNET_NAME \
  --allow-vnet-access \
  --allow-forwarded-traffic

# Create a public IP for the Firewall
echo "Creating public IP for Firewall..."
az network public-ip create \
  --resource-group $RESOURCE_GROUP \
  --name fw-pip \
  --sku Standard \
  --allocation-method Static

# Create Firewall
echo "Creating Azure Firewall..."
az network firewall create \
  --resource-group $RESOURCE_GROUP \
  --name $FIREWALL_NAME \
  --location $LOCATION

# Configure Firewall IP
echo "Configuring Firewall IP..."
az network firewall ip-config create \
  --resource-group $RESOURCE_GROUP \
  --firewall-name $FIREWALL_NAME \
  --name fw-ip-config \
  --public-ip-address fw-pip \
  --vnet-name $HUB_VNET_NAME

# Create network rule to allow desktop IP to access private IPs
echo "Creating Network Rule Collection..."
az network firewall network-rule create \
  --resource-group $RESOURCE_GROUP \
  --firewall-name $FIREWALL_NAME \
  --collection-name desktop-access-rules \
  --priority 100 \
  --action Allow \
  --name allow-desktop-to-private \
  --protocols "Any" \
  --source-addresses $DESKTOP_IP \
  --destination-addresses "10.0.0.0/16" "10.1.0.0/16" \
  --destination-ports "*"

# Create route table for spoke VNet
echo "Creating route table for spoke VNet..."
az network route-table create \
  --resource-group $RESOURCE_GROUP \
  --name spoke-route-table

# Get Firewall private IP
FIREWALL_PRIVATE_IP=$(az network firewall show \
  --resource-group $RESOURCE_GROUP \
  --name $FIREWALL_NAME \
  --query "ipConfigurations[0].privateIpAddress" \
  --output tsv)

# Create route for traffic to go through Firewall
echo "Creating route for traffic through Firewall..."
az network route-table route create \
  --resource-group $RESOURCE_GROUP \
  --route-table-name spoke-route-table \
  --name to-hub \
  --address-prefix "0.0.0.0/0" \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address $FIREWALL_PRIVATE_IP

# Associate route table with spoke subnet
echo "Associating route table with spoke subnet..."
az network vnet subnet update \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $SPOKE_VNET_NAME \
  --name DefaultSubnet \
  --route-table spoke-route-table

echo "Setup complete!"
echo "Hub VNet: $HUB_VNET_NAME ($HUB_VNET_ADDRESS)"
echo "Spoke VNet: $SPOKE_VNET_NAME ($SPOKE_VNET_ADDRESS)"
echo "Firewall: $FIREWALL_NAME"
echo "Traffic from your desktop IP ($DESKTOP_IP) is allowed to private IPs in both VNets"
