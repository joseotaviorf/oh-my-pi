## Enrich Rental Crawlers Listings

### Purpose

Creates enriched tables for the context `Crawlers Listings` from OLX, VivaReal, Zap Imoveis. This schema has tables that extract data from all these websites.
The ingestion is incremental, partitioned on city, year, month and day columns.

### Execution Interval

Three times a week. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `olx`
- `viva_real`
- `zap_imoveis`
