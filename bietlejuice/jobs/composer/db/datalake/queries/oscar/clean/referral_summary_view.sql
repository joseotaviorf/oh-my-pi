select 
    referred_id as id_referred,
    name as user_name,
    email as user_email,
    phone as user_phone,
    created_at as ts_created,
    recommended_house_count as count_recommended_house,
    status,
    referrer_id as id_referrer
from datalake_oscar_raw.referral_summary_view