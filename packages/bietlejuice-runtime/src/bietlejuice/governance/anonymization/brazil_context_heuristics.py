"""Column-context heuristics for PERSON/LOCATION false positives (DPLT-971).

NER (spaCy) frequently tags PERSON / LOCATION on columns that are clearly business
metadata (deal titles, CRM blobs, metrics). A naive deny-list demotes those, but a
broad token such as ``condominio`` also wrongly demotes a legitimate location column
like ``condominio_name``.

Model (per entity, allow-list wins over deny-list):

1. PERSON  -> keep if the column is a person-name column (PT-BR + EN allow-list);
   demote on geo/address columns (a `city`/`street` tagged PERSON is a model error).
2. LOCATION -> keep if the column is a geo/address column (PT-BR + EN allow-list).
3. Demote PERSON/LOCATION on temporal columns (ts_/dt_/_date/_at), identifier
   columns (id/uuid/ticket/transaction/number), and business/CRM blob columns.
4. Default -> keep (favor recall; weak hits were already filtered by score floors).
"""

from __future__ import annotations

import re
from typing import Optional

from bietlejuice.governance.anonymization.brazil_datetime_heuristics import (
    is_identifier_like_column,
    is_temporal_column,
)

PERSON_ENTITY = "PERSON"
LOCATION_ENTITY = "LOCATION"

# Person-role tokens that, next to name/nome, denote a human name (PT-BR + EN).
_PERSON_ROLE = (
    r"user|usuario|customer|client|cliente|tenant|locatario|inquilino|locador|"
    r"landlord|proprietario|owner|proponent|proponente|beneficiary|beneficiario|"
    r"guarantor|fiador|contact|contato|responsavel|representante|signatory|"
    r"signatario|titular|holder|person|pessoa|morador|hospede|guest|author|autor|"
    r"assignee|colaborador|employee|funcionario|candidato|candidate|lead|payer|"
    r"pagador|recipient|destinatario|emitente|portador"
)

# Standalone person-name columns (full-column match to avoid matching deal_name etc.).
_PERSON_STANDALONE = (
    r"name|nome|full_?name|nome_completo|first_?name|primeiro_nome|last_?name|"
    r"ultimo_nome|middle_name|nome_do_meio|nome_meio|segundo_nome|sobrenome|"
    r"surname|given_name|apelido|nickname|razao_social|nome_social|nome_fantasia"
)

PERSON_NAME_COLUMN_RE = re.compile(
    r"(?i)"
    r"^(?:" + _PERSON_STANDALONE + r")$"
    r"|(?:^|_)(?:" + _PERSON_ROLE + r")_(?:full_)?(?:name|nome)(?:_|$)"
    r"|(?:^|_)(?:name|nome)_(?:do_|da_|de_)?(?:" + _PERSON_ROLE + r")(?:_|$)"
)

# Geo / address tokens (PT-BR + EN).
_GEO_TOKEN = (
    r"address|addr|endereco|logradouro|rua|street|avenida|avenue|av|bairro|"
    r"neighborhood|neighbourhood|cidade|city|municipio|estado|state|uf|pais|"
    r"country|cep|zip|zipcode|zip_code|postal_code|postcode|codigo_postal|"
    r"complemento|complement|localizacao|location|regiao|region|quadra|lote|"
    r"apartamento|apto|bloco|torre|numero_endereco|num_endereco|num_address"
)

LOCATION_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(?:" + _GEO_TOKEN + r")(?:_|$)"
    r"|(?:^|_)(?:condominio|condominium|condo|edificio|empreendimento)_(?:name|nome)(?:_|$)"
    r"|(?:^|_)(?:name|nome)_(?:do_)?(?:condominio|condominium|condo|edificio|empreendimento)(?:_|$)"
)

# Business / CRM / metric columns where NER PERSON/LOCATION is almost always a FP.
BUSINESS_CONTEXT_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(deal|company|empresa|metric|metrica|total|condominio|crn|subject|"
    r"assunto|title|titulo|comment|comentario|body|extra|properties|metadata|"
    r"description|descricao|dimension|session|funnel|funil|status|type|tipo|"
    r"label|category|categoria|tag|association|associations|payload|amplitude|"
    r"receiver_info|ticket_breakdown)(?:_|$)|"
    r"utm_|search_query|device_|gallery_|price_tier|area_m2|pod_name|"
    r"previous_path|integration_|"
    r"deal_name|deal_|_deal$|_subject$|_assunto$|_comment$|_comentario$|"
    r"_description$|_descricao$|tickets_subject"
)

