# SokoMart Kenya: Advanced SQL Project

**Name:** Boaz Wangai
**Cohort:** LuxDevHQ Data Engineering / Data Analytics, Cohort 9
**Date:** 17th Nov 2026

This repository holds my answers to the SokoMart Kenya Advanced SQL project: one SQL file per section, a screenshot of every result, and the business insights I drew from those results.

---

# SokoMart Database: How to Run the SQL

The setup happens in three stages: first you create the schema and point your session at it, then you create the tables, and finally you load the data. Once the data is in place, you can run the analysis scripts.

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

## Step 2: Set the search path

Before creating any tables, point your session at the new schema:

```sql
SET search_path TO sokomart;

SHOW search_path;
```

`SHOW search_path` should return `sokomart`. From now on, any table you create or query without a schema name is placed in, or looked up in, `sokomart` instead of the default `public` schema. This keeps all the SokoMart tables together, and it lets the analysis scripts refer to the tables by their short names (`customers`, `orders` and so on).

The setting only lasts for the current session. If you open a new editor or reconnect, run it again. Every analysis script already starts with these two lines, so running a file from the top takes care of it. If you forget it, PostgreSQL will report that the relation (for example `customers`) does not exist, or the tables will end up in `public`.

## Step 3: Create the tables

Open each script from the `TableCreation` folder in the editor and run it, following the order explained here.

Start with the four tables that do not depend on any other table: `customers`, `products`, `payment_staging` and `audit_logs`. These can be created in any order among themselves because none of them contains a foreign key.

Next, create `orders`. Every order points to a customer through `customer_id`, so this script only works once `customers` already exists.

Finally, create the four tables that depend on orders or products. `order_items` needs both `orders` and `products`, because each item belongs to an order and refers to a product. `order_status_history` and `payments` each need `orders`. `product_price_history` needs `products`.

If you run these out of order, creation will fail with a message saying the referenced table does not exist. If that happens, create the missing parent table first and then run the failed script again.

## Step 4: Load the data

Open each script from the `Data` folder and run it, following the same logic: parent tables first, child tables after.

Begin with `customers` and `products`. Then load `orders`, because each order needs its customer to already exist. After that, load `order_items`, which needs both `orders` and `products`, and then `payments`, which needs `orders`. Load `payment_staging` last.


## Step 5: Check that everything loaded

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

## Step 6: Run the analysis scripts

With the database set up, open and run the scripts in the main project folder in this order:

1. `practice_drills.sql` (the unmarked warm-up drills)
2. `section_a_ctes_subqueries.sql` (Q1–Q5)
3. `section_b_window_functions.sql` (Q6–Q10)
4. `section_c_advanced_aggregation.sql` (Q11–Q15)
5. `section_d_views_functions_procedures.sql` (Q16–Q20)
6. `section_e_optimisation_transactions.sql` (Q21–Q25)

Sections A to C only read from the tables, so they can be run as many times as you like. Sections D and E are different: they create views, functions, procedures and a trigger, place a new order, change a price, change stock and delete duplicate rows from `payment_staging`. Run them once, top to bottom, on a fresh load. If you need to run them again, or before taking final screenshots of Sections A to C, reset the database with `07_reset_database.sql` and reload it by repeating Steps 1 to 5.

A few statements in Sections D and E are meant to fail, because the question asks to show the error message. These are:

- `fn_customer_spend(4000, '2026-02-01', '2026-01-01')` in Q17 (end date before start date)
- the KES 500.00 price change in Q18 (below cost price)
- `sp_update_order_status(49961, 'completed')` in Q19 (a cancelled order)
- `sp_place_order(408, ARRAY[6,59], ...)` in Q20 (product 59 has too little stock)
- the duplicate insert into `payment_staging` in Q24 (blocked by the new unique index)

In DBeaver or pgAdmin, run these one at a time, or the editor will stop at the first error.

---

## Results

The row counts below are the ones written in the header of each question in the SQL files. Every screenshot is in the `Screenshots` folder.

