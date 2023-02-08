## Reverse Atento

### Purpose

This DAG collects multiple data from Datalake and sends to an S3 bucket used to power Atento service.
Atento is an external QuintoAndar partner for managing customer support.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We incrementally load the following table into the Datalake Reverse bucket, for backup pourposes:

- `general_metric`
- `backlog_metric`
- `demand_metric`
- `fcr_metric`
- `csat_front`
- `taxonomia_call`
- `taxonomia_chat`
- `taxonomia_email`
- `twilio_chat_aht`

This pipeline also exports results do atento bucket (`s3://atento-s3-data-quintoandar-com-br`).

</details>
