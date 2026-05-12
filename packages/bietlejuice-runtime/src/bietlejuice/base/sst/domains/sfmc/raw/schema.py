import xml.etree.ElementTree as ET
from typing import Dict, List
from xml.sax.saxutils import escape

import defusedxml.ElementTree as DefusedET
import requests
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("sst.domains.sfmc.raw.schema")

SFMC_TIMESTAMP_FORMATS = [
    "M/d/yyyy h:mm:ss a",
    "M/d/yyyy h:mm a",
    "M/d/yyyy H:mm:ss",
    "yyyy-MM-dd HH:mm:ss",
    "yyyy-MM-dd'T'HH:mm:ss",
]


def _get_text(xml_node: ET.Element, tag_name: str, namespaces: Dict[str, str]) -> str:
    node = xml_node.find(f"api:{tag_name}", namespaces)
    if node is None or node.text is None:
        return ""
    return str(node.text).strip()


def _ordinal_sort_value(raw_ordinal: str) -> int:
    try:
        return int(raw_ordinal)
    except (TypeError, ValueError):
        return 999999


@logger(exclude=["access_token"], exclude_return=False)
def get_data_extension_schema(
    soap_url: str,
    access_token: str,
    customer_key: str,
) -> List[Dict[str, str]]:
    escaped_access_token = escape(access_token)
    escaped_customer_key = escape(customer_key)
    request_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <soapenv:Header>
        <fueloauth xmlns="http://exacttarget.com">{escaped_access_token}</fueloauth>
    </soapenv:Header>
    <soapenv:Body>
        <RetrieveRequestMsg xmlns="http://exacttarget.com/wsdl/partnerAPI">
            <RetrieveRequest>
                <ObjectType>DataExtensionField</ObjectType>
                <Properties>Name</Properties>
                <Properties>FieldType</Properties>
                <Properties>IsPrimaryKey</Properties>
                <Properties>IsRequired</Properties>
                <Properties>MaxLength</Properties>
                <Properties>Ordinal</Properties>
                <Filter xsi:type="SimpleFilterPart">
                    <Property>DataExtension.CustomerKey</Property>
                    <SimpleOperator>equals</SimpleOperator>
                    <Value>{escaped_customer_key}</Value>
                </Filter>
            </RetrieveRequest>
        </RetrieveRequestMsg>
    </soapenv:Body>
