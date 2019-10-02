select
    hash,
    name,
    status,
    isEditable as is_editable,
    rateCardId as rate_card_id,
    updatedAt as updated_at,
    account_status,
    placement,
    account_hash,
    account_name,
    account_currency
from datalake_raw.marketing_rtb_sub_campaigns
where dt='{date}' and acc='{account}'