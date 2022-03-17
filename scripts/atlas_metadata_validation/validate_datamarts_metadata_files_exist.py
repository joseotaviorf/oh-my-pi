import argparse
import re

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.services import FileService, ConfigurationService
from bietlejuice.jobs.composer.services.git_service import GitService

logger = QuintoAndarLogger("validate_datamarts_metadata_files_exist")

DATAMARTS_DAG_REGEX = re.compile(
    r"/dags/dw_datamarts/(?P<context>\w+)/(?P<dagname>\w+)\.py"
)
DATAMARTS_YAML_REGEX = re.compile(
    r"/dags/dw_datamarts/(?P<context>\w+)/(?P<dagname>\w+)_(:?forno|prod)_conf\.(:?yml|yaml)"
)

# These datamarts were created without lineage due to the
# datamarts migration.
SKIP_LIST = {
    "dw_datamarts/cross": {
        "talk_to_agent",
        "lead_listing_flows",
        "buyer_prospect_status",
        "quintoandar_consultant_listings",
    },
    "dw_datamarts/growth": {
        "marketplace_intelligence_metrics",
        "performance_marketing_metrics_supply",
        "listings_online_metrics",
        "sale_performance_marketing_metrics_supply_cohort",
        "plaquinhas_houses",
        "tof_demand_online_events",
        "casa_mineira_top_of_funnel_volumes_monthly",
        "users_online_metrics",
        "performance_marketing_metrics_imobiliaria_casa_mineira",
        "market_share_by_sk_region",
        "performance_marketing_metrics_portal_casa_mineira",
        "attribution_conversion_paths_demand",
        "portal_casa_mineira_advertiser_metrics",
        "buyer_activation_events_combo",
        "unique_owners",
        "casa_mineira_top_of_funnel_volumes_weekly",
        "casa_mineira_top_of_funnel_volumes_daily",
    },
    "dw_datamarts/for_rent": {
        "house_available_hours",
        "house_weekly_available_hours",
        "datamart_kpi_weekly",
        "datamart_cohort_rentals",
        "house_weekly_entrance_info",
        "repressed_demand",
        "ongoing_listed_suspended_listings",
        "contract_termination",
        "weekly_demand_metrics",
        "datamart_opportunity",
    },
    "dw_datamarts/for_sale_cross": {
        "sale_ongoing_listings",
        "houses_3p",
        "sale_events_funnel",
        "temp_supply_flows",
        "sale_cohort_conversions",
        "agents_3p",
    },
    "dw_datamarts/growth_dep_manual_costs": {
        "performance_marketing_metrics_demand",
        "performance_marketing_metrics_supply",
        "marketing_demand_supply_branding_costs",
        "sale_performance_marketing_metrics_demand",
        "marketing_allocated_costs",
        "sale_performance_marketing_metrics_supply_cohort",
        "sale_performance_marketing_metrics_supply_coincident",
        "indicaai_costs",
        "marketing_campaigns_costs_and_volumes",
        "unique_performance_marketing_metrics_supply_coincident",
        "affiliate_acquisition_metrics",
        "rental_performance_marketing_metrics_supply_coincident",
    },
    "dw_datamarts/growth_cross": {
        "rental_cohort_conversions",
        "sale_performance_marketing_metrics_demand",
        "inbound_attendance_leads_flows",
        "unique_performance_marketing_metrics_supply_coincident",
        "top_of_funnel_volumes_weekly",
        "rental_marketplace_flows",
        "top_of_funnel_volumes_monthly",
        "tenant_prospect_status",
        "marketing_allocated_costs",
        "affiliates_clusters",
        "efficiency_monitor_sale",
        "marketing_campaigns_costs_and_volumes",
        "plaquinhas_users_demand",
        "affiliate_acquisition_metrics",
        "plaquinhas_metrics",
        "unique_supply_events_funnel",
        "marketing_demand_supply_branding_costs",
        "house_demand_trends",
        "top_of_funnel_volumes_daily",
        "performance_marketing_cluster_promotional_bonus_costs",
        "tenant_prospects_activations",
        "rent_flow_interactions",
        "efficiency_monitor_rental",
        "rental_performance_marketing_metrics_supply_coincident",
        "pricing_rent_categorization",
        "demand_housing_cluster_changes",
        "performance_marketing_metrics_demand",
        "unique_supply_cohort_conversions",
        "performance_marketing_cluster_promotional_bonus",
        "daily_target_volumes_supply",
        "user_funnel",
        "sale_performance_marketing_metrics_supply_coincident",
        "indicaai_costs",
    },
    "dw_datamarts/support_and_service": {
        "house_media",
        "customer_sessions_resolution",
        "repressed_demand_booking_fit_in",
        "ongoing_refund_requests",
    },
    "dw_datamarts/for_sale": {
        "repressed_demand_sale",
        "neighborhood_competition",
        "temp_sale_offers",
        "temp_autonomous_agents_listings",
        "sale_agents_weekly_performance",
        "dim_house_listing_amenities",
        "sale_ongoing_listings_casa_mineira",
        "deal_making_funnel",
        "loft_house_listing",
        "loft_status_listing_flows",
        "em_casa_house_listing",
        "buyer_first_visit_intent",
        "repressed_demand_sale_booking_fit_in",
        "buyer_visit_lead_flows",
        "em_casa_house_listing_flows",
    },
    "dw_datamarts/for_rent_cross": {
        "rental_events_funnel_partners",
        "user_cohort_rental_demand_conversion",
        "rental_events_funnel",
        "credit_proposal_attribute",
        "rental_demand_events_funnel_flows",
    },
}


