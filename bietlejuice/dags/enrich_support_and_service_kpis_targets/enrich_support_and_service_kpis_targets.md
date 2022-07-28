## Enrich Support And Service Kpis Targets

### Purpose

Transform the KPIs target gsheets to a readable and mergeable format to insert on LookML

### Execution Interval

This DAG is triggered once per day via Mediator, after gsheets `load-target-service-kpis` and `load-target-support-kpis` task.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer (via full load):

- `kpis_targets`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the DAG owners