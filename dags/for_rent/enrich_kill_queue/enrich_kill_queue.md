## Enrich Kill Queue

### Purpose
Creates the enriched table for the context `Reservation` enriched from kill_queue.reservation and kill_queue.house.

It will track the user's reservation journey with all information, such as status, installments, house, and tenant id.

In addition, in order to guarantee unicity for tables that have an incremental mode at the clean layer, the tables house; documentation and user are recreated with a deduplication process.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output table:

1. In data lake enrich:
    - `documentation`
    - `house`
    - `reservation`
    - `user`

</details>
