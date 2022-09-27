## Velo Neurotech

### Purpose

This DAG imports, via Neurotech API, logs from the policy quintoandar_concessao_credito used by Velo for credit analysis.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily at 06:00am.

- Note that Neurotech generates reports usually around 3-4am, so it's better run the DAG always some hours after it, to guarantee that the report is already generated.

### Outputs

In datalake raw:

- `logs_credit_granting` (incremental load)

In datalake clean:

- `logs_credit_granting` (full load)

</details>
