# Jun 20 validation promotion report

Custom policy applied:
- All original **promote** cohort → promote
- Original **reject** cohort: reject if runtime failure or cost increased; promote if cost lower and validation wall ≤ 30 min

Promoted: **85**
Rejected (validation removed): **33**
Errors: **0**

## Promoted

- `bietlejuice.authx_scim` — original promote cohort
- `bietlejuice.betopera` — original promote cohort
- `bietlejuice.brokers_supply_processor` — original promote cohort
- `bietlejuice.chat_fup` — original promote cohort
- `bietlejuice.chatmanager` — original promote cohort
- `bietlejuice.checkout` — cost lower (-46.6%), val wall 11.6m <= 30.0m
- `bietlejuice.comms_manager` — original promote cohort
- `bietlejuice.company` — cost lower (-49.2%), val wall 10.4m <= 30.0m
- `bietlejuice.condominium_payments` — original promote cohort
- `bietlejuice.consorcio` — original promote cohort
- `bietlejuice.cyber_legal` — cost lower (-36.0%), val wall 17.3m <= 30.0m
- `bietlejuice.datazord` — original promote cohort
- `bietlejuice.docpilot` — original promote cohort
- `bietlejuice.docx` — cost lower (-12.0%), val wall 17.5m <= 30.0m
- `bietlejuice.dw_accounts_receivable` — cost lower (-25.5%), val wall 10.1m <= 30.0m
- `bietlejuice.dw_affiliate_costs` — cost lower (-46.7%), val wall 8.3m <= 30.0m
- `bietlejuice.dw_agent` — original promote cohort
- `bietlejuice.dw_agent_accreditation` — original promote cohort
- `bietlejuice.dw_agent_contract` — cost lower (-43.2%), val wall 12.7m <= 30.0m
- `bietlejuice.dw_agents_availability` — original promote cohort
- `bietlejuice.dw_atta` — original promote cohort
- `bietlejuice.dw_banking_file_payments` — original promote cohort
- `bietlejuice.dw_braze_events_user_dispatch` — original promote cohort
- `bietlejuice.dw_business_unit_region` — original promote cohort
- `bietlejuice.dw_buyer_prospect` — original promote cohort
- `bietlejuice.dw_employee_details` — original promote cohort
- `bietlejuice.dw_house` — cost lower (-57.7%), val wall 10.1m <= 30.0m
- `bietlejuice.dw_neurotech_quintocred` — original promote cohort
- `bietlejuice.dw_performance_rent` — cost lower (-1.0%), val wall 29.6m <= 30.0m
- `bietlejuice.dw_region` — original promote cohort
- `bietlejuice.dw_reservation` — original promote cohort
- `bietlejuice.dw_sale_listing_flow` — original promote cohort
- `bietlejuice.ebdb_listing_quality` — original promote cohort
- `bietlejuice.ebdb_proposal_fast_lane` — original promote cohort
- `bietlejuice.enrich_agents_matias` — original promote cohort
- `bietlejuice.enrich_airflow` — cost lower (-46.1%), val wall 11.7m <= 30.0m
- `bietlejuice.enrich_concierge_health_metrics` — original promote cohort
- `bietlejuice.enrich_crm` — original promote cohort
- `bietlejuice.enrich_customer_support` — cost lower (-56.5%), val wall 29.8m <= 30.0m
- `bietlejuice.enrich_cyber` — original promote cohort
- `bietlejuice.enrich_demand_conversion_events` — cost lower (-61.6%), val wall 11.0m <= 30.0m
- `bietlejuice.enrich_emlio` — original promote cohort
- `bietlejuice.enrich_google_analytics_classified` — original promote cohort
- `bietlejuice.enrich_growth_media_platform_metrics` — original promote cohort
- `bietlejuice.enrich_hubspot_crm` — original promote cohort
- `bietlejuice.enrich_kill_queue` — original promote cohort
- `bietlejuice.enrich_learning` — original promote cohort
- `bietlejuice.enrich_lost_listings` — original promote cohort
- `bietlejuice.enrich_prospect_status` — original promote cohort
- `bietlejuice.enrich_rental_historical_follow_up` — original promote cohort
- `bietlejuice.enrich_rental_management` — cost lower (-21.2%), val wall 9.2m <= 30.0m
- `bietlejuice.enrich_rental_transact` — cost lower (-25.5%), val wall 10.7m <= 30.0m
- `bietlejuice.enrich_sale_flows` — original promote cohort
- `bietlejuice.enrich_sale_listing_demand` — original promote cohort
- `bietlejuice.enrich_sale_offer` — original promote cohort
- `bietlejuice.enrich_sorting_hat` — original promote cohort
- `bietlejuice.enrich_ss_logic_model` — original promote cohort
- `bietlejuice.enrich_supply_outbound_flows` — original promote cohort
- `bietlejuice.enrich_table_dependency_tree` — original promote cohort
- `bietlejuice.enrich_tenant_journey` — original promote cohort
- `bietlejuice.enrich_top_of_funnel_supply` — original promote cohort
- `bietlejuice.enrich_trino_table_usage` — original promote cohort
- `bietlejuice.enrich_velo` — original promote cohort
- `bietlejuice.enrich_visit` — original promote cohort
- `bietlejuice.google_analytics_classified` — cost lower (-15.2%), val wall 19.1m <= 30.0m
- `bietlejuice.google_search_console` — original promote cohort
- `bietlejuice.hefesto` — original promote cohort
- `bietlejuice.insider` — original promote cohort
- `bietlejuice.inspection_services` — original promote cohort
- `bietlejuice.kill_queue` — original promote cohort
- `bietlejuice.legaut` — original promote cohort
- `bietlejuice.metric_ss__tickets` — original promote cohort
- `bietlejuice.pin_goal` — original promote cohort
- `bietlejuice.quinto_messenger` — original promote cohort
- `bietlejuice.reclameaqui` — original promote cohort
- `bietlejuice.reverse_birdie_access` — original promote cohort
- `bietlejuice.reverse_minority_report_ss` — original promote cohort
- `bietlejuice.salesforce_growth` — original promote cohort
- `bietlejuice.sauron` — original promote cohort
- `bietlejuice.survicate_respondent_attributes` — original promote cohort
- `bietlejuice.survicate_survey_attributes` — original promote cohort
- `bietlejuice.survicate_surveys` — cost lower (-14.8%), val wall 11.0m <= 30.0m
- `bietlejuice.table_usage_in_queries` — original promote cohort
- `bietlejuice.terminator` — original promote cohort
- `bietlejuice.text2filter_evals` — original promote cohort

