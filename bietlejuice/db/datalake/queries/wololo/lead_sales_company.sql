with lead_sales_company as (
    select
       p.referenceid as id_lead,
       from_unixtime(cast(revtstmp as bigint)/1000) as ts_sales_company_sent,
       salescompany as sales_company,
       rank() over (partition by p.referenceid order by revtstmp desc) as rank_last_to_first
    from datalake_wololo_raw_prod.prospect p
      join datalake_wololo_raw_prod.prospectdimension_aud pd_aud
          on p.dimensionentity_id =  pd_aud.id
      join datalake_wololo_raw_prod.revinfo info
         on pd_aud.rev = info.rev
)
select
    id_lead,
    sales_company,
    ts_sales_company_sent
from
    lead_sales_company
where
    -- extracting the latest relation of lead - sales_company
    rank_last_to_first = 1