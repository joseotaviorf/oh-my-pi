import json
import requests
import threading
import concurrent.futures

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.clients.db_clients import SparkClient


JOB_NAME = "load_reverse_bic_ss"


def create_data_payload(item):
    """
    Create the data payload based on the original spark dataframe.
    """
    data = {
        "keyName": key_name,
        "type": api_type,
    }
    data["keyValue"] = item["id_user"]

    # Create the contextFields dictionary with the desired structure
    context_fields = {
        "ts_user_updated": item.get("ts_user_updated"),
        "ts_user_created": item.get("ts_user_created"),
        "is_blocked": item.get("is_blocked"),
        "dt_user_birth": item.get("dt_user_birth"),
        "app": {
            "ts_last_app_installed": item.get("ts_last_app_installed"),
            "has_app_installed": item.get("has_app_installed"),
            "app_version": item.get("app_version"),
        },
        "persona": {
            "is_pp_multi": item.get("is_pp_multi"),
            "is_tenant": item.get("is_tenant"),
            "is_broker": item.get("is_broker"),
            "is_property_owner": item.get("is_landlord"),
            "is_photographer": item.get("is_photographer"),
        },
        "support": {
            "id_last_csi_ticket": item.get("id_last_csi_ticket"),
            "has_created_csi_ticket": item.get("has_created_csi_ticket"),
            "ts_most_recent_csi_ticket_creation_date": item.get(
                "ts_most_recent_csi_ticket_creation_date"
            ),
            "ts_most_recent_csi_ticket_solved_date": item.get(
                "ts_most_recent_csi_ticket_solved_date"
            ),
            "total_csi_tickets_created": item.get("total_csi_tickets_created"),
            "last_bot_csat_answered_score": item.get("last_bot_csat_answered_score"),
            "bot_csat_detractor_percentage_within_three_months": item.get(
                "bot_csat_detractor_percentage_within_three_months"
            ),
            "total_bot_csat_answered": item.get("total_bot_csat_answered"),
            "total_bot_csat_promoter": item.get("total_bot_csat_promoter"),
            "total_bot_csat_neutral": item.get("total_bot_csat_neutral"),
            "total_bot_csat_detractor": item.get("total_bot_csat_detractor"),
            "avg_bot_csat_score_within_three_months": item.get(
                "avg_bot_csat_score_within_three_months"
            ),
            "total_bot_csat_detractor_within_three_months": item.get(
                "total_bot_csat_detractor_within_three_months"
            ),
            "total_bot_csat_neutral_within_three_months": item.get(
                "total_bot_csat_neutral_within_three_months"
            ),
            "total_bot_csat_answered_within_three_months": item.get(
                "total_bot_csat_answered_within_three_months"
            ),
            "has_answered_bot_csat_within_three_months": item.get(
                "has_answered_bot_csat_within_three_months"
            ),
            "ts_last_bot_csat_created": item.get("ts_last_bot_csat_created"),
            "human_csat_detractor_percentage_within_three_months": item.get(
                "human_csat_detractor_percentage_within_three_months"
            ),
            "last_human_csat_answered_score": item.get(
                "last_human_csat_answered_score"
            ),
            "total_human_csat_answered": item.get("total_human_csat_answered"),
            "total_human_csat_promoter": item.get("total_human_csat_promoter"),
            "total_human_csat_neutral": item.get("total_human_csat_neutral"),
            "total_human_csat_detractor": item.get("total_human_csat_detractor"),
            "avg_human_csat_score_within_three_months": item.get(
                "avg_human_csat_score_within_three_months"
            ),
            "total_human_csat_detractor_within_three_months": item.get(
                "total_human_csat_detractor_within_three_months"
            ),
            "total_human_csat_neutral_within_three_months": item.get(
                "total_human_csat_neutral_within_three_months"
            ),
            "total_human_csat_promoter_within_three_months": item.get(
                "total_human_csat_promoter_within_three_months"
            ),
            "total_human_csat_answered_within_three_months": item.get(
                "total_human_csat_answered_within_three_months"
            ),
            "has_answered_human_csat_within_three_months": item.get(
                "has_answered_human_csat_within_three_months"
            ),
            "ts_last_human_csat_created": item.get("ts_last_human_csat_created"),
        },
        "rental": {
            "tenant_journey_step": item.get("tenant_journey_step"),
            "tenant_persona_step": item.get("tenant_persona_step"),
            "is_tenant_offboarding": item.get("is_tenant_offboarding"),
            "is_tenant_ongoing": item.get("is_tenant_ongoing"),
            "is_tenant_onboarding": item.get("is_tenant_onboarding"),
            "is_tenant_contract_to_entrance": item.get(
                "is_tenant_contract_to_entrance"
            ),
            "is_tenant_visits_to_offer": item.get("is_tenant_visits_to_offer"),
            "is_tenant_listing_and_search": item.get("is_tenant_listing_and_search"),
            "is_tenant_pre_contract": item.get("is_tenant_pre_contract"),
            "is_tenant_post_contract": item.get("is_tenant_post_contract"),
            "landlord_journey_step": item.get("landlord_journey_step"),
            "landlord_persona_step": item.get("landlord_persona_step"),
            "is_landlord_offboarding": item.get("is_landlord_offboarding"),
            "is_landlord_ongoing": item.get("is_landlord_ongoing"),
            "is_landlord_onboarding": item.get("is_landlord_onboarding"),
            "is_landlord_contract_to_entrance": item.get(
                "is_landlord_contract_to_entrance"
            ),
            "is_landlord_visits_to_offer": item.get("is_landlord_visits_to_offer"),
            "is_landlord_listing_and_search": item.get(
                "is_landlord_listing_and_search"
            ),
            "is_landlord_pre_contract": item.get("is_landlord_pre_contract"),
            "is_landlord_post_contract": item.get("is_landlord_post_contract"),
            "total_bookings": item.get("total_bookings"),
            "total_reservations": item.get("total_reservations"),
            "total_canceled_bookings": item.get("total_canceled_bookings"),
            "total_completed_visits": item.get("total_completed_visits"),
            "total_sent_offers": item.get("total_sent_offers"),
            "total_accepted_offers": item.get("total_accepted_offers"),
            "total_rejected_offers": item.get("total_rejected_offers"),
            "total_started_evaluation_proposals": item.get(
                "total_started_evaluation_proposals"
            ),
            "total_approved_evaluation_proposals": item.get(
                "total_approved_evaluation_proposals"
            ),
            "total_sent_document_proposals": item.get("total_sent_document_proposals"),
            "total_approved_credit_proposals": item.get(
                "total_approved_credit_proposals"
            ),
            "total_rejected_proposals": item.get("total_rejected_proposals"),
            "total_signed_contracts": item.get("total_signed_contracts"),
            "total_active_contracts": item.get("total_active_contracts"),
            "total_finished_contracts": item.get("total_finished_contracts"),
            "total_active_termination_contracts": item.get(
                "total_active_termination_contracts"
            ),
            "has_searched_house": item.get("has_searched_house"),
            "has_published_listings": item.get("has_published_listings"),
            "has_opted_out_listings_only": item.get("has_opted_out_listings_only"),
            "has_pending_listings_only": item.get("has_pending_listings_only"),
            "has_funnel_step": item.get("has_funnel_step"),
            "has_booked_visit": item.get("has_booked_visit"),
            "has_completed_visit": item.get("has_completed_visit"),
            "has_sent_offer": item.get("has_sent_offer"),
            "has_offer_approved": item.get("has_offer_approved"),
            "has_started_evaluation": item.get("has_started_evaluation"),
            "has_evaluation_approved": item.get("has_evaluation_approved"),
            "has_sent_doc": item.get("has_sent_doc"),
            "has_credit_approved": item.get("has_credit_approved"),
            "has_active_contract": item.get("has_active_contract"),
            "has_finished_contract": item.get("has_finished_contract"),
            "has_active_termination": item.get("has_active_termination"),
            "ts_last_house_searching": item.get("ts_last_house_searching"),
            "ts_last_listing_updated": item.get("ts_last_listing_updated"),
            "ts_last_booking": item.get("ts_last_booking"),
            "ts_last_reservation": item.get("ts_last_reservation"),
            "ts_last_booking_canceled": item.get("ts_last_booking_canceled"),
            "ts_last_visiting": item.get("ts_last_visiting"),
            "ts_last_offer_sending": item.get("ts_last_offer_sending"),
            "ts_last_offer_rejected": item.get("ts_last_offer_rejected"),
            "ts_last_offer_approval": item.get("ts_last_offer_approval"),
            "ts_last_evaluation_start": item.get("ts_last_evaluation_start"),
            "ts_last_evaluation_approval": item.get("ts_last_evaluation_approval"),
            "ts_last_doc_sending": item.get("ts_last_doc_sending"),
            "ts_last_credit_approval": item.get("ts_last_credit_approval"),
            "ts_last_proposal_rejected": item.get("ts_last_proposal_rejected"),
            "ts_last_contract_signed": item.get("ts_last_contract_signed"),
            "ts_last_termination_created": item.get("ts_last_termination_created"),
            "ts_last_termination_finished": item.get("ts_last_termination_finished"),
        },
    }

    data["contextFields"] = context_fields
    return data


