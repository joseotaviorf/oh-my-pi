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

- bank_account
- bolecode
- boleto
- boleto_webhook
- boleto_webhook_config
- change_owner_control
- charge
- charge_status_log
- credit_card
- credit_card_acquire_fee
- credit_card_capture_attempt
- credit_card_fee
- credit_card_fee_installment
- credit_card_status_log
- credit_card_token
- credit_card_webhook
- order
- payment_config
- payment_gateway_error
- permission
- pix
- pix_refund
- pix_webhook
- refund_attempt
- requester
- requester_role
- role
- role_permission
- webhook

</details>
