## Datamarts Growth Cross

### Purpose

Creates/updates the datamart tables that have cross squad dependencies, for the context of Growth, in data lake.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `affiliate_acquisition_metrics`
- `affiliates_clusters`
- `daily_target_volumes_supply`
- `efficiency_monitor_rental`
- `efficiency_monitor_sale`
- `inbound_attendance_leads_flows`
- `marketing_campaigns_costs_and_volumes`
- `marketing_demand_supply_branding_costs`
- `performance_marketing_cluster_promotional_bonus_costs`
- `performance_marketing_cluster_promotional_bonus`
- `performance_marketing_metrics_demand`
- `plaquinhas_users_metrics_demand`
- `pricing_rent_categorization`
- `rent_flow_interactions`
- `rental_cohort_conversions`
- `rental_marketplace_flows`
- `rental_performance_marketing_metrics_supply_coincident`
- `sale_performance_marketing_metrics_demand`
- `sale_performance_marketing_metrics_supply_coincident`
- `tenant_prospect_status`
- `tenant_prospects_activations`
- `top_of_funnel_volumes_daily`
- `top_of_funnel_volumes_monthly`
- `top_of_funnel_volumes_weekly`
- `unique_performance_marketing_metrics_supply_coincident`
- `unique_supply_cohort_conversions`
- `unique_supply_events_funnel`
- `user_funnel`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data For Sale team.

### Additional Information

The file [growth_cross.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/dags/dw_datamarts_spark/growth_cross/growth_cross.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.

</details>
