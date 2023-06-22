## DW Rent Demand Events Snapshot

### Purpose

This DAG creates snapshot tables of rent demand events and cohort conversions, which are base to build the rent demand and rent cohort conversions metrics and is also used to debug historical data updates.

These are incremental tables and are partitioned by "country_code", "year", "month", "day".

### Execution Interval

Daily.

### Outputs

Produces the following output table on the `dw_rent_snapshot` schema (which is not available for the public):
 
- `dw_rent_snapshot.rent_cohort_conversions_snapshot`
- `dw_rent_snapshot.rent_demand_events_snapshot`


