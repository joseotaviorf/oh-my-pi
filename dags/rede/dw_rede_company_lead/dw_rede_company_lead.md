## DW Rede Company Lead

### Purpose

This DAG creates the model for companies leads of Rede QuintoAndar, which is a marketplace. This data comes mostly from HubSpot.

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `rede`:

- `dim_company_lead`
