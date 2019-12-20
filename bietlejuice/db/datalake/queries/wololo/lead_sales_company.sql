with
lead_revision as (
    select
      referenceid as id_lead,
      dimensionentity_id,
      salescompany as sales_company,
      from_unixtime(info.revtstmp/1000) as rev_datetime,
      min(from_unixtime(info.revtstmp/1000)) over (partition by referenceid) as insert_time,
      case when lag (salescompany) over (partition by referenceid order by from_unixtime(info.revtstmp/1000) asc) <> salescompany then true else false end as flag_change_sales_company
    from datalake_wololo_raw_prod.prospect_aud p
      join datalake_wololo_raw_prod.prospectdimension_aud pd_aud
          on p.dimensionentity_id =  pd_aud.id
      join datalake_wololo_raw_prod.revinfo info
         on pd_aud.rev = info.rev
),
last_change_company as (
    select
        id_lead,
        max(case when flag_change_sales_company = true then rev_datetime else insert_time end) as last_change_company_time
    from lead_revision
    group by 1
)
select
    lr.id_lead,
    sales_company,
    last_change_company_time as ts_sales_company_sent
from lead_revision lr
     join last_change_company lcc
        on lr.id_lead = lcc.id_lead
        and lcc.last_change_company_time = lr.rev_datetime
