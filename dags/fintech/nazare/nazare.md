## Nazare

### Purpose

This DAG load tables from Nazare, the service that calculates the Revenue Share with external partners and executives.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables, all via **full load**:

1. In data lake raw:

- All tables available in source's database, except for operational tables:

- `schema_migrations`
- `change_owner_control`

1. In data lake clean:​​

- `advance`
- `agent`
- `associate_executive_bonus`
- `associate_executive_bonus_revision`
- `brokerage_fee_baseline`
- `brokerage_fee_baseline_revision`
- `business_unit`
- `campaign`
- `hub_bonus`
- `hub_bonus_revision`
- `offer`
- `offer_agent`
- `offer_partner`
- `partner`
- `partner_revision`
- `revenue_share_by_participant`
- `revenue_share_file`
- `revenue_share_file_importation_error`
- `tier_bonus`
- `tier_bonus_revision`

</details>
