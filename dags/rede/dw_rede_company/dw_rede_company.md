## DW Rede Company

### Purpose

This DAG creates the model for companies of Rede QuintoAndar, which is a marketplace. Most of this data comes from HubSpot, and in the future, Company

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `rede`:

- `dim_company`
- `dim_company_event_type`
- `fact_company_event`
- `fact_company_journey`