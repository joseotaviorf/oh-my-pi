## Facebook Insights

### Purpose

Facebook Insights brings our marketing campaigns data from facebook platform. We implemented an [API client](https://github.com/quintoandar/facebook-api-client-python) for usage in raw. We have a yaml file (facebook_insights_config) to define some columns and configs about the ingestion instead of using airflow variables.

Since social account has a special breakdown/field treatment, we decided to separate this account from others.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw, staging (clean) and clean layers:

- `facebook_insights`
- `facebook_social_insights`
