## DW Chattermill

### Purpose

​
This DAG load the DW tables for Chatttermill data. Those data are related to NPS.
​

### Execution​ Interval

This DAG is triggered once per day via Mediator, after enrich_chattermill DAG, usually around 5 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output tables:
​

- `fact_answer_category` – Contains sentiments, score, comments among other informations.
- `dim_answer_category` – Contains category and theme of the NPS response categorization.
  ​
