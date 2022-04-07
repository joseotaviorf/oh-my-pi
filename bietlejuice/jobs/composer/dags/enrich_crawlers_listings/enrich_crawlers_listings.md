## Enrich Crawlers Listings

### Purpose

Creates enriched tables for the context `Crawlers Listings` from OLX and VivaReal. This schema has tables that extract data from both websites.
The ingestion is incremental, partitioned on city, year, month and day columns.

### Execution Interval

Twice a week. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `olx`
- `viva_real`
