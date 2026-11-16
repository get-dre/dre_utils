select * from ({{ dre_utils.unpivot('sales', exclude=['id', 'REGION', 'month']) }}) u order by id, name