def get_all_datamarts_files():
    return {
        file: "M"
        for file in FileService.list_dag_files()
        if re.search(DATAMARTS_DAG_REGEX, file)
    }


def get_files_from_diff(branch):
    if branch == "master":
        from_branch = "HEAD~1"
    else:
        from_branch = "origin/master"

    git_service = GitService()
    return git_service.get_modified_files_from_diff(from_branch, "HEAD")


def table_in_skip_list(intermediate_path, table_name):
    try:
        if table_name in SKIP_LIST[intermediate_path]:
            return True
        else:
            return False
    except KeyError:
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(dest="branch")
    parser.add_argument(
        "--validate-all-files", dest="validate_all_files", action="store_true"
    )
    args = parser.parse_args()
    validate_all_files = args.validate_all_files
    branch = args.branch

    if validate_all_files:
        files = get_all_datamarts_files()
    else:
        files = get_files_from_diff(branch)

    if not files:
        print(f"No new/modified files found")
        exit(0)

    failed = []

    for file, status in files.items():
        if status == "D":
            logger.debug(f"file={file} msg=Skipping deleted file")
            continue

        match_dag = re.search(DATAMARTS_DAG_REGEX, file)
        match_yaml = re.search(DATAMARTS_YAML_REGEX, file)

        if match_dag:
            match_dict = match_dag.groupdict()
        elif match_yaml:
            match_dict = match_yaml.groupdict()
        else:
            # skipping non-matched file
            continue

        context = match_dict.get("context")
        dag_name = match_dict.get("dagname")
        if context and dag_name:
            dag_intermediate_path = f"dw_datamarts/{context}"
            lineage_intermediate_path = f"dw_datamarts_{context}"
            configs = ConfigurationService(
                dag_name, intermediate_path=dag_intermediate_path, env="prod"
            )
            for pipeline, pipe_configs in configs.get_config("pipeline").items():
                table_name = pipe_configs["dw"]["table"]
                if table_in_skip_list(dag_intermediate_path, table_name):
                    logger.info(
                        f"dag={dag_intermediate_path}, table_name={table_name}, msg=Table in skip list"
                    )
                    continue
                if not FileService.metadata_file_exists(
                    lineage_intermediate_path, "dw", table_name
                ):
                    failed.append((dag_intermediate_path, table_name))

    if failed:
        print("Datamart tables without metadata files:")
        for intermediate_path, table_name in failed:
            print(f"dag={intermediate_path} table={table_name}")
        print("Please create missing lineage YAML files")
        exit(1)
    else:
        print("All files successfully validated!")
        exit(0)


if __name__ == "__main__":
    main()
