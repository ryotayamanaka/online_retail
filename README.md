# Oracle's Property Graph for Real-Time Recommendations

## Introduction

Recommendation engines have become a popular solution for online retailers and streaming content providers looking to suggest products and media to users. Also known as recommender systems, these tools filter out less relevant information in order to predict how likely a user is to purchase an item or engage with certain videos or images, and suggest those things to the user. The recommender systems benefit greatly by exploiting the relationships through the expressive power of Graphs.

Property graphs have become a useful way to model, manage, query and analyze much of the connected data found in today’s applications and information systems. They allow you to represent data based on relationships and connectivity, query data by traversing those connections, and analyze data using algorithms that evaluate the strength of the connections, patterns and anomalies in the graph, the importance of elements in the graph, and other factors.

### Objectives

The objectives of this workshop are as follows:

- Build a Property Graph on data stored in Autonomous Database to model database relationships
- Query, analyze, and visualize graphs to provide real-time product recommendations

### Prerequisites

- Oracle Cloud Account
- Graph Server (connected to Database)
  - This tutorial is tested with Graph Server **20.4** and **21.2**

In this tutorial, we load the product purchase information from Database to Graph Server, for making the recommendations using graph algorithms. Since the graph algorithms can run efficiently on Graph Server, we need a Graph Server setup (= 3-tier deployment) for this use case.

# Lab 1: Load Dataset into Database

## Introduction

