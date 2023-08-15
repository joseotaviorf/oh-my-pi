## Enrich House Feature Inference
​
### Purpose
​
This DAG infers which features each EBDB house has, that are not necessarily declared in the register. For example, if the description mentions "tem elevador",
we can infer that the house has an elevator. This is useful for the Vespúcio project, which aims to collect data from several sources to create a source of truth.

Documentations about Vespúcio project [here](https://docs.google.com/spreadsheets/d/1v-6sGlfHUVeNyqMh28SXlLW7mUwDYuQNg0lul0Q28ck/edit#gid=396558073).
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output table:
​
- `description_features`: Table with house features inferred from its description.

</details>
