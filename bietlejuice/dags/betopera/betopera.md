## BetoPera

### Purpose

This DAG creates the incremental tables for betopera, the integration with Insurance providers.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, all via **incremental load**:

1. In data lake raw:

- All tables available in source's database, except for operational tables:

- `certificate_aud`
- `certificate_request_aud`
- `change_owner_control`
- `flyway_schema_history`
- `insurance_aud`
- `revinfo`

1. In data lake clean:​​

- `certificate`
- `certificate_request`
- `insurance`

</details>
