## Enrich Marketing Costs Facebook Insights

### Purpose

Marketing Costs Facebook Insights gathers information about Facebook media costs performed by marketing team. The enrich process:

- Creates a composite key for sk_ad
- Maps id_account to account_name (acc)
- Creates a Boolean column to verify test campaigns (is_test_campaign)

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables in our enrich layer:

- `facebook_insights`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).