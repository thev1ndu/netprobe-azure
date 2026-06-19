# Resource group & location
RG="rg-thevindu"
LOCATION="eastus2"

# Networking
VNET="vnet-aks-private"
AKS_SUBNET="snet-aks"
JUMP_SUBNET="snet-jumphost"

# Cluster & jumpbox
AKS_NAME="aks-wso2is"
VM_NAME="aks-jumphost"

# Storage & registry
STORAGE_ACCOUNT="sa18436"
SHARE_NAME="fileshare"
ACR_NAME="acrrrrrrrr"
Derived values (fetched from Azure — run after the static block):

# AKS subnet ID (needed when creating the cluster)
AKS_SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RG \
  --vnet-name $VNET \
  --name $AKS_SUBNET \
  --query id -o tsv)
echo "AKS_SUBNET_ID=$AKS_SUBNET_ID"

# Storage account key (needed for File Share operations and the ADO secret)
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RG \
  --account-name $STORAGE_ACCOUNT \
  --query "[0].value" -o tsv)
echo "STORAGE_KEY=<masked>"

# Jumpbox public IP (needed for manual SSH access)
VM_PUBLIC_IP=$(az vm show \
  --resource-group $RG \
  --name $VM_NAME \
  -d \
  --query publicIps -o tsv)
echo "VM_PUBLIC_IP=$VM_PUBLIC_IP"

# ACR login server (needed for image push/pull)
ACR_LOGIN_SERVER=$(az acr show \
  --resource-group $RG \
  --name $ACR_NAME \
  --query loginServer -o tsv)
echo "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER"

# Kubelet identity client ID (needed to grant AcrPull)
KUBELET_CLIENT_ID=$(az aks show \
  --resource-group $RG \
  --name $AKS_NAME \
  --query identityProfile.kubeletidentity.clientId -o tsv)
echo "KUBELET_CLIENT_ID=$KUBELET_CLIENT_ID"

az vmss create \
  --resource-group $RG \
  --name is-vmss \
  --orchestration-mode Uniform \
  --image Ubuntu2204 \
  --vm-sku Standard_B2s \
  --instance-count 1 \
  --vnet-name $VNET \
  --subnet $JUMP_SUBNET \
  --admin-username azureuser \
  --authentication-type ssh \
  --generate-ssh-keys \
  --custom-data cloud-init.yaml \
  --public-ip-address "" \
  --load-balancer ""