SELECT
    id,
    prospectid AS id_prospect,
    userid AS id_user,
    businesscontext AS business_context,
    salescompany AS sales_company,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_wololo_raw.conversion