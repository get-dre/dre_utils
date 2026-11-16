select * from ({{ dre_utils.date_spine("'2026-02-27'", "'2026-03-03'") }}) s order by date_day
