## Reverse DSAT Report Access

### Purpose
This DAG consolidates data from DSAT.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>


### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline exports the following tables from the reverse_dsat_report schema to an S3 Bucket:

- `sale_dsat_report`

This pipeline also exports results to a SQS Queue (`arn:aws:sqs:us-east-1:569412621543:FornoRiskAndMortgageCustomerSatisfaction`).

</details>
