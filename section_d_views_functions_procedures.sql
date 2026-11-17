

set search_path to sokomart;

show search_path;

-- =============================================================
-- q16. views and materialized views
-- result: (screenshot: screenshots/q16_views.png)
-- =============================================================
-- (a) customer summary view
create or replace view v_customer_purchase_summary as
with order_stats as (
    select 
        customer_id,
        count(order_id) as completed_orders,
        sum(total_amount) as lifetime_spent,
        avg(total_amount) as avg_order_value,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date
    from orders
    where order_status = 'completed'
    group by customer_id
)
select 
    c.customer_id,
    c.first_name || ' ' || c.last_name as full_name,
    c.county,
    c.registration_date,
    coalesce(o.completed_orders, 0) as completed_orders,
    coalesce(o.lifetime_spent, 0) as lifetime_spent,
    coalesce(o.avg_order_value, 0) as avg_order_value,
    o.first_order_date,
    o.last_order_date,
    case 
        when o.last_order_date is not null 
        then extract(day from ('2026-10-31'::timestamp - o.last_order_date))
        else null 
    end as days_since_last_order
from customers c
left join order_stats o on c.customer_id = o.customer_id;

-- queries against view
-- 10 rows
select * from v_customer_purchase_summary 
where county = 'Kiambu' 
order by lifetime_spent desc 
limit 10;

-- 1 row
select 
    count(*) as total_view_rows,
    count(*) filter (where completed_orders = 0) as zero_order_customers
from v_customer_purchase_summary;

-- (b) materialized view
-- 5 rows
create materialized view mv_monthly_category_sales as
select 
    date_trunc('month', o.order_date) as sales_month,
    p.category,
    count(distinct o.order_id) as orders,
    sum(i.quantity) as units_sold,
    sum(i.line_total) as revenue,
    sum(i.line_total - (i.quantity * p.cost_price)) as gross_profit
from orders o
join order_items i on o.order_id = i.order_id
join products p on i.product_id = p.product_id
where o.order_status = 'completed'
group by date_trunc('month', o.order_date), p.category;

create unique index idx_mv_monthly_category_sales on mv_monthly_category_sales(sales_month, category);

-- 5 rows
select * from mv_monthly_category_sales 
where sales_month = '2025-12-01' 
order by revenue desc;

-- =============================================================
-- q17. function: customer spend for a date range
-- result: multiple outputs (screenshot: screenshots/q17_function_spend.png)
-- =============================================================
create or replace function fn_customer_spend(p_customer_id integer, p_start_date date, p_end_date date) 
returns numeric 
language plpgsql as $$
declare
    v_total_spent numeric;
begin
    if p_end_date < p_start_date then
        raise exception 'end date cannot be before start date';
    end if;

    select coalesce(sum(i.line_total), 0) into v_total_spent
    from orders o
    join order_items i on o.order_id = i.order_id
    where o.customer_id = p_customer_id
      and o.order_status = 'completed'
      and o.order_date >= p_start_date 
      and o.order_date < (p_end_date + interval '1 day');
      
    return v_total_spent;
end;
$$;

-- 1. tests
-- 1 row

select fn_customer_spend(4000, '2025-01-01', '2025-12-31');
select fn_customer_spend(4000, '2026-01-01', '2026-10-31');
select fn_customer_spend(4000, '2025-01-01', '2026-10-31');
select fn_customer_spend(4000, '2025-12-01', '2025-12-31');
select fn_customer_spend(-1, '2025-01-01', '2025-12-31');

-- 2. comparison against view
-- 1 row

select 
    customer_id, 
    lifetime_spent, 
    fn_customer_spend(customer_id, '1900-01-01', '2100-01-01') as fn_value,
    (lifetime_spent = fn_customer_spend(customer_id, '1900-01-01', '2100-01-01')) as matches
from v_customer_purchase_summary
where customer_id = 4000;

-- 3. query usage
-- 5 rows

select 
    c.customer_id,
    c.first_name || ' ' || c.last_name as full_name,
    fn_customer_spend(c.customer_id, '2025-12-01', '2025-12-31') as december_2025_spend
from customers c
where c.county = 'Nairobi'
order by december_2025_spend desc
limit 5;

-- 4. exception
select fn_customer_spend(4000, '2026-02-01', '2026-01-01');

-- =============================================================
-- q18. procedure: change a price and keep its history
-- result: (screenshot: screenshots/q18_price_change.png)
-- =============================================================
create or replace procedure sp_update_product_price(p_product_id integer, p_new_price numeric, p_reason varchar)
language plpgsql as $$
declare
    v_old_price numeric;
    v_cost_price numeric;
