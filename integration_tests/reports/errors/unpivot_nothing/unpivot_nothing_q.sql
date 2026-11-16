select * from ({{ dre_utils.unpivot('orders', exclude=['id','region','month','amount','note','_etl_ts']) }}) u
