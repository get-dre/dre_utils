select id, {{ dre_utils.safe_divide('amount', 'units') }} as per_unit from sales order by id
