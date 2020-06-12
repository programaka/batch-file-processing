# Dapr - Batch File Processing End to End Sample

This sample demonstrates an end to end sample for processing a batch of related text files using microservices and Dapr. Through this sample you will learn about Dapr's state management, bindings, pub sub, and end to end tracing.

## Scenario

An enterprise receives sales orders from distributors via CSV files, similar to that of many businesses. These files come in batches. Each batch is made up of exactly three different files, each with different information about orders. Here is an example of a batch:

`20180518151300-OrderHeaderDetails.csv`

`20180518151300-OrderLineItems.csv`

`20180518151300-ProductInformation.csv`

Files from the same batch have the same prefix, a date time format. These files can arrive in any order and at different times, so we need wait until all the files for the same batch arrive before processing them. The processing of a batch consists of combine the content of all three these files, converting them from CSV to one JSON per order, and storing each order into a data store.

## Solution

This sample implementation for the batch file processing scenario combines Dapr and Azure. As Dapr is cloud independent it would be possible to reimplement the solution using non-Azure or different Azure components. In this sample Azure services like Service Bus and Cosmos DB, App Insight as a back-end for tracing are used, but other services could be used; for example, instead of using Service Bus as a message broker, Redis Streams or Google Cloud Pub/Sub could be used. The same would apply for state store, output binding to database, and tracing.

Azure Storage receives batches of files (from the batch generator simulator). Each file will trigger an Event Grid notification to a Batch Receiver microservice that uses state management to identify when all files for a batch have arrived. Then Pub Sub is used to trigger a Batch Processor that will transform the batches into individual JSON based orders, and save to Cosmos DB. Dapr's end to end tracing is used to send tracing information to App Insights. Pub Sub is used to provide a layer of load levelling and for scaling the Batch Processor using KEDA, as the processor does the bulk of the processing work.

![Solution Diagram](images/solution-diagram.png)

In this reference implementation the following components are used.

### Components

`Storage` - Azure Blob Storage is where the batches of files will arrive. This sample includes a Batch Generator to simulate distributors sending  batches of files into storage.

`Event Grid` - Event Grid is used to send event notifications of new blobs (each file in the batches) to the ingress controller of Kubernetes (Nginx in this sample).

`Kubernetes/Azure Kubernetes Service (AKS)` - used to orchestrate and host the containers and their Dapr sidecars for the microservices implemented by this sample, as well as Nginx and the Redis instance used by the solution.

`Ngix` - the ingress controller for Kubernetes used in this sample that will receive the notifications from Event Grid about new blobs in storage and route them to the Batch Processor microservice.

`Batch Generator` - a node app microservice that simulates distributors generating CSV files with order information and sends them to `Storage` every 1 min.

`Batch Receiver` - a node app microservice running in Kubernetes that gets called for each CSV file. It has a Dapr sidecar to provide tracing, state management, and pub sub features. It extracts the file prefix as a batch id, then uses that batch id as the key for writing to Dapr's state management, keeping track of what files arrived for each batch. It uses Dapr's state management with `Redis` to get and update the state **(link)**. Once a batch has all 3 files, Batch Receiver will put a message into Dapr pub-sub (batchReceived topic) using `Service Bus` as a message broker.

`Batch Processor` - a node app microservice triggered from Dapr's pub-sub. It has a Dapr sidecar to provide tracing, pub sub, and output binding features. It subscribes to messages from the batchReceived topic and when a message is received, it will fetch all the the three files for a batch from storage, transform them into an array of JSON orders and store each JSON order into `Cosmos DB`. It uses Dapr's Cosmos DB output binding to store the data. This microservice is scaled using `KEDA`.

