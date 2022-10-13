## Enrich Lost Listings

### Purpose

Enrich Lost listings DAG runs a Spark job that uses a Scikit-learn model over a set of house listings characteristics to apply a segmentation group to each listing, enabling more homogeneous grouped views for a better understanding of the reasons that hinder the renting flow, allowing analysts to select levers to enchance the share o transactions.

The model used for this segmentation is stored in Databricks File System, in the path:

```
/dbfs/FileStore/models/marketing/lost_listings_model.joblib
```

More infromation is available in [this Lost Listings presentation](https://docs.google.com/presentation/d/1HdV_cJ3uIgcg4ksG8EhJS9GahD6tgyZMS7Tx4_I_75E/).

### Disclamer

The resulting table of this enrich DAG is different than other enrich DAGs as it's not a direct result of a query execution, but a result of a Scikit-learn model applied on a query result set.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- `enrich` layer:
  - `datalake_marketing_segmentations.lost_listings`

</details>
