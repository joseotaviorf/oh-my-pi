# Metric Fintech Collections Segmentation

This DAG materializes recovery metrics based on different segmentations for the collections domain.
It serves as a metric layer to facilitate analysis in Superset, reducing computational load by pre-calculating metrics.

## Datasets

1. **daily_recovery_segmentation**: Recovery metrics by theoretical segmentation calculated from `dw_collections_segmentation.fact_contract_features_timeline`. This table provides recovery metrics aggregated by the theoretical segmentation model, excluding active-current and ended-current segments.

2. **daily_recovery_chargehub_audiences**: Recovery metrics by Chargehub audiences. This table provides recovery metrics aggregated by audience names from the Chargehub system (`datalake_trato_feito_clean.contract_segment_distribution_history`).

## Granularity

- Daily granularity (`dt_reference`) with monthly aggregation context (`dt_month_ref`/`month_ref`).
- Metrics are calculated both at reference date (`_at_reference`) and accumulated (`_acc`) from the invoice creation until the observation date.
- Breakdown by delay buckets (T1, T2) for invoices, amounts, and recovery metrics.
- Digital recovery breakdown by channel type.

## Key Metrics

Both tables include:
- Contract and invoice counts (at reference and accumulated)
- Due amounts and recovery amounts (overall, T1, T2 breakdowns)
- Digital recovery amounts by delay bucket
- Recovery counts for invoices and contracts

## Output Tables

- `metric_fintech.daily_recovery_segmentation`
- `metric_fintech.daily_recovery_chargehub_audiences`
