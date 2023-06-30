## Enrich Vespucio
​
### Purpose
​
This DAG create the enriched table condo for the Vespúcio project.

QuintoAndar has several sources and methods of capturing properties and their respective condominiums, but the availability of data is disorderly and has low reliability. That being said, Vespúcio project aims to collect, organize and enrich data about condominiums, properties and owners, through a process of extraction, transformation, unification and delivery of data in an organized and easy to query structure (APIs and Plugins).

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
- `condo_incremental`: Contains ebdb and sindiconet enrich data about condominiums (duplicated data).
- `condo_full`: Contains ebdb and sindiconet enrich data about condominiums (deduplicated data).
- `condo`: Final table with calculated score for each column and id_dejavu (that represents unique address).

</details>
