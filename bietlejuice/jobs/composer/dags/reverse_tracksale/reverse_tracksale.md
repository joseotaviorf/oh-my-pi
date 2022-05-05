## Reverse Tracksale
### Purpose
This DAG collects customer data from our DW layer and sends it to the Tracksale API in order to schedule NPS survey dispatches.

Tracksale is an external service that monitors in real time the customer’s experience. We use it to manage NPS and customer reviews.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We incrementally load the following table into the Datalake Reverse bucket, for backup pourposes:

- `lost_buyer_proposals`
- `lost_buyer_visits`
- `lost_iq_proposals`
- `lost_iq_rejected`
- `lost_iq_visitas`
- `lost_pp`
- `lost_seller_unpublished`
- `true_buyer_ccv_central`
- `true_buyer_ccv_hub`
- `true_buyer_ccv`
- `true_buyer_registry`
- `true_offboarding_iq`
- `true_offboarding_pp`
- `true_onboarding_iq`
- `true_onboarding_pp`
- `true_ongoing_iq`
- `true_ongoing_pp`
- `true_seller_ccv_central`
- `true_seller_ccv_hub`
- `true_seller_ccv`
- `true_seller_registry`

This pipeline also POST data to the Tracksale API (endpoint: `dispatches`) aiming to schedule NPS survey dispatches.

For further information, please read [this documentation](https://docs.google.com/document/d/15YEa41mdZ2YRUgpKpMNK63sIrHhCSXAYuf2QbW_Df7E).

</details>
