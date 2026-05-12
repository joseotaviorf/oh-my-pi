import json


class JsonService:
    @staticmethod
    def transform_json_list_terms(full_json_list, cls=None):
        """Transform nested json terms into plain string.
        :param full_json_list: Full json list to transform
        :param cls: custom JSONEncoder subclass. If not specified JSONEncoder is used.
        :return: Transformed json
        """
        if not isinstance(full_json_list, list):
            raise TypeError("m=transform_json_list_terms, msg=object is not a list")

        transformed_json = []
        for item in full_json_list:
            transformed_json.append(JsonService.transform_json_terms(item, cls=cls))

        return transformed_json

    @staticmethod
    def transform_json_terms(full_json, cls=None):
        """Transform nested json terms into plain string.
        :param full_json: Full json to transform
        :param cls: custom JSONEncoder subclass. If not specified JSONEncoder is used.
        :return: Transformed json
        """
        transformed_json = {}
        for k, v in full_json.items():
            if isinstance(v, dict) or isinstance(v, list):
                transformed_json[k] = json.dumps(v, cls=cls)
            elif v is not None:
                transformed_json[k] = v

        return transformed_json

    @staticmethod
    def transform_columns_type_to_string(full_json, cls=None):
        """
        Transform all json columns to string.
        :param full_json: Full json to transform
        :param cls: custom JSONEncoder subclass. If not specified JSONEncoder is used.
        :return: json with columns of string type.
        """
        transformed_json = {}
        for k, v in full_json.items():
            if not isinstance(v, str):
                transformed_json[k] = json.dumps(v, ensure_ascii=False, cls=cls)
            else:
                transformed_json[k] = v

        return transformed_json
