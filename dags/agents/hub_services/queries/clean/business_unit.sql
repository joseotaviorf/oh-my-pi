WITH deduped AS (
    SELECT
        id,
        version,
        name AS hub_name,
        business_context,
        sdr_type,
        negotiation_type,
        lead_types,
        operational_context,
        created_at AS ts_created,
        updated_at AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.business_unit
)
SELECT
    id,
    version,
    hub_name,
    business_context,
    sdr_type,
    negotiation_type,
    lead_types,
    operational_context,
    ts_created,
    ts_updated,
    year,
    month,
    day,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    deduped
WHERE
    rn = 1
