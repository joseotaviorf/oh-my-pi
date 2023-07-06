## Enrich Rede Lead Acquisition
​
### Purpose
​
This DAG creates the enriched table that tells us the acquisition team of each lead, which depends on when the company became
a Rede member and when the lead was sent.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via full load:

- `lead_3p_acquisition`

​</details>
