## Firestore

### Purpose
Firestore DAG retrieves Firestore audit data from Google Cloud Platform Pub/Sub subscriptions. It uses [Cloud Pub/Sub SDK for Python](https://cloud.google.com/pubsub/docs/pull#synchronous_pull), which invokes a subscriber client that calls synchronous batch pulls from the listed subscriptions, retrieving "messages" and quiting the calls when no message is returned after multiple requests in a exponentially increasing interval. Finally, the `acknowledge` call is executed to inform Pub/Sub that the messages retrieved by the subscriber can be dumped in the service.

Pub/Sub, which stands for Publisher/Subscriber, is used for streaming analytics and data integration pipelines to ingest and distribute data, allowing services to communicate asynchronously.

The Firestore's messages containing new offers with the submission date are originally posted on the [offer-topic](https://console.cloud.google.com/cloudpubsub/topic/detail/offer-topic?project=quintoandar-com-br-pwa) and than loaded to [offers-audit-topic](https://console.cloud.google.com/cloudpubsub/topic/detail/offers-audit-topic?project=quintoandar-com-br-pwa) by the [firestore-audit](https://github.com/quintoandar/firestore-audit) project through [audit-offersOnWrite](https://console.cloud.google.com/functions/details/us-central1/audit-offersOnWrite?env=gen1&project=quintoandar-com-br-pwa) Cloud Run Function. This proccess will stop working on 2025-01-30 due to the Node.js 16 deprecation by Google.

### Important notes when testing Pub/Sub
---

**⚠️ MESSAGES ARE TRANSIENT:**

- Messages stored in Pub/Sub are transient, therefore if a message is retrieved and is succeeded by an `acknowledge` call, the message is dumped from the subscrition and may not be retrieved again if the `Retain acknowledged messages` subscription configuration in GCP is set to `No`.

**⚠️ SUBSCRIPTIONS MAY HAVE LIMITED DELIVERY ATTEMPTS:**

- Subscriptions may have configured a maximum number of delivery attempts (default is 5). When a message fails to be delivered, subscriptions may republish it to a specified dead letter topic.
- Be aware that if no `acknowledge` call happens until the acknowledgement deadline time is reached, Pub/Sub will consider this as an attempt of delivery.
- After a successfull delivery with no `acknowledge` calls, Pub/Sub may delay new deliveries in a exponential interval when set (check `Retry policy` configuration) or republish it to a dead letter topic when a delivery attempt limit is reached (check `Maximum delivery attempts` and `Dead letter topic` configurations).


**⚠️ WRITE MODE IS SET TO APPEND:**

- Data is appended when loaded, due to the absense of date filters in Pub/Sub service.
- As message deliveries are defined with the "at least once" nature, **there is the possibility of duplicated rows when jobs with the same execution date are executed more than once.**

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Subscriptions currently subscribed by this pipeline

- [`domainSaleOffer-audit-data-engineering-subscription`](https://console.cloud.google.com/cloudpubsub/subscription/detail/domainSaleOffer-audit-data-engineering-subscription?project=quintoandar-com-br-pwa)
- [`offers-audit-data-engineering-subscription`](https://console.cloud.google.com/cloudpubsub/subscription/detail/offers-audit-data-engineering-subscription?project=quintoandar-com-br-pwa)
- [`mondayBoard-audit-data-engineering-subscription`](https://console.cloud.google.com/cloudpubsub/subscription/detail/mondayBoard-audit-data-engineering-subscription?project=quintoandar-com-br-pwa)

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake's `raw` layer:
    - `datalake_firestore_raw.monday`
    - `datalake_firestore_raw.rent_offer`
    - `datalake_firestore_raw.sale_offer`
- In datalake's `clean` layer:
    - `datalake_firestore_clean.monday`
    - `datalake_firestore_clean.rent_offer`
    - `datalake_firestore_clean.sale_offer`

</details>
