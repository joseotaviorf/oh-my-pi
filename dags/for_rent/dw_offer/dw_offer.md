## DW Offer

### Purpose

This DAG loads to DW our models related to rental offers.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load and partitioned by `country_code`:

- `dim_offer`

</details>
