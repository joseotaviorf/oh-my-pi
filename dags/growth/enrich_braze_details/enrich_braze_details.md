## Enrich Braze Details
​
### Purpose
​
This DAG creates the incremental enriched table from Braze Details clean tables.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_braze_details DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output table:
​
- `canvas_step_details` – Contains the details of each Canvas step, such as it's id, name, message and id of the next step.
​
### Additional Information
​
The Data Analytics team responsible for Braze data is also on aforementioned document.
​</details>
