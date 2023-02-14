## DW Sale Offer Users

### Purpose

This DAG creates the models for Sale Offer Users via full loading.

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `sale`:

- `dim_sale_offer_user_info`
- `dim_sale_offer_user`
- `fact_sale_offer_users`
