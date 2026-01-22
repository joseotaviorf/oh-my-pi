## DW Sale Offers Test

### Purpose

This DAG creates the model for Sale Offers via full loading.

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `sale`:

- `dim_offer`
- `dim_sale_agreement`
- `fact_offers`
