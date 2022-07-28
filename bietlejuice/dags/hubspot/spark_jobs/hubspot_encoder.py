import datetime
import json


class HubSpotEncoder(json.JSONEncoder):
    def default(self, o):
        if "ValueWithTimestamp" in str(type(o)):
            return o.to_dict()
        if isinstance(o, datetime.datetime):
            return o.isoformat()

        return json.JSONEncoder.default(self, o)
