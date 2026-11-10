# SokoMart Database: How to Run the SQL

The setup happens in three stages: first you create the schema, then the tables, and finally you load the data. Once the data is in place, you can run the analysis scripts.

The order of the steps matters. The tables are connected through foreign keys, which means some tables refer to rows in other tables. For example, every order belongs to a customer, so the customers table must exist and contain data before any orders can be added. If a table is created or filled before the table it depends on, PostgreSQL will reject it with an error.

## Before you start

Start PostgreSQL and connect to the database you intend to work in. Open DBeaver or pgAdmin, connect to that database, and open a new SQL editor. All the scripts in this project are run from this editor.

The table creation scripts are in the `TableCreation` folder, and the data scripts are in the `Data` folder.

## Step 1: Create the schema

All the tables in this project live inside a schema called `sokomart`.

To create the schema, run:

```sql
CREATE SCHEMA IF NOT EXISTS sokomart;
```

After running it, refresh the database in the navigator panel and you should see `sokomart` listed under Schemas.

## Step 2: Create the tables

Open each script from the `TableCreation` folder in the editor and run it, following the order explained here.

Start with the four tables that do not depend on any other table: `customers`, `products`, `payment_staging` and `audit_logs`. These can be created in any order among themselves because none of them contains a foreign key.

Next, create `orders`. Every order points to a customer through `customer_id`, so this script only works once `customers` already exists.

Finally, create the four tables that depend on orders or products. `order_items` needs both `orders` and `products`, because each item belongs to an order and refers to a product. `order_status_history` and `payments` each need `orders`. `product_price_history` needs `products`.

If you run these out of order, creation will fail with a message saying the referenced table does not exist. If that happens, create the missing parent table first and then run the failed script again.

## Step 3: Load the data

Open each script from the `Data` folder and run it, following the same logic: parent tables first, child tables after.

Begin with `customers` and `products`. Then load `orders`, because each order needs its customer to already exist. After that, load `order_items`, which needs both `orders` and `products`, and then `payments`, which needs `orders`. Load `payment_staging` last.


## Step 4: Check that everything loaded

Once all the data scripts have run, you can confirm the load by counting the rows in each table:

```sql
SELECT 'customers' AS table_name, COUNT(*) FROM sokomart.customers
UNION ALL SELECT 'products',        COUNT(*) FROM sokomart.products
UNION ALL SELECT 'orders',          COUNT(*) FROM sokomart.orders
UNION ALL SELECT 'order_items',     COUNT(*) FROM sokomart.order_items
UNION ALL SELECT 'payments',        COUNT(*) FROM sokomart.payments
UNION ALL SELECT 'payment_staging', COUNT(*) FROM sokomart.payment_staging;
```

You should see 5,000 customers, 300 products, 50,000 orders, 120,000 order items, 50,000 payments and 2,640 payment staging rows. If any number is different, a script was skipped, failed partway through, or was run more than once.

## Step 5: Run the analysis scripts

With the database set up, open and run the scripts in the main project folder. Start with `section_a_ctes_subqueries.sql`, then `section_b_window_functions.sql`, and finish with `practice_drills.sql`. These scripts only read from the tables, so they can be run as many times as you like.