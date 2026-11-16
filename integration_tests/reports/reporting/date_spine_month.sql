select * from ({{ dre_utils.date_spine("'2025-11-15'", "'2026-03-01'", 'month') }}) s order by date_month