An open dataset of retail transactions is available for download from [UCI](https://archive.ics.uci.edu/ml/datasets/online+retail) (and also [Kaggle](https://www.kaggle.com/jihyeseo/online-retail-data-set-from-uci-ml-repo)). This dataset contains real-world transactions of customer purchases along with product and customer data - very suitable for generating real-time product recommendations based on property graph.

According to [UCI Machine Learning Repository](https://archive.ics.uci.edu/ml/datasets/online+retail), "the Online Retail Dataset is a transnational data set which contains all the transactions occurring between 01/12/2010 and 09/12/2011 for a UK-based and registered non-store online retail. The company mainly sells unique all-occasion gifts. Many customers of the company are wholesalers."

## **STEP 1** : Login to SQL Client

You may use [Cloud Shell](https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm) or any SSH client of your choice to SSH into the lab environment. Whatever method you choose, ensure the **SSH Keys** are setup for the client. Click [here](https://docs.cloud.oracle.com/en-us/iaas/Content/GSG/Tasks/testingconnection.htm ) for configuring various SSH clients to connect to OCI Compute instance.

1. Start an SSH session using your private key **labkey**, **{VM IP Address}**, and **opc** user. The below step assumes you are using the SSH client from the terminal.

    ```
    <copy>ssh -i ~/oracle-pg/keys/labkey opc@{VM IP Address}</copy>
    ```

2. Switch current user to **oracle**. All lab steps are run as the oracle user, so ensure in all sessions that you are connected as **oracle** before running any commands.

    ```
    <copy>sudo su - oracle</copy>
    ```

## **STEP 2** : Create the Database Schema

2. Start a SQL client session and connect as the **ADMIN** user using **{ADB Admin Password}** and to **{ADB Service Name HIGH}** database service.

    ```
    <copy>sqlplus ADMIN/{ADB Admin Password}@{ADB Service Name HIGH}</copy>
    ```

3. Create the **RETAIL** database user with a suitable password. The default tablespace is `data` in ADB or `users` in DBCS.

    ```
    CREATE USER retail IDENTIFIED BY <password_retail>;
    ALTER USER retail QUOTA UNLIMITED ON <data_or_users>;
    ```

4. Grant the required privileges to the **RETAIL** user.

    - The Oracle Graph server by default uses an Oracle database as the identity manager, which means that you log into the graph server using Oracle Database credentials. The Database user needs to be granted appropriate privileges to support this authentication method, mainly the **CREATE SESSION** and  **GRAPH_DEVELOPER** or **GRAPH_ADMINISTRATOR** role.

    ```
    GRANT connect, resource, create view, graph_developer TO retail;
    ```

5. Connect as the **RETAIL** user.

    ```
    <copy>sqlplus retail/<password_retail>@<service_name></copy>
    ```

6. Create the **TRANSACTIONS** table.

    ```
    CREATE TABLE transactions (
      invoice_no VARCHAR2(255)
    , stock_code VARCHAR2(255)
    , description VARCHAR2(255)
    , quantity NUMBER(10)
    , invoice_date VARCHAR2(255)
    , unit_price NUMBER(10)
    , customer_id NUMBER(10)
    , country VARCHAR2(255)
    );
    ```

## **STEP 3** : Load the Dataset

1. In the previous SSH connection as the **oracle** user, change directory to **/home/oracle/dataset** as all files for the load are in this folder.

    ```
    cd /home/oracle/dataset
    ```

2. Download the Online Retail dataset using **wget** using a direct download URL from UCI.

    ```
    <copy>wget https://archive.ics.uci.edu/ml/machine-learning-databases/00352/Online%20Retail.xlsx -O OnlineRetail.xlsx</copy>
    ```

3. Once the download completes, convert the Excel file to CSV format using open source **libreoffice**, as the data needs to be converted to plain text for loading.

    - The file conversion takes a few minutes to complete.

    ```
    <copy>libreoffice --headless --convert-to csv OnlineRetail.xlsx</copy>
    ```

    Alternatively, open with Excel and save the file as `OnlineRetail.csv` in CSV format. (Save As > File Format: CSV UTF-8)

    ```
    $ dos2unix OnlineRetail.csv
    ```

4. Load the CSV file into **TRANSACTIONS** table using **SQL Loader** and the control file provided (control file defines the format of the input file to SQL Loader).

  Invoke SQL Loader using the following command line, replacing **{Retail Password}** and **{ADB Service Name}**.

    ```
    sqlldr userid=retail/<password_retail>@<service_name> data=OnlineRetail.csv control=sqlldr.ctl log=sqlldr.log bad=sqlldr.bad direct=true
    ```

5. Observe that over **540k** rows get loaded from the dataset.

## **STEP 4** : Populate Tables for Graph

The transactional data that was just loaded needs to be normalized into relational entities, mainly **CUSTOMERS**, **PRODUCTS**, **PURCHASES** and **PURCHASES_DISTINCT**. These tables will be used to build the property graph later.

1. Connect as the **RETAIL** user.

    ```
    sqlplus retail/<password_retail>@<service_name>
    ```

2. Populate the normalized tables.

    **CUSTOMERS** table:

    ```
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

    SET ECHO ON
    SELECT * FROM customers WHERE ROWNUM <= 5;
    ```

    **PRODUCTS** table:

    ```
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

    SET ECHO ON
    SELECT * FROM products WHERE ROWNUM <= 5;
    ```

    **PURCHASES** table:

    ```
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

    SET ECHO ON
    SELECT * FROM purchases WHERE ROWNUM <= 5;
    ```

    **PURCHASES_DISTINCT** table:

    ```
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

    SET ECHO ON
    SELECT * FROM purchases_distinct WHERE ROWNUM <= 5;
    ```

# Lab 2: Create Property Graph

## Introduction

As part of the Converged Oracle Database, a scalable property graph database along with a graph query language and developer APIs are provided. In this lab, you will create the property graph on the retail dataset to help demonstrate the power of graphs for analyzing relationships in data, in ways that relational queries possibly can’t.

## **STEP 1** : Login to Graph Server

Login to the Graph Server VM, and connect to Graph Server as the **RETAIL** user using the Python client. If you use a remote Graph Client,  

    $ opgpy --base_url https://localhost:7007 --user retail
    enter password for user moneyflows (press Enter for no password): <password_retail>
    Oracle Graph Server Shell 20.4.0
    >>>

## **STEP 2** : Create a Graph

Set the create property graph statement.

```
statement = '''
CREATE PROPERTY GRAPH "Online Retail"
VERTEX TABLES (
    online_retail.customers
    LABEL "Customer"
    PROPERTIES (
        customer_id AS "customer_id"
    , "country"
    )
, online_retail.products
    LABEL "Product"
    PROPERTIES (
        stock_code AS "stock_code"
    , "description"
    )
)
EDGE TABLES (
    online_retail.purchases_distinct
    KEY (purchase_id)
    SOURCE KEY(customer_id) REFERENCES customers
    DESTINATION KEY(stock_code) REFERENCES products
    LABEL "has_purchased"
    PROPERTIES (
        purchase_id
    )
, online_retail.purchases_distinct AS purchases_distinct_2
    KEY (purchase_id)
    SOURCE KEY(stock_code) REFERENCES products
    DESTINATION KEY(customer_id) REFERENCES customers
    LABEL "purchased_by"
    PROPERTIES (
        purchase_id
    )
)
'''
```

Run the statement. `False` is returned when the command succeeded.

```
>>> session.prepare_pgql(statement).execute()
False
```

Attach the created graph on memory.

```
>>> graph = session.get_graph("Moneyflows")
>>> graph
PgxGraph(name: Online Retail, v: 8258, e: 532452, directed: True, memory(Mb): 10)
```

Try an example PGQL query.

```
>>> graph.query_pgql(" SELECT ID(n), n.description MATCH (n:Product) LIMIT 3 ").print()
+---------------------------------------------+
| ID(n) | n.description                       |
+---------------------------------------------+
| 4339  | SET OF 3 HEART COOKIE CUTTERS       |
| 4340  | STRIPEY CHOCOLATE NESTING BOXES     |
| 4341  | incorrectly credited C550456 see 47 |
+---------------------------------------------+
```

# Lab 3: Generate Recommendation

## Introduction

Many algorithms exist to help data scientists in generating recommendations but the choice depends on the availability of data, technology platforms and business requirements.

In this lab you will generate recommendations directly on the dataset using a built-in algorithm of the Graph Server called Personalized PageRank. You will then use a visual interface called GraphViz to visualize the graphs and the recommendation results.

## Generate Recommendation

List the products purchased by a customer "cust_12353".

```
graph.query_pgql("""
  SELECT ID(c), ID(p), p.description
  FROM MATCH (c)-[has_purchased]->(p)
  WHERE ID(c) = 'cust_12353'
""").print()
```
```
+--------------------------------------------------------------+
| ID(c)      | ID(p)      | description                        |
+--------------------------------------------------------------+
| cust_12353 | prod_37446 | MINI CAKE STAND WITH HANGING CAKES |
| cust_12353 | prod_22890 | NOVELTY BISCUITS CAKE STAND 3 TIER |
| cust_12353 | prod_37449 | CERAMIC CAKE STAND + HANGING CAKES |
| cust_12353 | prod_37450 | CERAMIC CAKE BOWL + HANGING CAKES  |
+--------------------------------------------------------------+
```

Run Personalized PageRank (PPR) having the customer "cust_12353" as a focused node.

```
rs = graph.query_pgql("SELECT ID(c) FROM MATCH (c) WHERE c.customer_id = 'cust_12353'")
vertex = graph.get_vertex(rs.get_row(0))
graph.destroy_vertex_property_if_exists("ppr")
analyst.personalized_pagerank(graph, vertex, rank="ppr")
```
```
VertexProperty(name: ppr, type: double, graph: Online Retail)
```

Get the top 10 recommended products.

```
graph.query_pgql("""
  SELECT ID(p), p.description, p.ppr
  FROM MATCH (p)
  WHERE LABEL(p) = 'Product'
    AND NOT EXISTS (
      SELECT *
      FROM MATCH (p)-[:purchased_by]->(c)
      WHERE c.customer_id = 'cust_12353'
    )
  ORDER BY p.ppr DESC
  LIMIT 10
""").print()
```
```
+--------------------------------------------------------------------+
| ID(p) | description                        | ppr                   |
+--------------------------------------------------------------------+
| 7991  | REGENCY CAKESTAND 3 TIER           | 0.0013483656895780102 |
| 6394  | WHITE HANGING HEART T-LIGHT HOLDER | 0.001300076481737166  |
| 5722  | STRAWBERRY CERAMIC TRINKET POT     | 0.0010642787031750636 |
| 5442  | SET OF 3 CAKE TINS PANTRY DESIGN   | 9.987259826891447E-4  |
| 4940  | PARTY BUNTING                      | 8.800446053134877E-4  |
| 7118  | SWEETHEART CERAMIC TRINKET BOX     | 8.793185974570989E-4  |
| 7518  | PACK OF 72 RETROSPOT CAKE CASES    | 7.74948580210001E-4   |
| 5299  | 60 TEATIME FAIRY CAKE CASES        | 7.561654694509065E-4  |
| 5100  | JUMBO BAG RED RETROSPOT            | 7.258904143858246E-4  |
| 6538  | ASSORTED COLOUR BIRD ORNAMENT      | 7.223349157689754E-4  |
+--------------------------------------------------------------------+
```

## Visualization

Open Graph Visualization (https://localhost:7007/ui) with username: retail, password: <password_retail>.

![](https://user-images.githubusercontent.com/4862919/91992834-9084da80-ed6f-11ea-89ee-6d6134c2bb3d.jpg)

Select "Online Retail" graph, and run the query below to see the paths between the customer "cust_12353" and the top recommended product above.

    SELECT *
    MATCH (c1)-[e1]->(p1)<-[e2]-(c2)-[e3]->(p2)
    WHERE ID(c1) = 'cust_12353'
      AND ID(p2) = 'prod_23166'
      AND ID(c1) != ID(c2)
      AND ID(p1) != ID(p2)

Import [`highlights.json`](https://github.com/ryotayamanaka/oracle-pg/blob/20.3/graphs/online_retail/highlights.json) for adding icons and changing the size of nodes according to the pagerank.

![](https://user-images.githubusercontent.com/4862919/91992798-86fb7280-ed6f-11ea-9586-8b600c94a8ed.jpg)

Exit from the shell to close the session.

    opg-jshell> /exit

## Notebook

Open Zeppelin (http://localhost:8080) and import [`zeppelin.json`](https://github.com/ryotayamanaka/oracle-pg/blob/20.3/graphs/online_retail/zeppelin.json) to load the "Online Retail" note.

You will connect to Graph Server in the first step, and load the graph next. You can access the same graph from Graph Visuzlization using the session ID returned at the first step.

---

## Appendix 1

There are two loading configuration files in the directory, [`config-tables.json`](https://github.com/ryotayamanaka/oracle-pg/blob/master/graphs/retail/config-tables.json) and [`config-tables-distinct.json`](https://github.com/ryotayamanaka/oracle-pg/blob/master/graphs/retail/config-tables-distinct.json). The former counts all duplicated purchases (when customers has purchased the same products multiple times), while such duplicated edges are merged in the latter. We use the distinct version for making recommendations here.

## Appendix 2

For pre-loading the graph into Graph Server, add these two entries to conf/pgx.conf.

    {
      "authorization": [
        "pgx_permissions": [
        , { "preloaded_graph": "Online Retail", "grant": "READ"}            <--

      "preload_graphs": [
      , {"path": "/graphs/online_retail/config-tables-distinct.json", "name": "Online Retail"}   <--

Restart Graph Server.

    $ cd oracle-pg/
    $ docker-compose restart graph-server