`KEDA` - [Kubernetes-based Event Driven Autoscaling](https://github.com/kedacore/keda). Used to scale out the Batch Processor based on the number of unprocessed messages in the Service Bus topic used between the microservices for pub-sub.

`Cosmos DB` - the NoSQL data store used by the sample to store the individual orders in JSON format. This would then be used downstream by other solutions in the company.

`App Insights` - Azure App Insights is used for all the end to end tracing created by Dapr for the microservices in the solution.

## Deployment

### Prerequisites

* Docker
* kubectl
* Azure CLI
* Helm3

### Set up Cluster

In this sample we'll be using AKS, but you can install Dapr on any Kubernetes cluster.

Login to Azure:

```Shell
az login
```

Set the default subscription:

```Shell
az account set -s <subscription_id>
```

Create a resource group:

```Shell
az group create --name <resource_group> --location <location> (ex: westus)
```

Create an Azure Kubernetes Service cluster:

```Shell
az aks create --resource-group <resource-group> --name <cluster_name> --node-count 2 --kubernetes-version 1.14.8 --enable-addons http_application_routing --enable-rbac --generate-ssh-keys
```

References:

* [Deploy AKS using Portal](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough-portal)
* [Deploy AKS using CLI](https://github.com/dapr/docs/blob/master/getting-started/cluster/setup-aks.md)
* [Setup Cluster](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#setup-cluster)

### Install Dapr

* [Install Dapr CLI](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#installing-dapr-cli)
* [Install Dapr in standalone mode](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#installing-dapr-in-standalone-mode)
* [Install Dapr on a Kubernetes cluster using Helm](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md#using-helm-advanced)

References:
[Dapr Environment Setup](https://github.com/dapr/docs/blob/master/getting-started/environment-setup.md)

### Create Blob Storage

1. Create a storage account of kind StorageV2 (general purpose v2) in your Azure Subscription:

    ```Shell
    az storage account create \
        --name <storage-account> \
        --resource-group <resource-group> \
        --location <location> \
        --sku Standard_RAGRS \
        --kind StorageV2
    ```

2. Create a new blob container in your storage account in the [Azure Portal](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-portal) or using [CLI](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-cli):

    ```Shell
    az storage container create \
        --account-name <storage-account> \
        --name <container>
    ```

3. In the portal, generate SAS token for your storage account.

4. Replace <storage_account_base_url> in [/batchProcessor/configMap.yaml](/batchProcessor/configMap.yaml).

5. Replace <storage_sas_token> in [/batchProcessor/configMap.yaml](/batchProcessor/configMap.yaml) with
the SAS token that you generated.

6. Replace <storage_account_name> and <storage_account_access_key> with your account name and key (Azure Portal -> Storage Account -> Access keys):
    * [deploy/blob-storage.yaml](deploy/blob-storage.yaml)
    * [components/blob-storage.yaml](components/blob-storage.yaml)

### Set up public IP, domain name and HTTPS

In our solution we're using the NGINX ingress controller as an entry point to our Azure Kubernetes Service (AKS) cluster. Follow [this guide](https://docs.microsoft.com/en-us/azure/aks/ingress-static-ip) to deploy the NGINX ingress controller with a static public IP address and map a DNS name to the public IP.

Event Grid Web Hook which we'll be configuring in the next step has to be HTTPS and self-signed certificates are not supported, it needs to be from a certificate authority. We will be using the cert-manager project to automatically generate and configure Let's Encrypt certificates.

Copy the domain name, we will need it in the next step.

### Subscribe to the Blob Storage

Now we need to subscribe to a topic to tell Event Grid which events we want to track, and where to send the events.

1. In the portal, navigate to your Azure Storage account that you created earlier.
2. On the Storage account page, select Events on the left menu.
3. Create new Event Subscription:
    1. Enter a name for the event subscription.
    2. Select Blob Created event in the Event Types drop-down.
    3. Select Web Hook for Endpoint type.
    4. Select an endpoint where you want your events to be sent to (https://<domain_name>/api/blobAddedHandler).

References:
[Subscribe to the Blob storage](https://docs.microsoft.com/en-us/azure/event-grid/blob-event-quickstart-portal?toc=%2fazure%2fstorage%2fblobs%2ftoc.json#subscribe-to-the-blob-storage)

### Create a Data Store for storing orders

In our sample we are using Cosmos DB, but you can pick any data store that dapr integrates with ([Dapr Bindings](https://github.com/dapr/docs/tree/master/concepts/bindings)).

1. Create an Azure Cosmos DB account, database and container in the [Azure Portal](https://docs.microsoft.com/en-us/azure/cosmos-db/create-cosmosdb-resources-portal) or using [CLI](https://docs.microsoft.com/en-us/cli/azure/cosmosdb?view=azure-cli-latest).

2. Create an Azure Cosmos DB database account:

    ```Shell
    az cosmosdb create \
        --name <storage-account> \
        --resource-group <resource-group> \
    ```

3. Create a database:

    ```Shell
    az cosmosdb database create \
        --name <storage-account> \
        --resource-group <resource-group> \
        --db-name IcecreamDB
    ```

4. Create Orders container:

    ```Shell
    az cosmosdb sql container create \
        --account-name <storage-account>
        --database-name IcecreamDB \
        --name Orders \
        --partition-key-path "/id" \
        --resource-group <resource-group>
    ```

5. Set DB URL, DB key, database and container name in
    * [deploy/cosmosdb-orders](/deploy/cosmosdb-orders)
    * [components/cosmosdb-orders](/components/cosmosdb-orders)

### Redis

1. Follow [this tutorial](https://github.com/RicardoNiepel/dapr-docs/blob/master/howto/setup-state-store/setup-redis.md) on how to create a Redis Cache in your Kubernetes Cluster using Helm.

2. Set Redis password in [deploy/statestore.yaml](/deploy/statestore.yaml).

References:
[Setup a Dapr state store](https://github.com/dapr/docs/tree/master/howto/setup-state-store)

### Dapr pub/sub

In this sample we used Azure Service Bus as a message broker. Follow [these instructions](https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-topics-subscriptions-portal) to create Azure Service Bus namespace. The topic will be created automatically when the code is run.

Replace <namespace_connection_string> with your connection string in these files:

* [components/messagebus.yaml](/components/messagebus.yaml)
* [deploy/messagebus.yaml](/deploy/messagebus.yaml)

References:

* [Setup a Dapr pub/sub](https://github.com/dapr/docs/tree/master/howto/setup-pub-sub-message-broker)
* [Setup Azure Service Bus](https://github.com/dapr/docs/blob/master/howto/setup-pub-sub-message-broker/setup-azure-servicebus.md)

### Set up distributed tracing

#### Application Insights

1. Follow [this guide](https://docs.microsoft.com/en-us/azure/azure-monitor/app/create-new-resource) to create an Application Insights resource.
2. Copy the value of the *Instrumentation Key*.

#### LocalForwarder

1. Open the [deployment file](/deploy/localforwarder-deployment.yaml) and set the Instrumentation Key value.
2. Deploy the LocalForwarder to your cluster.

   ```Shell
   kubectl apply -f ./deploy/localforwarder-deployment.yaml
   ```

#### Dapr tracing

1. Deploy the dapr tracing configuration:

   ```Shell
   kubectl apply -f ./deploy/dapr-tracing.yaml
   ```

2. Deploy the exporter:

   ```Shell
   kubectl apply -f ./deploy/dapr-tracing-exporter.yaml
   ```

### KEDA

1. [Deploy KEDA with Helm](https://keda.sh/docs/1.4/deploy/#helm).
2. In the Azure Portal, go to your Service Bus topic and create a Shared Access Policy of type Manage. Copy the connection string.
3. Create a base64 representation of the connection string and update [deploy/batch-processor-keda.yaml](/deploy/batch-processor-keda.yaml) file.

References:
[Azure Service Bus Scaler](https://keda.sh/docs/1.4/scalers/azure-service-bus/)

### Deploy the services to AKS

First, we need to create an image and push it to the Azure Container Registry (ACR).

1. Create a container registry using the Azure CLI:

    ```Shell
    az acr create --resource-group <resource-group> --name <container_registry> --sku Basic
    ```

    Take note of loginServer in the output.

2. Log in to the registry:

    ```Shell
    az acr login --name <registry_name>
    ```

3. Build an image from a Dockerfile (for batchProcessor):

    ```Shell
    cd <workspace_folder>
    docker build -t batch-processor:v1 batchProcessor
    ```

4. Tag the image:

    ```Shell
    docker tag batch-processor:v1 <registryLoginServer>/batch-processor:v1
    ```

5. Push the image to the Azure Container Registry instance.

    ```Shell
    docker push <registryLoginServer>/batch-processor:v1
    ```

6. Run [scripts/deploy_generator.ps1](scripts/deploy_generator.ps1) and [scripts/deploy_receiver.ps1](scripts/deploy_receiver.ps1) to deploy batchGenerator and batchReceiver.

7. Replace `registryLoginServer` with your registryLoginServer in:
    * [deploy/batch-generator.yaml](deploy/batch-generator.yaml)
    * [deploy/batch-processor-keda.yaml](deploy/batch-processor-keda.yaml)
    * [deploy/batch-receiver.yaml](deploy/batch-receiver.yaml)

8. Deploy Dapr components:

    ```Shell
    kubectl apply -f ./deploy/statestore.yaml
    kubectl apply -f ./deploy/cosmosdb-orders.yaml
    kubectl apply -f ./deploy/messagebus.yaml
    kubectl apply -f ./deploy/blob-storage.yaml
    ```

9. Deploy services:

    ```Shell
    kubectl apply -f ./deploy/batch-generator.yaml
    kubectl apply -f ./deploy/batch-receiver.yaml
    kubectl apply -f ./deploy/batch-processor-keda.yaml
    ```

References:
[Create a private container registry using the Azure CLI](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-get-started-azure-cli)