# Identifier / technical columns: surrogate keys, codes, sequences. A PERSON or
# LOCATION hit here is a NER false positive (e.g. id_application tagged PERSON).
# Actor FK columns (*_by, id_*_by) share the same rule as datetime heuristics.
IDENTIFIER_COLUMN_RE = re.compile(
    r"(?i)(?:^|_)(id|ids|uuid|guid|key|sk|fk|pk|hash|token|code|codigo|sku|seq|"
    r"sequence|sequencia|protocol|protocolo|reference|referencia|external_id|"
    r"application|amplitude|ticket|transaction|number|numero|nr|incremental|"
    r"version|revtype|offset|partition)(?:_|$)|"
    r"(?:^|_)id_[a-z0-9_]+|[a-z0-9]+_id$|^id$|"
    r"[a-z0-9_]*uuid$|"
    r"_by$"
)

UUID_VALUE_RE = re.compile(
    r"(?i)^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$"
)


def looks_like_uuid_value(matched_value: Optional[str]) -> bool:
    if matched_value is None:
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False
    return bool(UUID_VALUE_RE.match(value))


def is_person_name_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    return bool(PERSON_NAME_COLUMN_RE.search(column_name))


# Backward-compatible alias (previously matched PERSON name columns only).
def is_strong_name_column(column_name: Optional[str]) -> bool:
    return is_person_name_column(column_name)


def is_location_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    return bool(LOCATION_COLUMN_RE.search(column_name))


def is_business_context_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    return bool(BUSINESS_CONTEXT_COLUMN_RE.search(column_name))


def is_identifier_column(column_name: Optional[str]) -> bool:
    if not column_name:
        return False
    if is_identifier_like_column(column_name):
        return True
    return bool(IDENTIFIER_COLUMN_RE.search(column_name))


def should_keep_person_or_location(
    entity_type: Optional[str],
    column_name: Optional[str],
    matched_value: Optional[str],
) -> bool:
    if entity_type not in (PERSON_ENTITY, LOCATION_ENTITY):
        return True
    if matched_value is None:
        return False
    value = str(matched_value).strip()
    if not value or value == "SAMPLE_TOO_BIG":
        return False

    column = column_name or ""

    if entity_type == PERSON_ENTITY:
        if looks_like_uuid_value(value):
            return False
        # Allow-list (clear person-name columns) wins over every deny-list.
        if is_person_name_column(column):
            return True
        # A geo/address column tagged PERSON is a misclassification (e.g. the PT-BR
        # model tags `city` / `street` values as PER). Demote it.
        if is_location_column(column):
            return False
        if is_temporal_column(column):
            return False
        if is_identifier_column(column):
            return False
        if is_business_context_column(column):
            return False
        return True

    # LOCATION: allow-list (geo/address) wins over the deny-lists.
    if is_location_column(column):
        return True
    if is_temporal_column(column):
        return False
    if is_identifier_column(column):
        return False
    if is_business_context_column(column):
        return False
    return True


def apply_context_heuristics_to_cleaned_results(
    cleaned_results: list[dict],
    column_name: str,
) -> list[dict]:
    adjusted = []
    for item in cleaned_results:
        entity_type = item.get("type")
        if should_keep_person_or_location(
            entity_type, column_name, item.get("matched_value")
        ):
            adjusted.append(item)
        else:
            adjusted.append(
                {
                    "type": "NOT_FOUND",
                    "score": 0.0,
                    "matched_value": item.get("matched_value"),
                }
            )
    return adjusted


def apply_context_heuristics_to_nested_cleaned_results(
    nested_cleaned: list[list[dict]],
    column_name: str,
) -> list[list[dict]]:
    return [
        apply_context_heuristics_to_cleaned_results(chunk, column_name)
        for chunk in nested_cleaned
    ]
