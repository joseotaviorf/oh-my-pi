# cdc_wave2 — EMR validation evidence (fintech)

Subset of [`cdc_wave2_emr_cluster_validation_results.md`](cdc_wave2_emr_cluster_validation_results.md) for this business-line promotion PR (DPLT-1502).

**DAGs promoted in this PR:** 19

### Infra retry

`robin_hood` failed in the initial `cdc_wave2` batch and passed after re-trigger
(`val__20260625194733_8548`).

### Schema fix retry

`rental_guarantee` failed on `load-clean-sap` in the initial batch; passed after
EMR-safe `payment_entries` schema (#25534), shadow-table cleanup, and manual
re-trigger (`manual__2026-07-01T19:16:03.367706+00:00`).

## Validation runs

| DAG | Run ID | Airflow |
| --- | --- | --- |
| `ledger` | `val__20260625184738_748c` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.ledger__validation/grid?dag_run_id=val__20260625184738_748c) |
| `lending` | `val__20260625184738_e8a4` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.lending__validation/grid?dag_run_id=val__20260625184738_e8a4) |
| `monopoly` | `val__20260625184738_1f66` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.monopoly__validation/grid?dag_run_id=val__20260625184738_1f66) |
| `nazare` | `val__20260625184738_e4de` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.nazare__validation/grid?dag_run_id=val__20260625184738_e4de) |
| `owner_fees` | `val__20260625184738_2722` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.owner_fees__validation/grid?dag_run_id=val__20260625184738_2722) |
| `payout_system` | `val__20260625184738_f044` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.payout_system__validation/grid?dag_run_id=val__20260625184738_f044) |
| `pixar` | `val__20260625184738_87df` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.pixar__validation/grid?dag_run_id=val__20260625184738_87df) |
| `rental_guarantee` | `manual__2026-07-01T19:16:03.367706+00:00` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.rental_guarantee__validation/grid?dag_run_id=manual__2026-07-01T19:16:03.367706%2B00:00) |
| `rental_guarantee_fast_lane` | `val__20260625184738_4c20` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.rental_guarantee_fast_lane__validation/grid?dag_run_id=val__20260625184738_4c20) |
| `retsuko` | `val__20260625184738_67ff` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.retsuko__validation/grid?dag_run_id=val__20260625184738_67ff) |
| `retsuko_fast_lane` | `val__20260625184738_8103` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.retsuko_fast_lane__validation/grid?dag_run_id=val__20260625184738_8103) |
| `robin_hood` | `val__20260625194733_8548` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.robin_hood__validation/grid?dag_run_id=val__20260625194733_8548) |
| `sap_gateway` | `val__20260625184738_9dbf` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.sap_gateway__validation/grid?dag_run_id=val__20260625184738_9dbf) |
| `sorting_hat` | `val__20260625184738_600c` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.sorting_hat__validation/grid?dag_run_id=val__20260625184738_600c) |
| `sorting_hat_sonia` | `val__20260625184738_4d9f` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.sorting_hat_sonia__validation/grid?dag_run_id=val__20260625184738_4d9f) |
| `trato_feito` | `val__20260625184738_b867` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.trato_feito__validation/grid?dag_run_id=val__20260625184738_b867) |
| `vans` | `val__20260625184738_359f` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.vans__validation/grid?dag_run_id=val__20260625184738_359f) |
| `wall_street` | `val__20260625184738_e8c4` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.wall_street__validation/grid?dag_run_id=val__20260625184738_e8c4) |
| `wall_street_fast_lane` | `val__20260625184738_6634` | [grid](https://clzwwyxxe0mi101k4d80t3fgc.astronomer.run/d03z8k7v/dags/bietlejuice.wall_street_fast_lane__validation/grid?dag_run_id=val__20260625184738_6634) |