## Rejected

- `bietlejuice.arquivo_confidencial` — cost increased (+104.2%)
- `bietlejuice.batch_inference` — cost increased (+19.7%)
- `bietlejuice.big_agent_fast_lane` — cost increased (+59.8%)
- `bietlejuice.billing` — cost increased (+0.1%)
- `bietlejuice.bob` — cost increased (+16.6%)
- `bietlejuice.cart_system` — cost increased (+0.5%)
- `bietlejuice.copilot_service` — cost increased (+14.7%)
- `bietlejuice.docx_fast_lane` — cost increased (+13.9%)
- `bietlejuice.dw_ciq_listing_purchase` — runtime failure
- `bietlejuice.dw_collection_ai_agents` — runtime failure
- `bietlejuice.dw_collection_recovery_quintocred` — cost increased (+3.7%)
- `bietlejuice.dw_sale_listing_price_changes` — cost increased (+10.1%)
- `bietlejuice.ebdb_location` — cost increased (+20.1%)
- `bietlejuice.ebdb_proposal` — cost increased (+16.1%)
- `bietlejuice.emlio` — val wall 281.5m > 30.0m
- `bietlejuice.enrich_amplitude_inspections` — val wall 35.0m > 30.0m
- `bietlejuice.enrich_condo_monitoring` — cost increased (+2.5%)
- `bietlejuice.enrich_databricks_job_runs` — runtime failure; cost increased (+21.7%)
- `bietlejuice.enrich_fairness_assessment` — cost increased (+82.2%)
- `bietlejuice.enrich_spark_event_logs` — cost increased (+14.2%)
- `bietlejuice.google_ads` — cost increased (+63.2%)
- `bietlejuice.greenhouse_audit_log` — cost increased (+54.1%)
- `bietlejuice.inspection_services_fast_lane` — cost increased (+100.2%)
- `bietlejuice.metric_rent__bookings` — cost increased (+27.6%)
- `bietlejuice.quires` — runtime failure
- `bietlejuice.rental_guarantee` — cost increased (+61.2%)
- `bietlejuice.retsuko_fast_lane` — cost increased (+14.9%)
- `bietlejuice.reverse_demand_score` — cost increased (+25.0%)
- `bietlejuice.robin_hood` — cost increased (+43.7%)
- `bietlejuice.sorting_hat_sonia` — cost increased (+65.9%)
- `bietlejuice.trato_feito` — cost increased (+53.7%)
- `bietlejuice.twilio_flex_insights` — cost increased (+14.5%)
- `bietlejuice.vans` — cost increased (+61.9%)

