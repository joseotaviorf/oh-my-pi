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
- `booking_cancellation`
- `house_available_hours`
- `booking_review`

</details>
