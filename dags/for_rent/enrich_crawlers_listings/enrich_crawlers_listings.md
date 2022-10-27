## Enrich Crawlers Listings

### Purpose

Creates enriched tables for the context `Crawlers Listings` from OLX, VivaReal, Zap Imoveis, and Loft. This schema has tables that extract data from both websites.
The ingestion is incremental, partitioned on city, year, month and day columns.

### Execution Interval

Three times a week. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `loft_region_mapping`
- `loft_status_listing_flows`
- `olx`
- `viva_real`
- `zap_imoveis`