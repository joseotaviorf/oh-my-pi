## Datamarts Growth Cross

### Purpose

Creates/updates the datamart tables that have cross squad dependencies, for the context of Growth, in data lake.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `affiliate_acquisition_metrics`
- `efficiency_monitor_rental`
- `inbound_attendance_leads_flows`
- `marketing_campaigns_costs_and_volumes`
- `pricing_rent_categorization`
- `rent_flow_interactions`
- `efficiency_monitor_sale`
- `pricing_rent_categorization`
- `inbound_attendance_leads_flows`
- `unique_supply_cohort_conversions`
- `unique_supply_events_funnel`
- `marketing_campaigns_costs_and_volumes`
- `top_of_funnel_volumes_monthly`
- `sale_performance_marketing_metrics_supply_coincident`
- `tenant_prospects_activations`
- `performance_marketing_cluster_promotional_bonus`
- `performance_marketing_cluster_promotional_bonus_costs`
- `daily_target_volumes_supply`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data For Sale team.

### Additional Information

The file [growth_cross.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts_spark/growth_cross/growth_cross.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.
