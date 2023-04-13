## Enrich Metric Rent Demand Event

### Purpose

Creates the enrich table metric_rent_demand_event, containing the aggregated sum of demand events of For Rent, each line has the total volume of events related to the scope within the agregation. This is an incremental table and it is partitioned by "year", "month", "day" and "country_code".

### Execution Interval

Daily.

### Outputs

Produces the following output table:
 
- `datalake_metric_rent_demand_event.metric_rent_demand_event`


