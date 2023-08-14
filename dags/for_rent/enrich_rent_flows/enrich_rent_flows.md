## Enrich Rent Flows

### Purpose

Creates an enriched table about rent flows and its dimensions (property, tenant prospect, booking, offer, contract, etc.)

### Execution Interval

Daily.

### Outputs

Produces the following output table, partitioned by `country_code`:

- `datalake_rent_flows.rent_flows`
- `datalake_rent_flows.rent_flows_types`
