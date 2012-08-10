-- afterMigLoggingGroup.sql : complex scenario executed by an emaj_adm role
-- The E-Maj version is changed while groups are in logging state
-- This script is the part of operations performed after the migration
--
-----------------------------
-- Step 1 : for myGroup1, update tables, then rollback then update tables again then set 3 marks
-----------------------------
set search_path=myschema1;
--
update "myTbl3" set col33 = col33 / 2;
--
alter table mySchema1.myTbl2 disable trigger myTbl2trg;
select emaj.emaj_rollback_group('myGroup1','M2');
alter table mySchema1.myTbl2 enable trigger myTbl2trg;
--
insert into myTbl1 select i, 'DEF', E'\\000'::bytea from generate_series (100,110) as i;
insert into myTbl2 values (3,'GHI','2010-01-02');
delete from myTbl1 where col11 = 1;
--
select emaj.emaj_set_mark_group('myGroup1','M4');
--
update "myTbl3" set col33 = col33 / 2;
--
select emaj.emaj_set_mark_group('myGroup1','M5');
--
update myTbl1 set col11 = 99 where col11 = 1;
--
select emaj.emaj_set_mark_group('myGroup1','M6');
-----------------------------
-- Step 2 : for myGroup2, logged rollback again then unlogged rollback 
-----------------------------
select emaj.emaj_logged_rollback_group('myGroup2','M2');
--
select emaj.emaj_rollback_group('myGroup2','M3');

-----------------------------
-- Step 3 : for myGroup1, update tables, rollback, other updates, then logged rollback
-----------------------------
set search_path=myschema1;
--
insert into myTbl1 values (1, 'Step 6', E'\\000'::bytea);
insert into myTbl4 values (11,'FK...',1,1,'Step 6');
insert into myTbl4 values (12,'FK...',1,1,'Step 6');
--
alter table mySchema1.myTbl2 disable trigger myTbl2trg;
select emaj.emaj_rollback_group('myGroup1','M5');
alter table mySchema1.myTbl2 enable trigger myTbl2trg;
--
insert into myTbl1 values (1, 'Step 6', E'\\001'::bytea);
copy myTbl4 from stdin;
11		1	1	Step 6
12		1	1	Step 6
\.
--
alter table mySchema1.myTbl2 disable trigger myTbl2trg;
select emaj.emaj_logged_rollback_group('myGroup1','M4');
alter table mySchema1.myTbl2 enable trigger myTbl2trg;

-----------------------------
-- Step 4 : for myGroup1, update tables, rename a mark, then delete 2 marks then delete all before a mark 
-----------------------------
set search_path=myschema1;
--
delete from "myTbl3" where col31 between 14 and 18;
--
select emaj.emaj_rename_mark_group('myGroup1',mark_name,'Before logged rollback to M4') from emaj.emaj_mark where mark_name like 'RLBK_M4_%_START';
-- 
select emaj.emaj_delete_mark_group('myGroup1',mark_name) from emaj.emaj_mark where mark_name like 'RLBK_M4_%_DONE';
select emaj.emaj_delete_mark_group('myGroup1','M1');
--
select emaj.emaj_delete_before_mark_group('myGroup1','M4');

-----------------------------
-- test end: check and reset history
-----------------------------
select hist_id, hist_function, hist_event, hist_object, regexp_replace(regexp_replace(hist_wording,E'\\d\\d\.\\d\\d\\.\\d\\d\\.\\d\\d\\d','%','g'),E'\\[.+\\]','(timestamp)','g'), hist_user from 
  (select * from emaj.emaj_hist order by hist_id) as t;
--
reset role;
truncate emaj.emaj_hist;
alter sequence emaj.emaj_hist_hist_id_seq restart 10000;

-- the groups are left in their current state for the parallel rollback test.
-- perform some updates to prepare the parallel rollback test
-- set a mark for both groups
select emaj.emaj_set_mark_groups(array['myGroup1','myGroup2'],'Multi-1');

select count(*) from mySchema1.myTbl4;
select count(*) from mySchema1.myTbl1;
select count(*) from mySchema1.myTbl2; 
select count(*) from mySchema1."myTbl3";
select count(*) from mySchema1.myTbl2b;
select count(*) from mySchema2.myTbl4;
select count(*) from mySchema2.myTbl1;
select count(*) from mySchema2.myTbl2; 
select count(*) from mySchema2."myTbl3";
delete from mySchema1.myTbl4;
delete from mySchema1.myTbl1;
delete from mySchema1.myTbl2; 
delete from mySchema1."myTbl3";
delete from mySchema1.myTbl2b;
delete from mySchema2.myTbl4;
delete from mySchema2.myTbl1;
delete from mySchema2.myTbl2; 
delete from mySchema2."myTbl3";
alter sequence mySchema2.mySeq1 restart 9999;
-- but disable the application trigger
alter table mySchema1.myTbl2 disable trigger myTbl2trg;
