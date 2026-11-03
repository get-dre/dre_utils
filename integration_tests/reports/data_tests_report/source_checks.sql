-- Creates the relations the source checks read in this query's session: the detail against the
-- `sales_totals` summary, and a view over no rows, for `not_empty` to find empty.
create temp table regions_copy as select region, account_id from accounts;
create temp table amounts_copy as select amount from accounts;
create temp table account_totals as select account_id, amount from accounts;
