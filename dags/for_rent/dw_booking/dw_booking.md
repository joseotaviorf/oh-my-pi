## DW Booking

### Purpose

Full load of the context `Booking` models into DW with enriched data from Amplitude, Booking, Visits and Taxonomy sheets.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

- `dim_booking`
- `dim_tenant_booking_review`

