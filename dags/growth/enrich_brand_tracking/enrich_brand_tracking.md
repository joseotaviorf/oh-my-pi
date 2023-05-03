## Enrich Brand Tracking
​
### Purpose
​
This DAG creates the enriched tables of the first layer of enrichment from Brand Tracking DAG, by adding some flags and joining with a dictionary.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered quarterly.

More information about run time [here]({chart_url}{dag_id})

### Outputs
​
This pipeline produces the following output table:
​
- `brandtracking_full` – Contains all questions answered by a respondent and their respective answers.
- `brandtracking_lean` – Contains the main information about the respondents
​

</details>
