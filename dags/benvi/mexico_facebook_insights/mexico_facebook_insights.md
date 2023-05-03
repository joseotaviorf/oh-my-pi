## Mexico Facebook Insights

### Purpose

This DAG brings our marketing campaigns data from facebook platform related to our Performance Supply and Demand Benvi operation on Mexico.

We implemented an [API client](https://github.com/quintoandar/facebook-api-client-python) for usage in raw. We have a yaml file (facebook_insights_config) to define some columns and configs about the ingestion instead of using airflow variables.

Since social account has a special breakdown/field treatment, we decided to separate this account from others.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw, staging (clean) and clean layers, by incremental load:

- `facebook_insights`, which has data from the following accounts: MX - Performance - Demand (539892317592968), MX - Performance - Supply (728657465218917)
