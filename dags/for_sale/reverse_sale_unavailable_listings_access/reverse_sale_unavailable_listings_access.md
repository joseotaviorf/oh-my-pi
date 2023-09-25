## Reverse Unavailable Listings Access

### Purpose
This DAG has the purpose of making available to the product a list of listings of the platform that we have some suspicion of unavailability. With this, we will send an HSM to these sellers to confirm availability.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>


### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline exports the following tables from the reverse_sale_unavailable_listings schema to an S3 Bucket:

- `suspected_unavailable_listings`

This pipeline also exports results to bucket (`sale-unavailable-listings-s3-data-quintoandar-com-br`).

</details>
