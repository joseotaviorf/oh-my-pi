## Reverse Nazaré

### Purpose

This DAG collects multiple data from Datalake and sends to an S3 bucket used to power Nazaré service.
Nazaré is an internal QuintoAndar service for managing variable revenue share calculations.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We incrementally load the following table into the Datalake Reverse bucket, for backup pourposes:

- `agent`
- `brokerage_fee_baseline`
- `business_unit`
- `offer_agent`
- `offer_partner`
- `offer`
- `partner`
- `tier_bonus`

This pipeline also exports results do Nazaré bucket (`s3://nazare-revenue-share-{ENV}`).

For further information, please read [this documentation](https://docs.google.com/document/d/15YEa41mdZ2YRUgpKpMNK63sIrHhCSXAYuf2QbW_Df7E).

</details>
