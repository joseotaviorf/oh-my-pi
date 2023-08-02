import datetime
import json


class VespucioScoreCalculator:
    @staticmethod
    def get_greatest_dsr_and_updated_year(dataset, group_by_key, agg_keys) -> dict:
        """
        dsr means Data Source Reliability
        """

        """
        agg_keys[0] is updated_year
        agg_keys[1] is dsr
        """
        dic = {}

        for item in dataset:
            key = item[group_by_key]
            if key in dic:
                if int(item[agg_keys[0]]) > int(dic[key]["updated_year"]):
                    dic[key]["updated_year"] = item[agg_keys[0]]
                if item[agg_keys[1]] > dic[key]["dsr"]:
                    dic[key]["dsr"] = item[agg_keys[1]]
                    dic[key]["sum_dsr"] = dic[key]["sum_dsr"] + item[agg_keys[1]]
            else:
                dic[key] = {}
                dic[key]["updated_year"] = item[agg_keys[0]]
                dic[key]["dsr"] = item[agg_keys[1]]
                dic[key]["sum_dsr"] = item[agg_keys[1]]

        return dic

    @staticmethod
    def calculate_score(dataset):
        max_score = 0
        name_key = ""

        for key, value in dataset.items():
            age = datetime.date.today().year - int(value["updated_year"])
            total_sum = float(value["sum_dsr"]) - float(value["dsr"])
            score = float(value["dsr"]) + (total_sum * 0.5) - (age * 0.2)

            if score > max_score:
                name_key = key
                max_score = score

        if max_score > 0.9:
            max_score = 0.9
        if max_score < 0:
            max_score = 0

        return (name_key, round(max_score, 2))

    def get_score(col, updated_year, dsr) -> dict:
        """
        Parameters received example:
        col = ["Rua Igarata", "Rua Igarata"]
        updated_year = [2021, 2023]
        dsr = [0.4, 0.5]
        """

        if not col or not any(col):
            return None

        list_dict = []
        for col_item, updated_year_item, dsr_item in zip(col, updated_year, dsr):
            aggregate_info = {
                "col": col_item,
                "updated_year": updated_year_item,
                "dsr": dsr_item,
            }
            """
            aggregate_info example result for first iteration:
            {'col': 'Rua Igarata', 'updated_year': 2021, 'dsr': 0.4}
            """
            list_dict.append(aggregate_info)

        """
        list_dict example result:
        [
            {'col': 'Rua Igarata', 'updated_year': 2021, 'dsr': 0.4},
            {'col': 'Rua Igarata', 'updated_year': 2023, 'dsr': 0.5}
        ]
        """

        agg_dict = VespucioScoreCalculator.get_greatest_dsr_and_updated_year(
            list_dict, "col", ["updated_year", "dsr"]
        )

        """
        agg_dict example result:
        {Rua Igarata={dsr=0.5, updated_year=2023, sum_dsr=0.9}}
        """
        # return agg_dict
        name_key, score = VespucioScoreCalculator.calculate_score(agg_dict)

        return json.dumps({"value": name_key, "score": score}, default=str)
