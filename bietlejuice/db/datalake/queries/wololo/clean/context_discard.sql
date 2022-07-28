SELECT
    id,
    prospectid AS id_prospect,
    userid AS id_user,
    businesscontext AS business_context,
    reason,
    salescompany AS sales_company,
    automaticallydiscarded AS is_automatically_discarded,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_wololo_raw.context_discard
