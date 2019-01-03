import pandas as pd
import requests
from zenpy import Zenpy


def get_zendek_client(client_id, client_secret):
    payload_zendesk = {
        'grant_type': 'client_credentials',
        'client_id': client_id,
        'client_secret': client_secret,
        'scope': 'read',
    }

    response_zen = requests.post("https://quintoandar.zendesk.com/oauth/tokens", data=payload_zendesk).json()
    creds_zen = {
        "subdomain": "quintoandar",
        "oauth_token": response_zen.get('access_token')
    }
    return Zenpy(**creds_zen)


def get_chat_client(client_id, client_secret, auth_token, name='Data Team - Confidential Client'):
    json = {
        "name": name,
        "company": "QuintoAndar",
        "client_secret": client_id,
        "client_identifier": client_secret,
        "client_type": "confidential",
        "redirect_uris": "https://localhost:5000/autorize",
        "scopes": "read write"
    }
    headers = {
        "Authorization": "Bearer {}".format(auth_token)
    }
    url_clients = 'https://www.zopim.com/api/v2/oauth/clients'

    # TODO: Change DELETE/CREATE to UPDATE an existing Confidential Client
    response_list = requests.get("", json=json, headers=headers).json()
    df = pd.DataFrame.from_dict(response_list)
    frame_to_delete = df.loc[df['name'] == name]
    if not frame_to_delete.empty:
        for item in frame_to_delete.to_records():
            id = item['id']
            requests.delete("{}/{}".format(url_clients, id), json=json, headers=headers)
    response_creation = requests.post(url_clients, json=json, headers=headers).json()

    payload_chat = {
        'grant_type': 'client_credentials',
        "client_type": response_creation.get('client_type'),
        'client_id': response_creation.get('client_identifier'),
        'client_secret': response_creation.get('client_secret'),
        'redirect_uri': response_creation.get('redirect_uris')
    }

    response_chat = requests.post(
        "https://www.zopim.com/oauth2/token",
        params=payload_chat
    ).json()
    creds_chat = {
        "subdomain": "quintoandar",
        "oauth_token": response_chat.get('access_token')
    }
    return Zenpy(**creds_chat)


# chat_client = get_chat_client(
#     client_id='myHwYHrjakh42Nk5tmhNEZfn6qW9304RZ5autG9zeH8yAmQIIH',
#     client_secret='BhWzDqMSkioLUd9KBJWkQBWZSFaHkO3149qjRwtkc2BfNs8Lumhx2z2wvTNItZPQ',
#     auth_token='C6Q9zRE8soXyfojeX39f8Npp3uvzNqb0BE1uZXFMsZkhthfOh6iRCf8E8TJi0lcS'
# )
# while datetime.datetime.today() < datetime.datetime(2017,07,26, 18,0):
#     time = datetime.datetime.today().strftime('%Y%m%d-%H.%M.%S')
#     chats = chat_client.chats()
#     a = chats.process_page()
#     for chat in a:
#         if chat.history:
#             print(
#                 u'{};{};{}'.format(
#                     time,
#                     chat.visitor.name,
#                     chat.history[len(chat.history) - 1].get('timestamp')
#                 )
#             )
#     t.sleep(30)
# with BaseETL.open_gzip_fp() as fp:
#     for c in chats:
#         BaseETL.write_json_in_fp(c.to_dict(), fp)
#     gz = fp.fileobj
#
# file_path = 'chat/{}.gz'.format(datetime.datetime.now().strftime('%Y%m%d-%H.%M.%S'))
# BaseETL.obj_to_s3(
#     obj_io=gz,
#     bucket='bi-etl-ejuice-tmpfiles',
#     file_path=file_path
# )


zen_client = get_zendek_client('data_team', 'f598a6a42fae15afbfcb9304e8edea3ec15d898d757a004ab36a0a76b6fc8b98')
groups = zen_client.search()
# print groups
