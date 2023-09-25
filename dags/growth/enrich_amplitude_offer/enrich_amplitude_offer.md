## Enrich Amplitude Offer

### Purpose

Enrich offer context events in Amplitude and load into data lake.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via incremental load with a 6 days window:

- `offer_submitted_events`
- `sale_offer_raw_events`

</details>