begin
    select unit_price, cost_price into v_old_price, v_cost_price
    from products 
    where product_id = p_product_id 
    for update;

    if not found then
        raise exception 'product % does not exist', p_product_id;
    end if;

    if p_new_price <= 0 then
        raise exception 'price must be greater than zero';
    end if;

    if p_new_price < v_cost_price then
        raise exception 'new price cannot be below cost price';
    end if;

    update products
    set unit_price = p_new_price
    where product_id = p_product_id;

    insert into product_price_history (product_id, old_price, new_price, change_reason)
    values (p_product_id, v_old_price, p_new_price, p_reason);

    insert into audit_logs (table_name, record_id, action, old_data, new_data)
    values (
        'products', 
        p_product_id, 
        'UPDATE', 
        jsonb_build_object('unit_price', v_old_price), 
        jsonb_build_object('unit_price', p_new_price)
    );
end;
$$;

-- 1. show before values
-- 1 row


select product_id, product_name, unit_price, cost_price 
from products 
where product_id = 71;

-- call procedure
call sp_update_product_price(71, 1099.00, 'Supplier price increase - Nov 2026');

-- show after values
select product_id, product_name, unit_price, cost_price 
from products 
where product_id = 71;

-- show price history row (using price_history_id to get the latest instead of a date column)
select price_history_id, product_id, old_price, new_price, change_reason 
from product_price_history 
where product_id = 71 
order by price_history_id desc 
limit 1;

-- show audit log row
select table_name, record_id, action, old_data, new_data 
from audit_logs 
where table_name = 'products' and record_id = 71;

-- 2. rejection
call sp_update_product_price(71, 500.00, 'Below cost test');

-- =============================================================
-- q19. trigger + procedure: order status changes
-- result: multiple outputs (screenshot: screenshots/q19_trigger_audit.png)
-- =============================================================
-- (a) trigger

create or replace function fn_trg_orders_status_audit()
returns trigger 
language plpgsql as $$
begin
    if tg_op = 'INSERT' then
        insert into order_status_history (order_id, old_status, new_status)
        values (new.order_id, null, new.order_status);
        
        insert into audit_logs (table_name, record_id, action, old_data, new_data)
        values ('orders', new.order_id, 'INSERT', null, jsonb_build_object('order_status', new.order_status));
        
    elsif tg_op = 'UPDATE' and new.order_status is distinct from old.order_status then
        insert into order_status_history (order_id, old_status, new_status)
        values (new.order_id, old.order_status, new.order_status);
        
        insert into audit_logs (table_name, record_id, action, old_data, new_data)
        values (
            'orders', 
            new.order_id, 
            'UPDATE', 
            jsonb_build_object('order_status', old.order_status), 
            jsonb_build_object('order_status', new.order_status)
        );
    end if;
    return new;
end;
$$;

create trigger trg_orders_status_audit
after insert or update of order_status on orders
for each row execute function fn_trg_orders_status_audit();

-- (b) procedure
create or replace procedure sp_update_order_status(p_order_id integer, p_new_status varchar)
language plpgsql as $$
declare
    v_old_status varchar;
begin
    select order_status into v_old_status from orders where order_id = p_order_id for update;
    
    if (v_old_status = 'pending' and p_new_status in ('completed', 'cancelled')) or 
       (v_old_status = 'completed' and p_new_status = 'returned') then
        
        update orders set order_status = p_new_status where order_id = p_order_id;
        
        if p_new_status = 'completed' then
            update payments set payment_status = 'successful' where order_id = p_order_id;
        elsif p_new_status = 'cancelled' then
            update payments set payment_status = 'failed' where order_id = p_order_id and payment_status = 'pending';
        end if;
    else
        raise exception 'invalid status transition from % to %', v_old_status, p_new_status;
    end if;
end;
$$;

-- (c) tests
-- 1. show before values
-- 1 row

select o.order_id, o.order_status, p.payment_status 
from orders o 
join payments p on o.order_id = p.order_id 
where o.order_id = 48882;

-- 2. call procedure to change status to completed
-- error
call sp_update_order_status(48882, 'completed');

-- 3. show after values
-- 1 row
select o.order_id, o.order_status, p.payment_status 
from orders o 
join payments p on o.order_id = p.order_id 
where o.order_id = 48882;

-- 4. check history and audit logs
--2 rows each
select * from order_status_history where order_id = 48882;
select * from audit_logs where table_name = 'orders' and record_id = 48882;

-- 5. test second valid transition
-- 2 rows
update orders set order_status = 'returned' where order_id = 48882;
select * from order_status_history where order_id = 48882;

