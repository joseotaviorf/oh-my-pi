from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.sst.configs.salesforce import AUTH_ENDPOINT
from bietlejuice.base.sst.core.api.credentials import retrieve_credentials
from bietlejuice.base.sst.core.api.request import post_request
from bietlejuice.base.sst.domains.salesforce.api.headers import (
    build_credential_payload,
)


def retrieve_token(endpoint=None, env="prod"):
    if not endpoint:
        raise ValueError("Endpoint is required to retrieve token")

    api_enum = APIEnum.SALESFORCE if env == "prod" else APIEnum.SALESFORCE_FORNO
    credentials = retrieve_credentials(api_enum)
    cred_payload = build_credential_payload(credentials=credentials)
    auth_response = post_request(
        endpoint=endpoint + AUTH_ENDPOINT, payload=cred_payload
    )
    return auth_response["access_token"]
