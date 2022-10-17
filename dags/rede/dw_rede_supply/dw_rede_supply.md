## DW Rede Supply

### Purpose

This DAG creates the models for the supply side of Rede QuintoAndar, which is a marketplace.

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `rede`:

- `dim_file`
- `dim_lead_3p`
- `dim_lead_3p_status`
- `dim_lead_3p_reason`
- `fact_lead_3p_flows`
- `fact_lead_3p_status`
- `fact_lead_3p_status_reason`