## Checkout API

### Purpose

This DAG creates the full tables for Checkout API, this product has the objetive of centralize all payments platform products in the same place.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables: 

1. In data lake raw: 
    - All tables available in source's database, except for operational tables:
      - `change_owner_control`
      - `flyway_schema_history`
      - `permission`
      - `requester_role`
      - `role`
      - `role_permission`

2. In data lake clean:

      - `boleto`
      - `boleto_webhook`
      - `webhook`
      - `payment_config`
      - `requester`
      - `bolecode`
      - `bank_account`
      - `pix`
      - `pix_refund`
      - `payment_gateway_error`
      - `charge`
      - `charge_status_log`
      - `order`

</details>
