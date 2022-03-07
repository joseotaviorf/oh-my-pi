## Datamarts For Rent Cross

### Purpose

Creates/updates the datamart tables that have cross squad dependencies, for the context of For Rent, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamart` of data lake and `datamarts` of DW.

- `credit_proposal_attribute`
- `funnel_credit_event_flows`
- `funnel_monthly_credit_user_flow`
- `funnel_weekly_credit_user_flow`
- `rental_demand_events_funnel_flows`
- `rental_events_funnel_partners`
- `rental_events_funnel`
- `user_cohort_rental_demand_conversion`

### Additional Information

The file [datamarts.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/datamarts/datamarts.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.
