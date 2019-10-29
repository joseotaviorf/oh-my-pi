select
    p.referenceid as sk_lead,
    salescompany as sales_company
from datalake_wololo_raw_prod.prospect p
join datalake_wololo_raw_prod.prospectdimension pd on pd.id = p.dimensionentity_id
