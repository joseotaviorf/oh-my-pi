## Datamarts Growth

Creates/updates the datamart tables that don't have cross squad dependencies, for the context of Growth, in data lake.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>​

### Purpose

Creates/updates the datamart tables, for the context of Growth, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake and `datamarts` of DW:

- attribution_conversion_paths_demand
- casa_mineira_top_of_funnel_volumes_daily
- casa_mineira_top_of_funnel_volumes_monthly
- casa_mineira_top_of_funnel_volumes_weekly
- performance_marketing_metrics_imobiliaria_casa_mineira
- performance_marketing_metrics_portal_casa_mineira
- sale_performance_marketing_metrics_supply_cohort
- plaquinhas_houses

### Additional Information

The file [growth.yml](growth.yml) declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.

</details>
