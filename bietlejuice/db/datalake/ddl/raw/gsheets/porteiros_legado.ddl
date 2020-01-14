drop table if exists datalake_raw.gsheets_porteiros_legado;

create external table datalake_raw.gsheets_porteiros_legado (
    address string,
    created_date string,
    crm_status string,
    doorman_id string,
    doorman_name string,
    id_house string,
    indication_date string,
    justification string,
    last_interaction_date string,
    lead_address string,
    observation string,
    owner_name string,
    owner_telephone string,
    payment string,
    reason string,
    status string,
    telephone string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
    'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/gsheets/porteiros_legado/'
;
