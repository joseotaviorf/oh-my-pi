## Pixar

### Purpose

This DAG creates the full tables for Pixar, the integration with PIX payment services.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, all via **full load**:

1. In data lake raw:

- All tables available in source's database, except for operational tables `schema_migrations`, `change_owner_control` and `charge_status_log`.

2. In data lake clean:​​

- `account`
- `charge`
- `refund`

</details>
