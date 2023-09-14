## Reverse CCV Price Report Access
### Purpose
This DAG is responsible for exporting the data aggregated by DAG `reverse_ccv_price_report_load`. With this, we will make it available via SNS to the product team (Reports). 

Like the Load DAG, we will run monthly.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>


### Execution Interval

Monthly. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline exports the following tables from the reverse_ccv_price_report schema to an SNS:

- `ccv_price_by_region`

</details>