-- 6. test update with same status (should not trigger history insert)
-- 1 row
update orders set shipping_county = shipping_county where order_id = 48882;
select count(*) as history_records_count from order_status_history where order_id = 48882;

-- 7. test invalid transition (will raise exception)
call sp_update_order_status(49961, 'completed');

-- =============================================================
-- q20. procedure: place an order atomically
-- result: multiple outputs (screenshot: screenshots/q20_atomic_order.png)
-- =============================================================
create or replace procedure sp_place_order(
    p_customer_id integer, 
    p_product_ids integer[], 
    p_quantities integer[], 
    p_payment_method varchar, 
    inout p_order_id integer default null
)
language plpgsql as $$
declare
    v_customer_county varchar;
    v_i integer;
    v_items_total numeric := 0;
    v_delivery_fee numeric := 0;
    v_product_price numeric;
begin
    select county into v_customer_county from customers 
    where customer_id = p_customer_id and customer_status = 'active';
    
    if not found then
        raise exception 'customer does not exist or is not active';
    end if;
    
    if array_length(p_product_ids, 1) != array_length(p_quantities, 1) then
        raise exception 'arrays must be the same length';
    end if;

    insert into orders (customer_id, order_status, order_date, shipping_county, delivery_fee, total_amount)
    values (p_customer_id, 'pending', current_timestamp, v_customer_county, 0, 0)
    returning order_id into p_order_id;

    for v_i in 1 .. array_length(p_product_ids, 1) loop
        update products 
        set stock_quantity = stock_quantity - p_quantities[v_i]
        where product_id = p_product_ids[v_i] and stock_quantity >= p_quantities[v_i] and product_status = 'active'
        returning unit_price into v_product_price;
        
        if not found then
            raise exception 'product % unavailable or insufficient stock for requested quantity %', p_product_ids[v_i], p_quantities[v_i];
        end if;
        
        insert into order_items (order_id, product_id, quantity, unit_price, line_total)
        values (p_order_id, p_product_ids[v_i], p_quantities[v_i], v_product_price, p_quantities[v_i] * v_product_price);
        
        v_items_total := v_items_total + (p_quantities[v_i] * v_product_price);
    end loop;

    if v_items_total >= 5000 then
        v_delivery_fee := 0;
    elsif v_customer_county = 'Nairobi' then
        v_delivery_fee := 200;
    elsif v_customer_county in ('Kiambu', 'Kajiado', 'Machakos') then
        v_delivery_fee := 250;
    else
        v_delivery_fee := 350;
    end if;

    update orders 
    set delivery_fee = v_delivery_fee, total_amount = v_items_total + v_delivery_fee
    where order_id = p_order_id;

    insert into payments (order_id, payment_method, amount, payment_status, transaction_reference)
    values (p_order_id, p_payment_method, v_items_total + v_delivery_fee, 'pending', case when p_payment_method != 'cash on delivery' then 'TXN-' || p_order_id else null end);
end;
$$;

-- Sync the orders table counter
select setval(pg_get_serial_sequence('orders', 'order_id'), (select max(order_id) from orders));

-- Sync the payments table counter
select setval(pg_get_serial_sequence('payments', 'payment_id'), (select max(payment_id) from payments));

-- Sync the order_items table counter (if it has an auto-incrementing ID)
select setval(pg_get_serial_sequence('order_items', 'order_item_id'), (select max(order_item_id) from order_items));

select customer_id, customer_status 
from customers 
where lower(customer_status) = 'active' 
limit 1;

-- 1. tests
select product_id, unit_price, stock_quantity from products where product_id in (6, 73, 82);
call sp_place_order(7, array[6,73,82], array[1,2,3], 'M-Pesa', null);
select max(order_id) from orders;
select * from orders where order_id = 50001;
select * from order_items where order_id = 50001;
select * from payments where order_id = 50001;
select product_id, stock_quantity from products where product_id in (6, 73, 82);
select * from order_status_history where order_id = 50001;

-- 2. failure test

-- 1 row
select count(*) from orders;

-- 2 rows
select product_id, stock_quantity from products where product_id in (6, 59);

-- error
call sp_place_order(408, array[6,59], array[1,2], 'card', null);

-- 1 row
select count(*) from orders;

-- 2 rows
select product_id, stock_quantity from products where product_id in (6, 59);

-- 3. view refresh
call sp_update_order_status(50001, 'completed');

refresh materialized view concurrently mv_monthly_category_sales;

-- 2 rows
select * from mv_monthly_category_sales where sales_month = '2026-11-01';

-- 1 row
select max(order_id) from orders;
