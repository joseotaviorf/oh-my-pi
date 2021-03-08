## Enrich Booking

### Purpose

Creates the enriched tables for the context `Booking` enriched from ebdb and gsheets.

This DAG enriches data coming from ebdb and gsheet.
It'll track the user journey end to end with information about all booking status, changes, and the tenants.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `booking`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
