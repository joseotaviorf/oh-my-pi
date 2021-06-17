## Enrich Booking

### Purpose

Creates the enriched tables for the context `Booking` enriched from EBDB and gsheets.
It'll track the user journey end to end with information about all booking status, changes, and the tenants.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table, via full load:

- `booking`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>