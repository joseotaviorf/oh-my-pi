"""Argparse smoke tests for growth custom Spark jobs (cluster validation flags)."""

import re
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/growth/ada_crawls/spark_jobs/load_ada_crawls_raw.py",
    "dags/growth/amplitude_new/spark_jobs/load_amplitude_new_raw.py",
    "dags/growth/criteo_campaigns/spark_jobs/load_criteo_campaigns_raw.py",
    "dags/growth/enrich_ebdb_user/spark_jobs/user_merge.py",
    "dags/growth/enrich_house_feature_inference/spark_jobs/load_description_features.py",
    "dags/growth/enrich_lost_listings/spark_jobs/load_lost_listings_enrich.py",
    "dags/growth/enrich_pricing_agent/spark_jobs/load_interaction_state_tracker.py",
    "dags/growth/facebook_insights/spark_jobs/load_facebook_insights_raw.py",
    "dags/growth/facebook_insights_impression_device/spark_jobs/load_facebook_insights_impression_device_raw.py",
    "dags/growth/facebook_insights_region/spark_jobs/load_facebook_insights_region_raw.py",
    "dags/growth/google_ads/spark_jobs/load_google_ads_raw.py",
    "dags/growth/google_analytics_classified/spark_jobs/load_google_analytics_classified_raw.py",
    "dags/growth/google_search_console/spark_jobs/load_google_search_console_raw.py",
    "dags/growth/google_search_console_classified/spark_jobs/load_google_search_console_classified_raw.py",
    "dags/growth/hightouch_logs/spark_jobs/load_hightouch_logs.py",
    "dags/growth/hightouch_logs/spark_jobs/load_hightouch_sync_changelog.py",
    "dags/growth/hightouch_logs/spark_jobs/load_hightouch_sync_runs.py",
    "dags/growth/hightouch_logs/spark_jobs/load_hightouch_sync_snapshot.py",
    "dags/growth/hmb_ada/spark_jobs/load_hmb_ada_raw.py",
    "dags/growth/lifull_campaigns/spark_jobs/load_lifull_campaigns_raw.py",
    "dags/growth/olos_dialer_test/spark_jobs/load_olos_dialer_raw.py",
    "dags/growth/profound/spark_jobs/load_profound_raw.py",
    "dags/growth/quires/spark_jobs/load_quires_raw.py",
    "dags/growth/reverse_atlas_pricing_report_access/spark_jobs/load_into_sns.py",
    "dags/growth/reverse_demand_classifieds_ranking_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_demand_score_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_listing_quality_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_listings_locations_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_neighborhood_price_range_access/spark_jobs/load_into_s3.py",
    "dags/growth/reverse_rent_liquidity_score_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_supply_access/spark_jobs/load_into_s3.py",
    "dags/growth/salesforce_growth/spark_jobs/load_salesforce_growth_raw.py",
]

_REVERSE_EXPORT_JOBS = {
    "dags/growth/reverse_atlas_pricing_report_access/spark_jobs/load_into_sns.py",
    "dags/growth/reverse_demand_classifieds_ranking_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_demand_score_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_listing_quality_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_listings_locations_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_neighborhood_price_range_access/spark_jobs/load_into_s3.py",
    "dags/growth/reverse_rent_liquidity_score_access/spark_jobs/load_into_sqs.py",
    "dags/growth/reverse_supply_access/spark_jobs/load_into_s3.py",
}

_WRITE_TARGET_JOB_PATHS = [p for p in _JOB_PATHS if p not in _REVERSE_EXPORT_JOBS]


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    # Arrange
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")

    # Act & Assert
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _REVERSE_EXPORT_JOBS:
        assert "is_validation_run" in text
    else:
        assert "resolve_datalake_write_target(" in text


@pytest.mark.parametrize("job_path", _WRITE_TARGET_JOB_PATHS)
def test_spark_job_resolve_uses_validation_target_args(job_path: str):
    # Arrange
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")

    # Act & Assert
    for block in re.findall(
        r"resolve_datalake_write_target\((.*?)\)", text, flags=re.DOTALL
    ):
        uses_bare_target_name = (
            "target_database=target_database_name" in block
            or "target_table=target_table_name" in block
        )
        targets_parsed_from_args = (
            "target_database_name = args.target_database_name" in text
            or "parse_arguments()" in text
        )
        uses_args_targets = "target_database=args.target_database_name" in block or (
            "target_database=target_database_name," in block
            and targets_parsed_from_args
        )
        assert not uses_bare_target_name or uses_args_targets, (
            f"{job_path} passes unresolved target_database_name/target_table_name "
            "into resolve_datalake_write_target"
        )
