## Dependency Tree

### Purpose

This DAG ingest the `dependencies.yaml` file and generates a tabular table.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - `datalake_dependency_tree_raw.dependency_tree`


2. In datalake clean:
    - `datalake_dependency_tree_clean.dependency_tree`

</details>
