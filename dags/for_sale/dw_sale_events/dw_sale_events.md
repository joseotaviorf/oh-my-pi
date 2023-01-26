## DW Sale Events
​
### Purpose
​
This DAG creates the DW modelings for Sale Events. These tables track key events in the ForSale funnel, such as
visit booked, visit completed, offer submitted, sale agreement signed, and others.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema sale, via full load:
    - `dim_sale_cohort_type`
    - `dim_sale_event_type`
    - `fact_sale_cohort_conversion`
    - `fact_sale_demand_event`
​
​</details>