| Q | File | Rows | Screenshot |
|---|---|---|---|
| 1 | `section_a_ctes_subqueries.sql` | 1432 | [q01](Screenshots/q01_big_spenders.png) |
| 2 | `section_a_ctes_subqueries.sql` | 104 | [q02](Screenshots/q02_premium_products.png) |
| 3 | `section_a_ctes_subqueries.sql` | 10 | [q03](Screenshots/q03_monthly_pl_2026.png) |
| 4 | `section_a_ctes_subqueries.sql` | 346 | [q04](Screenshots/q04_nakuru_cross_category.png) |
| 5 | `section_a_ctes_subqueries.sql` | 24 | [q05](Screenshots/q05_unordered_products.png) |
| 6 | `section_b_window_functions.sql` | 42 | [q06](Screenshots/q06_county_leaderboards.png) |
| 7 | `section_b_window_functions.sql` | 15 | [q07](Screenshots/q07_best_sellers_2025.png) |
| 8 | `section_b_window_functions.sql` | 22 | [q08](Screenshots/q08_mom_growth.png) |
| 9 | `section_b_window_functions.sql` | 1332 | [q09](Screenshots/q09_nyeri_order_trends.png) |
| 10 | `section_b_window_functions.sql` | 22 | [q10](Screenshots/q10_ytd_revenue.png) |
| 11 | `section_c_advanced_aggregation.sql` | 4 | [q11](Screenshots/q11_customer_tiers.png) |
| 12 | `section_c_advanced_aggregation.sql` | 152 | [q12](Screenshots/q12_mombasa_october.png) |
| 13 | `section_c_advanced_aggregation.sql` | 4 | [q13](Screenshots/q13_payment_health.png) |
| 14 | `section_c_advanced_aggregation.sql` | 2 | [q14](Screenshots/q14_profit_departments.png) |
| 15 | `section_c_advanced_aggregation.sql` | 36 | [q15](Screenshots/q15_sales_subtotals.png) |
| 16 | `section_d_views_functions_procedures.sql` | 10 (Kiambu) / 1 (view count) / 5 (December 2025) | [q16](Screenshots/q16_views.png) |
| 17 | `section_d_views_functions_procedures.sql` | multiple outputs | [q17](Screenshots/q17_function_spend.png) |
| 18 | `section_d_views_functions_procedures.sql` | 1 (before) / 1 (after) | [q18](Screenshots/q18_price_change.png) |
| 19 | `section_d_views_functions_procedures.sql` | multiple outputs | [q19](Screenshots/q19_trigger_audit.png) |
| 20 | `section_d_views_functions_procedures.sql` | multiple outputs | [q20](Screenshots/q20_atomic_order.png) |
| 21 | `section_e_optimisation_transactions.sql` | 91 | [q21](Screenshots/q21_query_plan.png) |
| 22 | `section_e_optimisation_transactions.sql` | multiple plans | [q22](Screenshots/q22_indexes.png), [index size](Screenshots/q22_index_size.png) |
| 23 | `section_e_optimisation_transactions.sql` | multiple outputs | [q23](Screenshots/q23_transactions.png) |
| 24 | `section_e_optimisation_transactions.sql` | multiple outputs | [q24](Screenshots/q24_dedup_payments.png) |
| 25 | `section_e_optimisation_transactions.sql` | 10 | [q25](Screenshots/q25_three_months.png) |

---

## Business insights and recommendations

- **November and December are SokoMart's biggest months.** December 2025 revenue was KES 71.6M, 9.54% above November (KES 65.4M). November itself jumped 68.01% on October, and January 2026 then fell 22.16% (Q8). I recommend stocking up and planning promotions from mid-October, so the shop is ready before the November surge.

- **Fashion earns far less than Electronics but carries a big share of the profit.** In 2025 only Electronics and Fashion beat the average category gross profit of KES 18.5M. Fashion's revenue was KES 54.9M against KES 322.9M for Electronics, yet it made KES 24.5M in gross profit against KES 43.3M, because its margin is 44.57% compared with 13.42% (Q14). I recommend giving Fashion more homepage space and bundling it with Electronics purchases.

- **Margins are thin and steady.** Across January to October 2026 the monthly margin stayed between 18.04% and 19.89%, with August the best month for gross profit at KES 10.9M (Q3). Growth will have to come from selling more of the high-margin categories rather than from pricing alone.

- **M-Pesa failures cost the most money.** In 2026, 1,373 of 14,726 M-Pesa payments failed, worth KES 30.2M (Q13). M-Pesa's success rate (89.33%) is close to the other methods (89.09% to 90.08%), so the problem is volume, not a broken channel. Because most customers pay by M-Pesa, even a small improvement there recovers the most money.

- **Silver customers carry the business.** The 2,356 Silver customers bring in 54.65% of all completed revenue, while the 109 Platinum customers bring in 17.64% (Q11). I recommend a loyalty offer aimed at moving Silver customers into Gold, since that tier is where most of the spending already sits.

- **Nairobi dominates the five main counties.** Of the KES 316.3M earned in 2026 across Nairobi, Mombasa, Kisumu, Nakuru and Uasin Gishu, Nairobi alone brought in KES 181.4M, about 57% (Q15). Electronics is the largest category in every one of those counties. Mombasa (KES 48.4M) is the clear second market and the best place to grow next.

- **The settlement files were double-counting payments.** `payment_staging` held 240 extra rows for 200 payments, with up to 3 copies of the same payment (Q24). After removing them, the staged amount matched `payments` exactly. The unique index on `payment_id` now stops this from happening again.

**The one change I would make first:** recover failed M-Pesa payments. The KES 30.2M lost to M-Pesa failures in 2026 (Q13) is about 6.7% of the KES 451.9M in completed revenue for January to October 2026 (Q10). An automatic retry, or a second STK push sent a few minutes after a failure, needs no new stock, no new customers and no change in price, and M-Pesa is the method most of our customers already use. It is the quickest money SokoMart can win back.

---

## Challenges faced

Most of the hard parts were not the questions themselves but getting the tools and the database to behave.

The first problem was switching between `psql` and DBeaver. Some of my scripts used `psql` commands such as `\set` and `\echo`, which DBeaver does not understand, so it stopped with syntax errors until I took them out. The scripts provided were for `psql` and currently I am just conversant with DBeaver.

Once a statement fails inside a transaction, PostgreSQL refuses everything after it with `ERROR 25P02` (current transaction is aborted) until you run `ROLLBACK`. I learned to roll back and start again, and to run multi-step changes, such as the duplicate delete in Q24, as one block from `BEGIN` to `COMMIT`.

The table rules were strict too. My first restock entry in `audit_logs` broke a `CHECK` constraint, so I had to change the values I was inserting. In Q24, I had to run the test insert on its own to show the unique index blocking it.
