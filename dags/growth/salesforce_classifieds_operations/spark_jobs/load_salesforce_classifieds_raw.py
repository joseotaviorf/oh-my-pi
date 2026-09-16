import ast
import json
import logging
import re
from argparse import ArgumentParser

import requests
from pyspark.sql.functions import col, day, month, year
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_salesforce_classifieds_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn


def get_dbutils():
    return BaseDBUtils().get_dbutils()


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
    parser.add_argument(
        "source_partition_column", nargs="?", default="LastModifiedDate"
    )

    add_validation_target_args(parser)
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
    source_partition_column = args.source_partition_column

    return (
        environment,
        bucket,
        load_start_date,
        load_end_date,
        table_name,
        partitions,
        schema,
        forno_endpoint,
        prod_endpoint,
        query,
        source_partition_column,
        args.target_database_name,
        args.target_table_name,
    )


def validate_url(url):
    if not re.match(r"^https://.*\.my\.salesforce\.com$", url):
        raise ValueError("Invalid url")
    return url


def validate_endpoint(endpoint):
    if not re.match(r"^/services/data/v63.0/query/[^/]*$", endpoint):
        raise ValueError("Invalid endpoint")
    return endpoint


def get_access_token(url):

    valid_url = validate_url(url)

    dbutils = get_dbutils()

    api_credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.SALESFORCE_CLASSIFIEDS)
    )

    req_url = f"{valid_url}/services/oauth2/token"

    payload = {
        "client_id": api_credentials["client_id"],
        "client_secret": api_credentials["client_secret"],
        "grant_type": "client_credentials",
    }
    r = requests.post(req_url, data=payload)

    access_token = r.json().get("access_token")
    instance_url = r.json().get("instance_url")

    return access_token, instance_url


