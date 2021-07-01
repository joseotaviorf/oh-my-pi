with
lead_revision as (
    select
      id_reference as id_lead,
      id_dimension_entity,
      sales_company,
      ts_rev as rev_datetime,
      info.rev,
      min(ts_rev) over (partition by id_reference) as insert_time,
      case when lag (sales_company) over (partition by id_reference order by ts_rev asc) <> sales_company then true else false end as flag_change_sales_company
    from datalake_wololo_clean_prod.prospect_aud p
      join datalake_wololo_clean_prod.prospect_dimension_aud pd_aud
          on p.dimensionentity_id =  pd_aud.id
      join datalake_wololo_clean_prod.rev_info info
         on pd_aud.rev = info.rev
),
last_change_company as (
    select
        id_lead,
        max(case when flag_change_sales_company = true then rev_datetime else insert_time end) as last_change_company_time
    from lead_revision
    group by 1
),
distinct_lcc as (
select
    lr.id_lead,
    sales_company,
    last_change_company_time as ts_sales_company_sent,
    row_number() over (partition by lr.id_lead order by lr.rev desc) as rnk_lead
from lead_revision lr
     join last_change_company lcc
        on lr.id_lead = lcc.id_lead
        and lcc.last_change_company_time = lr.rev_datetime
)
select
    id_lead,
    sales_company,
    ts_sales_company_sent
from distinct_lcc
where rnk_lead = 1
