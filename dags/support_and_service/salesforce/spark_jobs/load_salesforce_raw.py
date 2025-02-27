import ast
import requests
import json

from argparse import ArgumentParser
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
import logging
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql.types import StructType, StructField, StringType
from pyspark.sql.functions import col, year, month, day


JOB_NAME = "load_salesforce_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def parse_arguments():
    """
    Parse the arguments passed to the job.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("bucket")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("table_name")
    parser.add_argument("partitions")
    parser.add_argument("schema")
    parser.add_argument("forno_endpoint")
    parser.add_argument("prod_endpoint")
    parser.add_argument("query")

    args = parser.parse_args()

    environment = args.env
    bucket = args.bucket
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name
    partitions = ast.literal_eval(args.partitions)
    schema = args.schema
    forno_endpoint = args.forno_endpoint
    prod_endpoint = args.prod_endpoint
    query = args.query

    return environment, bucket, load_start_date, load_end_date, table_name, partitions, schema, forno_endpoint, prod_endpoint, query

def get_access_token(endpoint):

    # Initializing clients
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    api_credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.SALESFORCE)
    )

    req_url = f'{endpoint}/services/oauth2/token'

    payload = {
        "client_id": api_credentials['client_id'],
        "client_secret": api_credentials['client_secret'],
        "grant_type": "client_credentials"
    }
    r = requests.post(req_url, data=payload)

    access_token = r.json().get("access_token")
    instance_url = r.json().get("instance_url")

    return access_token, instance_url

def schema_define():
    return {
        'terminations':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("Name", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("LastActivityDate", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("AdminTermination__c", StringType()),
                            StructField("AgreementAndImprovements__c", StringType()),
                            StructField("AllRepairsExemptedByOwner__c", StringType()),
                            StructField("BeforeRental__c", StringType()),
                            StructField("BudgetApprovalResponseIQ__c", StringType()),
                            StructField("BudgetApprovalResponsePP__c", StringType()),
                            StructField("ConsumptionProofSubmissionIQ__c", StringType()),
                            StructField("Eviction__c", StringType()),
                            StructField("HasBudgetApproval__c", StringType()),
                            StructField("HighValueContract__c", StringType()),
                            StructField("InspectionOptedOut__c", StringType()),
                            StructField("InspectionRequired__c", StringType()),
                            StructField("IntermediationRequired__c", StringType()),
                            StructField("InternalAdministration__c", StringType()),
                            StructField("JobTransfer__c", StringType()),
                            StructField("LandlordSelling__c", StringType()),
                            StructField("NoticeDue__c", StringType()),
                            StructField("ProOwner__c", StringType()),
                            StructField("RepairsChargedARorPP__c", StringType()),
                            StructField("RepairsChargedPP__c", StringType()),
                            StructField("RepairsChargedToTenant__c", StringType()),
                            StructField("RepairsContestedByTenant__c", StringType()),
                            StructField("RepairsDetectedByOwner__c", StringType()),
                            StructField("RepairsDetectedInternally__c", StringType()),
                            StructField("SuccesContactIQ__c", StringType()),
                            StructField("SuccesContactPP__c", StringType()),
                            StructField("TenantCondominiumPayer__c", StringType()),
                            StructField("TerminationInFirstYear__c", StringType()),
                            StructField("TerminationStatus__c", StringType()),
                            StructField("TerminationWithPenalty__c", StringType()),
                            StructField("Case__c", StringType()),
                            StructField("Contract__c", StringType()),
                            StructField("ExternalId__c", StringType()),
                            StructField("IsValidLetter__c", StringType()),
                            StructField("ResponsibleOffManager__c", StringType()),
                            StructField("TRTerminationCreatedDate__c", StringType()),
                            StructField("TerminationDateSync__c", StringType()),
                            StructField("VacancyDate__c", StringType()),
                            StructField("TerminationUrl__c", StringType()),
                            StructField("PropertyId__c", StringType()),
                            StructField("RelistingEnabled__c", StringType()),
                            StructField("DescriptionAgreementAndImprovements__c", StringType()),
                            StructField("OwnerAnsweredBudgetApprovalReview__c", StringType()),
                            StructField("OwnerAgreedBudgetApprovalReview__c", StringType()),
                            StructField("TenantAnsweredBudgetApprovalReview__c", StringType()),
                            StructField("TenantAgreedBudgetApprovalReview__c", StringType()),
                            StructField("RequestedBy__c", StringType()),
                            StructField("ContractId__c", StringType()),
                            StructField("FeedItemComment__c", StringType()),
                        ]
                    )
            },
        'account':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("MasterRecordId", StringType()),
                            StructField("Name", StringType()),
                            StructField("Type", StringType()),
                            StructField("RecordTypeId", StringType()),
                            StructField("ParentId", StringType()),
                            StructField("BillingStreet", StringType()),
                            StructField("BillingCity", StringType()),
                            StructField("BillingState", StringType()),
                            StructField("BillingPostalCode", StringType()),
                            StructField("BillingCountry", StringType()),
                            StructField("BillingLatitude", StringType()),
                            StructField("BillingLongitude", StringType()),
                            StructField("BillingGeocodeAccuracy", StringType()),
                            StructField("BillingAddress", StringType()),
                            StructField("ShippingStreet", StringType()),
                            StructField("ShippingCity", StringType()),
                            StructField("ShippingState", StringType()),
                            StructField("ShippingPostalCode", StringType()),
                            StructField("ShippingCountry", StringType()),
                            StructField("ShippingLatitude", StringType()),
                            StructField("ShippingLongitude", StringType()),
                            StructField("ShippingGeocodeAccuracy", StringType()),
                            StructField("ShippingAddress", StringType()),
                            StructField("Phone", StringType()),
                            StructField("Fax", StringType()),
                            StructField("AccountNumber", StringType()),
                            StructField("Website", StringType()),
                            StructField("PhotoUrl", StringType()),
                            StructField("Sic", StringType()),
                            StructField("Industry", StringType()),
                            StructField("AnnualRevenue", StringType()),
                            StructField("NumberOfEmployees", StringType()),
                            StructField("Ownership", StringType()),
                            StructField("TickerSymbol", StringType()),
                            StructField("Description", StringType()),
                            StructField("Rating", StringType()),
                            StructField("Site", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("LastActivityDate", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("SourceSystemIdentifier", StringType()),
                            StructField("Jigsaw", StringType()),
                            StructField("JigsawCompanyId", StringType()),
                            StructField("AccountSource", StringType()),
                            StructField("SicDesc", StringType()),
                            StructField("CustomerId__c", StringType()),
                            StructField("ExternalId__c", StringType()),
                            StructField("Email__c", StringType()),
                        ]
                    )
            },
       'contract_member':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("Name", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("Type__c", StringType()),
                            StructField("Account__c", StringType()),
                            StructField("Contract__c", StringType()),
                            StructField("ExternalId__c", StringType()),
                        ]
                    )
            },
       'contract':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("Name", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("LastActivityDate", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("ContractTerm__c", StringType()),
                            StructField("ExternalId__c", StringType()),
                            StructField("StartDate__c", StringType()),
                        ]
                    )
            },
       'case':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("MasterRecordId", StringType()),
                            StructField("CaseNumber", StringType()),
                            StructField("ContactId", StringType()),
                            StructField("AccountId", StringType()),
                            StructField("AssetId", StringType()),
                            StructField("ProductId", StringType()),
                            StructField("EntitlementId", StringType()),
                            StructField("SourceId", StringType()),
                            StructField("BusinessHoursId", StringType()),
                            StructField("ParentId", StringType()),
                            StructField("SuppliedName", StringType()),
                            StructField("SuppliedEmail", StringType()),
                            StructField("SuppliedPhone", StringType()),
                            StructField("SuppliedCompany", StringType()),
                            StructField("Type", StringType()),
                            StructField("RecordTypeId", StringType()),
                            StructField("Status", StringType()),
                            StructField("Reason", StringType()),
                            StructField("Origin", StringType()),
                            StructField("Language", StringType()),
                            StructField("Subject", StringType()),
                            StructField("Priority", StringType()),
                            StructField("Description", StringType()),
                            StructField("IsClosed", StringType()),
                            StructField("ClosedDate", StringType()),
                            StructField("IsEscalated", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("IsClosedOnCreate", StringType()),
                            StructField("SlaStartDate", StringType()),
                            StructField("SlaExitDate", StringType()),
                            StructField("IsStopped", StringType()),
                            StructField("StopStartDate", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("ContactPhone", StringType()),
                            StructField("ContactMobile", StringType()),
                            StructField("ContactEmail", StringType()),
                            StructField("ContactFax", StringType()),
                            StructField("Comments", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("ServiceContractId", StringType()),
                            StructField("MilestoneStatus", StringType()),
                            StructField("ContestationResponsabilityValid__c", StringType()),
                            StructField("InformationCollected__c", StringType()),
                            StructField("LandlordInformedServiceProvider__c", StringType()),
                            StructField("PastDueDateSimulation__c", StringType()),
                            StructField("SimulationTenantBudgetTimeLimit__c", StringType()),
                            StructField("criticality__c", StringType()),
                            StructField("followUpDescription__c", StringType()),
                            StructField("followUpExpectedResolutionDate__c", StringType()),
                            StructField("followUpReassignDate__c", StringType()),
                            StructField("followUpStatus__c", StringType()),
                            StructField("isContest__c", StringType()),
                            StructField("RepairId__c", StringType()),
                            StructField("serviceProviderJourney__c", StringType()),
                            StructField("serviceProviderName__c", StringType()),
                            StructField("serviceProviderPhone__c", StringType()),
                            StructField("serviceProviderType__c", StringType()),
                            StructField("AlreadyAskedForApproval__c", StringType()),
                            StructField("AlreadyContested__c", StringType()),
                            StructField("CaseCreationStartMilestoneClosed__c", StringType()),
                            StructField("CaseCreationStartMilestone__c", StringType()),
                            StructField("LLBudgetApprovalTimeLimit__c", StringType()),
                            StructField("LLServiceConcluded__c", StringType()),
                            StructField("LandlordInformedTTServiceProvider__c", StringType()),
                            StructField("LandlordProviderNoHelpMilestoneClosed__c", StringType()),
                            StructField("LandlordProviderNoHelpMilestone__c", StringType()),
                            StructField("PPacceptedDoingRepair__c", StringType()),
                            StructField("RequestedHelpTimeLimit__c", StringType()),
                            StructField("TTsolicitedHelp__c", StringType()),
                            StructField("TenantProviderOwnerApprovalClosed__c", StringType()),
                            StructField("TenantProviderOwnerApprovalMilestone__c", StringType()),
                            StructField("TenantServiceProviderMilestoneClosed__c", StringType()),
                            StructField("TenantServiceProviderMilestone__c", StringType()),
                            StructField("ContractId__c", StringType()),
                            StructField("ZendeskId__c", StringType()),
                            StructField("ZendeskUrl__c", StringType()),
                            StructField("AgentRepublishedWithPP__c", StringType()),
                            StructField("ContactSuccess__c", StringType()),
                            StructField("MS_TT_Close_BudgetReviewIQ__c", StringType()),
                            StructField("MS_TT_Close_BudgetReviewPP__c", StringType()),
                            StructField("MS_TT_Close_ReportReviewIQ__c", StringType()),
                            StructField("MS_TT_Close_ReportReviewPP__c", StringType()),
                            StructField("MS_TT_Open_BudgetReviewIQ__c", StringType()),
                            StructField("MS_TT_Open_BudgetReviewPP__c", StringType()),
                            StructField("MS_TT_Open_ReportReviewIQ__c", StringType()),
                            StructField("MS_TT_Open_ReportReviewPP__c", StringType()),
                            StructField("Termination__c", StringType()),
                            StructField("ExternalId__c", StringType()),
                        ]
                    )
            },
       'task':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("WhoId", StringType()),
                            StructField("WhatId", StringType()),
                            StructField("WhoCount", StringType()),
                            StructField("WhatCount", StringType()),
                            StructField("Subject", StringType()),
                            StructField("ActivityDate", StringType()),
                            StructField("Status", StringType()),
                            StructField("Priority", StringType()),
                            StructField("IsHighPriority", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("Description", StringType()),
                            StructField("Type", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("AccountId", StringType()),
                            StructField("IsClosed", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("IsArchived", StringType()),
                            StructField("CallDurationInSeconds", StringType()),
                            StructField("CallType", StringType()),
                            StructField("CallDisposition", StringType()),
                            StructField("CallObject", StringType()),
                            StructField("ReminderDateTime", StringType()),
                            StructField("IsReminderSet", StringType()),
                            StructField("RecurrenceActivityId", StringType()),
                            StructField("IsRecurrence", StringType()),
                            StructField("RecurrenceStartDateOnly", StringType()),
                            StructField("RecurrenceEndDateOnly", StringType()),
                            StructField("RecurrenceTimeZoneSidKey", StringType()),
                            StructField("RecurrenceType", StringType()),
                            StructField("RecurrenceInterval", StringType()),
                            StructField("RecurrenceDayOfWeekMask", StringType()),
                            StructField("RecurrenceDayOfMonth", StringType()),
                            StructField("RecurrenceInstance", StringType()),
                            StructField("RecurrenceMonthOfYear", StringType()),
                            StructField("RecurrenceRegeneratedType", StringType()),
                            StructField("TaskSubtype", StringType()),
                            StructField("CompletedDateTime", StringType()),
                            StructField("PassDueDate__c", StringType()),
                            StructField("ResponsabilityContestingIsGood__c", StringType()),
                            StructField("TaskName__c", StringType()),
                            StructField("Type__c", StringType()),
                            StructField("TaskInteractionType__c", StringType()),
                            StructField("FirstInteractionDate__c", StringType()),
                            StructField("DelayMessage__c", StringType()),
                            StructField("CaseCriticality__c", StringType()),
                            StructField("CaseAccount__c", StringType()),
                            StructField("Answer__c", StringType()),
                            StructField("TaskCreatedDate__c", StringType()),
                            StructField("Observation__c", StringType()),
                            StructField("ContractId__c", StringType()),
                        ]
                    )
            },
       'checklist':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("Name", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("LastActivityDate", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("Done__c", StringType()),
                            StructField("Active__c", StringType()),
                            StructField("Termination__c", StringType()),
                            StructField("Type__c", StringType()),
                            StructField("ExternalId__c", StringType()),
                        ]
                    )
            },
    }

def get_next_page_data(query, headers, instance_url, table_name, is_done, next_url):
    # Make a GET request to the Salesforce API
    if next_url is None and is_done == False:
        endpoint = f'/services/data/v52.0/query/?q={query.replace(" ", "+")}'
    elif next_url is not None and is_done == False:
        endpoint = next_url

    api_endpoint = f'{instance_url}{endpoint}'

    response = requests.get(api_endpoint, headers=headers)
    response_json = response.json()

    print(response_json)

    is_done = response_json['done']
    next_url = response_json.get('nextRecordsUrl', None)

    df_schema = schema_define()[table_name]['schema']
    df = spark.createDataFrame(response_json.get('records', []), schema=df_schema)

    df = df.withColumn("dt_updated", col("LastModifiedDate").cast("date"))
    df = df.withColumn("year", year(col("dt_updated")))
    df = df.withColumn("month", month(col("dt_updated")))
    df = df.withColumn("day", day(col("dt_updated")))

    return df, is_done, next_url

def main():
    environment, bucket, load_start_date, load_end_date, table_name, partitions, schema, forno_endpoint, prod_endpoint, query = parse_arguments()

    load_start_timstamp = f"{load_start_date}T00:00:00.000000Z"
    load_end_timstamp = f"{load_end_date}T23:59:59.000000Z"

    query += f" WHERE LastModifiedDate >= {load_start_timstamp} AND LastModifiedDate <= {load_end_timstamp}"

    if environment == 'forno':
        access_token, instance_url = get_access_token(forno_endpoint)
    elif environment == 'prod':
        access_token, instance_url = get_access_token(prod_endpoint)

    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
    }

    spark_client = SparkClient()
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    db_info = DatalakeMetastoreService.get_db_info(environment, schema, bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    is_done = False
    next_url = None

    unioned_df = None

    while is_done == False:
        df, is_done, next_url = get_next_page_data(query, headers, instance_url, table_name, is_done, next_url)

        if unioned_df is None:
            unioned_df = df
        else:
            unioned_df = unioned_df.unionByName(df, allowMissingColumns=True)

    IncrementalTableLoaderPipeline(
            database_name=database_name,
            table_name=table_name,
            database_location=database_location,
            layer=LayerEnum.RAW,
            query=None,
            partitions=partitions,
    ).load_and_register(unioned_df, format_options)

if __name__ == "__main__":
    main()
