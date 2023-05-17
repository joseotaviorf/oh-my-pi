## DW Rent Demand Events Snapshot

### Purpose

This DAG creates a snapshot table of rent demand events, which is the base to build the rent demand metrics and is also used to debug historical data updates.

It contains the aggregated sum of demand events of For Rent, where each line has the total volume of events related to the scope within the agregation.

This is an incremental table and is partitioned by "country_code", "year", "month", "day".

### Execution Interval

Daily.

### Outputs

Produces the following output table on the `dw_rent_snapshot` schema (which is not available for the public):
 
- `dw_rent_snapshot.rent_demand_events_snapshot`


