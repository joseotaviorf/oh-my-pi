## Enrich Mexico CIB Segmentation

### Purpose
This DAG has the goal to create the CIB's segmentation.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered once per month, in the first day of the month, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output table in the enrich layer, via full load:

- `cib_segmentation`

</details>
