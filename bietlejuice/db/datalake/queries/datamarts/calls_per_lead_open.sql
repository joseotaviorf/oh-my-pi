with tasks_updated as (
    with max_dt as (
        SELECT id, max(dt) as max_dt
        FROM datalake_clean.crm_tasks
        WHERE type in ('ConverterLead', 'ConverterLeadPrioritario')
        GROUP BY 1
    )
    SELECT ct.id, ct.score_factor, ct.dt, ct.id_origin
    FROM datalake_clean.crm_tasks ct
    JOIN max_dt m on m.id = ct.id AND ct.dt = m.max_dt
    WHERE type in ('ConverterLead', 'ConverterLeadPrioritario')
),
mailing_list_updated as (
        with max_id_hosanna as (
        SELECT m.codigo, max(id) as max_id
        FROM datalake_raw.autodialer_mailing_list m
        GROUP BY 1
    )
    SELECT m.codigo, m.id
    FROM datalake_raw.autodialer_mailing_list m
    JOIN max_id_hosanna mh on mh.codigo = m.codigo AND mh.max_id = m.id
),
base as (
    SELECT
        l.id,
        l.ts_created as criadoEm,
        fhl.mkt_origin  as "canal",
        l.city as cidade,
        dr.city_group   as "city_group",
        dr.name         as "region_name",
        l.zip_code as cep,
        l.address as endereco,
        l.house_number as numero,
        l.complement as complemento,
        l.advertiser_name as nomeAnunciante,
        l.advertiser_phone as telefoneAnunciante,
        l.advertiser_second_phone as telefoneAnuncianteDois,
        l.advertiser_third_phone telefoneAnuncianteTres,
        l.id_lead_owner as proprietarioLead_id,
        l.reason,
        l.status,
        t.score_factor,
        cast(substr(eventdate, 1, 19) as timestamp)                         as ts_call,
        concat('https://user.quintoandar.com.br/lead/', cast(l.id as varchar), '/converter') as "url_admin"
    FROM datalake_clean.autodialer_task_reference_inbound_event_histories events
    LEFT JOIN tasks_updated t on t.id = events.task_id
    LEFT JOIN datalake_ebdb_clean_prod.lead l on cast(l.id as varchar) = t.id_origin
    LEFT JOIN datalake_clean.ods_fact_house_listing_flows fhl on fhl.sk_lead = cast(l.id as varchar)
    JOIN datalake_clean.autodialer_task_references r on r.task_id = t.id
    JOIN mailing_list_updated m on m.codigo = r.task_id
    LEFT JOIN datalake_clean.ods_dim_region dr on dr.sk_region = fhl.sk_region
    WHERE taskReferenceEventOrigin = 'WEB_HOOK_BEFORE_NOTIFICATION'
        AND date(l.ts_created) >= CURRENT_DATE - interval '120' day
        AND reason = 'OWNER_WONT_ANSWER_PHONE'
        AND status = 'Prospeccao'
),
call_number_filter as (
    SELECT id, count(distinct ts_call) as number_of_calls
    FROM base
    GROUP BY 1
)
SELECT distinct b.criadoEm,
                b.id,
                canal,
                cidade,
                city_group,
                region_name,
                cep,
                endereco,
                numero,
                complemento,
                nomeAnunciante,
                telefoneAnunciante,
                telefoneAnuncianteDois,
                telefoneAnuncianteTres,
                proprietarioLead_id,
                reason,
                status,
                score_factor,
                url_admin,
                b2.number_of_calls
FROM base b
         JOIN call_number_filter b2 on b2.id = b.id
ORDER BY 1, 2;
