## Enrich Offboarding Repairs Probability

### Purpose

Enrich Offboarding Repairs Probability DAG runs a spark job that uses a Scikit-learn model to predict the probability of an offboarding inspection resulting in a repair. This DAG also saves the input data used for predictions as a table named `contracts`. The model is stored in Databricks File System, in the path:

```
/dbfs/FileStore/models/inspections/
```

### Disclamer

The resulting table of this enrich DAG is different than other enrich DAGs as it's not a direct result of a query execution, but a result of a Scikit-learn model applied on a query result set.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- `enrich` layer:
  - `datalake_offboarding_repairs_probability.contracts`
  - `datalake_offboarding_repairs_probability.predictions`

</details>
