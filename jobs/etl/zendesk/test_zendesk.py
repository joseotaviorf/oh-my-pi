from zenpy import Zenpy
import requests


payload = {
    'grant_type': 'client_credentials',
    'client_id': 'data_team',
    'client_secret': 'f598a6a42fae15afbfcb9304e8edea3ec15d898d757a004ab36a0a76b6fc8b98',
    'scope': 'read',
}

# payload = {
#     'grant_type': 'client_credentials',
#     'client_id': 'ZxX3T69QKMHHZkTG9r9qVjDZAfXTXqWFV7MlXT7dokUlSfgkNv',
#     'client_secret': 'UMeGIsnu7HAbVQef9ptBDRs3z3Gp63vgw39HV6XG9FrUlEm20QPYZV8u4hfLLAMN',
#     'redirect_uri': 'https://quintoandar.zendesk.com',
#     'scope': 'read write'
# }
#
# creds = {
#     "subdomain": "quintoandar",
#     "token": "jg44PTqJfPQjtECWgERJUegvwnAXaLubWcyFrGvv",
#     "email": "compras@quintoandar.com.br"
# }

# response = requests.post("https://www.zopim.com/oauth2/token", params=payload).json()

response = requests.post("https://quintoandar.zendesk.com/oauth/tokens", data=payload).json()
oauth_token = response.get('access_token')
creds = {
    "subdomain": "quintoandar",
    "oauth_token": oauth_token
}

zenpy_client = Zenpy(**creds)

g = zenpy_client.groups()
print g.next()

a = zenpy_client.chats.search("zenpy", created_between=['2017-07-22', '2017-07-22'], type='ticket', minus='negated')
print a
