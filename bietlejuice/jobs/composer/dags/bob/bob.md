## Bob

### Purpose

This DAG brings [Bob (bob-o-construtor)](https://github.com/quintoandar/bob-o-construtor) data, a service developed by B2B for house registry and now it has been used by AA (Autonomous Agents).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw and clean, via full load:
- `attribution_progress`
- `house_draft`
- `location`
- `location_aud`
- `registrar`
- `registrar_aud`
- `submission_progress`
- `submission_progress_aud`


1. In datalake raw and clean, via incremental load:
 - `attribution_progress_aud`
 - `house_draft_aud`
 - `rev_info`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
  
</details>