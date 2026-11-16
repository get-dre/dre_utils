select id, region, {{ dre_utils.pct_of_total('amount', partition_by='region') }} as share from sales order by id
