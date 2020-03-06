-- Some fields are JSON strings. We're using REGEX because it's not possible to use get_json_object because of the special characters.

select
    -- format {{"$oid":"sdjds092jls3"}}
    regexp_extract(_id, '(\\w+\\d+)', 1) as _id,
    regexp_extract(entity_id, '(\\w+\\d+)', 1) as id_entity,
    entity_data,
    boolean(status) as is_status,
    collection as collection_name,
    -- format {{"$date":"2019-02-12T00:15:27.000+0000"}}
    cast(regexp_extract(revision_date, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_revised,
    query,
    operation as operation_type
from 
    datalake_cidade_alerta_raw.audit
where
    year={year} and month={month} and day={day}