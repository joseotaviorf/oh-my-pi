## Enrich NPS Reversion

### Purpose

Enrich NPS Reversion DAG runs two spark jobs that use a Scikit-learn model to predict the probability of a tenant or a landlord being detractor in the NPS survey of Offboarding step. This DAG also saves the input data used for predictions in two tables named `offboarding_tenant_input` and `offboarding_landlord_input`. Besides that, this DAG save a log table named `offboarding_tenant_input` that allow users to understand the aggregations os sk_user's considered for each sk_contract in the model. The models are stored in Databricks File System, in the paths:

```
/dbfs/FileStore/models/nps_reversion/offboarding/tenant
/dbfs/FileStore/models/nps_reversion/offboarding/landlord
```

You can find more information about the development proccess [here](https://github.com/quintoandar/support-and-service/tree/main/ml-models/nps-reversion).

### Disclamer

The resulting table of this enrich DAG is different than other enrich DAGs as it's not a direct result of a query execution, but a result of a Scikit-learn model applied on a query result set.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- `enrich` layer:
  - `datalake_nps_reversion.contract_people`
  - `datalake_nps_reversion.offboarding_tenant_input`
  - `datalake_nps_reversion.offboarding_tenant_predictions`
  - `datalake_nps_reversion.offboarding_landlord_input`
  - `datalake_nps_reversion.offboarding_landlord_predictions`

</details>
