import json


class JsonService:
    @staticmethod
    def transform_json_list_terms(full_json_list):
        """Transform nested json terms into plain string.
        :param full_json_list: Full json list to transform
        :return: Transformed json
        """
        if not isinstance(full_json_list, list):
            raise TypeError("m=transform_json_list_terms, msg=object is not a list")

        transformed_json = []
        for item in full_json_list:
            transformed_json.append(JsonService.transform_json_terms(item))

        return transformed_json

    @staticmethod
    def transform_json_terms(full_json):
        """Transform nested json terms into plain string.
        :param full_json: Full json to transform
        :return: Transformed json
        """
        transformed_json = {}
        for k, v in full_json.items():
            if isinstance(v, dict) or isinstance(v, list):
                transformed_json[k] = json.dumps(v)
            elif v is not None:
                transformed_json[k] = v

        return transformed_json

    @staticmethod
    def transform_columns_type_to_string(full_json):
        """
        Transform all json columns to string.
        :param full_json: Full json to transform
        :return: json with columns of string type.
        """
        transformed_json = {}
        for k, v in full_json.items():
            if not isinstance(v, str):
                transformed_json[k] = json.dumps(v, ensure_ascii=False)
            else:
                transformed_json[k] = v

        return transformed_json
