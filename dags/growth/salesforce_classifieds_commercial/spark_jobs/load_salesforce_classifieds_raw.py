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
        "Account": {
            "schema": StructType(
                [
                    StructField("AccountSource", StringType(), True),
                    StructField("Alias_Cta_Cte__c", StringType(), True),
                    StructField("Area_en_la_empresa__pc", StringType(), True),
                    StructField("BillingCity", StringType(), True),
                    StructField("BillingCountry", StringType(), True),
                    StructField("BillingGeocodeAccuracy", StringType(), True),
                    StructField("BillingLatitude", StringType(), True),
                    StructField("BillingLongitude", StringType(), True),
                    StructField("BillingPostalCode", StringType(), True),
                    StructField("BillingState", StringType(), True),
                    StructField("BillingStreet", StringType(), True),
                    StructField("Bloqueado__c", StringType(), True),
                    StructField("CBU__c", StringType(), True),
                    StructField("Ciudad_de_facturacion2__c", StringType(), True),
                    StructField("Ciudad_de_operacion__c", StringType(), True),
                    StructField("Cliente_validado__c", StringType(), True),
                    StructField("Codigo_postal_de_facturacion__c", StringType(), True),
                    StructField("Codigo_postal_de_operacion__c", StringType(), True),
                    StructField("Condicion_fiscal__c", StringType(), True),
                    StructField("Consulta_de_facturas_en_SAP__c", StringType(), True),
                    StructField("Contacto_principal__pc", StringType(), True),
                    StructField("Convertido_a_empresarial__c", StringType(), True),
                    StructField(
                        "Correo_electronico_de_contacto_principal__c",
                        StringType(),
                        True,
                    ),
                    StructField("Creado_de_prospecto__pc", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("Direccion_de_facturacion__c", StringType(), True),
                    StructField("Direccion_de_operacion__c", StringType(), True),
                    StructField("Dominio_HR__c", StringType(), True),
                    StructField("Email_adicional__pc", StringType(), True),
                    StructField("Error_de_SAP__c", StringType(), True),
                    StructField("Error_de_SAP__pc", StringType(), True),
                    StructField("et4ae5__HasOptedOutOfMobile__pc", StringType(), True),
                    StructField("et4ae5__Mobile_Country_Code__pc", StringType(), True),
                    StructField("Fecha_de_ultimo_error_SAP__c", StringType(), True),
                    StructField("Fecha_de_ultimo_error_SAP__pc", StringType(), True),
                    StructField("FirstName", StringType(), True),
                    StructField("Funcion__c", StringType(), True),
                    StructField("Gestion_Atta__c", StringType(), True),
                    StructField("Gestion_CasaMineira__c", StringType(), True),
                    StructField("Gestion_IWB_WIM__c", StringType(), True),
                    StructField("Gestion_NokNox__c", StringType(), True),
                    StructField("Gestion_SindicoNet__c", StringType(), True),
                    StructField("Gestion_Union__c", StringType(), True),
                    StructField("Gestion_Velo__c", StringType(), True),
                    StructField("Giro_comercial__c", StringType(), True),
                    StructField("Giro_de_Negocio__c", StringType(), True),
                    StructField("Grupo_economico__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("ID_Cliente_SAP__c", StringType(), True),
                    StructField("ID_Contacto_SAP__pc", StringType(), True),
                    StructField("ID_Cuenta_SF__c", StringType(), True),
                    StructField("Id_externo_autonumerico__pc", StringType(), True),
                    StructField("id_externo_exclusivo__c", StringType(), True),
                    StructField("Industry", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsPersonAccount", StringType(), True),
                    StructField("Jigsaw", StringType(), True),
                    StructField("JigsawCompanyId", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastName", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("MasterRecordId", StringType(), True),
                    StructField("Matricula_Licencia__c", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Nombre_de_Fantasia__c", StringType(), True),
                    StructField(
                        "Nombre_del_propietario_de_la_cuenta__c", StringType(), True
                    ),
                    StructField("NumberOfEmployees", StringType(), True),
                    StructField("Numero_de_documento_fiscal__c", StringType(), True),
                    StructField(
                        "Organizacion_de_venta_principal__c", StringType(), True
                    ),
                    StructField("Organizaciones_de_venta__pc", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Pais_de_facturacion__c", StringType(), True),
                    StructField("Pais_de_operacion__c", StringType(), True),
                    StructField("ParentId", StringType(), True),
                    StructField("Perfil_crediticio__c", StringType(), True),
                    StructField("PersonAssistantName", StringType(), True),
                    StructField("PersonAssistantPhone", StringType(), True),
                    StructField("PersonBirthdate", StringType(), True),
                    StructField("PersonContactId", StringType(), True),
                    StructField("PersonDepartment", StringType(), True),
                    StructField("PersonEmail", StringType(), True),
                    StructField("PersonEmailBouncedDate", StringType(), True),
                    StructField("PersonEmailBouncedReason", StringType(), True),
                    StructField("PersonHasOptedOutOfEmail", StringType(), True),
                    StructField("PersonHomePhone", StringType(), True),
                    StructField("PersonLastCURequestDate", StringType(), True),
                    StructField("PersonLastCUUpdateDate", StringType(), True),
                    StructField("PersonLeadSource", StringType(), True),
                    StructField("PersonMailingCity", StringType(), True),
                    StructField("PersonMailingCountry", StringType(), True),
                    StructField("PersonMailingGeocodeAccuracy", StringType(), True),
                    StructField("PersonMailingLatitude", StringType(), True),
                    StructField("PersonMailingLongitude", StringType(), True),
                    StructField("PersonMailingPostalCode", StringType(), True),
                    StructField("PersonMailingState", StringType(), True),
                    StructField("PersonMailingStreet", StringType(), True),
                    StructField("PersonMobilePhone", StringType(), True),
                    StructField("PersonTitle", StringType(), True),
                    StructField("Phone", StringType(), True),
                    StructField("PhotoUrl", StringType(), True),
                    StructField(
                        "Provincia_Estado_de_facturacion__c", StringType(), True
                    ),
                    StructField("Provincia_Estado_de_operacion__c", StringType(), True),
                    StructField("Puesto__pc", StringType(), True),
                    StructField("RecordTypeId", StringType(), True),
                    StructField("Regimen_societario__c", StringType(), True),
                    StructField("Requiere_orden_de_compra__c", StringType(), True),
                    StructField("Salutation", StringType(), True),
                    StructField("ShippingCity", StringType(), True),
                    StructField("ShippingCountry", StringType(), True),
                    StructField("ShippingGeocodeAccuracy", StringType(), True),
                    StructField("ShippingLatitude", StringType(), True),
                    StructField("ShippingLongitude", StringType(), True),
                    StructField("ShippingPostalCode", StringType(), True),
                    StructField("ShippingState", StringType(), True),
                    StructField("ShippingStreet", StringType(), True),
                    StructField("SicDesc", StringType(), True),
                    StructField("System_Cta_Cte__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Tipo_de_documento__c", StringType(), True),
                    StructField(
                        "Tipo_de_documento_necesita_validar__c", StringType(), True
                    ),
                    StructField("Type", StringType(), True),
                    StructField(
                        "Ultimo_propietario_no_actualizado__c", StringType(), True
                    ),
                    StructField("URL_ultima_orden_de_servicio__c", StringType(), True),
                    StructField("URL_ultima_orden_de_servicio__pc", StringType(), True),
                    StructField("Website", StringType(), True),
                    StructField("whatslly__Created_by_Whatslly__c", StringType(), True),
                    StructField(
                        "whatslly__Created_by_Whatslly__pc", StringType(), True
                    ),
                    StructField(
                        "whatslly__Last_WhatsApp_Message_Time__c", StringType(), True
                    ),
                    StructField(
                        "whatslly__Last_WhatsApp_Message_Time__pc", StringType(), True
                    ),
                    StructField("whatslly__Whatslly_Person_Id__c", StringType(), True),
                    StructField("whatslly__Whatslly_Person_Id__pc", StringType(), True),
                    StructField(
                        "whatslly__Whatslly_Threads_ID__pc", StringType(), True
                    ),
                    StructField(
                        "Zona_Barrio_Colonia_Comuna_facturacion2__c", StringType(), True
                    ),
                    StructField(
                        "Zona_Barrio_Colonia_Comuna_operacion__c", StringType(), True
                    ),
                ]
            )
        },
        "Ciudad__c": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_de_Ciudad__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Provincia_Estado__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Condicion_fiscal__c": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_Clase__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Pais__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Tipo_de_documento__c", StringType(), True),
                ]
            )
        },
        "Contact": {
            "schema": StructType(
                [
                    StructField("AccountId", StringType(), True),
                    StructField("Area_en_la_empresa__c", StringType(), True),
                    StructField("AssistantName", StringType(), True),
                    StructField("AssistantPhone", StringType(), True),
                    StructField("Birthdate", StringType(), True),
                    StructField("Contacto_principal__c", StringType(), True),
                    StructField("Creado_de_prospecto__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Department", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("Email", StringType(), True),
                    StructField("Email_adicional__c", StringType(), True),
                    StructField("EmailBouncedDate", StringType(), True),
                    StructField("EmailBouncedReason", StringType(), True),
                    StructField("Error_de_SAP__c", StringType(), True),
                    StructField("et4ae5__HasOptedOutOfMobile__c", StringType(), True),
                    StructField("et4ae5__Mobile_Country_Code__c", StringType(), True),
                    StructField("Fax", StringType(), True),
                    StructField("Fecha_de_ultimo_error_SAP__c", StringType(), True),
                    StructField("FirstName", StringType(), True),
                    StructField("HasOptedOutOfEmail", StringType(), True),
                    StructField("HomePhone", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("ID_Contacto_SAP__c", StringType(), True),
                    StructField("Id_externo_autonumerico__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsEmailBounced", StringType(), True),
                    StructField("IsPersonAccount", StringType(), True),
                    StructField("Jigsaw", StringType(), True),
                    StructField("JigsawContactId", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastCURequestDate", StringType(), True),
                    StructField("LastCUUpdateDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastName", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("LeadSource", StringType(), True),
                    StructField("MailingCity", StringType(), True),
                    StructField("MailingCountry", StringType(), True),
                    StructField("MailingGeocodeAccuracy", StringType(), True),
                    StructField("MailingLatitude", StringType(), True),
                    StructField("MailingLongitude", StringType(), True),
                    StructField("MailingPostalCode", StringType(), True),
                    StructField("MailingState", StringType(), True),
                    StructField("MailingStreet", StringType(), True),
                    StructField("MasterRecordId", StringType(), True),
                    StructField("MobilePhone", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Organizaciones_de_venta__c", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Phone", StringType(), True),
                    StructField("PhotoUrl", StringType(), True),
                    StructField("Puesto__c", StringType(), True),
                    StructField("ReportsToId", StringType(), True),
                    StructField("Salutation", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Title", StringType(), True),
                    StructField("URL_ultima_orden_de_servicio__c", StringType(), True),
                    StructField("whatslly__Created_by_Whatslly__c", StringType(), True),
                    StructField(
                        "whatslly__Last_WhatsApp_Message_Time__c", StringType(), True
                    ),
                    StructField("whatslly__Whatslly_Person_Id__c", StringType(), True),
                    StructField("whatslly__Whatslly_Threads_ID__c", StringType(), True),
                ]
            )
        },
        "Contract": {
            "schema": StructType(
                [
                    StructField("AccountId", StringType(), True),
                    StructField("ActivatedById", StringType(), True),
                    StructField("ActivatedDate", StringType(), True),
                    StructField("Asignado__c", StringType(), True),
                    StructField("BillingCity", StringType(), True),
                    StructField("BillingCountry", StringType(), True),
                    StructField("BillingGeocodeAccuracy", StringType(), True),
                    StructField("BillingLatitude", StringType(), True),
                    StructField("BillingLongitude", StringType(), True),
                    StructField("BillingPostalCode", StringType(), True),
                    StructField("BillingState", StringType(), True),
                    StructField("BillingStreet", StringType(), True),
                    StructField("CompanySignedDate", StringType(), True),
                    StructField("CompanySignedId", StringType(), True),
                    StructField("Condiciones_de_pago__c", StringType(), True),
                    StructField(
                        "Contacto_de_facturacion_aprobacion__c", StringType(), True
                    ),
                    StructField("ContractNumber", StringType(), True),
                    StructField("ContractTerm", StringType(), True),
                    StructField("Correo_al_que_se_envi_la_OS__c", StringType(), True),
                    StructField("Creada_por_ecommerce__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("CustomerSignedDate", StringType(), True),
                    StructField("CustomerSignedId", StringType(), True),
                    StructField("CustomerSignedTitle", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("Descuento__c", StringType(), True),
                    StructField("Empresa_portal__c", StringType(), True),
                    StructField("EndDate", StringType(), True),
                    StructField("Error_de_Sap__c", StringType(), True),
                    StructField("Estado_de_la_firma__c", StringType(), True),
                    StructField("fecha_a_facturar__c", StringType(), True),
                    StructField("Fecha_de_cancelacion__c", StringType(), True),
                    StructField("Fecha_de_fin_de_vigencia__c", StringType(), True),
                    StructField("Fecha_de_inicio_de_vigencia__c", StringType(), True),
                    StructField(
                        "Fecha_en_la_que_se_firmo_la_OS__c", StringType(), True
                    ),
                    StructField("Fecha_maxima_de_productos__c", StringType(), True),
                    StructField("Fecha_prepago__c", StringType(), True),
                    StructField("Funcion_del_propietario__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_exclusivo__c", StringType(), True),
                    StructField("ID_pedido_SAP__c", StringType(), True),
                    StructField("Importe_anualizado__c", StringType(), True),
                    StructField("Importe_mensualizado__c", StringType(), True),
                    StructField("Importe_mensualizado2__c", StringType(), True),
                    StructField("Importe_original2__c", StringType(), True),
                    StructField("Importe2__c", StringType(), True),
                    StructField("IP_en_la_que_se_firmo_la_OS__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastApprovedDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Layout_de_factura__c", StringType(), True),
                    StructField("MP_token__c", StringType(), True),
                    StructField(
                        "Numero_de_identificacion_de_pago__c", StringType(), True
                    ),
                    StructField("Numero_de_orden_de_compra__c", StringType(), True),
                    StructField("Orden_de_servicio_relacionada__c", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("OwnerExpirationNotice", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Prepago_Finalizado__c", StringType(), True),
                    StructField("Pricebook2Id", StringType(), True),
                    StructField(
                        "Requirio_aprobacion_del_cliente__c", StringType(), True
                    ),
                    StructField("RT_Oportunidad__c", StringType(), True),
                    StructField("ShippingCity", StringType(), True),
                    StructField("ShippingCountry", StringType(), True),
                    StructField("ShippingGeocodeAccuracy", StringType(), True),
                    StructField("ShippingLatitude", StringType(), True),
                    StructField("ShippingLongitude", StringType(), True),
                    StructField("ShippingPostalCode", StringType(), True),
                    StructField("ShippingState", StringType(), True),
                    StructField("ShippingStreet", StringType(), True),
                    StructField("SpecialTerms", StringType(), True),
                    StructField("StartDate", StringType(), True),
                    StructField("Status", StringType(), True),
                    StructField("StatusCode", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Texto_adicional_de_factura__c", StringType(), True),
                    StructField("Tipo__c", StringType(), True),
                    StructField("Ultima_fecha_de_indexacion__c", StringType(), True),
                    StructField("Ultimo_envio_a_sap__c", StringType(), True),
                    StructField(
                        "Valor_de_porcentaje_por_inflacion__c", StringType(), True
                    ),
                    StructField("Via_de_pago__c", StringType(), True),
                    StructField("Acceso_a_mercadopago__c", StringType(), True),
                    StructField("Cancelado_por__c", StringType(), True),
                ]
            )
        },
        "Empresa_portal__c": {
            "schema": StructType(
                [
                    StructField("Acceso_Panoramix__c", StringType(), True),
                    StructField("Bloqueado__c", StringType(), True),
                    StructField("Bloqueado_icono__c", StringType(), True),
                    StructField("Cantidad_de_Propiedades__c", StringType(), True),
                    StructField("Cartera_Ecom_fecha__c", StringType(), True),
                    StructField("Cartera_Ecom_Resolucion__c", StringType(), True),
                    StructField("Cartera_Ecom_Status_Plan__c", StringType(), True),
                    StructField("Cartera_fecha__c", StringType(), True),
                    StructField("Cartera_Resolucion__c", StringType(), True),
                    StructField("Cartera_Status_Plan__c", StringType(), True),
                    StructField("Clasificacion_local__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CRM_Navent__c", StringType(), True),
                    StructField("Cuenta__c", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Error_de_SAP__c", StringType(), True),
                    StructField("Error_Portal__c", StringType(), True),
                    StructField("Fecha_de_ultimo_error_SAP__c", StringType(), True),
                    StructField("Flag_Desarrollo__c", StringType(), True),
                    StructField("Flag_EC__c", StringType(), True),
                    StructField("Flag_Premier__c", StringType(), True),
                    StructField("Flag_Recurrencia__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("ID_cliente_CRM__c", StringType(), True),
                    StructField("ID_Empresa_portal__c", StringType(), True),
                    StructField("ID_Empresa_Portal_SAP__c", StringType(), True),
                    StructField("ID_Empresa_Site_exclusivo__c", StringType(), True),
                    StructField("ID_Usuario_SF__c", StringType(), True),
                    StructField("Industria__c", StringType(), True),
                    StructField("Integrador_RE__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Lista_de_precios__c", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField(
                        "Organizacion_de_venta_picklist__c", StringType(), True
                    ),
                    StructField("OwnerId", StringType(), True),
                    StructField("Periodo_Stock__c", StringType(), True),
                    StructField("Primer_error_portal__c", StringType(), True),
                    StructField("Propietario_de_Empresa_Portal__c", StringType(), True),
                    StructField("SAP_prox_bloqueo__c", StringType(), True),
                    StructField("SAP_prox_vencimiento__c", StringType(), True),
                    StructField("SAP_total_deuda_a_vencer__c", StringType(), True),
                    StructField("SAP_total_deuda_vencida__c", StringType(), True),
                    StructField("Sitio__c", StringType(), True),
                    StructField("Sizing__c", StringType(), True),
                    StructField("Status_riesgo__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Total_Avisos__c", StringType(), True),
                    StructField("Total_Avisos_Des_Destacado__c", StringType(), True),
                    StructField("Total_Avisos_Des_SuperDest__c", StringType(), True),
                    StructField("Total_Avisos_Desa_Simple__c", StringType(), True),
                    StructField("Total_Avisos_Destacado__c", StringType(), True),
                    StructField(
                        "Total_Avisos_Online_Des_Destacado__c", StringType(), True
                    ),
                    StructField(
                        "Total_Avisos_Online_Des_SuperDest__c", StringType(), True
                    ),
                    StructField(
                        "Total_Avisos_Online_Desa_Simple__c", StringType(), True
                    ),
                    StructField("Total_Avisos_Online_Destacado__c", StringType(), True),
                    StructField("Total_Avisos_Online_Simple__c", StringType(), True),
                    StructField(
                        "Total_Avisos_Online_Sub_Simple__c", StringType(), True
                    ),
                    StructField("Total_Avisos_Online_SuperDest__c", StringType(), True),
                    StructField("Total_Avisos_Simple__c", StringType(), True),
                    StructField("Total_Avisos_Subsimple__c", StringType(), True),
                    StructField("Total_Avisos_SuperDest__c", StringType(), True),
                    StructField(
                        "Total_Disponible_Avisos_Des_Destacado__c", StringType(), True
                    ),
                    StructField(
                        "Total_Disponible_Avisos_Des_Superdest__c", StringType(), True
                    ),
                    StructField(
                        "Total_Disponible_Avisos_Desa_Simple__c", StringType(), True
                    ),
                    StructField(
                        "Total_Disponible_Avisos_Destacado__c", StringType(), True
                    ),
                    StructField(
                        "Total_Disponible_Avisos_Simple__c", StringType(), True
                    ),
                    StructField(
                        "Total_Disponible_Avisos_Subsimple__c", StringType(), True
                    ),
                    StructField(
                        "Total_Disponible_Avisos_SuperDest__c", StringType(), True
                    ),
                    StructField("Total_Disponibles__c", StringType(), True),
                    StructField("Total_Online__c", StringType(), True),
                    StructField("Total_ordenes_de_servicio__c", StringType(), True),
                    StructField("Total_Usado__c", StringType(), True),
                    StructField(
                        "Total_Usado_Avisos_Des_Destacado__c", StringType(), True
                    ),
                    StructField(
                        "Total_Usado_Avisos_Des_SuperDest__c", StringType(), True
                    ),
                    StructField(
                        "Total_Usado_Avisos_Desa_Simple__c", StringType(), True
                    ),
                    StructField("Total_Usado_Avisos_Destacado__c", StringType(), True),
                    StructField("Total_Usado_Avisos_Simple__c", StringType(), True),
                    StructField("Total_Usado_Avisos_Subsimple__c", StringType(), True),
                    StructField("Total_Usado_Avisos_SuperDest__c", StringType(), True),
                ]
            )
        },
        "Grupo_economico__c": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("Cuenta__c", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Envio_email_OS__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_grupo_economico__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Pais__c": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_de_Pais__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Pricebook2": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Description", StringType(), True),
                    StructField("Es_regional__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("ID_Lista_de_Precios_SAP__c", StringType(), True),
                    StructField("IsActive", StringType(), True),
                    StructField("IsArchived", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("IsStandard", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("Pais__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Provincia_Estado__c": {
            "schema": StructType(
                [
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_de_Provincia_Estado__c", StringType(), True),
                    StructField("Id_Salesforce__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Pais__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "User": {
            "schema": StructType(
                [
                    StructField("AccountId", StringType(), True),
                    StructField("Alias", StringType(), True),
                    StructField("BadgeText", StringType(), True),
                    StructField("BannerPhotoUrl", StringType(), True),
                    StructField("CallCenterId", StringType(), True),
                    StructField("Canal__c", StringType(), True),
                    StructField("Centro_de_costos__c", StringType(), True),
                    StructField("City", StringType(), True),
                    StructField("CommunityNickname", StringType(), True),
                    StructField("CompanyName", StringType(), True),
                    StructField("ContactId", StringType(), True),
                    StructField("Country", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("DefaultCurrencyIsoCode", StringType(), True),
                    StructField(
                        "DefaultGroupNotificationFrequency", StringType(), True
                    ),
                    StructField("DelegatedApproverId", StringType(), True),
                    StructField("Department", StringType(), True),
                    StructField("DigestFrequency", StringType(), True),
                    StructField("Division", StringType(), True),
                    StructField("Email", StringType(), True),
                    StructField("Email__c", StringType(), True),
                    StructField("EmailEncodingKey", StringType(), True),
                    StructField("EmailPreferencesAutoBcc", StringType(), True),
                    StructField(
                        "EmailPreferencesAutoBccStayInTouch", StringType(), True
                    ),
                    StructField(
                        "EmailPreferencesStayInTouchReminder", StringType(), True
                    ),
                    StructField("EmployeeNumber", StringType(), True),
                    StructField("EndDay", StringType(), True),
                    StructField("Error_SAP__c", StringType(), True),
                    StructField("et4ae5__Default_ET_Page__c", StringType(), True),
                    StructField("et4ae5__Default_MID__c", StringType(), True),
                    StructField(
                        "et4ae5__ExactTarget_OAuth_Token__c", StringType(), True
                    ),
                    StructField(
                        "et4ae5__ExactTargetForAppExchangeAdmin__c", StringType(), True
                    ),
                    StructField(
                        "et4ae5__ExactTargetForAppExchangeUser__c", StringType(), True
                    ),
                    StructField("et4ae5__ExactTargetUsername__c", StringType(), True),
                    StructField("et4ae5__ValidExactTargetAdmin__c", StringType(), True),
                    StructField("et4ae5__ValidExactTargetUser__c", StringType(), True),
                    StructField("Extension", StringType(), True),
                    StructField("Fax", StringType(), True),
                    StructField("Fecha_de_ultimo_error_SAP__c", StringType(), True),
                    StructField("FederationIdentifier", StringType(), True),
                    StructField("FirstName", StringType(), True),
                    StructField("ForecastEnabled", StringType(), True),
                    StructField("FullPhotoUrl", StringType(), True),
                    StructField("GeocodeAccuracy", StringType(), True),
                    StructField("Gerente_padre__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_usuario_SAP__c", StringType(), True),
                    StructField("ID_Usuario_SF__c", StringType(), True),
                    StructField("IsActive", StringType(), True),
                    StructField("IsExtIndicatorVisible", StringType(), True),
                    StructField("IsPartner", StringType(), True),
                    StructField("IsPortalEnabled", StringType(), True),
                    StructField("IsProfilePhotoActive", StringType(), True),
                    StructField("LanguageLocaleKey", StringType(), True),
                    StructField("LastLoginDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastName", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Latitude", StringType(), True),
                    StructField("Link_Calendly__c", StringType(), True),
                    StructField("LocaleSidKey", StringType(), True),
                    StructField("Longitude", StringType(), True),
                    StructField("ManagerId", StringType(), True),
                    StructField("MediumBannerPhotoUrl", StringType(), True),
                    StructField("MediumPhotoUrl", StringType(), True),
                    StructField("MobilePhone", StringType(), True),
                    StructField("Mostrar_datos__c", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OfflinePdaTrialExpirationDate", StringType(), True),
                    StructField("OfflineTrialExpirationDate", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("OutOfOfficeMessage", StringType(), True),
                    StructField("Pais__c", StringType(), True),
                    StructField("PasswordExpirationDate", StringType(), True),
                    StructField("Phone", StringType(), True),
                    StructField("PortalRole", StringType(), True),
                    StructField("PostalCode", StringType(), True),
                    StructField("ReceivesAdminInfoEmails", StringType(), True),
                    StructField("ReceivesInfoEmails", StringType(), True),
                    StructField("Rol_padre__c", StringType(), True),
                    StructField("SenderEmail", StringType(), True),
                    StructField("SenderName", StringType(), True),
                    StructField("Signature", StringType(), True),
                    StructField("SmallBannerPhotoUrl", StringType(), True),
                    StructField("SmallPhotoUrl", StringType(), True),
                    StructField("StartDay", StringType(), True),
                    StructField("State", StringType(), True),
                    StructField("StayInTouchNote", StringType(), True),
                    StructField("StayInTouchSignature", StringType(), True),
                    StructField("StayInTouchSubject", StringType(), True),
                    StructField("Street", StringType(), True),
                    StructField("SuAccessExpirationDate", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("TimeZoneSidKey", StringType(), True),
                    StructField("Title", StringType(), True),
                    StructField("Username", StringType(), True),
                    StructField("UserRoleId", StringType(), True),
                    StructField("UserType", StringType(), True),
                ]
            )
        },
        "UserRole": {
            "schema": StructType(
                [
                    StructField("CaseAccessForAccountOwner", StringType(), True),
                    StructField("ContactAccessForAccountOwner", StringType(), True),
                    StructField("DeveloperName", StringType(), True),
                    StructField("ForecastUserId", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("MayForecastManagerShare", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OpportunityAccessForAccountOwner", StringType(), True),
                    StructField("ParentRoleId", StringType(), True),
                    StructField("PortalAccountId", StringType(), True),
                    StructField("PortalAccountOwnerId", StringType(), True),
                    StructField("PortalType", StringType(), True),
                    StructField("RollupDescription", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Zona_Barrio_Colonia_Comuna__c": {
            "schema": StructType(
                [
                    StructField("Ciudad__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField(
                        "Id_de_Zona_Barrio_Colonia_Comuna__c", StringType(), True
                    ),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                ]
            )
        },
        "Organizacion_de_venta__c": {
            "schema": StructType(
                [
                    StructField("Campana_oblig_en_Oport__c", StringType(), True),
                    StructField("Carga_Id_empresa_manual__c", StringType(), True),
                    StructField("CreatedById", StringType(), True),
                    StructField("CreatedDate", StringType(), True),
                    StructField("CRM_Navent__c", StringType(), True),
                    StructField("CurrencyIsoCode", StringType(), True),
                    StructField("Descuentos_permitidos__c", StringType(), True),
                    StructField("Duracion_descuentos__c", StringType(), True),
                    StructField("Emails_envio_OS__c", StringType(), True),
                    StructField("Id", StringType(), True),
                    StructField("Id_de_portal__c", StringType(), True),
                    StructField("Id_SAP__c", StringType(), True),
                    StructField("Id_unidad_de_negocio_Pardot__c", StringType(), True),
                    StructField("IsDeleted", StringType(), True),
                    StructField("LastActivityDate", StringType(), True),
                    StructField("LastModifiedById", StringType(), True),
                    StructField("LastModifiedDate", StringType(), True),
                    StructField("LastReferencedDate", StringType(), True),
                    StructField("LastViewedDate", StringType(), True),
                    StructField("Moneda_base__c", StringType(), True),
                    StructField("Monedas_aceptadas__c", StringType(), True),
                    StructField("Name", StringType(), True),
                    StructField("Organizacion_de_venta__c", StringType(), True),
                    StructField("OwnerId", StringType(), True),
                    StructField("Pais__c", StringType(), True),
                    StructField("Perfil_crediticio__c", StringType(), True),
                    StructField("Portal__c", StringType(), True),
                    StructField(
                        "Renovacion_automatica_de_oportunidades__c", StringType(), True
                    ),
                    StructField("Sincroniza_con_pardot__c", StringType(), True),
                    StructField("SystemModstamp", StringType(), True),
                    StructField("Vertical__c", StringType(), True),
                    StructField("Vias_de_pago_aceptadas__c", StringType(), True),
                ]
            )
        },
    }


def get_next_page_data(
    spark, query, headers, instance_url, table_name, is_done, next_url
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

    df = df.withColumn("dt_updated", col("LastModifiedDate").cast("date"))
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
        target_database_name,
        target_table_name,
    ) = parse_arguments()

    load_start_timstamp = f"{load_start_date}T00:00:00.000000Z"
    load_end_timstamp = f"{load_end_date}T23:59:59.000000Z"

    query += f" WHERE LastModifiedDate >= {load_start_timstamp} AND LastModifiedDate <= {load_end_timstamp}"

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
            spark, query, headers, instance_url, table_name, is_done, next_url
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