</soapenv:Envelope>"""

    response = requests.post(
        f"{soap_url.rstrip('/')}/Service.asmx",
        data=request_xml.encode("utf-8"),
        headers={
            "Content-Type": "text/xml; charset=utf-8",
            "SOAPAction": "Retrieve",
        },
        timeout=120,
    )
    response.raise_for_status()

    namespaces = {
        "soap": "http://schemas.xmlsoap.org/soap/envelope/",
        "api": "http://exacttarget.com/wsdl/partnerAPI",
    }
    xml_root = DefusedET.fromstring(response.text)

    fault = xml_root.find(".//soap:Fault", namespaces)
    if fault is not None:
        fault_message = " ".join(text.strip() for text in fault.itertext() if text)
        raise ValueError(f"SFMC SOAP fault while retrieving schema: {fault_message}")

    fields: List[Dict[str, str]] = []
    for item in xml_root.findall(".//api:Results", namespaces):
        ordinal = _get_text(item, "Ordinal", namespaces)
        fields.append(
            {
                "field_name": _get_text(item, "Name", namespaces),
                "field_type": _get_text(item, "FieldType", namespaces),
                "is_primary_key": _get_text(item, "IsPrimaryKey", namespaces),
                "is_required": _get_text(item, "IsRequired", namespaces),
                "max_length": _get_text(item, "MaxLength", namespaces),
                "ordinal": ordinal if ordinal else "999999",
            }
        )

    if not fields:
        raise ValueError(
            f"No DataExtensionField metadata returned for customer_key={customer_key}."
        )

    return sorted(fields, key=lambda field: _ordinal_sort_value(field["ordinal"]))


def build_schema_columns(schema_fields: List[Dict[str, str]]) -> Dict[str, str]:
    schema_columns = {}
    for field in schema_fields:
        source_field_name = str(field.get("field_name", "")).strip()
        if not source_field_name:
            continue

        if source_field_name in schema_columns:
            raise ValueError(
                f"Duplicated column name in SFMC schema: {source_field_name}"
            )
        schema_columns[source_field_name] = str(field.get("field_type", "")).strip()

    return schema_columns


def _compact_column_name(column_name: str) -> str:
    return "".join(char for char in str(column_name).lower() if char.isalnum())


def _find_schema_alias_column(normalized_columns: List[str], schema_column: str) -> str:
    if schema_column in normalized_columns:
        return schema_column

    compact_columns = {}
    for column in normalized_columns:
        compact_name = _compact_column_name(column)
        compact_columns.setdefault(compact_name, []).append(column)

    def _get_unique_column(compact_name: str) -> str:
        candidates = compact_columns.get(compact_name, [])
        if len(candidates) == 1:
            return candidates[0]
        return ""

    direct_alias = _get_unique_column(_compact_column_name(schema_column))
    if direct_alias:
        return direct_alias

    if schema_column.startswith("id_"):
        entity_name = schema_column[len("id_") :]
        id_alias_compacts = (
            _compact_column_name(f"{entity_name}id"),
            _compact_column_name(f"{entity_name}_id"),
        )
        for alias_compact in id_alias_compacts:
            alias_column = _get_unique_column(alias_compact)
            if alias_column:
                return alias_column

    return ""


def _parse_sfmc_timestamp(column_expression):
    timestamp_candidates = [
        F.to_timestamp(column_expression, timestamp_format)
        for timestamp_format in SFMC_TIMESTAMP_FORMATS
    ]
    timestamp_candidates.append(F.to_timestamp(column_expression))
    return F.coalesce(*timestamp_candidates)


def _cast_by_sfmc_field_type(df, column_name: str, field_type: str):
    normalized_type = str(field_type).strip().lower()
    if normalized_type in {"number", "decimal"}:
        return df.withColumn(column_name, F.col(column_name).cast("double"))
    if normalized_type == "boolean":
        return df.withColumn(column_name, F.col(column_name).cast("boolean"))
    return df


def _cast_datetime_column_with_validation(df, column_name: str):
    raw_column = f"__raw_{column_name}"
    transformed_df = df.withColumn(raw_column, F.col(column_name).cast("string"))
    transformed_df = transformed_df.withColumn(
        column_name, _parse_sfmc_timestamp(F.col(raw_column))
    )

    parse_fail_count = transformed_df.where(
        F.col(raw_column).isNotNull()
        & (F.length(F.trim(F.col(raw_column))) > 0)
        & F.col(column_name).isNull()
    ).count()

    transformed_df = transformed_df.drop(raw_column)
    if parse_fail_count > 0:
        raise ValueError(
            "Failed to parse SFMC datetime values "
            f"for column={column_name}. Unparsed rows={parse_fail_count}."
        )

    return transformed_df


def _ensure_schema_column(df, schema_column: str):
    if schema_column in df.columns:
        return df

    alias_column = _find_schema_alias_column(df.columns, schema_column)
    if alias_column:
        logger.info(
            "m=_ensure_schema_column, "
            f"msg=Applying schema alias, alias_column={alias_column}, target_column={schema_column}"
        )
        if alias_column == schema_column:
            return df
        return df.withColumnRenamed(alias_column, schema_column)

    return df.withColumn(schema_column, F.lit(None).cast("string"))


def align_and_cast_with_schema(df, schema_columns: Dict[str, str]):
    transformed_df = df
    for column_name, field_type in schema_columns.items():
        transformed_df = _ensure_schema_column(transformed_df, column_name)

        if str(field_type).strip().lower() in {"date", "datetime"}:
            transformed_df = _cast_datetime_column_with_validation(
                transformed_df, column_name
            )
            continue

        transformed_df = _cast_by_sfmc_field_type(
            df=transformed_df,
            column_name=column_name,
            field_type=field_type,
        )

    return transformed_df.select(list(schema_columns.keys()))