def schema_define():
    return {
        "cases": {
            "schema": StructType(
                [
                    StructField("AccountId", StringType(), True),
                    StructField("botmakerglobal__BotmakerId__c", StringType(), True),
                    StructField("CaseNumber", StringType(), True),
                    StructField("ClosedDate", StringType(), True),
                    StructField("Codigo_Postal__c", StringType(), True),
                    StructField("Comments", StringType(), True),
                    StructField("Condicion_fiscal__c", StringType(), True),
                    StructField("ContactEmail", StringType(), True),
                    StructField("ContactFax", StringType(), True),
                    StructField("ContactId", StringType(), True),
                    StructField("ContactMobile", StringType(), True),
                    StructField("ContactPhone", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Datos_bancarios__c", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("Dias_Transcurridos__c", StringType(), True),
                    StructField("Direccion_del_cliente__c", StringType(), True),
                    StructField(
                        "Email_envio_comprobante_de_devolucion__c", StringType(), True
                    ),
                    StructField("Email_para_validacion__c", StringType(), True),
                    StructField("Fecha_de_entrega__c", StringType(), True),
                    StructField("Fecha_de_pago__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("ID_Genesys__c", StringType(), True),
                    StructField("ID_pedido_SAP__c", StringType(), True),
                    StructField("Importe__c", StringType(), True),
                    StructField("IsClosed", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsEscalated", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("MasterRecordId", StringType(), True),
                    StructField("Monto_sin_impuestos__c", StringType(), True),
                    StructField("Nombre_de_Integrador__c", StringType(), True),
                    StructField(
                        "Nombre_del_cliente_Razon_social__c", StringType(), True
                    ),
                    StructField("Nuevo_email__c", StringType(), True),
                    StructField("Nuevo_numero_OS__c", StringType(), True),
                    StructField("Numero_de_factura__c", StringType(), True),
                    StructField("Numero_de_la_oportunidad__c", StringType(), True),
                    StructField("Oportunidad__c", StringType(), True),
                    StructField("Orden_de_servicio__c", StringType(), True),
                    StructField(
                        "Organizacion_de_venta_picklist__c", StringType(), True
                    ),
                    StructField("Origin", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Pais__c", StringType(), True),
                    StructField("ParentId", StringType(), True),
                    StructField("Priority", StringType(), True),
                    StructField("Reason", StringType(), True),
                    StructField("RecordTypeId", StringType(), True),
                    StructField(
                        "Se_requiere_reenviar_la_factura__c", StringType(), True
                    ),
                    StructField("SourceId", StringType(), True),
                    StructField("Status", StringType(), True),
                    StructField("Subject", StringType(), True),
                    StructField("Subtipo__c", StringType(), True),
                    StructField("SuppliedCompany", StringType(), True),
                    StructField("SuppliedEmail", StringType(), True),
                    StructField("SuppliedName", StringType(), True),
                    StructField("SuppliedPhone", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Ticket_JIRA__c", StringType(), True),
                    StructField("Tipo_de_pago__c", StringType(), True),
                    StructField(
                        "Total_de_expectativas_de_PI_Leads__c", StringType(), True
                    ),
                    StructField("Type", StringType(), True),
                    StructField("Valor_total_del_PI__c", StringType(), True),
                    StructField("whatslly__Created_by_Whatslly__c", StringType(), True),
                ]
            )
        },
        "Task": {
            "schema": StructType(
                [
                    StructField("AccountId", StringType(), True),
                    StructField("ActivityDate", StringType(), True),
                    StructField("Call_Ani__c", StringType(), True),
                    StructField("CallDisposition", StringType(), True),
                    StructField("CallDurationInSeconds", StringType(), True),
                    StructField("Called_Number__c", StringType(), True),
                    StructField("CallObject", StringType(), True),
                    StructField("CallType", StringType(), True),
                    StructField("CompletedDateTime", StringType(), True),
                    StructField("Conversation_Id__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("Fecha_de_finalizacion__c", StringType(), True),
                    StructField("Gestion_Cross_selling__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Interaction_Url__c", StringType(), True),
                    StructField("IsArchived", StringType(), True),
                    StructField("IsClosed", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsHighPriority", StringType(), True),
                    StructField("IsRecurrence", StringType(), True),
                    StructField("IsReminderSet", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Priority", StringType(), True),
                    StructField("Queue_Name__c", StringType(), True),
                    StructField("RecurrenceActivityId", StringType(), True),
                    StructField("RecurrenceDayOfMonth", StringType(), True),
                    StructField("RecurrenceDayOfWeekMask", StringType(), True),
                    StructField("RecurrenceEndDateOnly", StringType(), True),
                    StructField("RecurrenceInstance", StringType(), True),
                    StructField("RecurrenceInterval", StringType(), True),
                    StructField("RecurrenceMonthOfYear", StringType(), True),
                    StructField("RecurrenceRegeneratedType", StringType(), True),
                    StructField("RecurrenceStartDateOnly", StringType(), True),
                    StructField("RecurrenceTimeZoneSidKey", StringType(), True),
                    StructField("RecurrenceType", StringType(), True),
                    StructField("ReminderDateTime", StringType(), True),
                    StructField("Resultado_Lead__c", StringType(), True),
                    StructField("Status", StringType(), True),
                    StructField("Status_Lead__c", StringType(), True),
                    StructField("Subject", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("TaskSubtype", StringType(), True),
                    StructField("Total_Acd_Time__c", StringType(), True),
                    StructField("Total_Ivr_Time__c", StringType(), True),
                    StructField("Type", StringType(), True),
                    StructField("WhatCount", StringType(), True),
                    StructField("WhatId", StringType(), True),
                    StructField("whatslly__Created_by_Whatslly__c", StringType(), True),
                    StructField("whatslly__Is_WhatsApp_Task__c", StringType(), True),
                    StructField("whatslly__Whatslly_Number__c", StringType(), True),
                    StructField("WhoCount", StringType(), True),
                    StructField("WhoId", StringType(), True),
                ]
            )
        },
        "Event": {
            "schema": StructType(
                [
                    StructField("AccountId", StringType(), True),
                    StructField("ActivityDate", StringType(), True),
                    StructField("ActivityDateTime", StringType(), True),
                    StructField("Call_Ani__c", StringType(), True),
                    StructField("Called_Number__c", StringType(), True),
                    StructField("Conversation_Id__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("DurationInMinutes", StringType(), True),
                    StructField("EndDate", StringType(), True),
                    StructField("EndDateTime", StringType(), True),
                    StructField("EventSubtype", StringType(), True),
                    StructField("Fecha_de_finalizacion__c", StringType(), True),
                    StructField("Gestion_Cross_selling__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Interaction_Url__c", StringType(), True),
                    StructField("IsAllDayEvent", StringType(), True),
                    StructField("IsArchived", StringType(), True),
                    StructField("IsChild", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsGroupEvent", StringType(), True),
                    StructField("IsPrivate", StringType(), True),
                    StructField("IsRecurrence", StringType(), True),
                    StructField("IsRecurrence2", StringType(), True),
                    StructField("IsRecurrence2Exception", StringType(), True),
                    StructField("IsRecurrence2Exclusion", StringType(), True),
                    StructField("IsReminderSet", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("Location", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Queue_Name__c", StringType(), True),
                    StructField("Recurrence2PatternStartDate", StringType(), True),
                    StructField("Recurrence2PatternText", StringType(), True),
                    StructField("Recurrence2PatternTimeZone", StringType(), True),
                    StructField("RecurrenceActivityId", StringType(), True),
                    StructField("RecurrenceDayOfMonth", StringType(), True),
                    StructField("RecurrenceDayOfWeekMask", StringType(), True),
                    StructField("RecurrenceEndDateOnly", StringType(), True),
                    StructField("RecurrenceInstance", StringType(), True),
                    StructField("RecurrenceInterval", StringType(), True),
                    StructField("RecurrenceMonthOfYear", StringType(), True),
                    StructField("RecurrenceStartDateTime", StringType(), True),
                    StructField("RecurrenceTimeZoneSidKey", StringType(), True),
                    StructField("RecurrenceType", StringType(), True),
                    StructField("ReminderDateTime", StringType(), True),
                    StructField("Resultado_Lead__c", StringType(), True),
                    StructField("ShowAs", StringType(), True),
                    StructField("StartDateTime", StringType(), True),
                    StructField("Status_Lead__c", StringType(), True),
                    StructField("Subject", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Total_Acd_Time__c", StringType(), True),
                    StructField("Total_Ivr_Time__c", StringType(), True),
                    StructField("Type", StringType(), True),
                    StructField("WhatCount", StringType(), True),
                    StructField("WhatId", StringType(), True),
                    StructField("whatslly__Created_by_Whatslly__c", StringType(), True),
                    StructField("whatslly__Is_WhatsApp_Task__c", StringType(), True),
                    StructField("whatslly__Whatslly_Number__c", StringType(), True),
                    StructField("WhoCount", StringType(), True),
                    StructField("WhoId", StringType(), True),
                ]
            )
        },
        "Participant": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("ParticipantAppType", StringType(), True),
                    StructField("ParticipantRole", StringType(), True),
                    StructField("ParticipantSubject", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Conversation": {
            "schema": StructType(
                [
                    StructField("ConversationChannelId", StringType(), True),
                    StructField("ConversationIdentifier", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("EndTime", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("StartTime", StringType(), True),
                ]
            )
        },
        "ConversationEntry": {
            "schema": StructType(
                [
                    StructField("ActorId", StringType(), True),
                    StructField("ActorName", StringType(), True),
                    StructField("ActorType", StringType(), True),
                    StructField("ClientDuration", StringType(), True),
                    StructField("ClientTimestamp", StringType(), True),
                    StructField("ConversationEntityId", StringType(), True),
                    StructField("ConversationId", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("EntryEndTime", StringType(), True),
                    StructField("EntryTime", StringType(), True),
                    StructField("EntryTimeMilliSecs", StringType(), True),
                    StructField("EntryType", StringType(), True),
                    StructField("HasAttachments", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("Message", StringType(), True),
                    StructField("MessageDeliverTime", StringType(), True),
                    StructField("MessageIdentifier", StringType(), True),
                    StructField("MessageReadTime", StringType(), True),
                    StructField("MessageSendTime", StringType(), True),
                    StructField("MessageStatus", StringType(), True),
                    StructField("MessageStatusCode", StringType(), True),
                    StructField("Seq", StringType(), True),
                    StructField("ServerReceivedTimestamp", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "ConversationParticipant": {
            "schema": StructType(
                [
                    StructField("AppType", StringType(), True),
                    StructField("ConversationId", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("JoinedTime", StringType(), True),
                    StructField("LastActiveTime", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LeftTime", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("ParticipantContext", StringType(), True),
                    StructField("ParticipantDisplayName", StringType(), True),
                    StructField("ParticipantEntityId", StringType(), True),
                    StructField("ParticipantKey", StringType(), True),
                    StructField("ParticipantRole", StringType(), True),
                ]
            )
        },
        "MessagingChannel": {
            "schema": StructType(
                [
                    StructField("BusinessHoursId", StringType(), True),
                    StructField("ChannelAddressIdentifier", StringType(), True),
                    StructField("ChannelDefinitionId", StringType(), True),
                    StructField("ConsentType", StringType(), True),
                    StructField("ConversationEndResponse", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("DeveloperName", StringType(), True),
                    StructField("DoubleOptInPrompt", StringType(), True),
                    StructField("EngagedResponse", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("InitialResponse", StringType(), True),
                    StructField("IsActive", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsoCountryCode", StringType(), True),
                    StructField("IsRequireDoubleOptIn", StringType(), True),
                    StructField("IsRestrictedToBusinessHours", StringType(), True),
                    StructField("Language", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("MasterLabel", StringType(), True),
                    StructField("MessageType", StringType(), True),
                    StructField("MessagingPlatformKey", StringType(), True),
                    StructField("OfflineAgentsResponse", StringType(), True),
                    StructField("OptInPrompt", StringType(), True),
                    StructField("OutsideBusinessHoursResponse", StringType(), True),
                    StructField("PlatformType", StringType(), True),
                    StructField("RoutingConfigurationId", StringType(), True),
                    StructField("RoutingType", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("TargetQueueId", StringType(), True),
                ]
            )
        },
        "MessagingEndUser": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsFullyOptedIn", StringType(), True),
                    StructField("IsoCountryCode", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Locale", StringType(), True),
                    StructField("MessageType", StringType(), True),
                    StructField("MessagingChannelId", StringType(), True),
                    StructField("MessagingConsentStatus", StringType(), True),
                    StructField("MessagingPlatformKey", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("ProfilePictureUrl", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "MessagingSession": {
            "schema": StructType(
                [
                    StructField("AcceptTime", StringType(), True),
                    StructField("AgentMessageCount", StringType(), True),
                    StructField("AgentType", StringType(), True),
                    StructField("CaseId", StringType(), True),
                    StructField("ChannelEndUserFormula", StringType(), True),
                    StructField("ChannelGroup", StringType(), True),
                    StructField("ChannelIntent", StringType(), True),
                    StructField("ChannelKey", StringType(), True),
                    StructField("ChannelLocale", StringType(), True),
                    StructField("ChannelName", StringType(), True),
                    StructField("ChannelType", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("EndTime", StringType(), True),
                    StructField("EndUserAccountId", StringType(), True),
                    StructField("EndUserContactId", StringType(), True),
                    StructField("EndUserMessageCount", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("LeadId", StringType(), True),
                    StructField("MessagingChannelId", StringType(), True),
                    StructField("MessagingEndUserId", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OpportunityId", StringType(), True),
                    StructField("Origin", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("PreviewDetails", StringType(), True),
                    StructField("SessionKey", StringType(), True),
                    StructField("StartTime", StringType(), True),
                    StructField("Status", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("TargetUserId", StringType(), True),
                ]
            )
        },
        "et4ae5__IndividualEmailResult__c": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("et4ae5__CampaignMemberId__c", StringType(), True),
                    StructField("et4ae5__Clicked__c", StringType(), True),
                    StructField("et4ae5__Contact__c", StringType(), True),
                    StructField("et4ae5__Contact_ID__c", StringType(), True),
                    StructField("et4ae5__DateBounced__c", StringType(), True),
                    StructField("et4ae5__DateOpened__c", StringType(), True),
                    StructField("et4ae5__DateSent__c", StringType(), True),
                    StructField("et4ae5__DateUnsubscribed__c", StringType(), True),
                    StructField("et4ae5__Email__c", StringType(), True),
                    StructField("et4ae5__Email_Asset_ID__c", StringType(), True),
                    StructField("et4ae5__Email_ID__c", StringType(), True),
                    StructField("et4ae5__FromAddress__c", StringType(), True),
                    StructField("et4ae5__FromName__c", StringType(), True),
                    StructField("et4ae5__HardBounce__c", StringType(), True),
                    StructField("et4ae5__Lead__c", StringType(), True),
                    StructField("et4ae5__Lead_ID__c", StringType(), True),
                    StructField("et4ae5__MergeId__c", StringType(), True),
                    StructField("et4ae5__NumberOfTotalClicks__c", StringType(), True),
                    StructField("et4ae5__NumberOfUniqueClicks__c", StringType(), True),
                    StructField("et4ae5__Opened__c", StringType(), True),
                    StructField("et4ae5__SendDefinition__c", StringType(), True),
                    StructField("et4ae5__SoftBounce__c", StringType(), True),
                    StructField("et4ae5__SubjectLine__c", StringType(), True),
                    StructField("et4ae5__Tracking_As_Of__c", StringType(), True),
                    StructField(
                        "et4ae5__TriggeredSendDefinition__c", StringType(), True
                    ),
                    StructField(
                        "et4ae5__TriggeredSendDefinitionName__c", StringType(), True
                    ),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Portal__c": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField(
                        "Organizaciones_con_ID_Empresa_compartido__c",
                        StringType(),
                        True,
                    ),
                    StructField("OwnerId", StringType(), True),
                    StructField("Permite_compartir_id_site__c", StringType(), True),
                    StructField("Portal__c", StringType(), True),
                    StructField("Sitio__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Vertical__c", StringType(), True),
                ]
            )
        },
        "Empresa_portal__History": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("DataType", StringType(), True),
                    StructField("Field", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("NewValue", StringType(), True),
                    StructField("OldValue", StringType(), True),
                    StructField("ParentId", StringType(), True),
                ]
            )
        },
        "Producto_de_orden_de_servicio__c": {
            "schema": StructType(
                [
                    StructField("Branch_ID__c", StringType(), True),
                    StructField("Cantidad__c", StringType(), True),
                    StructField("Cantidad_original__c", StringType(), True),
                    StructField("Codigo_de_producto__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Descripcion_de_partida__c", StringType(), True),
                    StructField("Descuento__c", StringType(), True),
                    StructField("Descuento_original__c", StringType(), True),
                    StructField("diferencia_meses__c", StringType(), True),
                    StructField("Duracion__c", StringType(), True),
                    StructField("Estado_de_vigencia__c", StringType(), True),
                    StructField("facturacion__c", StringType(), True),
                    StructField("Facturar_a__c", StringType(), True),
                    StructField("Fecha_de_fin_de_vigencia__c", StringType(), True),
                    StructField("Fecha_de_inicio_de_vigencia__c", StringType(), True),
                    StructField("Frecuencia_de_Facturacion__c", StringType(), True),
                    StructField("Frecuencia_de_facturacion2__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_externo__c", StringType(), True),
                    StructField("Id_externo_temporal__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Nombre_de_presupuesto__c", StringType(), True),
                    StructField("Orden_de_servicio__c", StringType(), True),
                    StructField("Pais_de_activacion__c", StringType(), True),
                    StructField("Precio_anual__c", StringType(), True),
                    StructField("Precio_de_lista__c", StringType(), True),
                    StructField("Precio_de_venta__c", StringType(), True),
                    StructField("Precio_de_venta_original__c", StringType(), True),
                    StructField("Precio_mensual__c", StringType(), True),
                    StructField("Precio_mensual2__c", StringType(), True),
                    StructField("Precio_total_original2__c", StringType(), True),
                    StructField("Precio_total2__c", StringType(), True),
                    StructField("Producto__c", StringType(), True),
                    StructField("Renovable__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Vigente__c", StringType(), True),
                ]
            )
        },
        "Facturacion__c": {
            "schema": StructType(
                [
                    StructField("CEBE__c", StringType(), True),
                    StructField("Clase_de_documento__c", StringType(), True),
                    StructField("Creada_por_ecommerce__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Divisa_OV__c", StringType(), True),
                    StructField("Documento_Posicion__c", StringType(), True),
                    StructField("Duracion_en_meses__c", StringType(), True),
                    StructField("Empresa_portal__c", StringType(), True),
                    StructField("Fecha_de_fin_de_vigencia__c", StringType(), True),
                    StructField("Fecha_de_inicio_de_vigencia__c", StringType(), True),
                    StructField("Fecha_documento__c", StringType(), True),
                    StructField("Frecuencia_de_Facturacion__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_pedido_portal__c", StringType(), True),
                    StructField("Id_pedido_SAP__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Linea_de_producto__c", StringType(), True),
                    StructField("Monto_en_Divisa_OV__c", StringType(), True),
                    StructField("Monto_en_Divisa_Transaccion__c", StringType(), True),
                    StructField("Monto_en_USD__c", StringType(), True),
                    StructField("Monto_mensualizado_moneda_OV__c", StringType(), True),
                    StructField("Motivo__c", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Oportunidad__c", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Producto__c", StringType(), True),
                    StructField("Propietario_de_empresa_portal__c", StringType(), True),
                    StructField("Referencia__c", StringType(), True),
                    StructField("Responsable_pago__c", StringType(), True),
                    StructField("Solicitante__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Tipificacion__c", StringType(), True),
                    StructField("Tipo__c", StringType(), True),
                    StructField("Via_de_pago__c", StringType(), True),
                ]
            )
        },
        "Cartera_mensual__c": {
            "schema": StructType(
                [
                    StructField("A_cobrar_MP__c", StringType(), True),
                    StructField("A_facturar__c", StringType(), True),
                    StructField("Alias_Cta_Cte__c", StringType(), True),
                    StructField("Baja_Inicial__c", StringType(), True),
                    StructField("Cancelado__c", StringType(), True),
                    StructField("Cant_oport_canceladas__c", StringType(), True),
                    StructField("Cartera_inicial__c", StringType(), True),
                    StructField("Comentario_Gestion__c", StringType(), True),
                    StructField("Con_bloqueo_cliente__c", StringType(), True),
                    StructField("Con_bloqueo_pedido__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CRM_Navent__c", StringType(), True),
                    StructField("Cuenta__c", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Descuento_temporal__c", StringType(), True),
                    StructField("Ecommerce__c", StringType(), True),
                    StructField("Empresa_portal__c", StringType(), True),
                    StructField("En_curso__c", StringType(), True),
                    StructField("En_revision__c", StringType(), True),
                    StructField("Facturado__c", StringType(), True),
                    StructField("Facturado_con_NC__c", StringType(), True),
                    StructField("Fecha__c", StringType(), True),
                    StructField("Fecha_primer_factura_mes__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_exclusivo__c", StringType(), True),
                    StructField("Importe_mensual_real__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Monto_cartera_mensual_final__c", StringType(), True),
                    StructField("Monto_cartera_mensual_inicial__c", StringType(), True),
                    StructField("Monto_factura__c", StringType(), True),
                    StructField("Motivo_Churn__c", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("NC_y_otros__c", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Primer_proximo_vencimiento__c", StringType(), True),
                    StructField("Resolucion__c", StringType(), True),
                    StructField("Semana_Gestion__c", StringType(), True),
                    StructField("Sizing__c", StringType(), True),
                    StructField("Status_Gestion__c", StringType(), True),
                    StructField("Status_plan__c", StringType(), True),
                    StructField("Subtotal_plan_renovacion__c", StringType(), True),
                    StructField("System_Cta_Cte__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Target_a_facturar__c", StringType(), True),
                    StructField("Target_comentario__c", StringType(), True),
                    StructField("Tipo_de_cartera__c", StringType(), True),
                    StructField("Total_facturacion__c", StringType(), True),
                    StructField("Total_plan__c", StringType(), True),
                    StructField(
                        "Ultimo_dia_de_vigencia_anterior__c", StringType(), True
                    ),
                    StructField("Venta_a_renovar_mensualizada__c", StringType(), True),
                    StructField("Venta_mensualizada__c", StringType(), True),
                    StructField("Ventas_a_renovar__c", StringType(), True),
                    StructField("Ventas_por_unica_vez__c", StringType(), True),
                    StructField("Ventas_recurrentes__c", StringType(), True),
                ]
            )
        },
        "Plan_de_facturacion__c": {
            "schema": StructType(
                [
                    StructField("Bloqueo_posicion__c", StringType(), True),
                    StructField("Creada_por_ecommerce__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Empresa_portal__c", StringType(), True),
                    StructField("Fecha_de_cancelacion__c", StringType(), True),
                    StructField("Fecha_factura__c", StringType(), True),
                    StructField("Fecha_fin_liquidacion__c", StringType(), True),
                    StructField("Fecha_inicio_liquidacion__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_pedido_posicion_SAP__c", StringType(), True),
                    StructField("Id_pedido_SAP__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Monto__c", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Numero_de_oportunidad__c", StringType(), True),
                    StructField("Numero_de_pedido_portal__c", StringType(), True),
                    StructField("Oportunidad__c", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Producto__c", StringType(), True),
                    StructField("Reasigna_propietario__c", StringType(), True),
                    StructField("Responsable_pago__c", StringType(), True),
                    StructField("Solicitante__c", StringType(), True),
                    StructField("Status_factura__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Via_de_pago__c", StringType(), True),
                ]
            )
        },
        "ProcessDefinition": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("DeveloperName", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LockType", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("State", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("TableEnumOrId", StringType(), True),
                    StructField("Type", StringType(), True),
                ]
            )
        },
        "ProcessInstance": {
            "schema": StructType(
                [
                    StructField("CompletedDate", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("ElapsedTimeInDays", StringType(), True),
                    StructField("ElapsedTimeInHours", StringType(), True),
                    StructField("ElapsedTimeInMinutes", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActorId", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("ProcessDefinitionId", StringType(), True),
                    StructField("Status", StringType(), True),
                    StructField("SubmittedById", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("TargetObjectId", StringType(), True),
                ]
            )
        },
        "ProcessInstanceStep": {
            "schema": StructType(
                [
                    StructField("ActorId", StringType(), True),
                    StructField("Comments", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("ElapsedTimeInDays", StringType(), True),
                    StructField("ElapsedTimeInHours", StringType(), True),
                    StructField("ElapsedTimeInMinutes", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("OriginalActorId", StringType(), True),
                    StructField("ProcessInstanceId", StringType(), True),
                    StructField("StepNodeId", StringType(), True),
                    StructField("StepStatus", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
    }


def get_next_page_data(
    spark,
    query,
    headers,
    instance_url,
    table_name,
    is_done,
    next_url,
    source_partition_column,
):
    # Make a GET request to the Salesforce API
    if next_url is None and is_done == False:
        endpoint = f"/services/data/v63.0/query/?q={query.replace(' ', '+')}"
    elif next_url is not None and is_done == False:
        endpoint = next_url

    valid_url = validate_url(instance_url)
    valid_endpoint = validate_endpoint(endpoint)

    api_endpoint = f"{valid_url}{valid_endpoint}"

    response = requests.get(api_endpoint, headers=headers)
    response_json = response.json()

    is_done = response_json["done"]
    next_url = response_json.get("nextRecordsUrl", None)

    df_schema = schema_define()[table_name]["schema"]
    df = spark.createDataFrame(response_json.get("records", []), schema=df_schema)

    df = df.withColumn("dt_updated", col(source_partition_column).cast("date"))
    df = df.withColumn("year", year(col("dt_updated")))
    df = df.withColumn("month", month(col("dt_updated")))
    df = df.withColumn("day", day(col("dt_updated")))

    return df, is_done, next_url


def main():

    # Parse arguments
    (
        environment,
        bucket,
        load_start_date,
        load_end_date,
        table_name,
        partitions,
        schema,
        forno_endpoint,
        prod_endpoint,
        query,
        source_partition_column,
        target_database_name,
        target_table_name,
    ) = parse_arguments()

    load_start_timstamp = f"{load_start_date}T00:00:00.000000Z"
    load_end_timstamp = f"{load_end_date}T23:59:59.000000Z"

    query += f" WHERE {source_partition_column} >= {load_start_timstamp} AND {source_partition_column} <= {load_end_timstamp}"

    if environment == "forno":
        access_token, instance_url = get_access_token(forno_endpoint)
    elif environment == "prod":
        access_token, instance_url = get_access_token(prod_endpoint)

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }

    # Initialize Spark Client & Metastore Service
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    db_info = DatalakeMetastoreService.get_db_info(environment, schema, bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=bucket,
            target_database=target_database_name,
            target_table=target_table_name,
        )
    )

    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(write_database_name)

    is_done = False
    next_url = None

    unioned_df = None

    while is_done == False:
        df, is_done, next_url = get_next_page_data(
            spark,
            query,
            headers,
            instance_url,
            table_name,
            is_done,
            next_url,
            source_partition_column,
        )

        if unioned_df is None:
            unioned_df = df
        else:
            unioned_df = unioned_df.unionByName(df, allowMissingColumns=True)

    IncrementalTableLoaderPipeline(
        database_name=write_database_name,
        table_name=write_table_name,
        database_location=write_location,
        layer=LayerEnum.RAW,
        query=None,
        partitions=partitions,
    ).load_and_register(unioned_df, format_options)


if __name__ == "__main__":
    main()
