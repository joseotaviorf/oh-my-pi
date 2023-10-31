## Cypress Reports

### Purpose

Cypress is an End to End testing framework used by the product team here at Quinto Andar. This DAG retrieves JSON data from Cypress' reports in S3 source bucket and make it available for the QAs to analyse.


​<details>
### Execution Interval

This DAG runs daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables for both our raw and clean layers: 

- `execution`
- `suites`
- `tests`

</details>