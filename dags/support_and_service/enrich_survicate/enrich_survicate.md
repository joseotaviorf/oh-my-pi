## Enrich Survicate
### Purpose

Transform survey response collected from [Survicate](https://developers.survicate.com/data-export/#get-the-list-of-surveys). 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, after `load-surveys-to-clean` task of the Survicate extraction DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer (via incremental load):

- `keys_surveys`
- `photo_surveys`
- `surveys`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact its owner.

</details>