## Datamarts Cross

### Purpose

Creates/updates the datamart tables, for cross squads context, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following tables in the schema `dw_datamart` of data lake and `datamarts` of DW:

    - `funnel_demand_flows`
    - `lead_listing_flows`
    - `quintoandar_consultant_listings`
    - `talk_to_agent`

### Additional Information

The file [datamarts.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/datamarts/datamarts.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.
