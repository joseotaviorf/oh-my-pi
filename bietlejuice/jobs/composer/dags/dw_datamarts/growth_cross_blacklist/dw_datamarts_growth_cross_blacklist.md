## Datamarts Growth Cross Blacklist

### Purpose

Creates/updates the blacklisted datamart tables, for the context of Growth that depends on Cross datamarts, in data lake and DW. These datamarts are blacklist due to performance or SLA issues.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake and `datamarts` of DW.
