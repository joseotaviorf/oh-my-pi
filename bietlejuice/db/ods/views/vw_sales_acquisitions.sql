--drop view if exists vw_sales_acquisitions;
--create or replace view vw_sales_acquisitions as
with legacy_doorman as (
    select
        porteiros_legado."Status" as status,
        892700000 + porteiros_legado."Cod Imóvel"::double precision::bigint as imovel_id
    from
        gsheets.porteiros_legado
    where
        porteiros_legado."Status" in ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead')
        and porteiros_legado."Cod Imóvel" is not null
)
select
    f.id,
    case
        when d.imovel_id is not null and f.is_not_reprocessed then 'Lead Flow'
        else f.flow
    end as flow,
    case
        when d.imovel_id is not null and f.is_not_reprocessed then 'Non-Self Service'
        else f.acquisition_method
    end as acquisition_method,
    case
        when d.imovel_id is not null and f.is_not_reprocessed then 'Doorman'
        else f.acquisition_channel_rep
    end as acquisition_channel,
    case
        when d.imovel_id is not null and f.is_not_reprocessed then 'Doorman'
        else f.acquisition_source
    end as acquisition_source,
    case
        when d.imovel_id is not null and f.is_not_reprocessed then true
        else f.acquisition_source = 'Doorman'
    end as is_doorman
from
    sales_listing_flows_with_reprocessed_leads f
left join
    legacy_doorman d
        on f.imovel_id = d.imovel_id
