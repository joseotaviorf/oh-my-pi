## DW Reservation Temp

### Purpose

Full load of the context `Reservation` models into DW
with data of kill queue.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

- `dw_public.dim_reservation`
