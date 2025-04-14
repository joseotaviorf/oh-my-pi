import datetime
import businesstimedelta
import holidays as pyholidays
import json


class FintechUDFs:
    @staticmethod
    def fintechops_work_min_sla(
        ts_started: datetime.datetime, ts_finished: datetime.datetime
    ) -> float:
        workday = businesstimedelta.WorkDayRule(
            start_time=datetime.time(7),
            end_time=datetime.time(21),
            working_days=[0, 1, 2, 3, 4],
        )
        workday_sat = businesstimedelta.WorkDayRule(
            start_time=datetime.time(8), end_time=datetime.time(20), working_days=[5]
        )

        my_holidays = pyholidays.country_holidays("BR", subdiv="SP")
        holidays = businesstimedelta.HolidayRule(my_holidays)

        business_hours = businesstimedelta.Rules([workday, workday_sat, holidays])

        working_hours_delta = business_hours.difference(ts_started, ts_finished)
        working_hours_delta_to_seconds = working_hours_delta.hours * 3600.0

        ts_working_hours = (
            working_hours_delta.seconds + working_hours_delta_to_seconds
        ) / 60.0
        return ts_working_hours

    @staticmethod
    def fintech_collections_renegotiation(
        invoice: str, invoice_map_str: str, due_date_map_str: str, mode: str
    ) -> str:
        """
        Returns the anchor invoice for a given invoice within a renegotiation structure,
        based on its immediate parents and their due dates.

        Parameters
        ----------
        invoice : str
            The current invoice ID being evaluated.

        invoice_map_str : str
            A JSON string representing a mapping of child invoices to their parent invoices.
            Format example: {"17593126149859":[17592726483979,17592743820253]}

        due_date_map_str : str
            A JSON string representing the due dates of invoices.
            Format example: {"17592726483979":"2021-07-19","17592743820253":"2021-08-19"}

        mode : str
            Defines how to select the anchor invoice:
            - 'oldest' → selects the parent with the earliest due date
            - 'latest' → selects the parent with the latest due date

        Returns
        -------
        str
            A JSON string containing:
            - invoice : str → selected anchor invoice ID
            - level : int → renegotiation depth (1 if parent exists, 0 otherwise)
            - due_date : str or None → due date of the anchor invoice
            Example:
            {"invoice": "17592726483979", "level": 1, "due_date": "2021-07-19"}
        """
        try:
            invoice_map = json.loads(invoice_map_str or "{}")
            due_date_map = json.loads(due_date_map_str or "{}")
        except Exception:
            return json.dumps({"invoice": invoice, "level": 0, "due_date": None})

        visited = set()
        anchors = []
        stack = [(str(invoice), 0)]

        while stack:
            current, level = stack.pop()
            if current in visited:
                continue
            visited.add(current)

            parents = invoice_map.get(current)
            if not parents:
                anchors.append((current, level))
            else:
                if isinstance(parents, str):
                    parents = [parents]
                for p in parents:
                    stack.append((str(p), level + 1))

        anchors_with_due = [
            (inv, lvl, due_date_map.get(inv))
            for inv, lvl in anchors
            if due_date_map.get(inv) is not None
        ]

        if anchors_with_due:
            anchors_with_due.sort(key=lambda x: x[2])
            selected = anchors_with_due[0] if mode == "oldest" else anchors_with_due[-1]
        else:
            selected = anchors[0]

        return json.dumps(
            {
                "invoice": selected[0],
                "level": selected[1],
                "due_date": due_date_map.get(selected[0]),
            }
        )
