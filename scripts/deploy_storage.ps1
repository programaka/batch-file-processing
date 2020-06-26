Write-Host "Creating storage account..."
az storage account create `
    --name <storage-account-name> `
    --resource-group <resource-group-name> `
    --location <location> `
    --sku Standard_RAGRS `
    --kind StorageV2

Write-Host "Creating blob container..."
az storage container create `
    --name orders `
    --account-name <storage-account-name> `
    --auth-mode login

Write-Host "Generating SAS..."
az storage account generate-sas `
    --account-name <storage-account-name> `
    --expiry <YYYY-MM-DD> `
    --https-only `
    --permissions rwdlacup `
    --resource-types c `
    --services b

Write-Host "Getting storage account access keys..."
az storage account keys list --account-name <storage-account-name>
