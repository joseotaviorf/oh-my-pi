## Enrich EBDB House

### Purpose

Creates enriched tables for the context `House` from ebdb.

This DAG is responsible for creating enriched tables about the house domain with a direct dependency on the EBDB.
As a home domain, these would be characteristics, conditions and statuses that are independent of the listing (they don't change after a publication/depublication).


<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

1. In data lake enrich:
    - `maintenance_condition_history`

</details>
