## Scenario
Best For You Organics Company (BFYOC) receives orders from distributors via CSV files, similar to that of many businesses. These files come in batches. Each batch is made up of exactly three different files, each with different information about orders. Here is an example of a batch.

* `20180518151300-OrderHeaderDetails.csv`
* `20180518151300-OrderLineItems.csv`
* `20180518151300-ProductInformation.csv`

Files from the same batch have the same prefix. Each file can come in at different times, so we need wait until all the files for the same batch arrive before processing them. Then we need to combine the content of these files and store each order into a data store.

## Components
`Batch Generator` - node app that generates CSV files with order information and sends them to `Blob Storage` every 1 min.
As soon as a new file is added to the storage, `Event Grid` is going to call `Batch Receiver`, which is another node app running in Kubernetes and what it does it stores the names of the files into a state store (`Redis`) using batch id as a key (to keep track of what files arrived for each batch). And here I am using Dapr state bindings to get and update the state (link).
Once a batch has all 3 files, Batch Receiver will put a message into Dapr pub-sub (batchReceived topic) using `Service Bus` as a message broker.
`Batch Processor`, which is another node app, is subscribed to receive messages for batchReceived topic and when a message is received, it will fetch files from the blob storage, transform them into orders and store them into `Cosmos DB`. And here I am using Dapr Cosmos DB output binding to store the data.
For scaling we’ll use `KEDA` - Event-driven Autoscaler. It will scale our Batch Processor based on the number of messages in the Service Bus queue.
One thing to notice, here I used Azure services like Service Bus and Cosmos DB, App Insight as a back-end for tracing, but Dapr integrates with a few other services within Azure and outside of Azure. For example, instead of using Service Bus as a message broker I could use Redis Streams or Google Cloud Pub/Sub, same for the state store, database and back-end for tracing.

<img src="images/solution-diagram.png">

## Debugging
There are 3 debug configurations in launch.json for each app.

to be continued...