def initialize_worker(local):
    local.session = requests.Session()
    local.session.headers.update(
        {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {dbutils.secrets.get(scope='quintoandar', key='MINORITY_REPORT_API')}"
        }
    )
    logger.info(f"Initializing session for thread {threading.current_thread().name}")


def send_batch_data(local, batch_number, batch):
    session = local.session
    try:
        resp = session.post(
            minority_report_endpoint,
            data=json.dumps(batch),
        )
        resp.raise_for_status()
        logger.info(f"m=send_batch_data, batch_number={batch_number} msg=Success")
    except Exception as e:
        logger.error(f"BATCH {batch_number}: {e}")


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    logger = QuintoAndarLogger("MinorityReportAPIClient")

    parser.add_argument("environment")
    parser.add_argument("dag_name")
    parser.add_argument("minority_report_endpoint")
    parser.add_argument("minority_request_header")
    parser.add_argument("api_type")
    parser.add_argument("key_name")
    parser.add_argument("batch_size")
    parser.add_argument("table_to_send")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    dag_name = args.dag_name
    minority_report_endpoint = args.minority_report_endpoint
    minority_request_header = json.loads(args.minority_request_header)
    api_type = args.api_type
    key_name = args.key_name
    batch_size = args.batch_size
    table_to_send = args.table_to_send
    execution_date = args.execution_date

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")

    query_model = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=dag_name, layer=LayerEnum.REVERSE.value, table_name=table_to_send
    )

    query_bic = query_model.format(
        year=execution_date.year,
        month=execution_date.month,
        day=execution_date.day,
    )

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, source={dag_name},
        minority_report_endpoint={minority_report_endpoint},
        execution_date={execution_date}, reverse_tag={api_type},
        table_to_send={table_to_send}"""
        "msg=Starting spark job..."
    )

    spark_client = SparkClient()

    batch_size = int(batch_size)

    max_cores = 10
    local = threading.local()

    logger.info("msg=Building dataframe list...")
    df = spark_client.conn.sql(query_bic)
    df_list = df.toJSON().map(lambda str_json: json.loads(str_json)).collect()

    logger.info("msg=Converting dataframe to batches list...")
    batches = [
        df_list[x : x + batch_size] for x in range(0, len(df_list), batch_size)
    ].copy()

    data_payload = [[create_data_payload(x) for x in batch] for batch in batches]

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=max_cores, initializer=initialize_worker, initargs=(local,)
    ) as executor:
        future_to_batch = {
            executor.submit(send_batch_data, local, batch_number, batch): (
                batch_number,
                batch,
            )
            for batch_number, batch in enumerate(data_payload, start=1)
        }
