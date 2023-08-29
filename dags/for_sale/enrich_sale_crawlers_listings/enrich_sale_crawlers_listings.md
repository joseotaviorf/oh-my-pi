## Enrich Sale Crawlers Listings

### Purpose

Creates enriched tables for the context `Crawlers Listings` from Em Casa and Loft. This schema has tables that extract data from both websites.
The ingestion is incremental and full. The partitions for incremental tables are described below in Outputs section.

### Execution Interval

Three times a week. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `em_casa`
- `em_casa_listing_flows`
- `em_casa_region_mapping` - Partition column: ts_updated
- `loft`
- `loft_region_mapping` - Partition column: dt_updated
- `loft_status_listing_flows`
