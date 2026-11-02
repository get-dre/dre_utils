{% macro seed_data_tests() -%}
create temp table accounts as
select * from (values
  (1, 'north', 10.0),
  (2, 'south', 20.0),
  (3, 'merged', 20.0),
  (4, 'east', -5.0)
) t(account_id, region, amount);

-- The summary the totals checks reconcile against.
create temp table sales_totals as
select * from (values
  ('north', 10.0),
  ('south', 40.0)
) t(region, total);
{%- endmacro %}