## Manual overrides (runtime failures promoted per user request)

- `bietlejuice.dw_ciq_listing_purchase` — manual promote (had runtime failure in validation run)
- `bietlejuice.dw_collection_ai_agents` — manual promote (had runtime failure in validation run)
- `bietlejuice.quires` — manual promote (had runtime failure in validation run)

## EMR runtime corrections (post-promotion fix)

The promotion script copied Databricks validation twins (`consolidation_*` + `databricks_conn_id`) into prod for **28 DAGs** whose prod runtime on `master` is EMR (`emr_7_12_*`). Each file was corrected to the paired `emr_7_12_consolidation_*` preset (same tier/family as validation), `databricks_conn_id` removed, and validation-derived `custom_configurations` kept unchanged.

| DAG | master prod preset | corrected EMR preset |
|---|---|---|
| `bietlejuice.authx_scim` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_s_memory_cluster` |
| `bietlejuice.betopera` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_s_memory_cluster` |
| `bietlejuice.brokers_supply_processor` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_s_memory_cluster` |
| `bietlejuice.chat_fup` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_s_memory_cluster` |
| `bietlejuice.chatmanager` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_m_memory_single_node_cluster` |
| `bietlejuice.checkout` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.comms_manager` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.company` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.condominium_payments` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.consorcio` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.datazord` | `emr_7_12_consolidation_s_general_cluster` | `emr_7_12_consolidation_s_general_cluster` |
| `bietlejuice.docpilot` | `emr_7_12_consolidation_s_memory_cluster` | `emr_7_12_consolidation_m_memory_single_node_cluster` |
| `bietlejuice.docx` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_s_memory_cluster` |
| `bietlejuice.dw_accounts_receivable` | `emr_7_12_consolidation_s_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_affiliate_costs` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_agent` | `emr_7_12_consolidation_s_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_agent_contract` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_agents_availability` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_atta` | `emr_7_12_consolidation_m_memory_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_banking_file_payments` | `emr_7_12_consolidation_m_memory_cluster` | `emr_7_12_consolidation_m_memory_cluster` |
| `bietlejuice.dw_braze_events_user_dispatch` | `emr_7_12_consolidation_s_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_business_unit_region` | `emr_7_12_consolidation_s_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_buyer_prospect` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.dw_house` | `emr_7_12_consolidation_l_memory_cluster` | `emr_7_12_consolidation_m_memory_cluster` |
| `bietlejuice.ebdb_proposal_fast_lane` | `emr_7_12_consolidation_s_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.enrich_agents_matias` | `emr_7_12_consolidation_s_memory_cluster` | `emr_7_12_consolidation_s_memory_cluster` |
| `bietlejuice.enrich_airflow` | `emr_7_12_consolidation_m_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |
| `bietlejuice.enrich_trino_table_usage` | `emr_7_12_consolidation_s_general_cluster` | `emr_7_12_consolidation_xs_memory_cluster` |

Summary by corrected preset: `emr_7_12_consolidation_xs_memory_cluster` (17), `emr_7_12_consolidation_s_memory_cluster` (6), `emr_7_12_consolidation_s_general_cluster` (1), `emr_7_12_consolidation_m_memory_cluster` (2), `emr_7_12_consolidation_m_memory_single_node_cluster` (2).
