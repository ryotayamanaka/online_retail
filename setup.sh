#!/bin/bash
cd /graphs/online_retail/
sqlplus sys/Welcome1@orclpdb1 as sysdba @create_user.sql
sqlplus online_retail/Welcome1@orclpdb1 @create_table.sql
sqlldr online_retail/Welcome1@orclpdb1 sqlldr.ctl sqlldr.log sqlldr.bad direct=true
sqlplus online_retail/Welcome1@orclpdb1 @create_table_normalized.sql
