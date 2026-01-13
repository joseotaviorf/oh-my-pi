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

def get_access_token(endpoint, env):
    # Initializing clients
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    if env == "forno":
      api_credentials = json.loads(
          dbutils.secrets.get(scope="quintoandar", key=APIEnum.SALESFORCE_FORNO)
      )
    elif env == "prod":
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
       'cases':
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
                            StructField("IsABTest__c", StringType()),
                            StructField("ContractIdOddOrEven__c", StringType()),
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
                            StructField("AccountName__c", StringType()),
                            StructField("BYContactSuccess__c", StringType()),
                            StructField("BYCurrentOnboardingContact__c", StringType()),
                            StructField("CRNStatus__c", StringType()),
                            StructField("customerId__c", StringType()),
                            StructField("FlowSubType__c", StringType()),
                            StructField("ForSaleFlow__c", StringType()),
                            StructField("FS_BalancePaymentMade__c", StringType()),
                            StructField("FS_BY_KeyDeliveryDate__c", StringType()),
                            StructField("FS_BYNextContactDate__c", StringType()),
                            StructField("FS_CCVSigned__c", StringType()),
                            StructField("FS_CRI_HaveDemandNote__c", StringType()),
                            StructField("FS_CRIStatus__c", StringType()),
                            StructField("FS_DDAcceptedDate__c", StringType()),
                            StructField("FS_KeysReceived__c", StringType()),
                            StructField("FS_MilestoneFinish__c", StringType()),
                            StructField("FS_PDSL_SubscriptionSchedulingDate__c", StringType()),
                            StructField("FS_ReturnDate__c", StringType()),
                            StructField("FS_SL_KeyDeliveryDate__c", StringType()),
                            StructField("FS_SLNextContactDate__c", StringType()),
                            StructField("FS_StatusCRI__c", StringType()),
                            StructField("FS_SubscriptionModelBuyer__c", StringType()),
                            StructField("FS_SubscriptionModelSeller__c", StringType()),
                            StructField("KeyDeliveryDate__c", StringType()),
                            StructField("MS_TT_Date_BudgetReviewIQCreatedDateTD__c", StringType()),
                            StructField("PublicationOccurredOnProperty__c", StringType()),
                            StructField("PurchaseSaleContract__c", StringType()),
                            StructField("ReasonForRetry__c", StringType()),
                            StructField("SLContactSuccess__c", StringType()),
                            StructField("SLCurrentOnboardingContact__c", StringType()),
                            StructField("UnlistingReason__c", StringType()),
                            StructField("UnassignedReason__c", StringType()),
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
                            StructField("IsABTest__c", StringType()),
                            StructField("ContractIdOddOrEven__c", StringType()),
                            StructField("ExperimentGroup__c", StringType()),
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
                            StructField("CallId__c", StringType()),
                            StructField("CognitoLink__c", StringType()),
                            StructField("EntityId__c", StringType()),
                            StructField("FS_CRI_RegistrationCompleted__c", StringType()),
                            StructField("FS_KeysReceived__c", StringType()),
                            StructField("FS_OfferId__c", StringType()),
                            StructField("FS_PurchaseSaleContract__c", StringType()),
                            StructField("FS_ReasonDelay__c", StringType()),
                            StructField("FS_Seller__c", StringType()),
                            StructField("GetResponse__c", StringType()),
                            StructField("KeyDeliveryDate__c", StringType()),
                            StructField("PaidViaTed__c", StringType()),
                            StructField("QuestionResolvedInformedCustomer__c", StringType()),
                            StructField("RecordTypeId", StringType()),
                            StructField("ReturnDateCustomer__c", StringType()),
                            StructField("SchedulingDate__c", StringType()),
                            StructField("SchedulingManagement__c", StringType()),
                            StructField("SLA__c", StringType()),
                            StructField("Source__c", StringType()),
                            StructField("TaskAction__c", StringType()),
                            StructField("TaskDueDateFormula__c", StringType()),
                            StructField("TaskManagement__c", StringType()),
                            StructField("WasDisagreement__c", StringType()),
                            StructField("UnlistingReason__c", StringType()),
                            StructField("CommunicationTask__c", StringType()),
                            StructField("HSMSent__c", StringType()),
                            StructField("SourceTask__c", StringType()),
                            StructField("EmailSent__c", StringType()),
                            StructField("CommunicationStatus__c", StringType()),
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
       'purchase_sale_contract':
            {
                'schema':
					StructType(
      					[
      						StructField("Id",StringType()),
      						StructField("OwnerId",StringType()),
      						StructField("IsDeleted",StringType()),
      						StructField("Name",StringType()),
      						StructField("CreatedDate",StringType()),
      						StructField("CreatedById",StringType()),
      						StructField("LastModifiedDate",StringType()),
      						StructField("LastModifiedById",StringType()),
      						StructField("SystemModstamp",StringType()),
      						StructField("LastActivityDate",StringType()),
      						StructField("LastViewedDate",StringType()),
      						StructField("LastReferencedDate",StringType()),
      						StructField("CCVStatus__c",StringType()),
      						StructField("CRNStatus__c",StringType()),
      						StructField("ContinueWithPartnerRegistry__c",StringType()),
      						StructField("DiligenceClassification__c",StringType()),
      						StructField("DiligenceStatus__c",StringType()),
      						StructField("FS_CRIStatus__c",StringType()),
      						StructField("HasDownPaymentExtension__c",StringType()),
      						StructField("HouseChattelMortgage__c",StringType()),
      						StructField("HouseState__c",StringType()),
      						StructField("ITBIStatus__c",StringType()),
      						StructField("IsDiligenceAccepted__c",StringType()),
      						StructField("IsDownPaymentPaid__c",StringType()),
      						StructField("KeysReceived__c",StringType()),
      						StructField("PaidViaTed__c",StringType()),
      						StructField("PaymentMethod__c",StringType()),
      						StructField("SignalBrokerage__c",StringType()),
      						StructField("StageUF__c",StringType()),
      						StructField("Stage__c",StringType()),
      						StructField("AgentEmail__c",StringType()),
      						StructField("BYPaysEntireDeposit__c",StringType()),
      						StructField("Buyer__c",StringType()),
      						StructField("CCVSignedAt__c",StringType()),
      						StructField("CRNAgentEmail__c",StringType()),
      						StructField("RescissionStatusForm__c",StringType()),
      						StructField("CRNUser__c",StringType()),
      						StructField("ClauseIdentifiers__c",StringType()),
      						StructField("DownPaymentDeadline__c",StringType()),
      						StructField("ExternalId__c",StringType()),
      						StructField("FS_BY_KeyDeliveryDate__c",StringType()),
      						StructField("FS_SL_KeyDeliveryDate__c",StringType()),
      						StructField("HouseRegistryMustBeUpdated__c",StringType()),
      						StructField("IsSuspended__c",StringType()),
      						StructField("KeyDeliveryDate__c",StringType()),
      						StructField("OfferId__c",StringType()),
      						StructField("SalesFlowUrl__c",StringType()),
      						StructField("Seller__c",StringType()),
      						StructField("SubscriptionSchedulingDate__c",StringType()),
      						StructField("TerminationCreatedAt__c",StringType()),
      						StructField("ZendeskUrl__c",StringType()),
      						StructField("FS_BalancePaymentMade__c",StringType()),
      						StructField("SimplifiedStage__c",StringType()),
      						StructField("SubscriptionModelBuyer__c",StringType()),
      						StructField("SubscriptionModelSeller__c",StringType()),
      						StructField("CRI_Password__c",StringType()),
      						StructField("CRI_Protocol__c",StringType()),
      						StructField("IsAssigned__c",StringType()),
      						StructField("CRNName__c",StringType()),
      						StructField("AlienationStatus__c",StringType()),
      						StructField("BypassRescissionValidation__c",StringType()),
      						StructField("CCVTerminationCreatedAt__c",StringType()),
      						StructField("CRI_HaveDemandNote__c",StringType()),
      						StructField("CRNPartner__c",StringType()),
      						StructField("Escrivao__c",StringType()),
      						StructField("HaveUnpaidAlienation__c",StringType()),
      						StructField("HouseOccupant__c",StringType()),
      						StructField("PreemptiveRight__c",StringType()),
      						StructField("ProofPaymentReceived__c",StringType()),
      						StructField("RequestType__c",StringType()),
      						StructField("RequestedBy__c",StringType()),
      						StructField("RescissionStatus__c",StringType()),
      						StructField("ShareCommunityPortal__c",StringType()),
      						StructField("AddendumStatus__c",StringType()),
      						StructField("ListViewUser__c",StringType()),
      						StructField("AddendumStatusForm__c",StringType()),
      						StructField("AVE_HaveDemandNote__c",StringType()),
      						StructField("FID_DischargeTermReceived__c",StringType()),
      						StructField("BookkeepingDoneDateCCV__c",StringType()),
      						StructField("CRIDoneDateCCV__c",StringType()),
      						StructField("ConcomitantRegistration__c",StringType()),
      						StructField("DDAcceptedDate__c",StringType()),
      						StructField("FS_AVE_PasswordCCV__c",StringType()),
      						StructField("FS_AVE_ProtocolCCV__c",StringType()),
      						StructField("FS_CRINameCCV__c",StringType()),
      						StructField("FS_CRI_RequestDateCCV__c",StringType()),
      						StructField("FS_EndorsementStatusCCV__c",StringType()),
      						StructField("FS_Endorsement_RequestDateCCV__c",StringType()),
      						StructField("FS_IDCartorioCCV__c",StringType()),
      						StructField("FS_ReasonNonConversionCCV__c",StringType()),
      						StructField("Address__c",StringType()),
      						StructField("DealMakerEmail__c",StringType()),
      						StructField("FS_ResponsibleAssistantCCV__c",StringType()),
      						StructField("LTBookkeepingDoneForm__c",StringType()),
      						StructField("FS_ReasonsLTOverrunRegisterCCV__c",StringType()),
      						StructField("FS_ReasonsLTOverrunCCV__c",StringType()),
      						StructField("DealMakerName__c",StringType()),
      						StructField("HubName__c",StringType()),
      						StructField("LeaseComplaintSent__c",StringType()),
      						StructField("LongTermPayment__c",StringType()),
      						StructField("Faixa_de_Dias_desde_CCV__c",StringType()),
      						StructField("ThreadId__c",StringType()),
      						StructField("HouseRegistryMustBeUpdatedForm__c",StringType()),
      						StructField("HaveDemandNoteReason__c",StringType()),
      						StructField("CCVCompletionDate__c",StringType()),
                            StructField("CRN_Complexity__c",StringType()),
      					]
    			)
            },
       'relisting_context':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id",StringType()),
                            StructField("OwnerId",StringType()),
                            StructField("HouseId__c",StringType()),
                            StructField("Contract__c",StringType()),
                            StructField("Termination__c",StringType()),
                            StructField("ExternalId__c",StringType()),
                            StructField("CreatedById",StringType()),
                            StructField("LastModifiedById",StringType()),
                            StructField("Name",StringType()),
                            StructField("ListingStatus__c",StringType()),
                            StructField("IsDeleted",StringType()),
                            StructField("IsEarlyRelistingActive__c",StringType()),
                            StructField("IsRelistingEligible__c",StringType()),
                            StructField("CreatedDate",StringType()),
                            StructField("LastModifiedDate",StringType()),
                            StructField("SystemModstamp",StringType()),
                            StructField("LastViewedDate",StringType()),
                            StructField("LastReferencedDate",StringType()),
                        ]
                    )
            },
       'users':
            {
                'schema':
                    StructType(
                    [
                        StructField("attributes", StringType()),
                        StructField("Id", StringType()),
                        StructField("Username", StringType()),
                        StructField("LastName", StringType()),
                        StructField("FirstName", StringType()),
                        StructField("MiddleName", StringType()),
                        StructField("Suffix", StringType()),
                        StructField("Name", StringType()),
                        StructField("CompanyName", StringType()),
                        StructField("Division", StringType()),
                        StructField("Department", StringType()),
                        StructField("Title", StringType()),
                        StructField("Street", StringType()),
                        StructField("City", StringType()),
                        StructField("State", StringType()),
                        StructField("PostalCode", StringType()),
                        StructField("Country", StringType()),
                        StructField("Latitude", StringType()),
                        StructField("Longitude", StringType()),
                        StructField("GeocodeAccuracy", StringType()),
                        StructField("Address", StringType()),
                        StructField("Email", StringType()),
                        StructField("EmailPreferencesAutoBcc", StringType()),
                        StructField("EmailPreferencesAutoBccStayInTouch", StringType()),
                        StructField("EmailPreferencesStayInTouchReminder", StringType()),
                        StructField("SenderEmail", StringType()),
                        StructField("SenderName", StringType()),
                        StructField("Signature", StringType()),
                        StructField("StayInTouchSubject", StringType()),
                        StructField("StayInTouchSignature", StringType()),
                        StructField("StayInTouchNote", StringType()),
                        StructField("Phone", StringType()),
                        StructField("Fax", StringType()),
                        StructField("MobilePhone", StringType()),
                        StructField("Alias", StringType()),
                        StructField("CommunityNickname", StringType()),
                        StructField("BadgeText", StringType()),
                        StructField("IsActive", StringType()),
                        StructField("TimeZoneSidKey", StringType()),
                        StructField("UserRoleId", StringType()),
                        StructField("LocaleSidKey", StringType()),
                        StructField("ReceivesInfoEmails", StringType()),
                        StructField("ReceivesAdminInfoEmails", StringType()),
                        StructField("EmailEncodingKey", StringType()),
                        StructField("ProfileId", StringType()),
                        StructField("UserType", StringType()),
                        StructField("StartDay", StringType()),
                        StructField("EndDay", StringType()),
                        StructField("LanguageLocaleKey", StringType()),
                        StructField("EmployeeNumber", StringType()),
                        StructField("DelegatedApproverId", StringType()),
                        StructField("ManagerId", StringType()),
                        StructField("LastLoginDate", StringType()),
                        StructField("LastPasswordChangeDate", StringType()),
                        StructField("CreatedDate", StringType()),
                        StructField("CreatedById", StringType()),
                        StructField("LastModifiedDate", StringType()),
                        StructField("LastModifiedById", StringType()),
                        StructField("SystemModstamp", StringType()),
                        StructField("PasswordExpirationDate", StringType()),
                        StructField("NumberOfFailedLogins", StringType()),
                        StructField("SuAccessExpirationDate", StringType()),
                        StructField("OfflineTrialExpirationDate", StringType()),
                        StructField("IndividualId", StringType()),
                        StructField("BPO__c", StringType()),
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
        access_token, instance_url = get_access_token(forno_endpoint, environment)
    elif environment == 'prod':
        access_token, instance_url = get_access_token(prod_endpoint, environment)

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
