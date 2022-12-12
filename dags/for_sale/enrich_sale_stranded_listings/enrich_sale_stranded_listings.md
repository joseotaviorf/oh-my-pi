## Enrich Sale Stranded Listings

### Purpose
This DAG creates the enriched tables for Stranded Listings context.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is intended to run daily, except for the `thresholds` table, which has ShortCircuitOperator that makes it run once a month for business and performance reasons.

- The `thresholds` table will calculate the number of days that we will theoretically define that a property is stranded. It will run monthly, on the first day of the month, since this metric does not tend to change so much over time, but we still want to follow this monthly evolution.

- The `stranded_status` (which will use the thresholds table) that will rank the status of listings over time.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following tables in enrich layer:

Via **incremental load**:
    - `thresholds`

Via **full load**:
    - `stranded_status`

</details>