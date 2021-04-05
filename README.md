# Online Retail

In this tutorial, we load the product purchase information from Database to Graph Server, and make recommendations using graph algorithms. Since the graph algorithms can run efficiently on Graph Server, we need a Graph Server (= 3-tier deployment) for this use case.

Please setup containers following the instruction [here](https://github.com/ryotayamanaka/oracle-pg/blob/master/README.md).

## Download Dataset

Download dataset `Online Retail.xlsx` from:

* Original site: http://archive.ics.uci.edu/ml/datasets/online+retail#
* Alternate site: https://www.kaggle.com/jihyeseo/online-retail-data-set-from-uci-ml-repo

Open with Excel and save the file as `data.csv` in CSV format. (Save As > File Format: CSV UTF-8)

Put this file to the `online_retail` directory.

    $ mv data.csv oracle-pg/graphs/online_retail/
    $ dos2unix data.csv

## Load Data into Database

Run a bash console on `database` container as user "54321" (= "oracle" user in the container, for writing the sqlldr files).

    $ cd oracle-pg/
    $ docker-compose exec --user 54321 database /bin/bash

Move to the project directory (inside the container).

    $ cd /graphs/online_retail/

Create a database user `online_retail`.

    $ sqlplus sys/Welcome1@orclpdb1 as sysdba @create_user.sql

Create a table `transactions`.

    $ sqlplus online_retail/Welcome1@orclpdb1 @create_table.sql

Load the data from the CSV file.

    $ sqlldr online_retail/Welcome1@orclpdb1 sqlldr.ctl sqlldr.log sqlldr.bad direct=true

This table can be normalized to create 4 tables (`customers`, `products`, `purchases`, `purchases_distinct`).

    $ sqlplus online_retail/Welcome1@orclpdb1 @create_table_normalized.sql

Give `graph_dev` the permission to access the tables.

    $ sqlplus online_retail/Welcome1@orclpdb1 @grant.sql

Exit from the database container.

    $ exit

## Make Recommendations

Connect to Graph Server using Graph Client (JShell).

    $ cd oracle-pg/
    $ docker-compose exec graph-client opg-jshell -b http://graph-server:7007 --user graph_dev --secret_store /opt/oracle/keystore.p12
    enter password for user graph_dev (press Enter for no password): [Welcome1]
    enter password for keystore /opt/oracle/keystore.p12: [oracle]
    ...
    opg-jshell>


Read the data from database and convert to a graph. ([[Appendix 1]])

    opg-jshell> var graph = session.readGraphWithProperties("/graphs/online_retail/config-tables-distinct.json", "Online Retail");
    graph ==> PgxGraph[name=Online Retail,N=8258,E=532452,created=1599043512155]

Try a simple PGQL query.

    opg-jshell> graph.queryPgql(" SELECT n.description MATCH (n:Product) LIMIT 3 ").print();
    +-----------------------------------+
    | n.description                     |
    +-----------------------------------+
    | LUNCH BAG WOODLAND                |
    | GROW YOUR OWN BASIL IN ENAMEL MUG |
    | CHOCOLATE BOX RIBBONS             |
    +-----------------------------------+

List the products purchased by a customer "cust_12353".

    opg-jshell> graph.queryPgql(" SELECT ID(c), ID(p), p.description FROM MATCH (c)-[has_purchased]->(p) WHERE ID(c) = 'cust_12353' ").print();
    +--------------------------------------------------------------+
    | ID(c)      | ID(p)      | description                        |
    +--------------------------------------------------------------+
    | cust_12353 | prod_37446 | MINI CAKE STAND WITH HANGING CAKES |
    | cust_12353 | prod_22890 | NOVELTY BISCUITS CAKE STAND 3 TIER |
    | cust_12353 | prod_37449 | CERAMIC CAKE STAND + HANGING CAKES |
    | cust_12353 | prod_37450 | CERAMIC CAKE BOWL + HANGING CAKES  |
    +--------------------------------------------------------------+

Run Personalized PageRank (PPR) having the customer "cust_12353" as a focused node.

    opg-jshell> var vertex = graph.getVertex("cust_12353");
    opg-jshell> analyst.personalizedPagerank(graph, vertex);

Get the top 10 recommended products.

    opg-jshell>
    graph.queryPgql(
    "  SELECT ID(p), p.description, p.pagerank " +
    "  MATCH (p) " +
    "  WHERE LABEL(p) = 'Product' " +
    "    AND NOT EXISTS ( " +
    "     SELECT * " +
    "     MATCH (p)-[:purchased_by]->(a) " +
    "     WHERE ID(a) = 'cust_12353' " +
    "    ) " +
    "  ORDER BY p.pagerank DESC" +
    "  LIMIT 10"
    ).print();
    +--------------------------------------------------------------------------+
    | ID(p)       | p.description                      | p.pagerank            |
    +--------------------------------------------------------------------------+
    | prod_22423  | REGENCY CAKESTAND 3 TIER           | 0.00134836568957801   |
    | prod_85123A | WHITE HANGING HEART T-LIGHT HOLDER | 0.0013000764817371663 |
    | prod_21232  | STRAWBERRY CERAMIC TRINKET POT     | 0.0010642787031750636 |
    | prod_22720  | SET OF 3 CAKE TINS PANTRY DESIGN   | 9.987259826891447E-4  |
    | prod_47566  | PARTY BUNTING                      | 8.800446053134877E-4  |
    | prod_21231  | SWEETHEART CERAMIC TRINKET BOX     | 8.793185974570989E-4  |
    | prod_21212  | PACK OF 72 RETROSPOT CAKE CASES    | 7.749485802100009E-4  |
    | prod_84991  | 60 TEATIME FAIRY CAKE CASES        | 7.561654694509063E-4  |
    | prod_85099B | JUMBO BAG RED RETROSPOT            | 7.258904143858246E-4  |
    | prod_84879  | ASSORTED COLOUR BIRD ORNAMENT      | 7.223349157689752E-4  |
    +--------------------------------------------------------------------------+

To login to Graph Visualization with the same session, get the current session ID.

    opg-jshell> session.getId();
    $1 ==> "21526873-768b-49b7-9742-3fa798e00130"

For visualizing this graph, please **do not exit** from the shell so you can keep the session.

## Visualization

Open Graph Visualization (http://localhost:7007/ui) with username: graph_dev, password: Welcome1, session ID: (above).

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
