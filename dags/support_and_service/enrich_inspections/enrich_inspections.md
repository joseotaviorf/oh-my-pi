## Enrich Inspections
### Purpose

This DAG is responsible for the union tables between new Inspection Services data and old PWA data, as well as the construction of metrics through this data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer:

- `inspection`
- `inspection_metrics`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible.

</details>