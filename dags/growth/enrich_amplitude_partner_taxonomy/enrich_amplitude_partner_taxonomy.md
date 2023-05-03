## Enrich Amplitude Partner Taxonomy

### Purpose

This DAG creates the enriched table amplitude_partner_taxonomy, which we will use to add a taxonomy to our Dim partner table. This table contains events data from the event type "register_form_completed".

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is dependent on our `amplitude_events` DAG, and therefore is triggered via mediator after it is completed.

More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output table:

- `amplitude_partner_taxonomy` – Contains UTM information about certain events.

</details>
