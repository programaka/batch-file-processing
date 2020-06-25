az login
az account set -s <subscription-id>
az group create --name <resource-group-name> --location <location> # ex: westus2
az aks create --resource-group <resource-group-name> --name <cluster-name> --node-count 2 --kubernetes-version 1.14.8 --enable-addons http_application_routing --generate-ssh-keys --location westus2

# Connect to the cluster
az aks get-credentials --resource-group <resource-group-name> --name <cluster-name>