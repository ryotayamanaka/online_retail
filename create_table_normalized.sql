SET ECHO ON
SET LINESIZE 200
COL stock_code FOR a20
COL country FOR a20
COL description FOR a40

CREATE TABLE customers (
  customer_id
, "country"
, CONSTRAINT customers_pk PRIMARY KEY (customer_id)
) AS
SELECT DISTINCT
  'cust_' || customer_id
, MAX(country)
FROM transactions
WHERE customer_id IS NOT NULL
  AND quantity > 0
GROUP BY customer_id
;

SELECT * FROM customers WHERE ROWNUM <= 5;

CREATE TABLE products (
  stock_code
, "description"
, CONSTRAINT product_pk PRIMARY KEY (stock_code)
) AS
SELECT DISTINCT
  'prod_' || stock_code
, MAX(description)
FROM transactions
WHERE stock_code IS NOT NULL
  AND stock_code < 'A'
  AND quantity > 0
GROUP BY stock_code
;

SELECT * FROM products WHERE ROWNUM <= 5;

CREATE TABLE purchases (
  purchase_id
, stock_code
, customer_id
, "quantity"
, "unit_price"
) AS
SELECT
  ROWNUM AS purchase_id
, 'prod_' || stock_code
, 'cust_' || customer_id
, quantity
, unit_price
FROM transactions
WHERE stock_code IS NOT NULL
  AND stock_code < 'A'
  AND customer_id IS NOT NULL
  AND quantity > 0
;

SELECT * FROM purchases WHERE ROWNUM <= 5;

CREATE TABLE purchases_distinct (
  purchase_id
, stock_code
, customer_id
) AS
SELECT
  ROWNUM AS purchase_id
, stock_code
, customer_id
FROM (
  SELECT DISTINCT
    'prod_' || stock_code AS stock_code
  , 'cust_' || customer_id AS customer_id
  FROM transactions
  WHERE stock_code IS NOT NULL
    AND stock_code < 'A'
    AND customer_id IS NOT NULL
    AND quantity > 0
);

SELECT * FROM purchases_distinct WHERE ROWNUM <= 5;

EXIT
