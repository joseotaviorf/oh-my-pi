select
    id,
    bank_id as id_bank,
    sha2(agency,256) as agency,
    sha2(account,256) as account, 
    boolean(active) as is_active,
    sha2(account_digit,256) as account_digit
from
    datalake_vans_raw.bank_boleto