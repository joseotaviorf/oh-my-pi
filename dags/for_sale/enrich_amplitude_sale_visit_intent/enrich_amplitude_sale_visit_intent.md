## Enrich Amplitude Sale Visit Intent

### Purpose

Enrich sale visit intent context events in Amplitude and load into Data Lake.
This DAG enriches data coming from Amplitude events that have a Sale context and a visit intent type.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table, incrementally:

- `amplitude_sale_visit_intent`
​</details>
