def build_credential_payload(credentials):
    return {
        "client_id": credentials["client_id"],
        "client_secret": credentials["client_secret"],
        "grant_type": "client_credentials",
    }


def build_salesforce_table_description_header(access_token):
    return {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Sforce-Query-Options": "batchSize=5",
    }


def build_authorization_header(access_token):
    return {
        "Authorization": f"Bearer {access_token}",
    }
