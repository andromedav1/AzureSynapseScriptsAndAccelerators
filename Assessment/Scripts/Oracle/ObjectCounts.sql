select SYS_CONTEXT ('USERENV','DB_NAME') AS INSTANCE_NAME, 
	owner as SCHEMA_NAME, 
	OBJECT_TYPE, 
	count(*) AS OBJECT_COUNT,
	SYS_CONTEXT ('USERENV','DB_NAME') || OWNER AS ROWKEY
from dba_objects 
where owner NOT IN ('SYS', 'SYSTEM', 'ANONYMOUS', 'CTXSYS', 'DBSNMP', 'LBACSYS', 'MDSYS', 'OLAPSYS', 'ORDPLUGINS', 'ORDSYS', 'OUTLN', 'SCOTT', 'WKSYS', 'WMSYS', 'XDB', 
	'DVSYS', 'EXFSYS', 'MGMT_VIEW', 'ORDDATA', 'OWBSYS', 'ORDPLUGINS', 'SYSMAN', 'WKSYS', 'WKPROXY', 'AUDSYS', 'GSMADMIN_INTERNAL', 'DBSFWUSER', 'OJVMSYS', 'APPQOSSYS', 'REMOTE_SCHEDULER_AGENT', 'DVF', 'ORACLE_OCM', 'PUBLIC')
GROUP BY SYS_CONTEXT ('USERENV','DB_NAME'), OWNER, OBJECT_TYPE;