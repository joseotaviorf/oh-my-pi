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

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>