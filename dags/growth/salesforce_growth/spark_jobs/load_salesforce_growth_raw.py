import ast
import requests
import json
import re
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


JOB_NAME = "load_salesforce_growth_raw"

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

def validate_url(url):
    if not re.match(r'^https://.*\.my\.salesforce\.com$', url):
        raise ValueError("Invalid url")
    return url
    
def validate_endpoint(endpoint):
    if not re.match(r'^/services/data/v63.0/query/[^/]*$', endpoint):
        raise ValueError("Invalid endpoint")
    return endpoint

def get_access_token(url):

    valid_url = validate_url(url)

    # Initializing clients
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    api_credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.SALESFORCE_GROWTH)
    )

    req_url = f'{valid_url}/services/oauth2/token'

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
        'lead':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("MasterRecordId", StringType()),
                            StructField("LastName", StringType()),
                            StructField("FirstName", StringType()),
                            StructField("Salutation", StringType()),
                            StructField("Name", StringType()),
                            StructField("RecordTypeId", StringType()),
                            StructField("Title", StringType()),
                            StructField("Company", StringType()),
                            StructField("Street", StringType()),
                            StructField("City", StringType()),
                            StructField("State", StringType()),
                            StructField("PostalCode", StringType()),
                            StructField("Country", StringType()),
                            StructField("Latitude", StringType()),
                            StructField("Longitude", StringType()),
                            StructField("GeocodeAccuracy", StringType()),
                            StructField("Address", StringType()),
                            StructField("Phone", StringType()),
                            StructField("MobilePhone", StringType()),
                            StructField("Fax", StringType()),
                            StructField("Email", StringType()),
                            StructField("Website", StringType()),
                            StructField("PhotoUrl", StringType()),
                            StructField("Description", StringType()),
                            StructField("LeadSource", StringType()),
                            StructField("Status", StringType()),
                            StructField("Industry", StringType()),
                            StructField("Rating", StringType()),
                            StructField("CurrencyIsoCode", StringType()),
                            StructField("AnnualRevenue", StringType()),
                            StructField("NumberOfEmployees", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("HasOptedOutOfEmail", StringType()),
                            StructField("IsConverted", StringType()),
                            StructField("ConvertedDate", StringType()),
                            StructField("ConvertedAccountId", StringType()),
                            StructField("ConvertedContactId", StringType()),
                            StructField("IsUnreadByOwner", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("LastActivityDate", StringType()),
                            StructField("DoNotCall", StringType()),
                            StructField("HasOptedOutOfFax", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("LastTransferDate", StringType()),
                            StructField("Jigsaw", StringType()),
                            StructField("JigsawContactId", StringType()),
                            StructField("EmailBouncedReason", StringType()),
                            StructField("EmailBouncedDate", StringType()),
                            StructField("Pronouns", StringType()),
                            StructField("GenderIdentity", StringType()),
                            StructField("IsPriorityRecord", StringType()),
                            StructField("Cantidad_de_propiedades__c", StringType()),
                            StructField("Ciudad_de_facturacion2__c", StringType()),
                            StructField("Codigo_postal__c", StringType()),
                            StructField("Codigo_postal_de_facturacion__c", StringType()),
                            StructField("Condicion_fiscal_texto__c", StringType()),
                            StructField("Direccion__c", StringType()),
                            StructField("Direccion_de_facturacion__c", StringType()),
                            StructField("Error_de_SAP__c", StringType()),
                            StructField("Es_empresa__c", StringType()),
                            StructField("sfleadcaphfprod__External_Lead_ID__c", StringType()),
                            StructField("ID_Empresa_Site__c", StringType()),
                            StructField("ID_Empresa_Site_exclusivo__c", StringType()),
                            StructField("Industria__c", StringType()),
                            StructField("Gestion_Atta__c", StringType()),
                            StructField("Matricula_Licencia__c", StringType()),
                            StructField("Motivo_de_no_califica__c", StringType()),
                            StructField("Motivo_de_no_interes__c", StringType()),
                            StructField("Nombre_de_fantasia__c", StringType()),
                            StructField("Numero_de_documento_fiscal__c", StringType()),
                            StructField("Oportunidad_por_ofrecer__c", StringType()),
                            StructField("Gestion_CasaMineira__c", StringType()),
                            StructField("Organizacion_de_venta__c", StringType()),
                            StructField("Origen_prospecto__c", StringType()),
                            StructField("Pais_texto__c", StringType()),
                            StructField("Gestion_IWB_WIM__c", StringType()),
                            StructField("Sitio__c", StringType()),
                            StructField("Gestion_NokNox__c", StringType()),
                            StructField("Zona_Barrio_Colonia_Comuna_facturacion2__c", StringType()),
                            StructField("Perfil_crediticio__c", StringType()),
                            StructField("Gestion_SindicoNet__c", StringType()),
                            StructField("Tipo_de_documento_necesita_validar__c", StringType()),
                            StructField("Organizacion_de_venta_Texto__c", StringType()),
                            StructField("Ciudad_Texto__c", StringType()),
                            StructField("Condicion_fiscal_pardot__c", StringType()),
                            StructField("Pais_de_facturacion_texto__c", StringType()),
                            StructField("Provincia_Estado_Texto__c", StringType()),
                            StructField("Gestion_Union__c", StringType()),
                            StructField("Error_de_envio_a_pardot__c", StringType()),
                            StructField("Dominio_HR__c", StringType()),
                            StructField("Zapier_email__c", StringType()),
                            StructField("whatslly__Created_by_Whatslly__c", StringType()),
                            StructField("whatslly__Last_WhatsApp_Message_Time__c", StringType()),
                            StructField("whatslly__Whatslly_Person_Id__c", StringType()),
                            StructField("Gestion_Velo__c", StringType()),
                            StructField("Organizacion_de_venta_picklist__c", StringType()),
                            StructField("et4ae5__HasOptedOutOfMobile__c", StringType()),
                            StructField("et4ae5__Mobile_Country_Code__c", StringType()),
                            StructField("Apto_mkt__c", StringType()),
                            StructField("whatslly__Tuvis_Chat_Id__c", StringType()),
                            StructField("botmakerglobal__BotmakerId__c", StringType()),
                            StructField("Error_Portal__c", StringType()),
                            StructField("ContactId__c", StringType()),
                            StructField("Fecha_contrato_firmado__c", StringType()),
                            StructField("PWA_Id__c", StringType()),
                            StructField("Fecha_de_env_o_de_la_offer__c", StringType()),
                            StructField("Monto_de_la_offer__c", StringType()),
                            StructField("Fecha_de_vencimiento_de_la_offer__c", StringType()),
                            StructField("Status_de_la_offer__c", StringType()),
                            StructField("Offer_enviada_al_cliente__c", StringType()),
                            StructField("Canal__c", StringType()),
                            StructField("Ha_respondido_el_contacto__c", StringType()),
                            StructField("Calificado__c", StringType()),
                            StructField("Codigo_PP_de_im_vel_Id_PP__c", StringType()),
                            StructField("Codigo_de_la_propiedad_registrada_Id_IM__c", StringType()),
                            StructField("Fecha_de_la_cita_para_las_fotos__c", StringType()),
                            StructField("Tipo_de_publicacion__c", StringType()),
                            StructField("Status_de_la_foto__c", StringType()),
                            StructField("Publicado__c", StringType()),
                            StructField("Fecha_de_la_publicacion__c", StringType()),
                            StructField("Operacion__c", StringType()),
                            StructField("Fecha_de_proximo_contacto__c", StringType()),
                            StructField("Link_Owner_Hyperlink__c", StringType()),
                            StructField("Celular__c", StringType()),
                            StructField("Hot_Lead__c", StringType()),
                            StructField("Fecha_de_preclasificado__c", StringType()),
                            StructField("Fecha_de_primer_contacto__c", StringType()),
                            StructField("Potencial_duplicado__c", StringType()),
                            StructField("Motivo_no_convierte__c", StringType()),
                        ]
                    )
            },
        'operation':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("Name", StringType()),
                            StructField("CurrencyIsoCode", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("LastActivityDate", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("Id_SAP__c", StringType()),
                            StructField("Id_de_portal__c", StringType()),
                            StructField("Monedas_aceptadas__c", StringType()),
                            StructField("Organizacion_de_venta__c", StringType()),
                            StructField("Vertical__c", StringType()),
                            StructField("Vias_de_pago_aceptadas__c", StringType()),
                            StructField("CRM_Navent__c", StringType()),
                            StructField("Perfil_crediticio__c", StringType()),
                            StructField("Id_unidad_de_negocio_Pardot__c", StringType()),
                            StructField("Sincroniza_con_pardot__c", StringType()),
                            StructField("Emails_envio_OS__c", StringType()),
                            StructField("Renovacion_automatica_de_oportunidades__c", StringType()),
                            StructField("Moneda_base__c", StringType()),
                            StructField("Campana_oblig_en_Oport__c", StringType()),
                            StructField("Descuentos_permitidos__c", StringType()),
                            StructField("Duracion_descuentos__c", StringType()),
                            StructField("Terminos_y_condiciones__c", StringType()),
                            StructField("Carga_Id_empresa_manual__c", StringType()),
                            StructField("Logo__c", StringType()),
                            StructField("Razon_social__c", StringType()),
                            StructField("Sitio__c", StringType()),
                            StructField("Visualizar_descuentos__c", StringType()),
                            StructField("Sincronizar_mkt__c", StringType()),
                            StructField("Requiere_aprobacion_por_target__c", StringType()),
                            StructField("Actualiza_EP_en_portal__c", StringType()),
                            StructField("Calcula_cartera__c", StringType())
                        ]
                    )
            },    
        'user':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("Username", StringType()),
                            StructField("LastName", StringType()),
                            StructField("FirstName", StringType()),
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
                            StructField("LocaleSidKey", StringType()),
                            StructField("ReceivesInfoEmails", StringType()),
                            StructField("ReceivesAdminInfoEmails", StringType()),
                            StructField("EmailEncodingKey", StringType()),
                            StructField("DefaultCurrencyIsoCode", StringType()),
                            StructField("CurrencyIsoCode", StringType()),
                            StructField("UserType", StringType()),
                            StructField("StartDay", StringType()),
                            StructField("EndDay", StringType()),
                            StructField("LanguageLocaleKey", StringType()),
                            StructField("EmployeeNumber", StringType()),
                            StructField("DelegatedApproverId", StringType()),
                            StructField("ManagerId", StringType()),
                            StructField("LastLoginDate", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("PasswordExpirationDate", StringType()),
                            StructField("SuAccessExpirationDate", StringType()),
                            StructField("OfflineTrialExpirationDate", StringType()),
                            StructField("OfflinePdaTrialExpirationDate", StringType()),
                            StructField("UserPermissionsMarketingUser", StringType()),
                            StructField("UserPermissionsOfflineUser", StringType()),
                            StructField("UserPermissionsAvantgoUser", StringType()),
                            StructField("UserPermissionsCallCenterAutoLogin", StringType()),
                            StructField("UserPermissionsSFContentUser", StringType()),
                            StructField("UserPermissionsKnowledgeUser", StringType()),
                            StructField("UserPermissionsInteractionUser", StringType()),
                            StructField("UserPermissionsSupportUser", StringType()),
                            StructField("ForecastEnabled", StringType()),
                            StructField("UserPreferencesActivityRemindersPopup", StringType()),
                            StructField("UserPreferencesEventRemindersCheckboxDefault", StringType()),
                            StructField("UserPreferencesTaskRemindersCheckboxDefault", StringType()),
                            StructField("UserPreferencesReminderSoundOff", StringType()),
                            StructField("UserPreferencesDisableAllFeedsEmail", StringType()),
                            StructField("UserPreferencesDisableFollowersEmail", StringType()),
                            StructField("UserPreferencesDisableProfilePostEmail", StringType()),
                            StructField("UserPreferencesDisableChangeCommentEmail", StringType()),
                            StructField("UserPreferencesDisableLaterCommentEmail", StringType()),
                            StructField("UserPreferencesDisProfPostCommentEmail", StringType()),
                            StructField("UserPreferencesHideCSNGetChatterMobileTask", StringType()),
                            StructField("UserPreferencesDisableMentionsPostEmail", StringType()),
                            StructField("UserPreferencesDisMentionsCommentEmail", StringType()),
                            StructField("UserPreferencesHideCSNDesktopTask", StringType()),
                            StructField("UserPreferencesHideChatterOnboardingSplash", StringType()),
                            StructField("UserPreferencesHideSecondChatterOnboardingSplash", StringType()),
                            StructField("UserPreferencesDisCommentAfterLikeEmail", StringType()),
                            StructField("UserPreferencesDisableLikeEmail", StringType()),
                            StructField("UserPreferencesSortFeedByComment", StringType()),
                            StructField("UserPreferencesDisableMessageEmail", StringType()),
                            StructField("UserPreferencesDisableBookmarkEmail", StringType()),
                            StructField("UserPreferencesDisableSharePostEmail", StringType()),
                            StructField("UserPreferencesActionLauncherEinsteinGptConsent", StringType()),
                            StructField("UserPreferencesAssistiveActionsEnabledInActionLauncher", StringType()),
                            StructField("UserPreferencesEnableAutoSubForFeeds", StringType()),
                            StructField("UserPreferencesDisableFileShareNotificationsForApi", StringType()),
                            StructField("UserPreferencesShowTitleToExternalUsers", StringType()),
                            StructField("UserPreferencesShowManagerToExternalUsers", StringType()),
                            StructField("UserPreferencesShowEmailToExternalUsers", StringType()),
                            StructField("UserPreferencesShowWorkPhoneToExternalUsers", StringType()),
                            StructField("UserPreferencesShowMobilePhoneToExternalUsers", StringType()),
                            StructField("UserPreferencesShowFaxToExternalUsers", StringType()),
                            StructField("UserPreferencesShowStreetAddressToExternalUsers", StringType()),
                            StructField("UserPreferencesShowCityToExternalUsers", StringType()),
                            StructField("UserPreferencesShowStateToExternalUsers", StringType()),
                            StructField("UserPreferencesShowPostalCodeToExternalUsers", StringType()),
                            StructField("UserPreferencesShowCountryToExternalUsers", StringType()),
                            StructField("UserPreferencesShowProfilePicToGuestUsers", StringType()),
                            StructField("UserPreferencesShowTitleToGuestUsers", StringType()),
                            StructField("UserPreferencesShowCityToGuestUsers", StringType()),
                            StructField("UserPreferencesShowStateToGuestUsers", StringType()),
                            StructField("UserPreferencesShowPostalCodeToGuestUsers", StringType()),
                            StructField("UserPreferencesShowCountryToGuestUsers", StringType()),
                            StructField("UserPreferencesShowForecastingChangeSignals", StringType()),
                            StructField("UserPreferencesLiveAgentMiawSetupDeflection", StringType()),
                            StructField("UserPreferencesHideS1BrowserUI", StringType()),
                            StructField("UserPreferencesDisableEndorsementEmail", StringType()),
                            StructField("UserPreferencesPathAssistantCollapsed", StringType()),
                            StructField("UserPreferencesCacheDiagnostics", StringType()),
                            StructField("UserPreferencesShowEmailToGuestUsers", StringType()),
                            StructField("UserPreferencesShowManagerToGuestUsers", StringType()),
                            StructField("UserPreferencesShowWorkPhoneToGuestUsers", StringType()),
                            StructField("UserPreferencesShowMobilePhoneToGuestUsers", StringType()),
                            StructField("UserPreferencesShowFaxToGuestUsers", StringType()),
                            StructField("UserPreferencesShowStreetAddressToGuestUsers", StringType()),
                            StructField("UserPreferencesLightningExperiencePreferred", StringType()),
                            StructField("UserPreferencesHideEndUserOnboardingAssistantModal", StringType()),
                            StructField("UserPreferencesHideLightningMigrationModal", StringType()),
                            StructField("UserPreferencesHideSfxWelcomeMat", StringType()),
                            StructField("UserPreferencesHideBiggerPhotoCallout", StringType()),
                            StructField("UserPreferencesGlobalNavBarWTShown", StringType()),
                            StructField("UserPreferencesGlobalNavGridMenuWTShown", StringType()),
                            StructField("UserPreferencesCreateLEXAppsWTShown", StringType()),
                            StructField("UserPreferencesFavoritesWTShown", StringType()),
                            StructField("UserPreferencesRecordHomeSectionCollapseWTShown", StringType()),
                            StructField("UserPreferencesRecordHomeReservedWTShown", StringType()),
                            StructField("UserPreferencesFavoritesShowTopFavorites", StringType()),
                            StructField("UserPreferencesExcludeMailAppAttachments", StringType()),
                            StructField("UserPreferencesSuppressTaskSFXReminders", StringType()),
                            StructField("UserPreferencesSuppressEventSFXReminders", StringType()),
                            StructField("UserPreferencesPreviewCustomTheme", StringType()),
                            StructField("UserPreferencesHasCelebrationBadge", StringType()),
                            StructField("UserPreferencesUserDebugModePref", StringType()),
                            StructField("UserPreferencesSRHOverrideActivities", StringType()),
                            StructField("UserPreferencesReverseOpenActivitiesView", StringType()),
                            StructField("UserPreferencesHasSentWarningEmail", StringType()),
                            StructField("UserPreferencesHasSentWarningEmail238", StringType()),
                            StructField("UserPreferencesHasSentWarningEmail240", StringType()),
                            StructField("UserPreferencesHideBrowseProductRedirectConfirmation", StringType()),
                            StructField("UserPreferencesHideOnlineSalesAppTabVisibilityRequirementsModal", StringType()),
                            StructField("UserPreferencesHideOnlineSalesAppWelcomeMat", StringType()),
                            StructField("UserPreferencesShowForecastingRoundedAmounts", StringType()),
                            StructField("HasUserVerifiedPhone", StringType()),
                            StructField("HasUserVerifiedEmail", StringType()),
                            StructField("ContactId", StringType()),
                            StructField("AccountId", StringType()),
                            StructField("CallCenterId", StringType()),
                            StructField("Extension", StringType()),
                            StructField("FederationIdentifier", StringType()),
                            StructField("AboutMe", StringType()),
                            StructField("FullPhotoUrl", StringType()),
                            StructField("SmallPhotoUrl", StringType()),
                            StructField("IsExtIndicatorVisible", StringType()),
                            StructField("OutOfOfficeMessage", StringType()),
                            StructField("MediumPhotoUrl", StringType()),
                            StructField("DigestFrequency", StringType()),
                            StructField("DefaultGroupNotificationFrequency", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("BannerPhotoUrl", StringType()),
                            StructField("SmallBannerPhotoUrl", StringType()),
                            StructField("MediumBannerPhotoUrl", StringType()),
                            StructField("IsProfilePhotoActive", StringType()),
                            StructField("Canal__c", StringType()),
                            StructField("Email__c", StringType()),
                            StructField("Error_SAP__c", StringType()),
                            StructField("Fecha_de_ultimo_error_SAP__c", StringType()),
                            StructField("Gerente_padre__c", StringType()),
                            StructField("Id_usuario_SAP__c", StringType()),
                            StructField("et4ae5__Default_ET_Page__c", StringType()),
                            StructField("Pais__c", StringType()),
                            StructField("Rol_padre__c", StringType()),
                            StructField("ID_Usuario_SF__c", StringType()),
                            StructField("Centro_de_costos__c", StringType()),
                            StructField("Link_Calendly__c", StringType()),
                            StructField("Organizacion_de_venta__c", StringType()),
                            StructField("et4ae5__Default_MID__c", StringType()),
                            StructField("et4ae5__ExactTargetForAppExchangeAdmin__c", StringType()),
                            StructField("et4ae5__ExactTargetForAppExchangeUser__c", StringType()),
                            StructField("et4ae5__ExactTargetUsername__c", StringType()),
                            StructField("et4ae5__ExactTarget_OAuth_Token__c", StringType()),
                            StructField("et4ae5__ValidExactTargetAdmin__c", StringType()),
                            StructField("et4ae5__ValidExactTargetUser__c", StringType()),
                            StructField("Mostrar_datos__c", StringType())     
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
                            StructField("CurrencyIsoCode", StringType()),
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
                            StructField("Fecha_de_finalizacion__c", StringType()),
                            StructField("Organizacion_de_venta__c", StringType()),
                            StructField("whatslly__Created_by_Whatslly__c", StringType()),
                            StructField("whatslly__Is_WhatsApp_Task__c", StringType()),
                            StructField("whatslly__Whatslly_Number__c", StringType()),
                            StructField("Gestion_Cross_selling__c", StringType()),
                            StructField("Status_Lead__c", StringType()),
                            StructField("Resultado_Lead__c", StringType()),
                            StructField("Call_Ani__c", StringType()),
                            StructField("Called_Number__c", StringType()),
                            StructField("Conversation_Id__c", StringType()),
                            StructField("Queue_Name__c", StringType()),
                            StructField("Total_Acd_Time__c", StringType()),
                            StructField("Total_Ivr_Time__c", StringType()),
                            StructField("Interaction_Url__c", StringType()),
                            StructField("Tipo__c", StringType()),
                            StructField("Resultado_FUP__c", StringType())
                        ]
                    )
            },
        'record_type':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("Name", StringType()),
                            StructField("DeveloperName", StringType()),
                            StructField("NamespacePrefix", StringType()),
                            StructField("Description", StringType()),
                            StructField("BusinessProcessId", StringType()),
                            StructField("SobjectType", StringType()),
                            StructField("IsActive", StringType()),
                            StructField("IsPersonType", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("SystemModstamp", StringType()),
                        ]
                    )
            },
        'whatslly_thread_message':
            {
                'schema':
                    StructType(
                        [
                            StructField("Id", StringType()),
                            StructField("OwnerId", StringType()),
                            StructField("IsDeleted", StringType()),
                            StructField("Name", StringType()),
                            StructField("CurrencyIsoCode", StringType()),
                            StructField("CreatedDate", StringType()),
                            StructField("CreatedById", StringType()),
                            StructField("LastModifiedDate", StringType()),
                            StructField("LastModifiedById", StringType()),
                            StructField("SystemModstamp", StringType()),
                            StructField("LastViewedDate", StringType()),
                            StructField("LastReferencedDate", StringType()),
                            StructField("whatslly__Datetime__c", StringType()),
                            StructField("whatslly__Direction__c", StringType()),
                            StructField("whatslly__Is_Past_24h__c", StringType()),
                            StructField("whatslly__Is_Sent__c", StringType()),
                            StructField("whatslly__Message_ID__c", StringType()),
                            StructField("whatslly__Message__c", StringType()),
                            StructField("whatslly__Recipient_Phone__c", StringType()),
                            StructField("whatslly__Related_Account__c", StringType()),
                            StructField("whatslly__Related_Contact__c", StringType()),
                            StructField("whatslly__Related_Lead__c", StringType()),
                            StructField("whatslly__Sender_Phone__c", StringType()),
                            StructField("whatslly__Whatslly_Person_Id__c", StringType()),
                            StructField("whatslly__Has_File__c", StringType()),
                            StructField("whatslly__Status__c", StringType()),
                            StructField("whatslly__Unique_Message_Id__c", StringType()),
                            StructField("whatslly__Sender_Name__c", StringType()),
                            StructField("whatslly__Quoted_Message_ID__c", StringType()),
                            StructField("whatslly__Msg_Latest_Update__c", StringType()),
                            StructField("whatslly__Tuvis_Created_By__c", StringType()),
                            StructField("whatslly__Transcript_Text__c", StringType())
                        ]
                    )
            }
    }

def get_next_page_data(query, headers, instance_url, table_name, is_done, next_url):
    # Make a GET request to the Salesforce API
    if next_url is None and is_done == False:
        endpoint = f'/services/data/v63.0/query/?q={query.replace(" ", "+")}'
    elif next_url is not None and is_done == False:
        endpoint = next_url

    valid_url = validate_url(instance_url)
    valid_endpoint = validate_endpoint(endpoint)

    api_endpoint = f'{valid_url}{valid_endpoint}'

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

    # Parse arguments
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

    # Initialize Spark Client
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
