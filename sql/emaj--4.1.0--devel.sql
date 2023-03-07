--
-- E-Maj: migration from 4.1.0 to <devel>
--
-- This software is distributed under the GNU General Public License.
--
-- This script upgrades an existing installation of E-Maj extension.
--

-- Complain if this script is executed in psql, rather than via an ALTER EXTENSION statement.
\echo Use "ALTER EXTENSION emaj UPDATE TO..." to upgrade the E-Maj extension. \quit

--SET client_min_messages TO WARNING;
SET client_min_messages TO NOTICE;

------------------------------------
--                                --
-- Checks                         --
--                                --
------------------------------------
-- Check that the upgrade conditions are met.
DO
$do$
  DECLARE
    v_emajVersion            TEXT;
    v_nbNoError              INT;
    v_nbWarning              INT;
  BEGIN
-- The emaj version registered in emaj_param must be '4.1.0'.
    SELECT param_value_text INTO v_emajVersion FROM emaj.emaj_param WHERE param_key = 'emaj_version';
    IF v_emajVersion <> '4.1.0' THEN
      RAISE EXCEPTION 'E-Maj upgrade: the current E-Maj version (%) is not 4.1.0',v_emajVersion;
    END IF;
-- The installed postgres version must be at least 11.
    IF current_setting('server_version_num')::int < 110000 THEN
      RAISE EXCEPTION 'E-Maj upgrade: the current PostgreSQL version (%) is not compatible with the new E-Maj version. The PostgreSQL '
                      'version should be at least 11.', current_setting('server_version');
    END IF;
-- Check E-Maj environment state.
    SELECT count(msg) FILTER (WHERE msg = 'No error detected'),
           count(msg) FILTER (WHERE msg LIKE 'Warning:%')
      INTO v_nbNoError, v_nbWarning
      FROM emaj.emaj_verify_all() AS t(msg);
    IF v_nbNoError = 0 THEN
      RAISE EXCEPTION 'E-Maj upgrade: the E-Maj environment is damaged. Please fix the issue before upgrading. You may execute '
                      '"SELECT * FROM emaj.emaj_verify_all();" to get more details.';
    END IF;
    IF v_nbWarning > 0 THEN
      RAISE WARNING 'E-Maj upgrade: the E-Maj environment health check reports warning. You may execute "SELECT * FROM '
                    'emaj.emaj_verify_all();" to get more details.';
    END IF;
  END;
$do$;

-- Some specific checks for this version upgrade.
DO
$do$
  DECLARE
    v_nbEventTrigger         INT;
    v_nbFunction             INT;
  BEGIN
-- Count the number of event triggers.
    SELECT count(*) INTO v_nbEventTrigger
      FROM pg_catalog.pg_event_trigger
      WHERE evtname IN ('emaj_protection_trg','emaj_sql_drop_trg','emaj_table_rewrite_trg');
-- Count the number of functions associated to event triggers.
    SELECT count(*) INTO v_nbFunction
      FROM pg_catalog.pg_proc JOIN pg_catalog.pg_namespace ON (pronamespace = pg_namespace.oid)
      WHERE (nspname = 'public' AND proname = '_emaj_protection_event_trigger_fnct')
         OR (nspname = 'emaj' AND proname = '_event_trigger_sql_drop_fnct')
         OR (nspname = 'emaj' AND proname = '_event_trigger_table_rewrite_fnct');
    IF v_nbEventTrigger + v_nbFunction < 6 THEN
      RAISE EXCEPTION 'E-Maj upgrade: some E-Maj event triggers and/or associated functions are missing. You could recreate them using '
                      'the emaj_upgrade_after_postgres_upgrade.sql script of the installed E-Maj version if it exists, or drop and '
                      'recreate the extension.';
    END IF;
  END;
$do$;

-- OK, the upgrade operation can start...

-- Insert the upgrade begin record in the operation history.
INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
  VALUES ('EMAJ_INSTALL','BEGIN','E-Maj <devel>', 'Upgrade from 4.1.0 started');

-- Lock emaj_group table to avoid any concurrent E-Maj activity.
LOCK TABLE emaj.emaj_group IN EXCLUSIVE MODE;

-- Disable the event triggers during the upgrade operation.
SELECT emaj._disable_event_triggers();

----------------------------------------------
--                                          --
-- emaj enums, tables, views and sequences  --
--                                          --
----------------------------------------------

-- Transform the 3 SERIAL/BIGSERIAL columns of technical tables into GENERATED AS IDENTITY columns.
DO
$do$
  DECLARE
    v_lastValue              BIGINT;
  BEGIN
-- emaj_hist.hist_id
    SELECT coalesce(max(hist_id), 0)
      INTO v_lastValue
      FROM emaj_hist;
    ALTER TABLE emaj.emaj_hist ALTER COLUMN hist_id DROP DEFAULT;
    DROP SEQUENCE emaj_hist_hist_id_seq;
    ALTER TABLE emaj.emaj_hist ALTER COLUMN hist_id SET DATA TYPE BIGINT;
    EXECUTE format('ALTER TABLE emaj.emaj_hist ALTER COLUMN hist_id ADD GENERATED ALWAYS AS IDENTITY (RESTART WITH %s)',
                   v_lastValue + 1);
-- emaj_time_stamp.time_id
    SELECT coalesce(max(time_id), 0)
      INTO v_lastValue
      FROM emaj_time_stamp;
    ALTER TABLE emaj_time_stamp ALTER COLUMN time_id DROP DEFAULT;
    DROP SEQUENCE emaj_time_stamp_time_id_seq;
    ALTER TABLE emaj_time_stamp ALTER COLUMN time_id SET DATA TYPE BIGINT;
    EXECUTE format('ALTER TABLE emaj.emaj_time_stamp ALTER COLUMN time_id ADD GENERATED ALWAYS AS IDENTITY (RESTART WITH %s)',
                   v_lastValue + 1);
-- emaj_rlbk.rlbk_id
    SELECT coalesce(max(rlbk_id), 0)
      INTO v_lastValue
      FROM emaj_rlbk;
    ALTER TABLE emaj_rlbk ALTER COLUMN rlbk_id DROP DEFAULT;
    DROP SEQUENCE emaj_rlbk_rlbk_id_seq;
    ALTER TABLE emaj_rlbk ALTER COLUMN rlbk_id SET DATA TYPE INT;
    EXECUTE format('ALTER TABLE emaj.emaj_rlbk ALTER COLUMN rlbk_id ADD GENERATED BY DEFAULT AS IDENTITY (RESTART WITH %s)',
                   v_lastValue + 1);
  END;
$do$;

--
-- Add created or recreated tables and sequences to the list of content to save by pg_dump.
--

------------------------------------
--                                --
-- emaj types                     --
--                                --
------------------------------------

------------------------------------
--                                --
-- emaj functions                 --
--                                --
------------------------------------
-- Recreate functions that have been previously dropped in the tables structure upgrade step and will not be recreated later in this script.


--<begin_functions>                              pattern used by the tool that extracts and insert the functions definition
------------------------------------------------------------------
-- drop obsolete functions or functions with modified interface --
------------------------------------------------------------------
DROP FUNCTION IF EXISTS emaj._build_alter_seq(P_REFLASTVALUE BIGINT,P_REFISCALLED BOOLEAN,P_REFINCREMENTBY BIGINT,P_REFSTARTVALUE BIGINT,P_REFMINVALUE BIGINT,P_REFMAXVALUE BIGINT,P_REFCACHEVALUE BIGINT,P_REFISCYCLED BOOLEAN,P_TRGLASTVALUE BIGINT,P_TRGISCALLED BOOLEAN,P_TRGINCREMENTBY BIGINT,P_TRGSTARTVALUE BIGINT,P_TRGMINVALUE BIGINT,P_TRGMAXVALUE BIGINT,P_TRGCACHEVALUE BIGINT,P_TRGISCYCLED BOOLEAN);

------------------------------------------------------------------
-- create new or modified functions                             --
------------------------------------------------------------------
CREATE OR REPLACE FUNCTION emaj._move_tables(p_schema TEXT, p_tables TEXT[], p_newGroup TEXT, p_mark TEXT, p_multiTable BOOLEAN,
                                             p_arrayFromRegex BOOLEAN)
RETURNS INTEGER LANGUAGE plpgsql AS
$_move_tables$
-- The function effectively moves tables from their tables group to another tables group.
-- Inputs: schema, array of table names, new group name, mark to set if for logging groups,
--         boolean to indicate whether several tables need to be processed,
--         a boolean indicating whether the tables array has been built from regex filters
-- Outputs: number of tables effectively moved to the tables group
  DECLARE
    v_function               TEXT;
    v_newGroupIsLogging      BOOLEAN;
    v_list                   TEXT;
    v_uselessTables          TEXT[];
    v_markName               TEXT;
    v_timeId                 BIGINT;
    v_groups                 TEXT[];
    v_loggingGroups          TEXT[];
    v_groupName              TEXT;
    v_groupIsLogging         BOOLEAN;
    v_oneTable               TEXT;
    v_nbMovedTbl             INT = 0;
  BEGIN
    v_function = CASE WHEN p_multiTable THEN 'MOVE_TABLES' ELSE 'MOVE_TABLE' END;
-- Insert the begin entry into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event)
      VALUES (v_function, 'BEGIN');
-- Check the group name and if ok, get some properties of the group.
    PERFORM emaj._check_group_names(p_groupNames := ARRAY[p_newGroup], p_mayBeNull := FALSE, p_lockGroups := TRUE, p_checkList := '');
    SELECT group_is_logging INTO v_newGroupIsLogging
      FROM emaj.emaj_group
      WHERE group_name = p_newGroup;
-- Check the tables list.
    IF NOT p_arrayFromRegex THEN
-- Remove duplicates values, NULL and empty strings from the supplied table names array.
      SELECT array_agg(DISTINCT table_name) INTO p_tables
        FROM unnest(p_tables) AS table_name
        WHERE table_name IS NOT NULL AND table_name <> '';
-- Check that the tables currently belong to a tables group (not necessarily the same for all table).
      WITH all_supplied_tables AS (
        SELECT unnest(p_tables) AS table_name
        ),
           tables_in_group AS (
        SELECT rel_tblseq
          FROM emaj.emaj_relation
          WHERE rel_schema = p_schema
            AND rel_tblseq = ANY(p_tables)
            AND upper_inf(rel_time_range)
        )
      SELECT string_agg(quote_ident(p_schema) || '.' || quote_ident(table_name), ', ' ORDER BY table_name) INTO v_list
        FROM
          (  SELECT table_name
               FROM all_supplied_tables
           EXCEPT
             SELECT rel_tblseq
               FROM tables_in_group
          ) AS t;
      IF v_list IS NOT NULL THEN
        RAISE EXCEPTION '_move_tables: some tables (%) do not currently belong to any tables group.', v_list;
      END IF;
-- Remove tables that already belong to the new group.
      SELECT string_agg(quote_ident(p_schema) || '.' || quote_ident(rel_tblseq), ', ' ORDER BY rel_tblseq), array_agg(rel_tblseq)
        INTO v_list, v_uselessTables
        FROM emaj.emaj_relation
        WHERE rel_schema = p_schema
          AND rel_tblseq = ANY(p_tables)
          AND upper_inf(rel_time_range)
          AND rel_group = p_newGroup;
      IF v_list IS NOT NULL THEN
        RAISE WARNING '_move_tables: some tables (%) already belong to the tables group %.', v_list, p_newGroup;
        SELECT array_agg(tbl) INTO p_tables
          FROM unnest(p_tables) AS tbl
          WHERE tbl <> ALL(v_uselessTables);
      END IF;
    END IF;
-- Get the lists of groups and logging groups holding these tables, if any.
-- It locks the tables groups so that no other operation simultaneously occurs these groups
-- (the CTE is needed for the FOR UPDATE clause not allowed when aggregate functions).
    WITH tables_group AS (
      SELECT group_name, group_is_logging FROM emaj.emaj_group
        WHERE group_name = p_newGroup OR
              group_name IN
               (SELECT DISTINCT rel_group FROM emaj.emaj_relation
                  WHERE rel_schema = p_schema
                    AND rel_tblseq = ANY(p_tables)
                    AND upper_inf(rel_time_range))
        FOR UPDATE OF emaj_group
      )
    SELECT array_agg(group_name ORDER BY group_name),
           array_agg(group_name ORDER BY group_name) FILTER (WHERE group_is_logging)
      INTO v_groups, v_loggingGroups
      FROM tables_group;
-- Check the supplied mark.
    SELECT emaj._check_new_mark(v_loggingGroups, p_mark) INTO v_markName;
-- OK,
    IF p_tables IS NULL THEN
-- When no tables are finaly selected, just warn.
      RAISE WARNING '_move_tables: No table to process.';
    ELSE
-- Get the time stamp of the operation.
      SELECT emaj._set_time_stamp('A') INTO v_timeId;
-- For LOGGING groups, lock all tables to get a stable point.
      IF v_loggingGroups IS NOT NULL THEN
-- Use a ROW EXCLUSIVE lock mode, preventing for a transaction currently updating data, but not conflicting with simple read access or
--  vacuum operation.
        PERFORM emaj._lock_groups(v_loggingGroups, 'ROW EXCLUSIVE', FALSE);
-- ... and set the mark, using the same time identifier.
        PERFORM emaj._set_mark_groups(v_loggingGroups, v_markName, TRUE, TRUE, NULL, v_timeId);
      END IF;
-- Effectively move each table.
      FOREACH v_oneTable IN ARRAY p_tables
      LOOP
-- Get some characteristics of the group that holds the table before the move.
        SELECT rel_group, group_is_logging INTO v_groupName, v_groupIsLogging
          FROM emaj.emaj_relation
               JOIN emaj.emaj_group ON (group_name = rel_group)
          WHERE rel_schema = p_schema
            AND rel_tblseq = v_oneTable
            AND upper_inf(rel_time_range);
-- Move this table.
        PERFORM emaj._move_tbl(p_schema, v_oneTable, v_groupName, v_groupIsLogging, p_newGroup, v_newGroupIsLogging, v_timeId, v_function);
        v_nbMovedTbl = v_nbMovedTbl + 1;
      END LOOP;
-- Adjust the groups characteristics.
      UPDATE emaj.emaj_group
        SET group_last_alter_time_id = v_timeId,
            group_nb_table =
              (SELECT count(*)
                 FROM emaj.emaj_relation
                 WHERE rel_group = group_name
                   AND upper_inf(rel_time_range)
                   AND rel_kind = 'r'
              )
        WHERE group_name = ANY (v_groups);
    END IF;
-- Insert the end entry into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_wording)
      VALUES (v_function, 'END', v_nbMovedTbl || ' tables moved to the tables group ' || p_newGroup);
--
    RETURN v_nbMovedTbl;
  END;
$_move_tables$;

CREATE OR REPLACE FUNCTION emaj._create_tbl(p_schema TEXT, p_tbl TEXT, p_groupName TEXT, p_priority INT, p_logDatTsp TEXT,
                                            p_logIdxTsp TEXT, p_ignoredTriggers TEXT[], p_timeId BIGINT,
                                            p_groupIsRollbackable BOOLEAN, p_groupIsLogging BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS
$_create_tbl$
-- This function creates all what is needed to manage the log and rollback operations for an application table.
-- Input: the application table to process,
--        the group to add it into,
--        the table properties: priority, tablespaces attributes and triggers to ignore at rollback time
--        the time id of the operation,
--        2 booleans indicating whether the group is rollbackable and whether the group is currently in logging state.
-- The objects created in the log schema:
--    - the associated log table, with its own sequence
--    - the function that logs the tables updates, defined as a trigger
  DECLARE
    v_emajNamesPrefix        TEXT;
    v_baseLogTableName       TEXT;
    v_baseLogIdxName         TEXT;
    v_baseLogFnctName        TEXT;
    v_baseSequenceName       TEXT;
    v_logSchema              TEXT;
    v_fullTableName          TEXT;
    v_logTableName           TEXT;
    v_logIdxName             TEXT;
    v_logFnctName            TEXT;
    v_sequenceName           TEXT;
    v_dataTblSpace           TEXT;
    v_idxTblSpace            TEXT;
    v_rlbkColList            TEXT;
    v_rlbkPkColList          TEXT;
    v_rlbkPkConditions       TEXT;
    v_genColList             TEXT;
    v_genValList             TEXT;
    v_genSetList             TEXT;
    v_genPkConditions        TEXT;
    v_nbGenAlwaysIdentCol    INTEGER;
    v_attnum                 SMALLINT;
    v_alter_log_table_param  TEXT;
    v_stmt                   TEXT;
    v_triggerList            TEXT;
  BEGIN
-- The checks on the table properties are performed by the calling functions.
-- Build the prefix of all emaj object to create.
    IF length(p_tbl) <= 50 THEN
-- For not too long table name, the prefix is the table name itself.
      v_emajNamesPrefix = p_tbl;
    ELSE
-- For long table names (over 50 char long), compute the suffix to add to the first 50 characters (#1, #2, ...), by looking at the
-- existing names.
      SELECT substr(p_tbl, 1, 50) || '#' || coalesce(max(suffix) + 1, 1)::TEXT INTO v_emajNamesPrefix
        FROM
          (SELECT (regexp_match(substr(rel_log_table, 51), '#(\d+)'))[1]::INT AS suffix
             FROM emaj.emaj_relation
             WHERE substr(rel_log_table, 1, 50) = substr(p_tbl, 1, 50)
          ) AS t;
    END IF;
-- Build the name of emaj components associated to the application table (non schema qualified and not quoted).
    v_baseLogTableName     = v_emajNamesPrefix || '_log';
    v_baseLogIdxName       = v_emajNamesPrefix || '_log_idx';
    v_baseLogFnctName      = v_emajNamesPrefix || '_log_fnct';
    v_baseSequenceName     = v_emajNamesPrefix || '_log_seq';
-- Build the different name for table, trigger, functions,...
    v_logSchema        = 'emaj_' || p_schema;
    v_fullTableName    = quote_ident(p_schema) || '.' || quote_ident(p_tbl);
    v_logTableName     = quote_ident(v_logSchema) || '.' || quote_ident(v_baseLogTableName);
    v_logIdxName       = quote_ident(v_baseLogIdxName);
    v_logFnctName      = quote_ident(v_logSchema) || '.' || quote_ident(v_baseLogFnctName);
    v_sequenceName     = quote_ident(v_logSchema) || '.' || quote_ident(v_baseSequenceName);
-- Prepare the TABLESPACE clauses for data and index
    v_dataTblSpace = coalesce('TABLESPACE ' || quote_ident(p_logDatTsp),'');
    v_idxTblSpace = coalesce('USING INDEX TABLESPACE ' || quote_ident(p_logIdxTsp),'');
-- Create the log table: it looks like the application table, with some additional technical columns.
    EXECUTE format('DROP TABLE IF EXISTS %s',
                   v_logTableName);
    EXECUTE format('CREATE TABLE %s (LIKE %s,'
                   '  emaj_verb      VARCHAR(3)  NOT NULL,'
                   '  emaj_tuple     VARCHAR(3)  NOT NULL,'
                   '  emaj_gid       BIGINT      NOT NULL   DEFAULT nextval(''emaj.emaj_global_seq''),'
                   '  emaj_changed   TIMESTAMPTZ DEFAULT clock_timestamp(),'
                   '  emaj_txid      BIGINT      DEFAULT txid_current(),'
                   '  emaj_user      VARCHAR(32) DEFAULT session_user,'
                   '  CONSTRAINT %s PRIMARY KEY (emaj_gid, emaj_tuple) %s'
                   '  ) %s',
                    v_logTableName, v_fullTableName, v_logIdxName, v_idxTblSpace, v_dataTblSpace);
-- Get the attnum of the emaj_verb column.
    SELECT attnum INTO STRICT v_attnum
      FROM pg_catalog.pg_attribute
           JOIN pg_catalog.pg_class ON (pg_class.oid = attrelid)
           JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
      WHERE nspname = v_logSchema
        AND relname = v_baseLogTableName
        AND attname = 'emaj_verb';
-- Adjust the log table structure with the alter_log_table parameter, if set.
    SELECT param_value_text INTO v_alter_log_table_param
      FROM emaj.emaj_param
      WHERE param_key = ('alter_log_table');
    IF v_alter_log_table_param IS NOT NULL AND v_alter_log_table_param <> '' THEN
      EXECUTE format('ALTER TABLE %s %s',
                     v_logTableName, v_alter_log_table_param);
    END IF;
-- Set the index associated to the primary key as cluster index (It may be useful for CLUSTER command).
    EXECUTE format('ALTER TABLE ONLY %s CLUSTER ON %s',
                   v_logTableName, v_logIdxName);
-- Remove the NOT NULL constraints of application columns.
--   They are useless and blocking to store truncate event for tables belonging to audit_only tables.
    SELECT string_agg(action, ',') INTO v_stmt
      FROM
        (SELECT ' ALTER COLUMN ' || quote_ident(attname) || ' DROP NOT NULL' AS action
           FROM pg_catalog.pg_attribute
                JOIN pg_catalog.pg_class ON (pg_class.oid = attrelid)
                JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
           WHERE nspname = v_logSchema
             AND relname = v_baseLogTableName
             AND attnum > 0
             AND attnum < v_attnum
             AND NOT attisdropped
             AND attnotnull
        ) AS t;
    IF v_stmt IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %s %s',
                     v_logTableName, v_stmt);
    END IF;
-- Create the sequence associated to the log table.
    EXECUTE format('CREATE SEQUENCE %s',
                   v_sequenceName);
-- Create the log function.
-- The new row is logged for each INSERT, the old row is logged for each DELETE and the old and new rows are logged for each UPDATE.
    EXECUTE 'CREATE OR REPLACE FUNCTION ' || v_logFnctName || '() RETURNS TRIGGER AS $logfnct$'
         || 'BEGIN'
-- The sequence associated to the log table is incremented at the beginning of the function ...
         || '  PERFORM NEXTVAL(' || quote_literal(v_sequenceName) || ');'
-- ... and the global id sequence is incremented by the first/only INSERT into the log table.
         || '  IF (TG_OP = ''DELETE'') THEN'
         || '    INSERT INTO ' || v_logTableName || ' SELECT OLD.*, ''DEL'', ''OLD'';'
         || '    RETURN OLD;'
         || '  ELSIF (TG_OP = ''UPDATE'') THEN'
         || '    INSERT INTO ' || v_logTableName || ' SELECT OLD.*, ''UPD'', ''OLD'';'
         || '    INSERT INTO ' || v_logTableName || ' SELECT NEW.*, ''UPD'', ''NEW'', lastval();'
         || '    RETURN NEW;'
         || '  ELSIF (TG_OP = ''INSERT'') THEN'
         || '    INSERT INTO ' || v_logTableName || ' SELECT NEW.*, ''INS'', ''NEW'';'
         || '    RETURN NEW;'
         || '  END IF;'
         || '  RETURN NULL;'
         || 'END;'
         || '$logfnct$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp;';
-- Create the log and truncate triggers.
    PERFORM emaj._handle_trigger_fk_tbl('DROP_TRIGGER', v_fullTableName, 'emaj_log_trg');
    PERFORM emaj._handle_trigger_fk_tbl('ADD_TRIGGER', v_fullTableName, 'emaj_log_trg', v_logFnctName);
    PERFORM emaj._handle_trigger_fk_tbl('DROP_TRIGGER', v_fullTableName, 'emaj_trunc_trg');
    PERFORM emaj._handle_trigger_fk_tbl('ADD_TRIGGER', v_fullTableName, 'emaj_trunc_trg');
    IF p_groupIsLogging THEN
-- If the group is in logging state, set the triggers as ALWAYS triggers, so that they can fire at rollback time.
      PERFORM emaj._handle_trigger_fk_tbl('SET_TRIGGER', v_fullTableName, 'emaj_log_trg', 'ALWAYS');
      PERFORM emaj._handle_trigger_fk_tbl('SET_TRIGGER', v_fullTableName, 'emaj_trunc_trg', 'ALWAYS');
    ELSE
-- If the group is idle, deactivate the triggers (they will be enabled at emaj_start_group time).
      PERFORM emaj._handle_trigger_fk_tbl('DISABLE_TRIGGER', v_fullTableName, 'emaj_log_trg');
      PERFORM emaj._handle_trigger_fk_tbl('DISABLE_TRIGGER', v_fullTableName, 'emaj_trunc_trg');
    END IF;
-- Set emaj_adm as owner of log objects.
    EXECUTE format('ALTER TABLE %s OWNER TO emaj_adm',
                   v_logTableName);
    EXECUTE format('ALTER SEQUENCE %s OWNER TO emaj_adm',
                   v_sequenceName);
    EXECUTE format('ALTER FUNCTION %s () OWNER TO emaj_adm',
                   v_logFnctName);
-- Grant appropriate rights to the emaj_viewer role.
    EXECUTE format('GRANT SELECT ON TABLE %s TO emaj_viewer',
                   v_logTableName);
    EXECUTE format('GRANT SELECT ON SEQUENCE %s TO emaj_viewer',
                   v_sequenceName);
-- Build some pieces of SQL statements that will be needed at table rollback and gen_sql times.
-- They are left NULL if the table has no pkey.
    SELECT * FROM emaj._build_sql_tbl(v_fullTableName)
      INTO v_rlbkColList, v_rlbkPkColList, v_rlbkPkConditions, v_genColList,
           v_genValList, v_genSetList, v_genPkConditions, v_nbGenAlwaysIdentCol;
-- Register the table into emaj_relation.
    INSERT INTO emaj.emaj_relation
               (rel_schema, rel_tblseq, rel_time_range, rel_group, rel_priority,
                rel_log_schema, rel_log_dat_tsp, rel_log_idx_tsp, rel_kind, rel_log_table,
                rel_log_index, rel_log_sequence, rel_log_function, rel_ignored_triggers, rel_emaj_verb_attnum,
                rel_has_always_ident_col, rel_sql_rlbk_columns, rel_sql_rlbk_pk_columns, rel_sql_rlbk_pk_conditions,
                rel_sql_gen_ins_col, rel_sql_gen_ins_val, rel_sql_gen_upd_set, rel_sql_gen_pk_conditions)
        VALUES (p_schema, p_tbl, int8range(p_timeId, NULL, '[)'), p_groupName, p_priority,
                v_logSchema, p_logDatTsp, p_logIdxTsp, 'r', v_baseLogTableName,
                v_baseLogIdxName, v_baseSequenceName, v_baseLogFnctName, p_ignoredTriggers, v_attnum,
                v_nbGenAlwaysIdentCol > 0, v_rlbkColList, v_rlbkPkColList, v_rlbkPkConditions,
                v_genColList, v_genValList, v_genSetList, v_genPkConditions);
-- Check if the table has application (neither internal - ie. created for fk - nor previously created by emaj) triggers not already
-- declared as 'to be ignored at rollback time'.
    SELECT string_agg(tgname, ', ' ORDER BY tgname) INTO v_triggerList
      FROM
        (SELECT tgname
           FROM pg_catalog.pg_trigger
           WHERE tgrelid = v_fullTableName::regclass
             AND tgconstraint = 0
             AND tgname NOT LIKE E'emaj\\_%\\_trg'
             AND NOT tgname = ANY(coalesce(p_ignoredTriggers, '{}'))
        ) AS t;
-- If yes, issue a warning.
-- If a trigger updates another table in the same table group or outside, it could generate problem at rollback time.
    IF v_triggerList IS NOT NULL THEN
      RAISE WARNING '_create_tbl: The table "%" has triggers that will be automatically disabled during E-Maj rollback operations (%).'
                    ' Use the emaj_modify_table() function to change this behaviour.', v_fullTableName, v_triggerList;
    END IF;
--
    RETURN;
  END;
$_create_tbl$;

CREATE OR REPLACE FUNCTION emaj._build_sql_tbl(p_fullTableName TEXT, OUT p_rlbkColList TEXT, OUT p_rlbkPkColList TEXT,
                                               OUT p_rlbkPkConditions TEXT, OUT p_genColList TEXT, OUT p_genValList TEXT,
                                               OUT p_genSetList TEXT, OUT p_genPkConditions TEXT, OUT p_nbGenAlwaysIdentCol INT)
LANGUAGE plpgsql AS
$_build_sql_tbl$
-- This function creates all pieces of SQL that will be recorded into the emaj_relation table, for one application table.
-- They will later be used at rollback or SQL script generation time.
-- All SQL pieces are left empty if the table has no pkey, neither rollback nor sql script generation operations being possible
--   in this case
-- The Insert columns list remains empty if it is not needed to have a specific list (i.e. when the application table does not contain
--   any generated column)
-- Input: the full application table name
-- Output: 7 pieces of SQL, and the number of columns declared GENERATED ALWAYS AS IDENTITY
  DECLARE
    v_stmt                   TEXT;
    v_nbGenAlwaysExprCol     INTEGER;
    v_unquotedType           CONSTANT TEXT[] = array['smallint','integer','bigint','numeric','decimal',
                                                     'int2','int4','int8','serial','bigserial',
                                                     'real','double precision','float','float4','float8','oid'];
    r_col                    RECORD;
  BEGIN
-- Build the pkey columns list and the "equality on the primary key" conditions for the rollback function
-- and for the UPDATE and DELETE statements of the sql generation function.
    SELECT string_agg(quote_ident(attname), ','),
           string_agg('tbl.' || quote_ident(attname) || ' = keys.' || quote_ident(attname), ' AND '),
           string_agg(
             CASE WHEN format_type = ANY(v_unquotedType) THEN
               quote_ident(replace(attname,'''','''''')) || ' = '' || o.' || quote_ident(attname) || ' || '''
                  ELSE
               quote_ident(replace(attname,'''','''''')) || ' = '' || quote_literal(o.' || quote_ident(attname) || ') || '''
             END, ' AND ')
      INTO p_rlbkPkColList, p_rlbkPkConditions, p_genPkConditions
      FROM
        (SELECT attname, regexp_replace(format_type(atttypid,atttypmod),E'\\(.*$','') AS format_type
           FROM pg_catalog.pg_attribute
                JOIN  pg_catalog.pg_index ON (pg_index.indrelid = pg_attribute.attrelid)
           WHERE attnum = ANY (indkey)
             AND indrelid = p_fullTableName::regclass
             AND indisprimary
             AND attnum > 0
             AND attisdropped = FALSE
           ORDER BY attnum
        ) AS t;
-- Retrieve from pg_attribute simple columns list and indicators.
-- If the table has no pkey, keep all the sql pieces to NULL (rollback or sql script generation operations being impossible).
    IF p_rlbkPkColList IS NOT NULL THEN
      v_stmt = 'SELECT string_agg(''tbl.'' || quote_ident(attname), '','') FILTER (WHERE attgenerated = ''''),'
--                             the columns list for rollback, excluding the GENERATED ALWAYS AS (expression) columns
               '       string_agg(quote_ident(replace(attname,'''''''','''''''''''')), '', '') FILTER (WHERE attgenerated = ''''),'
--                             the INSERT columns list for sql generation, excluding the GENERATED ALWAYS AS (expression) columns
               '       count(*) FILTER (WHERE attidentity = ''a''),'
--                             the number of GENERATED ALWAYS AS IDENTITY columns
               '       count(*) FILTER (WHERE attgenerated <> '''')'
--                             the number of GENERATED ALWAYS AS (expression) columns
               '  FROM ('
               '  SELECT attname, attidentity, %s AS attgenerated'
               '    FROM pg_catalog.pg_attribute'
               '    WHERE attrelid = %s::regclass'
               '      AND attnum > 0 AND NOT attisdropped'
               '  ORDER BY attnum) AS t';
      EXECUTE format(v_stmt,
                     CASE WHEN emaj._pg_version_num() >= 120000 THEN 'attgenerated' ELSE '''''::TEXT' END,
                     quote_literal(p_fullTableName))
        INTO p_rlbkColList, p_genColList, p_nbGenAlwaysIdentCol, v_nbGenAlwaysExprCol;
      IF v_nbGenAlwaysExprCol = 0 THEN
-- If the table doesn't contain any generated columns, the is no need for the columns list in the INSERT clause.
        p_genColList = '';
      END IF;
-- Retrieve from pg_attribute all columns of the application table and build :
-- - the VALUES list used in the INSERT statements
-- - the SET list used in the UPDATE statements.
-- The logic is too complex to be build with aggregate functions. So loop on all columns.
      p_genValList = '';
      p_genSetList = '';
      FOR r_col IN EXECUTE format(
        ' SELECT attname, format_type(atttypid,atttypmod) AS format_type, attidentity, %s AS attgenerated'
        ' FROM pg_catalog.pg_attribute'
        ' WHERE attrelid = %s::regclass'
        '   AND attnum > 0 AND NOT attisdropped'
        ' ORDER BY attnum',
        CASE WHEN emaj._pg_version_num() >= 120000 THEN 'attgenerated' ELSE '''''::TEXT' END,
        quote_literal(p_fullTableName))
      LOOP
-- Test if the column format (up to the parenthesis) belongs to the list of formats that do not require any quotation (like numeric
-- data types)
        IF regexp_replace(r_col.format_type,E'\\(.*$','') = ANY(v_unquotedType) THEN
-- Literal for this column can remain as is.
          IF r_col.attgenerated = '' THEN                                     -- GENERATED ALWAYS AS (expression) columns are not inserted
            p_genValList = p_genValList || ''' || coalesce(o.' || quote_ident(r_col.attname) || '::TEXT,''NULL'') || '', ';
          END IF;
          IF r_col.attidentity <> 'a' AND r_col.attgenerated = '' THEN        -- GENERATED ALWAYS columns are not updated
            p_genSetList = p_genSetList || quote_ident(replace(r_col.attname,'''','''''')) || ' = '' || coalesce(n.'
                                        || quote_ident(r_col.attname) || ' ::TEXT,''NULL'') || '', ';
          END IF;
        ELSE
-- Literal for this column must be quoted.
          IF r_col.attgenerated = '' THEN                                     -- GENERATED ALWAYS AS (expression) columns are not inserted
            p_genValList = p_genValList || ''' || quote_nullable(o.' || quote_ident(r_col.attname) || ') || '', ';
          END IF;
          IF r_col.attidentity <> 'a' AND r_col.attgenerated = '' THEN        -- GENERATED ALWAYS columns are not updated
            p_genSetList = p_genSetList || quote_ident(replace(r_col.attname,'''','''''')) || ' = '' || quote_nullable(n.'
                                        || quote_ident(r_col.attname) || ') || '', ';
          END IF;
        END IF;
      END LOOP;
-- Suppress the final separators.
      p_genValList = substring(p_genValList FROM 1 FOR char_length(p_genValList) - 2);
      p_genSetList = substring(p_genSetList FROM 1 FOR char_length(p_genSetList) - 2);
    END IF;
--
    RETURN;
  END;
$_build_sql_tbl$;

CREATE OR REPLACE FUNCTION emaj._remove_tbl(p_schema TEXT, p_table TEXT, p_group TEXT, p_groupIsLogging BOOLEAN,
                                            p_timeId BIGINT, p_function TEXT)
RETURNS VOID LANGUAGE plpgsql AS
$_remove_tbl$
-- The function removes a table from a group. It is called during an alter group or a dynamic removal operation.
-- If the group is in idle state, it simply calls the _drop_tbl() function.
-- Otherwise, only triggers, log function and log sequence are dropped now. The other components will be dropped later (at reset_group
-- time for instance).
-- Required inputs: schema and sequence to remove, related group name and logging state,
--                  time stamp id of the operation, main calling function.
-- The function is defined as SECURITY DEFINER so that emaj_adm role can drop triggers on application tables.
  DECLARE
    v_logSchema              TEXT;
    v_currentLogTable        TEXT;
    v_currentLogIndex        TEXT;
    v_logFunction            TEXT;
    v_logSequence            TEXT;
    v_logSequenceLastValue   BIGINT;
    v_namesSuffix            TEXT;
    v_fullTableName          TEXT;
  BEGIN
    IF NOT p_groupIsLogging THEN
-- If the group is in idle state, drop the table immediately.
      PERFORM emaj._drop_tbl(emaj.emaj_relation.*, p_timeId)
        FROM emaj.emaj_relation
        WHERE rel_schema = p_schema
          AND rel_tblseq = p_table
          AND upper_inf(rel_time_range);
    ELSE
-- The group is in logging state.
-- Get the current relation characteristics.
      SELECT rel_log_schema, rel_log_table, rel_log_index, rel_log_function, rel_log_sequence
        INTO v_logSchema, v_currentLogTable, v_currentLogIndex, v_logFunction, v_logSequence
        FROM emaj.emaj_relation
        WHERE rel_schema = p_schema
          AND rel_tblseq = p_table
          AND upper_inf(rel_time_range);
-- Get the current log sequence characteristics.
      SELECT tbl_log_seq_last_val INTO STRICT v_logSequenceLastValue
        FROM emaj.emaj_table
        WHERE tbl_schema = p_schema
          AND tbl_name = p_table
          AND tbl_time_id = p_timeId;
-- Compute the suffix to add to the log table and index names (_1, _2, ...), by looking at the existing names.
      SELECT '_' || coalesce(max(suffix) + 1, 1)::TEXT INTO v_namesSuffix
        FROM
          (SELECT (regexp_match(rel_log_table,'_(\d+)$'))[1]::INT AS suffix
             FROM emaj.emaj_relation
             WHERE rel_schema = p_schema
               AND rel_tblseq = p_table
          ) AS t;
-- Rename the log table and its index (they may have been dropped).
      EXECUTE format('ALTER TABLE IF EXISTS %I.%I RENAME TO %I',
                     v_logSchema, v_currentLogTable, v_currentLogTable || v_namesSuffix);
      EXECUTE format('ALTER INDEX IF EXISTS %I.%I RENAME TO %I',
                     v_logSchema, v_currentLogIndex, v_currentLogIndex || v_namesSuffix);
-- Drop the log and truncate triggers.
-- (check the application table exists before dropping its triggers to avoid an error fires with postgres version <= 9.3)
      v_fullTableName  = quote_ident(p_schema) || '.' || quote_ident(p_table);
      IF EXISTS
           (SELECT 0
              FROM pg_catalog.pg_class
                   JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
              WHERE nspname = p_schema
                AND relname = p_table
                AND relkind = 'r'
           ) THEN
        PERFORM emaj._handle_trigger_fk_tbl('DROP_TRIGGER', v_fullTableName, 'emaj_log_trg');
        PERFORM emaj._handle_trigger_fk_tbl('DROP_TRIGGER', v_fullTableName, 'emaj_trunc_trg');
      END IF;
-- Drop the log function and the log sequence.
-- (but we keep the sequence related data in the emaj_table and the emaj_seq_hole tables)
      EXECUTE format('DROP FUNCTION IF EXISTS %I.%I() CASCADE',
                     v_logSchema, v_logFunction);
      EXECUTE format('DROP SEQUENCE IF EXISTS %I.%I',
                     v_logSchema, v_logSequence);
-- Register the end of the relation time frame, the last value of the log sequence, the log table and index names change.
-- Reflect the changes into the emaj_relation rows:
--   - for all timeranges pointing to this log table and index
--     (do not reset the rel_log_sequence value: it will be needed later for _drop_tbl() for the emaj_sequence cleanup)
      UPDATE emaj.emaj_relation
        SET rel_log_table = v_currentLogTable || v_namesSuffix , rel_log_index = v_currentLogIndex || v_namesSuffix,
            rel_log_function = NULL, rel_sql_rlbk_columns = NULL, rel_sql_rlbk_pk_columns = NULL, rel_sql_rlbk_pk_conditions = NULL,
            rel_log_seq_last_value = v_logSequenceLastValue
        WHERE rel_schema = p_schema
          AND rel_tblseq = p_table
          AND rel_log_table = v_currentLogTable;
--   - and close the last timerange.
      UPDATE emaj.emaj_relation
        SET rel_time_range = int8range(lower(rel_time_range), p_timeId, '[)')
        WHERE rel_schema = p_schema
          AND rel_tblseq = p_table
          AND upper_inf(rel_time_range);
    END IF;
-- Insert an entry into the emaj_relation_change table.
    INSERT INTO emaj.emaj_relation_change (rlchg_time_id, rlchg_schema, rlchg_tblseq, rlchg_change_kind, rlchg_group)
      VALUES (p_timeId, p_schema, p_table, 'REMOVE_TABLE', p_group);
-- Insert an entry into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
      VALUES (p_function, 'TABLE REMOVED', quote_ident(p_schema) || '.' || quote_ident(p_table),
              'From the ' || CASE WHEN p_groupIsLogging THEN 'logging ' ELSE 'idle ' END || 'group ' || p_group);
--
    RETURN;
  END;
$_remove_tbl$;

CREATE OR REPLACE FUNCTION emaj._move_tbl(p_schema TEXT, p_table TEXT, p_oldGroup TEXT, p_oldGroupIsLogging BOOLEAN, p_newGroup TEXT,
                                          p_newGroupIsLogging BOOLEAN, p_timeId BIGINT, p_function TEXT)
RETURNS VOID LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
$_move_tbl$
-- The function changes the group ownership of a table. It is called during an alter group or a dynamic assignment operation.
-- Required inputs: schema and table to move, old and new group names and their logging state,
--                  time stamp id of the operation, main calling function.
  DECLARE
    v_logSchema              TEXT;
    v_logSequence            TEXT;
    v_currentLogTable        TEXT;
    v_currentLogIndex        TEXT;
    v_dataTblSpace           TEXT;
    v_idxTblSpace            TEXT;
    v_namesSuffix            TEXT;
  BEGIN
-- Get the current relation characteristics.
    SELECT rel_log_schema, rel_log_table, rel_log_index, rel_log_sequence,
           coalesce('TABLESPACE ' || quote_ident(rel_log_dat_tsp),''),
           coalesce('USING INDEX TABLESPACE ' || quote_ident(rel_log_idx_tsp),'')
      INTO v_logSchema, v_currentLogTable, v_currentLogIndex, v_logSequence,
           v_dataTblSpace,
           v_idxTblSpace
      FROM emaj.emaj_relation
      WHERE rel_schema = p_schema
        AND rel_tblseq = p_table
        AND upper_inf(rel_time_range);
-- Compute the suffix to add to the log table and index names (_1, _2, ...), by looking at the existing names.
    SELECT '_' || coalesce(max(suffix) + 1, 1)::TEXT INTO v_namesSuffix
      FROM
          (SELECT (regexp_match(rel_log_table,'_(\d+)$'))[1]::INT AS suffix
           FROM emaj.emaj_relation
           WHERE rel_schema = p_schema
             AND rel_tblseq = p_table
        ) AS t;
-- Rename the log table and its index (they may have been dropped).
    EXECUTE format('ALTER TABLE IF EXISTS %I.%I RENAME TO %I',
                   v_logSchema, v_currentLogTable, v_currentLogTable || v_namesSuffix);
    EXECUTE format('ALTER INDEX IF EXISTS %I.%I RENAME TO %I',
                   v_logSchema, v_currentLogIndex, v_currentLogIndex || v_namesSuffix);
-- Update emaj_relation to reflect the log table and index rename for all concerned rows.
    UPDATE emaj.emaj_relation
      SET rel_log_table = v_currentLogTable || v_namesSuffix , rel_log_index = v_currentLogIndex || v_namesSuffix
      WHERE rel_schema = p_schema
        AND rel_tblseq = p_table
        AND rel_log_table = v_currentLogTable;
-- Create the new log table, by copying the just renamed table structure.
    EXECUTE format('CREATE TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS) %s',
                    v_logSchema, v_currentLogTable, v_logSchema, v_currentLogTable || v_namesSuffix, v_dataTblSpace);
-- Add the primary key.
    EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAiNT %I PRIMARY KEY (emaj_gid, emaj_tuple) %s',
                    v_logSchema, v_currentLogTable, v_currentLogIndex, v_idxTblSpace);
-- Set the index associated to the primary key as cluster index. It may be useful for CLUSTER command.
    EXECUTE format('ALTER TABLE ONLY %I.%I CLUSTER ON %I',
                   v_logSchema, v_currentLogTable, v_currentLogIndex);
-- Grant appropriate rights to both emaj roles.
    EXECUTE format('ALTER TABLE %I.%I OWNER TO emaj_adm',
                   v_logSchema, v_currentLogTable);
    EXECUTE format('GRANT SELECT ON TABLE %I.%I TO emaj_viewer',
                   v_logSchema, v_currentLogTable);
-- Register the end of the previous relation time frame and create a new relation time frame with the new group.
    UPDATE emaj.emaj_relation
      SET rel_time_range = int8range(lower(rel_time_range),p_timeId,'[)')
      WHERE rel_schema = p_schema
        AND rel_tblseq = p_table
        AND upper_inf(rel_time_range);
    INSERT INTO emaj.emaj_relation (rel_schema, rel_tblseq, rel_time_range, rel_group, rel_kind, rel_priority, rel_log_schema,
                                    rel_log_table, rel_log_dat_tsp, rel_log_index, rel_log_idx_tsp, rel_log_sequence, rel_log_function,
                                    rel_ignored_triggers, rel_emaj_verb_attnum, rel_has_always_ident_col,
                                    rel_sql_rlbk_columns, rel_sql_rlbk_pk_columns, rel_sql_rlbk_pk_conditions,
                                    rel_sql_gen_ins_col, rel_sql_gen_ins_val, rel_sql_gen_upd_set, rel_sql_gen_pk_conditions,
                                    rel_log_seq_last_value)
      SELECT rel_schema, rel_tblseq, int8range(p_timeId, NULL, '[)'), p_newGroup, rel_kind, rel_priority, rel_log_schema,
             v_currentLogTable, rel_log_dat_tsp, v_currentLogIndex, rel_log_idx_tsp, rel_log_sequence, rel_log_function,
             rel_ignored_triggers, rel_emaj_verb_attnum, rel_has_always_ident_col,
             rel_sql_rlbk_columns, rel_sql_rlbk_pk_columns, rel_sql_rlbk_pk_conditions,
             rel_sql_gen_ins_col, rel_sql_gen_ins_val, rel_sql_gen_upd_set, rel_sql_gen_pk_conditions,
             rel_log_seq_last_value
        FROM emaj.emaj_relation
        WHERE rel_schema = p_schema
          AND rel_tblseq = p_table
          AND upper(rel_time_range) = p_timeId;
-- If the table is moved from an idle group to a group in logging state,
    IF NOT p_oldGroupIsLogging AND p_newGroupIsLogging THEN
-- ... get the log schema and sequence for the new relation,
      SELECT rel_log_schema, rel_log_sequence INTO v_logSchema, v_logSequence
        FROM emaj.emaj_relation
        WHERE rel_schema = p_schema
          AND rel_tblseq = p_table
          AND upper_inf(rel_time_range);
-- ... and record the new log sequence state in the emaj_table table for the current operation mark.
      INSERT INTO emaj.emaj_table (tbl_schema, tbl_name, tbl_time_id, tbl_tuples, tbl_pages, tbl_log_seq_last_val)
        SELECT p_schema, p_table, p_timeId, reltuples, relpages, last_value
          FROM pg_catalog.pg_class
               JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace),
               LATERAL emaj._get_log_sequence_last_value(v_logSchema, v_logSequence) AS last_value
          WHERE nspname = p_schema
            AND relname = p_table;
    END IF;
-- Insert an entry into the emaj_relation_change table.
    INSERT INTO emaj.emaj_relation_change (rlchg_time_id, rlchg_schema, rlchg_tblseq, rlchg_change_kind, rlchg_group, rlchg_new_group)
      VALUES (p_timeId, p_schema, p_table, 'MOVE_TABLE', p_oldGroup, p_newGroup);
-- Insert an entry into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
      VALUES (p_function, 'TABLE MOVED', quote_ident(p_schema) || '.' || quote_ident(p_table),
              'From the ' || CASE WHEN p_oldGroupIsLogging THEN 'logging ' ELSE 'idle ' END || 'group ' || p_oldGroup ||
              ' to the ' || CASE WHEN p_newGroupIsLogging THEN 'logging ' ELSE 'idle ' END || 'group ' || p_newGroup);
--
    RETURN;
  END;
$_move_tbl$;

CREATE OR REPLACE FUNCTION emaj._move_sequences(p_schema TEXT, p_sequences TEXT[], p_newGroup TEXT, p_mark TEXT, p_multiSequence BOOLEAN,
                                             p_arrayFromRegex BOOLEAN)
RETURNS INTEGER LANGUAGE plpgsql AS
$_move_sequences$
-- The function effectively moves sequences from their tables group to another tables group.
-- Inputs: schema, array of sequence names, new group name, mark to set if for logging groups,
--         boolean to indicate whether several sequences need to be processed,
--         a boolean indicating whether the sequences array has been built from regex filters
-- Outputs: number of sequences effectively moved to the tables group
  DECLARE
    v_function               TEXT;
    v_newGroupIsLogging      BOOLEAN;
    v_list                   TEXT;
    v_uselessSequences       TEXT[];
    v_markName               TEXT;
    v_timeId                 BIGINT;
    v_groups                 TEXT[];
    v_loggingGroups          TEXT[];
    v_groupName              TEXT;
    v_groupIsLogging         BOOLEAN;
    v_oneSequence            TEXT;
    v_nbMovedSeq             INT = 0;
  BEGIN
    v_function = CASE WHEN p_multiSequence THEN 'MOVE_SEQUENCES' ELSE 'MOVE_SEQUENCE' END;
-- Insert the begin entry into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event)
      VALUES (v_function, 'BEGIN');
-- Check the group name and if ok, get some properties of the group.
    PERFORM emaj._check_group_names(p_groupNames := ARRAY[p_newGroup], p_mayBeNull := FALSE, p_lockGroups := TRUE, p_checkList := '');
    SELECT group_is_logging INTO v_newGroupIsLogging
      FROM emaj.emaj_group
      WHERE group_name = p_newGroup;
-- Check the sequences list.
    IF NOT p_arrayFromRegex THEN
-- Remove duplicates values, NULL and empty strings from the supplied sequence names array.
      SELECT array_agg(DISTINCT sequence_name) INTO p_sequences
        FROM unnest(p_sequences) AS sequence_name
        WHERE sequence_name IS NOT NULL AND sequence_name <> '';
-- Check that the sequences currently belong to a tables group (not necessarily the same for all sequences).
      WITH all_supplied_sequences AS
        (SELECT unnest(p_sequences) AS sequence_name
        ),
           sequences_in_group AS
        (SELECT rel_tblseq
           FROM emaj.emaj_relation
           WHERE rel_schema = p_schema
             AND rel_tblseq = ANY(p_sequences)
             AND upper_inf(rel_time_range)
        )
      SELECT string_agg(quote_ident(p_schema) || '.' || quote_ident(sequence_name), ', ' ORDER BY sequence_name) INTO v_list
        FROM
          (  SELECT sequence_name
               FROM all_supplied_sequences
           EXCEPT
             SELECT rel_tblseq
               FROM sequences_in_group
          ) AS t;
      IF v_list IS NOT NULL THEN
        RAISE EXCEPTION '_move_sequences: some sequences (%) do not currently belong to any tables group.', v_list;
      END IF;
-- Remove sequences that already belong to the new group.
      SELECT string_agg(quote_ident(p_schema) || '.' || quote_ident(rel_tblseq), ', ' ORDER BY rel_tblseq), array_agg(rel_tblseq)
        INTO v_list, v_uselessSequences
        FROM emaj.emaj_relation
        WHERE rel_schema = p_schema
          AND rel_tblseq = ANY(p_sequences)
          AND upper_inf(rel_time_range)
          AND rel_group = p_newGroup;
      IF v_list IS NOT NULL THEN
        RAISE WARNING '_move_sequences: some sequences (%) already belong to the tables group %.', v_list, p_newGroup;
        SELECT array_agg(seq) INTO p_sequences
          FROM unnest(p_sequences) AS seq
          WHERE seq <> ALL(v_uselessSequences);
      END IF;
    END IF;
-- Get the lists of groups and logging groups holding these sequences, if any.
-- It locks the tables groups so that no other operation simultaneously occurs these groups
-- (the CTE is needed for the FOR UPDATE clause not allowed when aggregate functions).
    WITH tables_group AS
      (SELECT group_name, group_is_logging
         FROM emaj.emaj_group
         WHERE group_name = p_newGroup
            OR group_name IN
                 (SELECT DISTINCT rel_group
                    FROM emaj.emaj_relation
                    WHERE rel_schema = p_schema
                      AND rel_tblseq = ANY(p_sequences)
                      AND upper_inf(rel_time_range)
                 )
        FOR UPDATE OF emaj_group
      )
    SELECT array_agg(group_name ORDER BY group_name),
           array_agg(group_name ORDER BY group_name) FILTER (WHERE group_is_logging)
      INTO v_groups, v_loggingGroups
      FROM tables_group;
-- Check the supplied mark.
    SELECT emaj._check_new_mark(v_loggingGroups, p_mark) INTO v_markName;
-- OK,
    IF p_sequences IS NULL THEN
-- When no sequences are finaly selected, just warn.
      RAISE WARNING '_move_sequences: No sequence to process.';
    ELSE
-- Get the time stamp of the operation.
      SELECT emaj._set_time_stamp('A') INTO v_timeId;
-- For LOGGING groups, lock all tables to get a stable point.
      IF v_loggingGroups IS NOT NULL THEN
-- Use a ROW EXCLUSIVE lock mode, preventing for a transaction currently updating data, but not conflicting with simple read access or
-- vacuum operation,
        PERFORM emaj._lock_groups(v_loggingGroups, 'ROW EXCLUSIVE', FALSE);
-- ... and set the mark, using the same time identifier.
        PERFORM emaj._set_mark_groups(v_loggingGroups, v_markName, TRUE, TRUE, NULL, v_timeId);
      END IF;
-- Effectively move each sequence.
      FOREACH v_oneSequence IN ARRAY p_sequences
      LOOP
-- Get some characteristics of the group that holds the sequence before the move.
        SELECT rel_group, group_is_logging INTO v_groupName, v_groupIsLogging
          FROM emaj.emaj_relation
               JOIN emaj.emaj_group ON (group_name = rel_group)
          WHERE rel_schema = p_schema
            AND rel_tblseq = v_oneSequence
            AND upper_inf(rel_time_range);
-- Move this sequence.
        PERFORM emaj._move_seq(p_schema, v_oneSequence, v_groupName, v_groupIsLogging, p_newGroup, v_newGroupIsLogging, v_timeId,
                               v_function);
        v_nbMovedSeq = v_nbMovedSeq + 1;
      END LOOP;
-- Adjust the groups characteristics.
      UPDATE emaj.emaj_group
        SET group_last_alter_time_id = v_timeId,
            group_nb_sequence =
              (SELECT count(*)
                 FROM emaj.emaj_relation
                 WHERE rel_group = group_name
                   AND upper_inf(rel_time_range)
                   AND rel_kind = 'S'
              )
        WHERE group_name = ANY (v_groups);
    END IF;
-- Insert the end entry into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_wording)
      VALUES (v_function, 'END', v_nbMovedSeq || ' sequences moved to the tables group ' || p_newGroup);
--
    RETURN v_nbMovedSeq;
  END;
$_move_sequences$;

CREATE OR REPLACE FUNCTION emaj._rlbk_seq(r_rel emaj.emaj_relation, p_timeId BIGINT)
RETURNS VOID LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
$_rlbk_seq$
-- This function rollbacks one application sequence to a given mark.
-- The function is called by emaj.emaj._rlbk_end().
-- Input: the emaj_relation  row related to the application sequence to process, time id of the mark to rollback to.
-- The function is defined as SECURITY DEFINER so that emaj_adm role can use it even if it is not the owner of the application sequence.
  DECLARE
    v_stmt                   TEXT;
    v_fullSeqName            TEXT;
    mark_seq_rec             emaj.emaj_sequence%ROWTYPE;
    curr_seq_rec             emaj.emaj_sequence%ROWTYPE;
  BEGIN
-- Read sequence's characteristics at mark time.
    SELECT *
      INTO mark_seq_rec
      FROM emaj.emaj_sequence
      WHERE sequ_schema = r_rel.rel_schema
        AND sequ_name = r_rel.rel_tblseq
        AND sequ_time_id = p_timeId;
    IF NOT FOUND THEN
      RAISE EXCEPTION '_rlbk_seq: No mark at time id "%" can be found for the sequence "%.%".',
        p_timeId, r_rel.rel_schema, r_rel.rel_tblseq;
    END IF;
-- Read the current sequence's characteristics.
    SELECT *
      INTO curr_seq_rec
      FROM emaj._get_current_sequence_state(r_rel.rel_schema, r_rel.rel_tblseq, NULL);
-- Build the ALTER SEQUENCE statement, depending on the differences between the current sequence state and its characteristics
-- at the requested mark time.
    SELECT emaj._build_alter_seq(curr_seq_rec, mark_seq_rec) INTO v_stmt;
-- And execute the statement if at least one parameter has changed.
    v_fullSeqName = quote_ident(r_rel.rel_schema) || '.' || quote_ident(r_rel.rel_tblseq);
    IF v_stmt <> '' THEN
      EXECUTE format('ALTER SEQUENCE %s %s',
                     v_fullSeqName, v_stmt);
    END IF;
-- Insert the event into the history.
    INSERT INTO emaj.emaj_hist (hist_function, hist_object, hist_wording)
      VALUES ('ROLLBACK_SEQUENCE', v_fullSeqName, substr(v_stmt,2));
--
    RETURN;
  END;
$_rlbk_seq$;

CREATE OR REPLACE FUNCTION emaj._build_alter_seq(ref_seq_rec emaj.emaj_sequence, trg_seq_rec emaj.emaj_sequence)
RETURNS TEXT LANGUAGE plpgsql AS
$_build_alter_seq$
-- This function builds an ALTER SEQUENCE clause including only the sequence characteristics that have changed between a reference
-- and a target.
-- The function is called by _rlbk_seq() and _gen_sql_groups().
-- Input: 2 emaj_sequence records representing the reference and the target sequence characteristics
-- Output: the alter sequence clause with all modified characteristics
  DECLARE
    v_stmt                   TEXT;
  BEGIN
    v_stmt = '';
-- Build the ALTER SEQUENCE clause, depending on the differences between the reference and target values.
    IF ref_seq_rec.sequ_last_val <> trg_seq_rec.sequ_last_val OR
       ref_seq_rec.sequ_is_called <> trg_seq_rec.sequ_is_called THEN
      IF trg_seq_rec.sequ_is_called THEN
        v_stmt = v_stmt || ' RESTART ' || trg_seq_rec.sequ_last_val + trg_seq_rec.sequ_increment;
      ELSE
        v_stmt = v_stmt || ' RESTART ' || trg_seq_rec.sequ_last_val;
      END IF;
    END IF;
    IF ref_seq_rec.sequ_start_val <> trg_seq_rec.sequ_start_val THEN
      v_stmt = v_stmt || ' START ' || trg_seq_rec.sequ_start_val;
    END IF;
    IF ref_seq_rec.sequ_increment <> trg_seq_rec.sequ_increment THEN
      v_stmt = v_stmt || ' INCREMENT ' || trg_seq_rec.sequ_increment;
    END IF;
    IF ref_seq_rec.sequ_min_val <> trg_seq_rec.sequ_min_val THEN
      v_stmt = v_stmt || ' MINVALUE ' || trg_seq_rec.sequ_min_val;
    END IF;
    IF ref_seq_rec.sequ_max_val <> trg_seq_rec.sequ_max_val THEN
      v_stmt = v_stmt || ' MAXVALUE ' || trg_seq_rec.sequ_max_val;
    END IF;
    IF ref_seq_rec.sequ_cache_val <> trg_seq_rec.sequ_cache_val THEN
      v_stmt = v_stmt || ' CACHE ' || trg_seq_rec.sequ_cache_val;
    END IF;
    IF ref_seq_rec.sequ_is_cycled <> trg_seq_rec.sequ_is_cycled THEN
      IF trg_seq_rec.sequ_is_cycled = 'f' THEN
        v_stmt = v_stmt || ' NO ';
      END IF;
      v_stmt = v_stmt || ' CYCLE ';
    END IF;
--
    RETURN v_stmt;
  END;
$_build_alter_seq$;

CREATE OR REPLACE FUNCTION emaj._gen_sql_seq(r_rel emaj.emaj_relation, p_firstMarkTimeId BIGINT, p_lastMarkTimeId BIGINT, p_nbSeq BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS
$_gen_sql_seq$
-- This function generates a SQL command to set the final characteristics of a sequence.
-- The command is stored into a temporary table created by the _gen_sql_groups() calling function.
-- Input: row from emaj_relation corresponding to the appplication sequence to proccess,
--        the time id at requested start and end marks,
--        the number of already processed sequences
-- Output: number of generated SQL statements (0 or 1)
  DECLARE
    v_endTimeId              BIGINT;
    v_rqSeq                  TEXT;
    ref_seq_rec              emaj.emaj_sequence%ROWTYPE;
    trg_seq_rec              emaj.emaj_sequence%ROWTYPE;
  BEGIN
-- Get the sequence characteristics at start mark.
    SELECT *
      INTO ref_seq_rec
      FROM emaj.emaj_sequence
      WHERE sequ_schema = r_rel.rel_schema
        AND sequ_name = r_rel.rel_tblseq
        AND sequ_time_id = p_firstMarkTimeId;
-- Get the sequence characteristics at end mark or the current state.
    IF p_lastMarkTimeId IS NULL AND upper_inf(r_rel.rel_time_range) THEN
-- No supplied last mark and the sequence currently belongs to its group, so get the current sequence characteritics.
    SELECT *
      INTO trg_seq_rec
      FROM emaj._get_current_sequence_state(r_rel.rel_schema, r_rel.rel_tblseq, NULL);
    ELSE
-- A last mark is supplied, or the sequence does not belong to its groupe anymore, so get the sequence characteristics
-- from the emaj_sequence table.
      v_endTimeId = CASE WHEN upper_inf(r_rel.rel_time_range) OR p_lastMarkTimeId < upper(r_rel.rel_time_range)
                           THEN p_lastMarkTimeId
                         ELSE upper(r_rel.rel_time_range) END;
      SELECT *
        INTO trg_seq_rec
        FROM emaj.emaj_sequence
        WHERE sequ_schema = r_rel.rel_schema
          AND sequ_name = r_rel.rel_tblseq
          AND sequ_time_id = v_endTimeId;
    END IF;
-- Build the ALTER SEQUENCE clause.
    SELECT emaj._build_alter_seq(ref_seq_rec, trg_seq_rec) INTO v_rqSeq;
-- Insert into the temp table and return 1 if at least 1 characteristic needs to be changed.
    IF v_rqSeq <> '' THEN
      v_rqSeq = 'ALTER SEQUENCE ' || quote_ident(r_rel.rel_schema) || '.' || quote_ident(r_rel.rel_tblseq) || ' ' || v_rqSeq || ';';
      EXECUTE 'INSERT INTO emaj_temp_script '
              '  SELECT NULL, -1 * $1, txid_current(), $2'
        USING p_nbSeq + 1, v_rqSeq;
      RETURN 1;
    END IF;
-- Otherwise return 0.
    RETURN 0;
  END;
$_gen_sql_seq$;

CREATE OR REPLACE FUNCTION emaj._get_current_sequence_state(p_schema TEXT, p_sequence TEXT, p_timeId BIGINT)
RETURNS emaj.emaj_sequence LANGUAGE plpgsql AS
$_get_current_sequence_state$
-- The function returns the current state of a single sequence.
-- Input: schema and sequence name,
--        time_id to set the sequ_time_id
-- Output: an emaj_sequence record
  DECLARE
    r_sequ                   emaj.emaj_sequence%ROWTYPE;
  BEGIN
    EXECUTE format('SELECT schemaname, sequencename, %s, rel.last_value, start_value, increment_by, max_value, min_value, cache_size,'
                   '       cycle, rel.is_called FROM %I.%I rel, pg_catalog.pg_sequences '
                   '  WHERE schemaname = %L AND sequencename = %L',
                   coalesce(p_timeId, 0), p_schema, p_sequence, p_schema, p_sequence)
      INTO STRICT r_sequ;
    RETURN r_sequ;
  END;
$_get_current_sequence_state$;

CREATE OR REPLACE FUNCTION emaj._verify_groups(p_groups TEXT[], p_onErrorStop BOOLEAN)
RETURNS SETOF emaj._verify_groups_type LANGUAGE plpgsql AS
$_verify_groups$
-- The function verifies the consistency of a tables groups array.
-- Input: - tables groups array,
--        - a boolean indicating whether the function has to raise an exception in case of detected unconsistency.
-- If onErrorStop boolean is false, it returns a set of _verify_groups_type records, one row per detected unconsistency, including
-- the faulting schema and table or sequence names and a detailed message.
-- If no error is detected, no row is returned.
-- This function may be directly called by the Emaj_web client.
  DECLARE
    v_hint                   CONSTANT TEXT = 'You may use "SELECT * FROM emaj.emaj_verify_all()" to look for other issues.';
    r_object                 RECORD;
  BEGIN
-- Note that there is no check that the supplied groups exist. This has already been done by all calling functions.
-- Let's start with some global checks that always raise an exception if an issue is detected.
-- Look for groups unconsistency.
-- Unlike emaj_verify_all(), there is no direct check that application schemas exist.
-- Check that all application relations referenced in the emaj_relation table still exist.
    FOR r_object IN
      SELECT t.rel_schema, t.rel_tblseq, r.rel_group,
             'In group "' || r.rel_group || '", the ' ||
               CASE WHEN t.rel_kind = 'r' THEN 'table "' ELSE 'sequence "' END ||
               t.rel_schema || '"."' || t.rel_tblseq || '" does not exist any more.' AS msg
        FROM
          (  SELECT rel_schema, rel_tblseq, rel_kind
               FROM emaj.emaj_relation
               WHERE rel_group = ANY (p_groups)
                 AND upper_inf(rel_time_range)
           EXCEPT                                -- all relations known by postgres
             SELECT nspname, relname, relkind::TEXT
               FROM pg_catalog.pg_class
                    JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
               WHERE relkind IN ('r','S')
          ) AS t, emaj.emaj_relation r         -- join with emaj_relation to get the group name
        WHERE t.rel_schema = r.rel_schema
          AND t.rel_tblseq = r.rel_tblseq
          AND upper_inf(r.rel_time_range)
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (1): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- Check that the log table for all tables referenced in the emaj_relation table still exist.
    FOR r_object IN
      SELECT rel_schema, rel_tblseq, rel_group,
             'In group "' || rel_group || '", the log table "' ||
               rel_log_schema || '"."' || rel_log_table || '" is not found.' AS msg
        FROM emaj.emaj_relation
        WHERE rel_group = ANY (p_groups)
          AND rel_kind = 'r'
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_log_schema
                     AND relname = rel_log_table
                )
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (2): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- Check that the log function for each table referenced in the emaj_relation table still exists.
    FOR r_object IN
                                                  -- the schema and table names are rebuilt from the returned function name
      SELECT rel_schema, rel_tblseq, rel_group,
             'In group "' || rel_group || '", the log function "' || rel_log_schema || '"."' || rel_log_function || '" is not found.'
               AS msg
        FROM emaj.emaj_relation
        WHERE rel_group = ANY (p_groups)
          AND rel_kind = 'r' AND upper_inf(rel_time_range)
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_proc
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = pronamespace)
                   WHERE nspname = rel_log_schema
                     AND proname = rel_log_function
                )
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (3): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- Check that log and truncate triggers for all tables referenced in the emaj_relation table still exist.
--   Start with the log trigger
    FOR r_object IN
      SELECT rel_schema, rel_tblseq, rel_group,
             'In group "' || rel_group || '", the log trigger "emaj_log_trg" on table "' ||
               rel_schema || '"."' || rel_tblseq || '" is not found.' AS msg
        FROM emaj.emaj_relation
        WHERE rel_group = ANY (p_groups)
          AND rel_kind = 'r'
          AND upper_inf(rel_time_range)
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_trigger
                        JOIN pg_catalog.pg_class ON (pg_class.oid = tgrelid)
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                     AND tgname = 'emaj_log_trg'
                )
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (4): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
--   Then the truncate trigger.
    FOR r_object IN
      SELECT rel_schema, rel_tblseq, rel_group,
             'In group "' || rel_group || '", the truncate trigger "emaj_trunc_trg" on table "' ||
             rel_schema || '"."' || rel_tblseq || '" is not found.' AS msg
        FROM emaj.emaj_relation
        WHERE rel_group = ANY (p_groups)
          AND rel_kind = 'r'
          AND upper_inf(rel_time_range)
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_trigger
                        JOIN pg_catalog.pg_class ON (pg_class.oid = tgrelid)
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                     AND tgname = 'emaj_trunc_trg'
                )
      ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (5): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- Check that all log tables have a structure consistent with the application tables they reference
-- (same columns and same formats). It only returns one row per faulting table.
    FOR r_object IN
      WITH cte_app_tables_columns AS                  -- application table's columns
        (SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
           FROM emaj.emaj_relation
                JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
                JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
                JOIN pg_catalog.pg_attribute ON (attrelid = pg_class.oid)
           WHERE attnum > 0
             AND attisdropped = FALSE
             AND rel_group = ANY (p_groups)
             AND rel_kind = 'r'
             AND upper_inf(rel_time_range)
        ),
           cte_log_tables_columns AS                  -- log table's columns
        (SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
           FROM emaj.emaj_relation
                JOIN pg_catalog.pg_class ON (relname = rel_log_table)
                JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_log_schema)
                JOIN pg_catalog.pg_attribute ON (attrelid = pg_class.oid)
            WHERE attnum > 0
              AND NOT attisdropped
              AND attnum < rel_emaj_verb_attnum
              AND rel_group = ANY (p_groups)
              AND rel_kind = 'r'
              AND upper_inf(rel_time_range))
      SELECT DISTINCT rel_schema, rel_tblseq, rel_group,
             'In group "' || rel_group || '", the structure of the application table "' ||
               rel_schema || '"."' || rel_tblseq || '" is not coherent with its log table ("' ||
             rel_log_schema || '"."' || rel_log_table || '").' AS msg
        FROM
          (
            (                                        -- application table's columns
               SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                 FROM cte_app_tables_columns
             EXCEPT                                   -- minus log table's columns
               SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                 FROM cte_log_tables_columns
            )
          UNION
            (                                         -- log table's columns
               SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                 FROM cte_log_tables_columns
             EXCEPT                                    -- minus application table's columns
               SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                 FROM cte_app_tables_columns
            )
          ) AS t
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (6): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- Check that all tables have their primary key if they belong to a rollbackable group.
    FOR r_object IN
      SELECT rel_schema, rel_tblseq, rel_group,
             'In rollbackable group "' || rel_group || '", the table "' ||
             rel_schema || '"."' || rel_tblseq || '" has no primary key any more.' AS msg
        FROM emaj.emaj_relation
             JOIN emaj.emaj_group ON (group_name = rel_group)
        WHERE rel_group = ANY (p_groups)
          AND rel_kind = 'r'
          AND upper_inf(rel_time_range)
          AND group_is_rollbackable
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                        JOIN pg_catalog.pg_constraint ON (connamespace = pg_namespace.oid AND conrelid = pg_class.oid)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                     AND contype = 'p'
                )
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (7): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- For rollbackable groups, check that no table has been altered as UNLOGGED or dropped and recreated as TEMP table after the tables
-- groups creation.
    FOR r_object IN
      SELECT rel_schema, rel_tblseq, rel_group,
             'In rollbackable group "' || rel_group || '", the table "' ||
             rel_schema || '"."' || rel_tblseq || '" is UNLOGGED or TEMP.' AS msg
        FROM emaj.emaj_relation
             JOIN emaj.emaj_group ON (group_name = rel_group)
             JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
             JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
        WHERE rel_group = ANY (p_groups)
          AND rel_kind = 'r'
          AND upper_inf(rel_time_range)
          AND group_is_rollbackable
          AND relpersistence <> 'p'
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (8): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- For rollbackable groups, with PG 11-, check that no table has been altered as WITH OIDS after tables groups creation.
    IF emaj._pg_version_num() < 120000 THEN
      FOR r_object IN
        SELECT rel_schema, rel_tblseq, rel_group,
               'In rollbackable group "' || rel_group || '", the table "' ||
               rel_schema || '"."' || rel_tblseq || '" is declared WITH OIDS.' AS msg
          FROM emaj.emaj_relation
               JOIN emaj.emaj_group ON (group_name = rel_group)
               JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
               JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
          WHERE rel_group = ANY (p_groups)
            AND rel_kind = 'r'
            AND upper_inf(rel_time_range)
            AND group_is_rollbackable
            AND relhasoids
          ORDER BY 1,2,3
      LOOP
        IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (9): % %',r_object.msg,v_hint; END IF;
        RETURN NEXT r_object;
      END LOOP;
    END IF;
-- Check that the primary key structure of all tables belonging to rollbackable groups is unchanged.
    FOR r_object IN
      SELECT rel_schema, rel_tblseq, rel_group,
             'In rollbackable group "' || rel_group || '", the primary key of the table "' ||
             rel_schema || '"."' || rel_tblseq || '" has changed (' ||
             rel_sql_rlbk_pk_columns || ' => ' || current_pk_columns || ').' AS msg
        FROM
          (SELECT rel_schema, rel_tblseq, rel_group, rel_sql_rlbk_pk_columns,
                 string_agg(quote_ident(attname), ',' ORDER BY attnum) AS current_pk_columns
             FROM emaj.emaj_relation
                  JOIN emaj.emaj_group ON (group_name = rel_group)
                  JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
                  JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
                  JOIN pg_catalog.pg_index ON (indrelid = pg_class.oid)
                  JOIN pg_catalog.pg_attribute ON (pg_attribute.attrelid = pg_index.indrelid)
             WHERE rel_group = ANY (p_groups)
               AND rel_kind = 'r'
               AND upper_inf(rel_time_range)
               AND group_is_rollbackable
               AND attnum = ANY (indkey)
               AND indisprimary
               AND attnum > 0
               AND NOT attisdropped
             GROUP BY rel_schema, rel_tblseq, rel_group, rel_sql_rlbk_pk_columns
          ) AS t
        WHERE rel_sql_rlbk_pk_columns <> current_pk_columns
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (10): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
-- Check that all log tables have the 6 required technical columns. It only returns one row per faulting table.
    FOR r_object IN
      SELECT DISTINCT rel_schema, rel_tblseq, rel_group,
             'In group "' || rel_group || '", the log table "' ||
             rel_log_schema || '"."' || rel_log_table || '" miss some technical columns (' ||
             string_agg(attname,', ') || ').' AS msg
        FROM
          (  SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname
               FROM emaj.emaj_relation,
                   (VALUES ('emaj_verb'), ('emaj_tuple'), ('emaj_gid'), ('emaj_changed'), ('emaj_txid'), ('emaj_user')) AS t(attname)
               WHERE rel_group = ANY (p_groups)
                 AND rel_kind = 'r'
                 AND upper_inf(rel_time_range)
                 AND EXISTS
                       (SELECT NULL
                          FROM pg_catalog.pg_class
                               JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                          WHERE nspname = rel_log_schema
                            AND relname = rel_log_table
                       )
           EXCEPT
             SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname
               FROM emaj.emaj_relation
                    JOIN pg_catalog.pg_class ON (relname = rel_log_table)
                    JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_log_schema)
                    JOIN pg_catalog.pg_attribute ON (attrelid = pg_class.oid)
               WHERE rel_group = ANY (p_groups)
                 AND rel_kind = 'r'
                 AND upper_inf(rel_time_range)
                 AND attnum > 0
                 AND attisdropped = FALSE
                 AND attname IN ('emaj_verb', 'emaj_tuple', 'emaj_gid', 'emaj_changed', 'emaj_txid', 'emaj_user')
          ) AS t2
        GROUP BY rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table
        ORDER BY 1,2,3
    LOOP
      IF p_onErrorStop THEN RAISE EXCEPTION '_verify_groups (11): % %',r_object.msg,v_hint; END IF;
      RETURN NEXT r_object;
    END LOOP;
--
    RETURN;
  END;
$_verify_groups$;

CREATE OR REPLACE FUNCTION emaj._rlbk_init(p_groupNames TEXT[], p_mark TEXT, p_isLoggedRlbk BOOLEAN, p_nbSession INT, p_multiGroup BOOLEAN,
                                           p_isAlterGroupAllowed BOOLEAN DEFAULT FALSE)
RETURNS INT LANGUAGE plpgsql AS
$_rlbk_init$
-- This is the first step of a rollback group processing.
-- It tests the environment, the supplied parameters and the foreign key constraints.
-- By calling the _rlbk_planning() function, it defines the different elementary steps needed for the operation,
-- and spread the load on the requested number of sessions.
-- It returns a rollback id that will be needed by next steps (or NULL if there are some NULL input).
-- This function may be directly called by the Emaj_web client.
  DECLARE
    v_markName               TEXT;
    v_markTimeId             BIGINT;
    v_markTimestamp          TIMESTAMPTZ;
    v_nbTblInGroups          INT;
    v_nbSeqInGroups          INT;
    v_dbLinkCnxStatus        INT;
    v_isDblinkUsed           BOOLEAN;
    v_dbLinkSchema           TEXT;
    v_effNbTable             INT;
    v_histId                 BIGINT;
    v_stmt                   TEXT;
    v_rlbkId                 INT;
  BEGIN
-- Check supplied group names and mark parameters.
    SELECT emaj._rlbk_check(p_groupNames, p_mark, p_isAlterGroupAllowed, FALSE) INTO v_markName;
    IF v_markName IS NOT NULL THEN
-- Check that no group is damaged.
      PERFORM 0
        FROM emaj._verify_groups(p_groupNames, TRUE);
-- Get the time stamp id and its clock timestamp for the first group (as we know this time stamp is the same for all groups of the array).
      SELECT time_id, time_clock_timestamp INTO v_markTimeId, v_markTimestamp
        FROM emaj.emaj_mark
             JOIN emaj.emaj_time_stamp ON (time_id = mark_time_id)
        WHERE mark_group = p_groupNames[1]
          AND mark_name = v_markName;
-- Insert a BEGIN event into the history.
      INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
        VALUES (CASE WHEN p_multiGroup THEN 'ROLLBACK_GROUPS' ELSE 'ROLLBACK_GROUP' END, 'BEGIN',
                array_to_string(p_groupNames,','),
                CASE WHEN p_isLoggedRlbk THEN 'Logged' ELSE 'Unlogged' END || ' rollback to mark ' || v_markName
                || ' [' || v_markTimestamp || ']'
               )
        RETURNING hist_id INTO v_histId;
-- Get the total number of tables and sequences for these groups.
      SELECT sum(group_nb_table), sum(group_nb_sequence) INTO v_nbTblInGroups, v_nbSeqInGroups
        FROM emaj.emaj_group
        WHERE group_name = ANY (p_groupNames) ;
-- First try to open a dblink connection.
      SELECT p_status, (p_status >= 0), CASE WHEN p_status >= 0 THEN p_schema ELSE NULL END
        INTO v_dbLinkCnxStatus, v_isDblinkUsed, v_dbLinkSchema
        FROM emaj._dblink_open_cnx('rlbk#1');
-- For parallel rollback (i.e. when nb sessions > 1), the dblink connection must be ok.
      IF p_nbSession > 1 AND NOT v_isDblinkUsed THEN
        RAISE EXCEPTION '_rlbk_init: Cannot use several sessions without dblink connection capability. (Status of the dblink'
                        ' connection attempt = % - see E-Maj documentation)',
          v_dbLinkCnxStatus;
      END IF;
-- Create the row representing the rollback event in the emaj_rlbk table and get the rollback id back.
      v_stmt = 'INSERT INTO emaj.emaj_rlbk (rlbk_groups, rlbk_mark, rlbk_mark_time_id, rlbk_is_logged, rlbk_is_alter_group_allowed, ' ||
               'rlbk_nb_session, rlbk_nb_table, rlbk_nb_sequence, rlbk_status, rlbk_begin_hist_id, ' ||
               'rlbk_dblink_schema, rlbk_is_dblink_used) ' ||
               'VALUES (' || quote_literal(p_groupNames) || ',' || quote_literal(v_markName) || ',' ||
               v_markTimeId || ',' || p_isLoggedRlbk || ',' || quote_nullable(p_isAlterGroupAllowed) || ',' ||
               p_nbSession || ',' || v_nbTblInGroups || ',' || v_nbSeqInGroups || ', ''PLANNING'',' || v_histId || ',' ||
               quote_nullable(v_dbLinkSchema) || ',' || v_isDblinkUsed || ') RETURNING rlbk_id';
      SELECT emaj._dblink_sql_exec('rlbk#1', v_stmt, v_dblinkSchema) INTO v_rlbkId;
-- Create the session row the emaj_rlbk_session table.
      v_stmt = 'INSERT INTO emaj.emaj_rlbk_session (rlbs_rlbk_id, rlbs_session, rlbs_txid, rlbs_start_datetime) ' ||
               'VALUES (' || v_rlbkId || ', 1, ' || txid_current() || ',' ||
                quote_literal(clock_timestamp()) || ') RETURNING 1';
      PERFORM emaj._dblink_sql_exec('rlbk#1', v_stmt, v_dblinkSchema);
-- Call the rollback planning function to define all the elementary steps to perform, compute their estimated duration
-- and spread the elementary steps among sessions.
      v_stmt = 'SELECT emaj._rlbk_planning(' || v_rlbkId || ')';
      SELECT emaj._dblink_sql_exec('rlbk#1', v_stmt, v_dblinkSchema) INTO v_effNbTable;
-- Update the emaj_rlbk table to set the real number of tables to process and adjust the rollback status.
      v_stmt = 'UPDATE emaj.emaj_rlbk SET rlbk_eff_nb_table = ' || v_effNbTable ||
               ', rlbk_status = ''LOCKING'' ' || ' WHERE rlbk_id = ' || v_rlbkId || ' RETURNING 1';
      PERFORM emaj._dblink_sql_exec('rlbk#1', v_stmt, v_dblinkSchema);
    END IF;
--
    RETURN v_rlbkId;
  END;
$_rlbk_init$;

CREATE OR REPLACE FUNCTION emaj._rlbk_planning(p_rlbkId INT)
RETURNS INT LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
$_rlbk_planning$
-- This function builds the rollback steps for a rollback operation.
-- It stores the result into the emaj_rlbk_plan table.
-- The function returns the effective number of tables to process.
-- It is called to perform a rollback operation. It is also called to simulate a rollback operation and get its duration estime.
-- It is called in an autonomous dblink transaction, if possible.
-- The function is defined as SECURITY DEFINER so that emaj_viewer role can write into rollback tables, when estimating the rollback
--   duration, without having specific privileges on them to do it.
  DECLARE
    v_groupNames             TEXT[];
    v_mark                   TEXT;
    v_isLoggedRlbk           BOOLEAN;
    v_nbSession              INT;
    v_ctrlStepName           emaj._rlbk_step_enum;
    v_markTimeId             BIGINT;
    v_avg_row_rlbk           INTERVAL;
    v_avg_row_del_log        INTERVAL;
    v_avg_fkey_check         INTERVAL;
    v_fixed_step_rlbk        INTERVAL;
    v_fixed_dblink_rlbk      INTERVAL;
    v_effNbTable             INT;
    v_isEmajExtension        BOOLEAN;
    v_batchNumber            INT;
    v_checks                 INT;
    v_estimDuration          INTERVAL;
    v_estimMethod            INT;
    v_estimDropFkDuration    INTERVAL;
    v_estimDropFkMethod      INT;
    v_estimSetFkDefDuration  INTERVAL;
    v_estimSetFkDefMethod    INT;
    v_sessionLoad            INTERVAL[];
    v_minSession             INT;
    v_minDuration            INTERVAL;
    v_nbStep                 INT;
    r_tbl                    RECORD;
    r_fk                     RECORD;
    r_batch                  RECORD;
  BEGIN
-- Get the rollback characteristics for the emaj_rlbk event.
    SELECT rlbk_groups, rlbk_mark, rlbk_is_logged, rlbk_nb_session,
           CASE WHEN rlbk_is_dblink_used THEN 'CTRL+DBLINK'::emaj._rlbk_step_enum ELSE 'CTRL-DBLINK'::emaj._rlbk_step_enum END
      INTO v_groupNames, v_mark, v_isLoggedRlbk, v_nbSession, v_ctrlStepName
      FROM emaj.emaj_rlbk
      WHERE rlbk_id = p_rlbkId;
-- Get some mark attributes from emaj_mark.
    SELECT mark_time_id INTO v_markTimeId
      FROM emaj.emaj_mark
      WHERE mark_group = v_groupNames[1]
        AND mark_name = v_mark;
-- Get all duration parameters that will be needed later from the emaj_param table, or get default values for rows
-- that are not present in emaj_param table.
    SELECT coalesce ((SELECT param_value_interval FROM emaj.emaj_param
                        WHERE param_key = 'avg_row_rollback_duration'),'100 microsecond'::INTERVAL),
           coalesce ((SELECT param_value_interval FROM emaj.emaj_param
                        WHERE param_key = 'avg_row_delete_log_duration'),'10 microsecond'::INTERVAL),
           coalesce ((SELECT param_value_interval FROM emaj.emaj_param
                        WHERE param_key = 'avg_fkey_check_duration'),'5 microsecond'::INTERVAL),
           coalesce ((SELECT param_value_interval FROM emaj.emaj_param
                        WHERE param_key = 'fixed_step_rollback_duration'),'2.5 millisecond'::INTERVAL),
           coalesce ((SELECT param_value_interval FROM emaj.emaj_param
                        WHERE param_key = 'fixed_dblink_rollback_duration'),'4 millisecond'::INTERVAL)
           INTO v_avg_row_rlbk, v_avg_row_del_log, v_avg_fkey_check, v_fixed_step_rlbk, v_fixed_dblink_rlbk;
-- Insert into emaj_rlbk_plan a row per table currently belonging to the tables groups to process.
    INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_is_repl_role_replica)
      SELECT p_rlbkId, 'LOCK_TABLE', rel_schema, rel_tblseq, '', FALSE
        FROM emaj.emaj_relation
        WHERE upper_inf(rel_time_range)
          AND rel_group = ANY(v_groupNames)
          AND rel_kind = 'r';
-- Insert into emaj_rlbk_plan a row per table to effectively rollback.
-- The numbers of log rows is computed using the _log_stat_tbl() function.
-- A final check will be performed after tables will be locked to be sure no new table will have been updated.
     INSERT INTO emaj.emaj_rlbk_plan
            (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_is_repl_role_replica, rlbp_target_time_id,
             rlbp_estimated_quantity)
      SELECT p_rlbkId, 'RLBK_TABLE', rel_schema, rel_tblseq, '', FALSE, greatest(v_markTimeId, lower(rel_time_range)),
             emaj._log_stat_tbl(t, greatest(v_markTimeId, lower(rel_time_range)), NULL)
        FROM
          (SELECT *
             FROM emaj.emaj_relation
             WHERE upper_inf(rel_time_range)
               AND rel_group = ANY (v_groupNames)
               AND rel_kind = 'r'
          ) AS t
        WHERE emaj._log_stat_tbl(t, greatest(v_markTimeId, lower(rel_time_range)), NULL) > 0;
      GET DIAGNOSTICS v_effNbTable = ROW_COUNT;
-- For tables having all foreign keys linking tables in the rolled back groups, set the rlbp_is_repl_role_replica flag to TRUE.
-- This only concerns emaj installed as an extension because one needs to be sure that the the _rlbk_tbl() function is executed with a
-- superuser role (this is needed to set the session_replication_role to 'replica').
      v_isEmajExtension = EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'emaj');
      IF v_isEmajExtension AND v_effNbTable > 0 THEN
        WITH fkeys AS (
            -- the foreign keys belonging to tables to rollback
            SELECT rlbp_schema, rlbp_table, c.conname, nf.nspname, tf.relname, rel_group,
                   rel_group = ANY (v_groupNames) AS are_both_tables_in_groups
              FROM emaj.emaj_rlbk_plan,
                   pg_catalog.pg_constraint c
                   JOIN pg_catalog.pg_class t ON (t.oid = c.conrelid)
                   JOIN pg_catalog.pg_namespace n ON (n.oid = t.relnamespace)
                   JOIN pg_catalog.pg_class tf ON (tf.oid = c.confrelid)
                   JOIN pg_catalog.pg_namespace nf ON (nf.oid = tf.relnamespace)
                   LEFT OUTER JOIN emaj.emaj_relation ON (rel_schema = nf.nspname AND rel_tblseq = tf.relname
                                                          AND upper_inf(rel_time_range))
              WHERE rlbp_rlbk_id = p_rlbkId                               -- The RLBK_TABLE steps for this rollback operation
                AND rlbp_step = 'RLBK_TABLE'
                AND contype = 'f'                                         -- FK constraints
                AND tf.relkind = 'r'                                      -- only constraints referencing true tables, ie. excluding
                                                                          --   partitionned tables
                AND t.relname = rlbp_table
                AND n.nspname = rlbp_schema
          UNION
            -- the foreign keys referencing tables to rollback
            SELECT rlbp_schema, rlbp_table, c.conname, n.nspname, t.relname, rel_group,
                   rel_group = ANY (v_groupNames) AS are_both_tables_in_groups
              FROM emaj.emaj_rlbk_plan,
                   pg_catalog.pg_constraint c
                   JOIN pg_catalog.pg_class t ON (t.oid = c.conrelid)
                   JOIN pg_catalog.pg_namespace n ON (n.oid = t.relnamespace)
                   JOIN pg_catalog.pg_class tf ON (tf.oid = c.confrelid)
                   JOIN pg_catalog.pg_namespace nf ON (nf.oid = tf.relnamespace)
                   LEFT OUTER JOIN emaj.emaj_relation ON (rel_schema = n.nspname AND rel_tblseq = t.relname
                                                          AND upper_inf(rel_time_range))
              WHERE rlbp_rlbk_id = p_rlbkId                               -- The RLBK_TABLE steps for this rollback operation
                AND rlbp_step = 'RLBK_TABLE'
                AND contype = 'f'                                         -- FK constraints
                AND t.relkind = 'r'                                       -- only constraints referenced by true tables, ie. excluding
                                                                          --   partitionned tables
                AND tf.relname = rlbp_table
                AND nf.nspname = rlbp_schema
        ), fkeys_agg AS (
          -- aggregated foreign keys by tables to rollback
          SELECT rlbp_schema, rlbp_table,
                 count(*) AS nb_all_fk, count(*) FILTER (WHERE are_both_tables_in_groups) AS nb_fk_groups_ok
            FROM fkeys
            GROUP BY 1,2
        )
        UPDATE emaj.emaj_rlbk_plan
          SET rlbp_is_repl_role_replica = TRUE
          FROM fkeys_agg
          WHERE rlbp_rlbk_id = p_rlbkId                                    -- The RLBK_TABLE steps for this rollback operation
            AND rlbp_step IN ('RLBK_TABLE', 'LOCK_TABLE')
            AND emaj_rlbk_plan.rlbp_table = fkeys_agg.rlbp_table
            AND emaj_rlbk_plan.rlbp_schema = fkeys_agg.rlbp_schema
            AND nb_all_fk = nb_fk_groups_ok                                -- if all fkeys are linking tables in the rolled back groups
        ;
      END IF;
--
-- Group tables into batchs to process all tables linked by foreign keys as a batch.
--
    v_batchNumber = 1;
-- Allocate tables with rows to rollback to batch number starting with the heaviest to rollback tables as reported by the
-- emaj_log_stat_group() function.
    FOR r_tbl IN
      SELECT rlbp_schema, rlbp_table, rlbp_is_repl_role_replica
        FROM emaj.emaj_rlbk_plan
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'RLBK_TABLE'
        ORDER BY rlbp_estimated_quantity DESC, rlbp_schema, rlbp_table
    LOOP
-- If the table is not already allocated to a batch number (it may have been already allocated because of a fkey link).
      IF EXISTS
          (SELECT 0
             FROM emaj.emaj_rlbk_plan
             WHERE rlbp_rlbk_id = p_rlbkId
               AND rlbp_step = 'RLBK_TABLE'
               AND rlbp_schema = r_tbl.rlbp_schema
               AND rlbp_table = r_tbl.rlbp_table
               AND rlbp_batch_number IS NULL
          ) THEN
-- Allocate the table to the batch number, with all other tables linked by foreign key constraints.
        PERFORM emaj._rlbk_set_batch_number(p_rlbkId, v_batchNumber, r_tbl.rlbp_schema, r_tbl.rlbp_table, r_tbl.rlbp_is_repl_role_replica);
        v_batchNumber = v_batchNumber + 1;
      END IF;
    END LOOP;
--
-- If unlogged rollback, register into emaj_rlbk_plan "disable log triggers", "deletes from log tables"
-- and "enable log trigger" steps.
--
    IF NOT v_isLoggedRlbk THEN
-- Compute the cost for each DIS_LOG_TRG step.
      SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
        FROM emaj._estimate_rlbk_step_duration('DIS_LOG_TRG', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
-- Insert all DIS_LOG_TRG steps.
      INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number,
                                       rlbp_estimated_duration, rlbp_estimate_method)
        SELECT p_rlbkId, 'DIS_LOG_TRG', rlbp_schema, rlbp_table, '', rlbp_batch_number,
               v_estimDuration, v_estimMethod
          FROM emaj.emaj_rlbk_plan
          WHERE rlbp_rlbk_id = p_rlbkId
            AND rlbp_step = 'RLBK_TABLE';
-- Insert all DELETE_LOG steps. But the duration estimates will be computed later.
-- The estimated number of log rows to delete is set to the estimated number of updates. This is underestimated in particular when
-- SQL UPDATES are logged. But the collected statistics used for duration estimates are also based on the estimated number of updates.
      INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_target_time_id,
                                       rlbp_batch_number, rlbp_estimated_quantity)
        SELECT p_rlbkId, 'DELETE_LOG', rlbp_schema, rlbp_table, '', rlbp_target_time_id, rlbp_batch_number, rlbp_estimated_quantity
          FROM emaj.emaj_rlbk_plan
          WHERE rlbp_rlbk_id = p_rlbkId
            AND rlbp_step = 'RLBK_TABLE';
-- Compute the cost for each ENA_LOG_TRG step.
      SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
        FROM emaj._estimate_rlbk_step_duration('ENA_LOG_TRG', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
-- Insert all ENA_LOG_TRG steps.
      INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number,
                                       rlbp_estimated_duration, rlbp_estimate_method)
        SELECT p_rlbkId, 'ENA_LOG_TRG', rlbp_schema, rlbp_table, '', rlbp_batch_number, v_estimDuration, v_estimMethod
          FROM emaj.emaj_rlbk_plan
          WHERE rlbp_rlbk_id = p_rlbkId
            AND rlbp_step = 'RLBK_TABLE';
    END IF;
--
-- Process application triggers to temporarily set as ALWAYS triggers.
-- This concerns triggers that must be kept enabled during the rollback processing but the rollback function for its table is executed
-- with session_replication_role = replica.
--
-- Compute the cost for each SET_ALWAYS_APP_TRG step.
    SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
      FROM emaj._estimate_rlbk_step_duration('SET_ALWAYS_APP_TRG', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
-- Insert all SET_ALWAYS_APP_TRG steps.
    INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number,
                                     rlbp_estimated_duration, rlbp_estimate_method)
      SELECT p_rlbkId, 'SET_ALWAYS_APP_TRG', rlbp_schema, rlbp_table, tgname, rlbp_batch_number, v_estimDuration, v_estimMethod
        FROM emaj.emaj_rlbk_plan
             JOIN pg_catalog.pg_class ON (relname = rlbp_table)
             JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rlbp_schema)
             JOIN pg_catalog.pg_trigger ON (tgrelid = pg_class.oid)
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'RLBK_TABLE'                               -- rollback step
          AND rlbp_is_repl_role_replica                              -- ... in session_replication_role = replica
          AND NOT tgisinternal                                       -- application triggers only
          AND tgname NOT IN ('emaj_trunc_trg','emaj_log_trg')
          AND tgenabled = 'O'                                        -- ... enabled in local mode
          AND EXISTS                                                 -- ... and to be kept enabled
                (SELECT 0
                   FROM emaj.emaj_relation
                   WHERE rel_schema = rlbp_schema
                     AND rel_tblseq = rlbp_table
                     AND upper_inf(rel_time_range)
                     AND tgname = ANY (rel_ignored_triggers)
                );
-- Compute the cost for each SET_LOCAL_APP_TRG step.
    SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
      FROM emaj._estimate_rlbk_step_duration('SET_LOCAL_APP_TRG', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
-- Insert all SET_LOCAL_APP_TRG steps
    INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object,
                                     rlbp_batch_number, rlbp_estimated_duration, rlbp_estimate_method)
      SELECT p_rlbkId, 'SET_LOCAL_APP_TRG', rlbp_schema, rlbp_table, rlbp_object,
             rlbp_batch_number, v_estimDuration, v_estimMethod
        FROM emaj.emaj_rlbk_plan
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'SET_ALWAYS_APP_TRG';
--
-- Process application triggers to disable and re-enable.
-- This concerns triggers that must be disabled during the rollback processing and the rollback function for its table is not executed
-- with session_replication_role = replica.
--
-- Compute the cost for each DIS_APP_TRG step.
    SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
      FROM emaj._estimate_rlbk_step_duration('DIS_APP_TRG', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
-- Insert all DIS_APP_TRG steps.
    INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number,
                                     rlbp_estimated_duration, rlbp_estimate_method)
      SELECT p_rlbkId, 'DIS_APP_TRG', rlbp_schema, rlbp_table, tgname, rlbp_batch_number, v_estimDuration, v_estimMethod
        FROM emaj.emaj_rlbk_plan
             JOIN pg_catalog.pg_class ON (relname = rlbp_table)
             JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rlbp_schema)
             JOIN pg_catalog.pg_trigger ON (tgrelid = pg_class.oid)
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'RLBK_TABLE'                               -- rollback step
          AND NOT tgisinternal                                       -- application triggers only
          AND tgname NOT IN ('emaj_trunc_trg','emaj_log_trg')
          AND (tgenabled IN ('A', 'R')                               -- enabled ALWAYS or REPLICA triggers
              OR (tgenabled = 'O' AND NOT rlbp_is_repl_role_replica) -- or enabled ORIGIN triggers for rollbacks not processed
              )                                                      --   in session_replication_role = replica)
          AND NOT EXISTS                                             -- ... that must be disabled
                (SELECT 0
                   FROM emaj.emaj_relation
                   WHERE rel_schema = rlbp_schema
                     AND rel_tblseq = rlbp_table
                     AND upper_inf(rel_time_range)
                     AND tgname = ANY (rel_ignored_triggers)
                );
-- Compute the cost for each ENA_APP_TRG step.
      SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
        FROM emaj._estimate_rlbk_step_duration('ENA_APP_TRG', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
-- Insert all ENA_APP_TRG steps.
    INSERT INTO emaj.emaj_rlbk_plan (rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object,
                                     rlbp_app_trg_type,
                                     rlbp_batch_number, rlbp_estimated_duration, rlbp_estimate_method)
      SELECT p_rlbkId, 'ENA_APP_TRG', rlbp_schema, rlbp_table, rlbp_object,
             CASE tgenabled WHEN 'A' THEN 'ALWAYS' WHEN 'R' THEN 'REPLICA' ELSE '' END,
             rlbp_batch_number, v_estimDuration, v_estimMethod
        FROM emaj.emaj_rlbk_plan
             JOIN pg_catalog.pg_class ON (relname = rlbp_table)
             JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rlbp_schema)
             JOIN pg_catalog.pg_trigger ON (tgrelid = pg_class.oid AND tgname = rlbp_object)
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'DIS_APP_TRG';
--
-- Process foreign key to define which action to perform on them
--
-- First compute the fixed duration estimates for each 'DROP_FK' and 'SET_FK_DEF' steps.
    SELECT p_estimateMethod, p_estimatedDuration INTO v_estimDropFkMethod, v_estimDropFkDuration
      FROM emaj._estimate_rlbk_step_duration('DROP_FK', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
    SELECT p_estimateMethod, p_estimatedDuration INTO v_estimSetFkDefMethod, v_estimSetFkDefDuration
      FROM emaj._estimate_rlbk_step_duration('SET_FK_DEF', NULL, NULL, NULL, NULL, v_fixed_step_rlbk, NULL);
-- Select all foreign keys belonging to or referencing the tables to process.
    FOR r_fk IN
        SELECT c.oid AS conoid, c.conname, n.nspname, t.relname, t.reltuples, pg_get_constraintdef(c.oid) AS def, c.condeferrable,
               c.condeferred, c.confupdtype, c.confdeltype, r.rlbp_batch_number
          FROM emaj.emaj_rlbk_plan r
               JOIN pg_catalog.pg_class t ON (t.relname = r.rlbp_table)
               JOIN pg_catalog.pg_namespace n ON (t.relnamespace  = n.oid AND n.nspname = r.rlbp_schema)
               JOIN pg_catalog.pg_constraint c ON (c.conrelid = t.oid)
          WHERE c.contype = 'f'                                            -- FK constraints only
            AND rlbp_rlbk_id = p_rlbkId
            AND rlbp_step = 'RLBK_TABLE'                                   -- Tables to rollback
            AND NOT rlbp_is_repl_role_replica                              -- ... not in a session_replication_role = replica
      UNION
        SELECT c.oid AS conoid, c.conname, n.nspname, t.relname, t.reltuples, pg_get_constraintdef(c.oid) AS def, c.condeferrable,
               c.condeferred, c.confupdtype, c.confdeltype, r.rlbp_batch_number
          FROM emaj.emaj_rlbk_plan r
               JOIN pg_catalog.pg_class rt ON (rt.relname = r.rlbp_table)
               JOIN pg_catalog.pg_namespace rn ON (rn.oid = rt.relnamespace AND rn.nspname = r.rlbp_schema)
               JOIN pg_catalog.pg_constraint c ON (c.confrelid = rt.oid)
               JOIN pg_catalog.pg_class t ON (t.oid = c.conrelid)
               JOIN pg_catalog.pg_namespace n ON (n.oid = t.relnamespace)
          WHERE c.contype = 'f'                                            -- FK constraints only
            AND rlbp_rlbk_id = p_rlbkId
            AND rlbp_step = 'RLBK_TABLE'                                   -- Tables to rollback
            AND NOT rlbp_is_repl_role_replica                              -- ... not in a session_replication_role = replica
          ORDER BY nspname, relname, conname
    LOOP
-- Depending on the foreign key characteristics, record as 'to be dropped' or 'to be set deferred' or 'to just be reset immediate'.
      IF NOT r_fk.condeferrable OR r_fk.confupdtype <> 'a' OR r_fk.confdeltype <> 'a' THEN
-- Non deferrable fkeys and deferrable fkeys with an action for UPDATE or DELETE other than 'no action' need to be dropped.
        INSERT INTO emaj.emaj_rlbk_plan (
          rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number,
          rlbp_estimated_duration, rlbp_estimate_method
          ) VALUES (
          p_rlbkId, 'DROP_FK', r_fk.nspname, r_fk.relname, r_fk.conname, r_fk.rlbp_batch_number,
          v_estimDropFkDuration, v_estimDropFkMethod
          );
        INSERT INTO emaj.emaj_rlbk_plan (
          rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number, rlbp_object_def, rlbp_estimated_quantity
          ) VALUES (
          p_rlbkId, 'ADD_FK', r_fk.nspname, r_fk.relname, r_fk.conname, r_fk.rlbp_batch_number, r_fk.def, r_fk.reltuples
          );
      ELSE
-- Other deferrable but not deferred fkeys need to be set deferred.
        IF NOT r_fk.condeferred THEN
          INSERT INTO emaj.emaj_rlbk_plan (
            rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number,
            rlbp_estimated_duration, rlbp_estimate_method
            ) VALUES (
            p_rlbkId, 'SET_FK_DEF', r_fk.nspname, r_fk.relname, r_fk.conname, r_fk.rlbp_batch_number,
            v_estimSetFkDefDuration, v_estimSetFkDefMethod
            );
        END IF;
-- Deferrable fkeys are recorded as 'to be set immediate at the end of the rollback operation'.
-- Compute the number of fkey values to check at set immediate time.
        SELECT (coalesce(
-- Get the number of rolled back rows in the referencing table, if any.
           (SELECT rlbp_estimated_quantity
              FROM emaj.emaj_rlbk_plan
              WHERE rlbp_rlbk_id = p_rlbkId
                AND rlbp_step = 'RLBK_TABLE'                                   -- tables of the rollback event
                AND rlbp_schema = r_fk.nspname
                AND rlbp_table = r_fk.relname)                                 -- referencing schema.table
            , 0)) + (coalesce(
-- Get the number of rolled back rows in the referenced table, if any.
           (SELECT rlbp_estimated_quantity
              FROM emaj.emaj_rlbk_plan
                   JOIN pg_catalog.pg_class rt ON (rt.relname = rlbp_table)
                   JOIN pg_catalog.pg_namespace rn ON (rn.oid = rt.relnamespace AND rn.nspname = rlbp_schema)
                   JOIN pg_catalog.pg_constraint c ON (c.confrelid  = rt.oid)
              WHERE rlbp_rlbk_id = p_rlbkId
                AND rlbp_step = 'RLBK_TABLE'                                   -- tables of the rollback event
                AND c.oid = r_fk.conoid                                        -- constraint id
           )
            , 0)) INTO v_checks;
-- And record the SET_FK_IMM step.
        INSERT INTO emaj.emaj_rlbk_plan (
          rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_batch_number, rlbp_estimated_quantity
          ) VALUES (
          p_rlbkId, 'SET_FK_IMM', r_fk.nspname, r_fk.relname, r_fk.conname, r_fk.rlbp_batch_number, v_checks
          );
      END IF;
    END LOOP;
--
-- Now compute the estimation duration for each complex step ('RLBK_TABLE', 'DELETE_LOG', 'ADD_FK', 'SET_FK_IMM').
--
-- Compute the rollback duration estimates for the tables.
    FOR r_tbl IN
      SELECT *
        FROM emaj.emaj_rlbk_plan
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'RLBK_TABLE'
    LOOP
      SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
        FROM emaj._estimate_rlbk_step_duration('RLBK_TABLE', r_tbl.rlbp_schema, r_tbl.rlbp_table, NULL,
                                               r_tbl.rlbp_estimated_quantity, v_fixed_step_rlbk, v_avg_row_rlbk);
      UPDATE emaj.emaj_rlbk_plan
        SET rlbp_estimated_duration = v_estimDuration, rlbp_estimate_method = v_estimMethod
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'RLBK_TABLE'
          AND rlbp_schema = r_tbl.rlbp_schema
          AND rlbp_table = r_tbl.rlbp_table;
    END LOOP;
-- Compute the estimated log rows delete duration.
    FOR r_tbl IN
      SELECT *
        FROM emaj.emaj_rlbk_plan
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'DELETE_LOG'
    LOOP
      SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
        FROM emaj._estimate_rlbk_step_duration('DELETE_LOG', r_tbl.rlbp_schema, r_tbl.rlbp_table, NULL,
                                               r_tbl.rlbp_estimated_quantity, v_fixed_step_rlbk, v_avg_row_del_log);
      UPDATE emaj.emaj_rlbk_plan
        SET rlbp_estimated_duration = v_estimDuration, rlbp_estimate_method = v_estimMethod
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'DELETE_LOG'
          AND rlbp_schema = r_tbl.rlbp_schema
          AND rlbp_table = r_tbl.rlbp_table;
    END LOOP;
-- Compute the fkey recreation duration.
    FOR r_fk IN
      SELECT *
        FROM emaj.emaj_rlbk_plan
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'ADD_FK'
    LOOP
      SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
        FROM emaj._estimate_rlbk_step_duration('ADD_FK', r_tbl.rlbp_schema, r_tbl.rlbp_table, r_fk.rlbp_object,
                                               r_tbl.rlbp_estimated_quantity, v_fixed_step_rlbk, v_avg_fkey_check);
      UPDATE emaj.emaj_rlbk_plan
        SET rlbp_estimated_duration = v_estimDuration, rlbp_estimate_method = v_estimMethod
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'ADD_FK'
          AND rlbp_schema = r_fk.rlbp_schema
          AND rlbp_table = r_fk.rlbp_table
          AND rlbp_object = r_fk.rlbp_object;
    END LOOP;
-- Compute the fkey checks duration.
    FOR r_fk IN
      SELECT * FROM emaj.emaj_rlbk_plan
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'SET_FK_IMM'
    LOOP
      SELECT p_estimateMethod, p_estimatedDuration INTO v_estimMethod, v_estimDuration
        FROM emaj._estimate_rlbk_step_duration('SET_FK_IMM', r_tbl.rlbp_schema, r_tbl.rlbp_table, r_fk.rlbp_object,
                                               r_tbl.rlbp_estimated_quantity, v_fixed_step_rlbk, v_avg_fkey_check);
      UPDATE emaj.emaj_rlbk_plan
        SET rlbp_estimated_duration = v_estimDuration, rlbp_estimate_method = v_estimMethod
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_step = 'SET_FK_IMM'
          AND rlbp_schema = r_fk.rlbp_schema
          AND rlbp_table = r_fk.rlbp_table
          AND rlbp_object = r_fk.rlbp_object;
    END LOOP;
--
-- Allocate batch number to sessions to spread the load on sessions as best as possible.
-- A batch represents all steps related to the processing of one table or several tables linked by foreign keys.
--
-- Initialisation.
    FOR v_session IN 1 .. v_nbSession LOOP
      v_sessionLoad [v_session] = '0 SECONDS'::INTERVAL;
    END LOOP;
-- Allocate tables batch to sessions, starting with the heaviest to rollback batch.
    FOR r_batch IN
        SELECT rlbp_batch_number, sum(rlbp_estimated_duration) AS batch_duration
          FROM emaj.emaj_rlbk_plan
          WHERE rlbp_rlbk_id = p_rlbkId
            AND rlbp_batch_number IS NOT NULL
          GROUP BY rlbp_batch_number
          ORDER BY sum(rlbp_estimated_duration) DESC
    LOOP
-- Compute the least loaded session.
      v_minSession=1; v_minDuration = v_sessionLoad [1];
      FOR v_session IN 2 .. v_nbSession LOOP
        IF v_sessionLoad [v_session] < v_minDuration THEN
          v_minSession = v_session;
          v_minDuration = v_sessionLoad [v_session];
        END IF;
      END LOOP;
-- Allocate the batch to the session.
      UPDATE emaj.emaj_rlbk_plan
        SET rlbp_session = v_minSession
        WHERE rlbp_rlbk_id = p_rlbkId
          AND rlbp_batch_number = r_batch.rlbp_batch_number;
      v_sessionLoad [v_minSession] = v_sessionLoad [v_minSession] + r_batch.batch_duration;
    END LOOP;
-- Assign session 1 to all 'LOCK_TABLE' steps not yet affected.
    UPDATE emaj.emaj_rlbk_plan
      SET rlbp_session = 1
      WHERE rlbp_rlbk_id = p_rlbkId
        AND rlbp_session IS NULL;
-- Create the pseudo 'CTRL+DBLINK' or 'CTRL-DBLINK' step and compute its duration estimate.
-- Get the number of recorded steps (except LOCK_TABLE).
    SELECT count(*) INTO v_nbStep
      FROM emaj.emaj_rlbk_plan
      WHERE rlbp_rlbk_id = p_rlbkId
        AND rlbp_step <> 'LOCK_TABLE';
    IF v_nbStep > 0 THEN
-- If CTRLxDBLINK statistics are available, compute an average cost.
      SELECT sum(rlbt_duration) * v_nbStep / sum(rlbt_quantity) INTO v_estimDuration
        FROM emaj.emaj_rlbk_stat
        WHERE rlbt_step = v_ctrlStepName
          AND rlbt_quantity > 0;
      v_estimMethod = 2;
      IF v_estimDuration IS NULL THEN
-- Otherwise, use the fixed_step_rollback_duration parameter.
        v_estimDuration = v_fixed_dblink_rlbk * v_nbStep;
        v_estimMethod = 3;
      END IF;
-- Insert the 'CTRLxDBLINK' pseudo step.
      INSERT INTO emaj.emaj_rlbk_plan (
          rlbp_rlbk_id, rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_estimated_quantity,
          rlbp_estimated_duration, rlbp_estimate_method
        ) VALUES (
          p_rlbkId, v_ctrlStepName, '', '', '', v_nbStep, v_estimDuration, v_estimMethod
        );
    END IF;
-- Return the number of tables to effectively rollback.
    RETURN v_effNbTable;
  END;
$_rlbk_planning$;

CREATE OR REPLACE FUNCTION emaj._rlbk_end(p_rlbkId INT, p_multiGroup BOOLEAN, OUT rlbk_severity TEXT, OUT rlbk_message TEXT)
RETURNS SETOF RECORD LANGUAGE plpgsql AS
$_rlbk_end$
-- This is the last step of a rollback group processing. It:
--    - deletes the marks that are no longer available,
--    - deletes the recorded sequences values for these deleted marks
--    - copy data into the emaj_rlbk_stat table,
--    - rollbacks all sequences of the groups,
--    - set the end rollback mark if logged rollback,
--    - and finaly set the operation as COMPLETED or COMMITED.
-- It returns the execution report of the rollback operation (a set of rows).
  DECLARE
    v_stmt                   TEXT;
    v_dblinkSchema           TEXT;
    v_isDblinkUsed           BOOLEAN;
    v_groupNames             TEXT[];
    v_mark                   TEXT;
    v_isLoggedRlbk           BOOLEAN;
    v_isAlterGroupAllowed    BOOLEAN;
    v_nbTbl                  INT;
    v_effNbTbl               INT;
    v_rlbkDatetime           TIMESTAMPTZ;
    v_ctrlDuration           INTERVAL;
    v_markTimeId             BIGINT;
    v_nbSeq                  INT;
    v_markName               TEXT;
    v_messages               TEXT[] = ARRAY[]::TEXT[];
    v_msg                    TEXT;
    v_msgList                TEXT;
    r_msg                    RECORD;
  BEGIN
-- Get the rollback characteristics from the emaj_rlbk table.
    SELECT rlbk_groups, rlbk_mark, rlbk_is_logged, rlbk_is_alter_group_allowed, rlbk_nb_table, rlbk_eff_nb_table, rlbk_nb_sequence,
           rlbk_dblink_schema, rlbk_is_dblink_used, time_clock_timestamp
      INTO v_groupNames, v_mark, v_isLoggedRlbk, v_isAlterGroupAllowed, v_nbTbl, v_effNbTbl, v_nbSeq,
           v_dblinkSchema, v_isDblinkUsed, v_rlbkDatetime
      FROM emaj.emaj_rlbk
           JOIN emaj.emaj_time_stamp ON (time_id = rlbk_time_id)
      WHERE rlbk_id = p_rlbkId;
-- Get the mark timestamp for the 1st group (they all share the same timestamp).
    SELECT mark_time_id INTO v_markTimeId
      FROM emaj.emaj_mark
      WHERE mark_group = v_groupNames[1]
        AND mark_name = v_mark;
-- If "unlogged" rollback, delete all marks later than the now rolled back mark and the associated sequences.
    IF NOT v_isLoggedRlbk THEN
-- Get the highest mark time id of the mark used for rollback, for all groups.
-- Delete the marks that are suppressed by the rollback (the related sequences have been already deleted by rollback functions)
-- with a logging in the history.
      WITH deleted AS
        (DELETE FROM emaj.emaj_mark
           WHERE mark_group = ANY (v_groupNames)
             AND mark_time_id > v_markTimeId
           RETURNING mark_time_id, mark_group, mark_name
        ),
           sorted_deleted AS                                         -- the sort is performed to produce stable results in regression tests
        (SELECT mark_group, mark_name
           FROM deleted
           ORDER BY mark_time_id, mark_group
        )
      INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
        SELECT CASE WHEN p_multiGroup THEN 'ROLLBACK_GROUPS' ELSE 'ROLLBACK_GROUP' END,
               'MARK DELETED', mark_group, 'mark ' || mark_name || ' is deleted'
        FROM sorted_deleted;
-- And reset the mark_log_rows_before_next column for the new last mark.
      UPDATE emaj.emaj_mark
        SET mark_log_rows_before_next = NULL
        WHERE mark_group = ANY (v_groupNames)
          AND (mark_group, mark_time_id) IN                -- select only the last non deleted mark of each concerned group
              (SELECT mark_group, max(mark_time_id)
                 FROM emaj.emaj_mark
                 WHERE mark_group = ANY (v_groupNames)
                   AND NOT mark_is_deleted
                 GROUP BY mark_group
              );
-- The sequences related to the deleted marks can be also suppressed.
-- Delete first application sequences related data for the groups.
      DELETE FROM emaj.emaj_sequence
        USING emaj.emaj_relation
        WHERE sequ_schema = rel_schema
          AND sequ_name = rel_tblseq
          AND upper_inf(rel_time_range)
          AND rel_group = ANY (v_groupNames)
          AND rel_kind = 'S'
          AND sequ_time_id > v_markTimeId
          AND lower(rel_time_range) <> sequ_time_id;
-- Delete then tables related data for the groups.
      DELETE FROM emaj.emaj_table
        USING emaj.emaj_relation
        WHERE tbl_schema = rel_schema
          AND tbl_name = rel_tblseq
          AND upper_inf(rel_time_range)
          AND rel_group = ANY (v_groupNames)
          AND rel_kind = 'r'
          AND tbl_time_id > v_markTimeId
          AND tbl_time_id <@ rel_time_range
          AND tbl_time_id <> lower(rel_time_range);
    END IF;
-- Delete the now useless 'LOCK TABLE' steps from the emaj_rlbk_plan table.
    v_stmt = 'DELETE FROM emaj.emaj_rlbk_plan ' ||
             ' WHERE rlbp_rlbk_id = ' || p_rlbkId || ' AND rlbp_step = ''LOCK_TABLE'' RETURNING 1';
    PERFORM emaj._dblink_sql_exec('rlbk#1', v_stmt, v_dblinkSchema);
-- Prepare the CTRLxDBLINK pseudo step statistic by computing the global time spent between steps.
    SELECT coalesce(sum(ctrl_duration),'0'::INTERVAL) INTO v_ctrlDuration
      FROM
        (SELECT rlbs_session, rlbs_end_datetime - min(rlbp_start_datetime) - sum(rlbp_duration) AS ctrl_duration
           FROM emaj.emaj_rlbk_session rlbs
                JOIN emaj.emaj_rlbk_plan rlbp ON (rlbp_rlbk_id = rlbs_rlbk_id AND rlbp_session = rlbs_session)
           WHERE rlbs_rlbk_id = p_rlbkId
           GROUP BY rlbs_session, rlbs_end_datetime
        ) AS t;
-- Report duration statistics into the emaj_rlbk_stat table.
    v_stmt = 'INSERT INTO emaj.emaj_rlbk_stat (rlbt_step, rlbt_schema, rlbt_table, rlbt_object,' ||
             '      rlbt_rlbk_id, rlbt_quantity, rlbt_duration)' ||
--   copy elementary steps for RLBK_TABLE, DELETE_LOG, ADD_FK and SET_FK_IMM step types
--     (record the rlbp_estimated_quantity as reference for later forecast)
             '  SELECT rlbp_step, rlbp_schema, rlbp_table, rlbp_object, rlbp_rlbk_id,' ||
             '      rlbp_estimated_quantity, rlbp_duration' ||
             '    FROM emaj.emaj_rlbk_plan' ||
             '    WHERE rlbp_rlbk_id = ' || p_rlbkId ||
             '      AND rlbp_step IN (''RLBK_TABLE'',''DELETE_LOG'',''ADD_FK'',''SET_FK_IMM'') ' ||
             '  UNION ALL ' ||
--   for 6 other steps, aggregate other elementary steps into a global row for each step type
             '  SELECT rlbp_step, '''', '''', '''', rlbp_rlbk_id, ' ||
             '      count(*), sum(rlbp_duration)' ||
             '    FROM emaj.emaj_rlbk_plan' ||
             '    WHERE rlbp_rlbk_id = ' || p_rlbkId ||
             '      AND rlbp_step IN (''DIS_APP_TRG'',''DIS_LOG_TRG'',''DROP_FK'',''SET_FK_DEF'',''ENA_APP_TRG'',''ENA_LOG_TRG'') ' ||
             '    GROUP BY 1, 2, 3, 4, 5' ||
             '  UNION ALL ' ||
--   and the final CTRLxDBLINK pseudo step statistic
             '  SELECT rlbp_step, '''', '''', '''', rlbp_rlbk_id, ' ||
             '      rlbp_estimated_quantity, ' || quote_literal(v_ctrlDuration) ||
             '    FROM emaj.emaj_rlbk_plan' ||
             '    WHERE rlbp_rlbk_id = ' || p_rlbkId ||
             '      AND rlbp_step IN (''CTRL+DBLINK'',''CTRL-DBLINK'') ' ||
             ' RETURNING 1';
    PERFORM emaj._dblink_sql_exec('rlbk#1', v_stmt, v_dblinkSchema);
-- Build the execution report.
-- Start with the NOTICE messages.
    v_messages = array_append(v_messages, 'Notice: ' || format ('%s / %s tables effectively processed.', v_effNbTbl::TEXT, v_nbTbl::TEXT));
    IF v_nbSeq > 0 THEN
      v_messages = array_append(v_messages, 'Notice: ' || format ('%s sequences processed.', v_nbSeq::TEXT));
    END IF;
-- And then the WARNING messages for any elementary action from group structure change that has not been rolled back.
    FOR r_msg IN
-- Steps are splitted into 2 groups to filter them differently.
        SELECT rlchg_time_id, rlchg_change_kind, rlchg_schema, rlchg_tblseq,
               (CASE rlchg_change_kind
                  WHEN 'ADD_SEQUENCE' THEN
                    'The sequence ' || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq) ||
                    ' has only been rolled back to its latest group attachment state ('
                    || to_char(time_tx_timestamp, 'YYYY/MM/DD HH:MI:SS TZ') || ')'
                  WHEN 'ADD_TABLE' THEN
                    'The table ' || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq) ||
                    ' has only been rolled back to its latest group attachment ('
                    || to_char(time_tx_timestamp, 'YYYY/MM/DD HH:MI:SS TZ') || ')'
                  WHEN 'REMOVE_SEQUENCE' THEN
                    'The sequence ' || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq) ||
                    ' has been left unchanged (not in group anymore since ' ||
                    to_char(time_tx_timestamp, 'YYYY/MM/DD HH:MI:SS TZ') || ')'
                  WHEN 'REMOVE_TABLE' THEN
                    'The table ' || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq) ||
                    ' has been left unchanged (not in group anymore since '
                    || to_char(time_tx_timestamp, 'YYYY/MM/DD HH:MI:SS TZ') || ')'
                  WHEN 'MOVE_SEQUENCE' THEN
                    'The sequence ' || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq) ||
                    ' has only been rolled back to its latest group attachment state ('
                    || to_char(time_tx_timestamp, 'YYYY/MM/DD HH:MI:SS TZ') || ')'
                  WHEN 'MOVE_TABLE' THEN
                    'The table ' || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq) ||
                    ' has only been rolled back to its latest group attachment ('
                    || to_char(time_tx_timestamp, 'YYYY/MM/DD HH:MI:SS TZ') || ')'
                  END)::TEXT AS message
          FROM
-- Suppress duplicate ADD_TABLE / MOVE_TABLE / REMOVE_TABLE or ADD_SEQUENCE / MOVE_SEQUENCE / REMOVE_SEQUENCE for same table or sequence,
-- by keeping the most recent changes.
            (SELECT rlchg_schema, rlchg_tblseq, rlchg_time_id, rlchg_change_kind
               FROM
                 (SELECT rlchg_schema, rlchg_tblseq, rlchg_time_id, rlchg_change_kind,
                         rank() OVER (PARTITION BY rlchg_schema, rlchg_tblseq ORDER BY rlchg_time_id DESC) AS rlchg_rank
                    FROM emaj.emaj_relation_change
                    WHERE rlchg_time_id > v_markTimeId
                      AND rlchg_group = ANY (v_groupNames)
                      AND rlchg_tblseq <> ''
                      AND rlchg_rlbk_id IS NULL
                      AND rlchg_change_kind IN
                            ('ADD_TABLE','ADD_SEQUENCE','REMOVE_TABLE','REMOVE_SEQUENCE','MOVE_TABLE','MOVE_SEQUENCE')
                  ) AS t1
               WHERE rlchg_rank = 1
            ) AS t2, emaj.emaj_time_stamp
          WHERE rlchg_time_id = time_id
      UNION
        SELECT rlchg_time_id, rlchg_change_kind, rlchg_schema, rlchg_tblseq,
               (CASE rlchg_change_kind
                  WHEN 'CHANGE_PRIORITY' THEN
                    'Tables group change not rolled back: E-Maj priority for '
                    || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq)
                  WHEN 'CHANGE_LOG_DATA_TABLESPACE' THEN
                    'Tables group change not rolled back: log data tablespace for '
                    || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq)
                  WHEN 'CHANGE_LOG_INDEX_TABLESPACE' THEN
                    'Tables group change not rolled back: log index tablespace for '
                    || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq)
                  WHEN 'CHANGE_IGNORED_TRIGGERS' THEN
                    'Tables group change not rolled back: ignored triggers list for '
                    || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq)
                  ELSE rlchg_change_kind::TEXT || ' / ' || quote_ident(rlchg_schema) || '.' || quote_ident(rlchg_tblseq)
                  END)::TEXT AS message
          FROM
-- Suppress duplicates for other change kind for each table or sequence.
            (SELECT rlchg_schema, rlchg_tblseq, rlchg_time_id, rlchg_change_kind
               FROM
                 (SELECT rlchg_schema, rlchg_tblseq, rlchg_time_id, rlchg_change_kind,
                         rank() OVER (PARTITION BY rlchg_schema, rlchg_tblseq ORDER BY rlchg_time_id DESC) AS rlchg_rank
                    FROM emaj.emaj_relation_change
                    WHERE rlchg_time_id > v_markTimeId
                      AND rlchg_group = ANY (v_groupNames)
                      AND rlchg_tblseq <> ''
                      AND rlchg_rlbk_id IS NULL
                      AND rlchg_change_kind NOT IN
                            ('ADD_TABLE','ADD_SEQUENCE','REMOVE_TABLE','REMOVE_SEQUENCE','MOVE_TABLE','MOVE_SEQUENCE')
                 ) AS t1
               WHERE rlchg_rank = 1
            ) AS t2
        ORDER BY rlchg_time_id, rlchg_change_kind, rlchg_schema, rlchg_tblseq
    LOOP
      v_messages = array_append(v_messages, 'Warning: ' || r_msg.message);
    END LOOP;
-- Update the groups structure changes that are been covered by the rollback.
    UPDATE emaj.emaj_relation_change
      SET rlchg_rlbk_id = p_rlbkId
      WHERE rlchg_time_id > v_markTimeId
        AND rlchg_group = ANY (v_groupNames)
        AND rlchg_rlbk_id IS NULL;
-- Rollback the application sequences belonging to the groups.
-- Warning, this operation is not transaction safe (that's why it is placed at the end of the rollback operation)!.
-- If the sequence has been added to its group after the target rollback mark, rollback up to the corresponding alter_group time.
    PERFORM emaj._rlbk_seq(t.*, greatest(v_markTimeId, lower(t.rel_time_range)))
      FROM
        (SELECT *
           FROM emaj.emaj_relation
           WHERE upper_inf(rel_time_range)
             AND rel_group = ANY (v_groupNames)
             AND rel_kind = 'S'
           ORDER BY rel_schema, rel_tblseq
        ) as t;
-- If rollback is a "logged" rollback, automatically set a mark representing the tables state just after the rollback.
-- This mark is named 'RLBK_<mark name to rollback to>_%_DONE', where % represents the rollback start time.
    IF v_isLoggedRlbk THEN
      v_markName = 'RLBK_' || v_mark || '_' || substring(to_char(v_rlbkDatetime, 'HH24.MI.SS.US') from 1 for 13) || '_DONE';
      PERFORM emaj._set_mark_groups(v_groupNames, v_markName, p_multiGroup, TRUE, v_mark);
    END IF;
-- Return and trace the execution report
    FOREACH v_msg IN ARRAY v_messages
    LOOP
      SELECT substring(v_msg FROM '^(Notice|Warning): '), substring(v_msg, '^(?:Notice|Warning): (.*)') INTO rlbk_severity, rlbk_message;
      RETURN NEXT;
      INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
        VALUES (CASE WHEN p_multiGroup THEN 'ROLLBACK_GROUPS' ELSE 'ROLLBACK_GROUP' END, UPPER(rlbk_severity), 'Rollback id ' || p_rlbkId,
                rlbk_message);
    END LOOP;
-- Update the emaj_rlbk table to set the real number of tables to process, adjust the rollback status and set the output messages.
    SELECT string_agg(quote_literal(msg), ',') FROM unnest(v_messages) AS msg INTO v_msgList;
    v_stmt = 'UPDATE emaj.emaj_rlbk SET rlbk_status = '''
          || CASE WHEN v_isDblinkUsed THEN 'COMPLETED' ELSE 'COMMITTED' END
          || ''', rlbk_end_datetime = clock_timestamp(), rlbk_messages = ARRAY[' || v_msgList || ']' ||
               ' WHERE rlbk_id = ' || p_rlbkId || ' RETURNING 1';
    PERFORM emaj._dblink_sql_exec('rlbk#1', v_stmt, v_dblinkSchema);
-- Close the dblink connection, if any.
    IF v_isDblinkUsed THEN
      PERFORM emaj._dblink_close_cnx('rlbk#1', v_dblinkSchema);
    END IF;
-- Insert a END event into the history.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
      VALUES (CASE WHEN p_multiGroup THEN 'ROLLBACK_GROUPS' ELSE 'ROLLBACK_GROUP' END, 'END',
              array_to_string(v_groupNames,','),
              'Rollback_id ' || p_rlbkId || ', ' || v_effNbTbl || ' tables and ' || v_nbSeq || ' sequences effectively processed'
             );
-- Final return.
    RETURN;
-- Trap and record exception during the rollback operation.
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN             -- Do not trap the exceptions raised by the function
      RAISE;
    WHEN OTHERS THEN                       -- Otherwise, log the E-Maj rollback abort in emaj_rlbk, if possible
      PERFORM emaj._rlbk_error(p_rlbkId, 'In _rlbk_end(): ' || SQLERRM, 'rlbk#1');
      RAISE;
  END;
$_rlbk_end$;

CREATE OR REPLACE FUNCTION emaj._reset_groups(p_groupNames TEXT[])
RETURNS INT LANGUAGE plpgsql AS
$_reset_groups$
-- This function empties the log tables for all tables of a group, using a TRUNCATE, and deletes the sequences images.
-- It is called by emaj_reset_group(), emaj_start_group() and emaj_alter_group() functions.
-- Input: group names array
-- Output: number of processed tables and sequences
-- There is no check of the groups state (this is done by callers).
  DECLARE
    v_eventTriggers          TEXT[];
    v_batchSize     CONSTANT INT = 100;
    v_tableList              TEXT;
    v_nbTbl                  INT;
    r_rel                    RECORD;
  BEGIN
-- Disable event triggers that protect emaj components and keep in memory these triggers name.
    SELECT emaj._disable_event_triggers() INTO v_eventTriggers;
-- Delete all marks for the groups from the emaj_mark table.
    DELETE FROM emaj.emaj_mark
      WHERE mark_group = ANY (p_groupNames);
-- Delete emaj_table rows related to the tables of the groups.
    DELETE FROM emaj.emaj_table
      USING emaj.emaj_relation r1
      WHERE tbl_schema = rel_schema
        AND tbl_name = rel_tblseq
        AND rel_group = ANY (p_groupNames)
        AND rel_kind = 'r'
        AND ((tbl_time_id <@ rel_time_range               -- all log sequences inside the relation time range
             AND (tbl_time_id <> lower(rel_time_range)    -- except the lower bound if
                  OR NOT EXISTS                           --   it is the upper bound of another time range for another group
                       (SELECT 0
                          FROM emaj.emaj_relation r2
                          WHERE r2.rel_schema = tbl_schema
                            AND r2.rel_tblseq = tbl_name
                            AND upper(r2.rel_time_range) = tbl_time_id
                            AND NOT (r2.rel_group = ANY (p_groupNames)) )))
            OR (tbl_time_id = upper(rel_time_range)        -- but including the upper bound if
                  AND NOT EXISTS                           --   it is not the lower bound of another time range (for any group)
                        (SELECT 0
                           FROM emaj.emaj_relation r3
                           WHERE r3.rel_schema = tbl_schema
                             AND r3.rel_tblseq = tbl_name
                             AND lower(r3.rel_time_range) = tbl_time_id
                        )
               ));
-- Delete all sequence holes for the tables of the groups.
-- It may delete holes for timeranges that do not belong to the group, if a table has been moved to another group,
-- but is safe enough for rollbacks.
    DELETE FROM emaj.emaj_seq_hole
      USING emaj.emaj_relation
      WHERE rel_schema = sqhl_schema
        AND rel_tblseq = sqhl_table
        AND rel_group = ANY (p_groupNames)
        AND rel_kind = 'r';
-- Drop obsolete log tables, but keep those linked to other groups.
    FOR r_rel IN
        SELECT DISTINCT rel_log_schema, rel_log_table
          FROM emaj.emaj_relation
          WHERE rel_group = ANY (p_groupNames)
            AND rel_kind = 'r'
            AND NOT upper_inf(rel_time_range)
      EXCEPT
        SELECT rel_log_schema, rel_log_table
          FROM emaj.emaj_relation
          WHERE rel_kind = 'r'
            AND (upper_inf(rel_time_range) OR NOT rel_group = ANY (p_groupNames))
        ORDER BY 1,2
    LOOP
      EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE',
                     r_rel.rel_log_schema, r_rel.rel_log_table);
    END LOOP;
-- Delete emaj_sequence rows related to the sequences of the groups.
    DELETE FROM emaj.emaj_sequence
      USING emaj.emaj_relation
      WHERE sequ_schema = rel_schema
        AND sequ_name = rel_tblseq
        AND rel_group = ANY (p_groupNames)
        AND rel_kind = 'S'
        AND ((sequ_time_id <@ rel_time_range               -- all application sequences inside the relation time range
             AND (sequ_time_id <> lower(rel_time_range)    -- except the lower bound if
                  OR NOT EXISTS                            --   it is the upper bound of another time range for another group
                       (SELECT 0
                          FROM emaj.emaj_relation r2
                          WHERE r2.rel_schema = sequ_schema
                            AND r2.rel_tblseq = sequ_name
                            AND upper(r2.rel_time_range) = sequ_time_id
                            AND NOT (r2.rel_group = ANY (p_groupNames))
                       )))
          OR (sequ_time_id = upper(rel_time_range)         -- including the upper bound if
                  AND NOT EXISTS                           --   it is not the lower bound of another time range for another group
                       (SELECT 0
                          FROM emaj.emaj_relation r3
                          WHERE r3.rel_schema = sequ_schema
                            AND r3.rel_tblseq = sequ_name
                            AND lower(r3.rel_time_range) = sequ_time_id
                       ))
            );
-- Keep a trace of the relation group ownership history
-- and finaly delete the old versions of emaj_relation rows (those with a not infinity upper bound).
    WITH deleted AS
      (DELETE FROM emaj.emaj_relation
         WHERE rel_group = ANY (p_groupNames)
           AND NOT upper_inf(rel_time_range)
         RETURNING rel_schema, rel_tblseq, rel_time_range, rel_group, rel_kind
      )
    INSERT INTO emaj.emaj_rel_hist
             (relh_schema, relh_tblseq, relh_time_range, relh_group, relh_kind)
      SELECT rel_schema, rel_tblseq, rel_time_range, rel_group, rel_kind
        FROM deleted;
-- Truncate remaining log tables for application tables.
-- For performance reason, execute one single TRUNCATE statement for every v_batchSize tables.
    v_tableList = NULL;
    v_nbTbl = 0;
    FOR r_rel IN
      SELECT quote_ident(rel_log_schema) || '.' || quote_ident(rel_log_table) AS full_relation_name
        FROM emaj.emaj_relation
        WHERE rel_group = ANY (p_groupNames)
          AND rel_kind = 'r'
        ORDER BY rel_priority, rel_schema, rel_tblseq
    LOOP
      v_tableList = coalesce(v_tableList || ',' || r_rel.full_relation_name, r_rel.full_relation_name);
      v_nbTbl = v_nbtbl + 1;
      IF v_nbTbl >= v_batchSize THEN
        EXECUTE 'TRUNCATE ' || v_tableList;
        v_nbTbl = 0;
        v_tableList = NULL;
      END IF;
    END LOOP;
    IF v_tableList IS NOT NULL THEN
      EXECUTE 'TRUNCATE ' || v_tableList;
    END IF;
-- Enable previously disabled event triggers.
    PERFORM emaj._enable_event_triggers(v_eventTriggers);
--
    RETURN sum(group_nb_table)+sum(group_nb_sequence)
      FROM emaj.emaj_group
      WHERE group_name = ANY (p_groupNames);
  END;
$_reset_groups$;

CREATE OR REPLACE FUNCTION emaj.emaj_snap_group(p_groupName TEXT, p_dir TEXT, p_copyOptions TEXT)
RETURNS INT LANGUAGE plpgsql AS
$emaj_snap_group$
-- This function creates a file for each table and sequence belonging to the group.
-- For tables, these files contain all rows sorted on primary key.
-- For sequences, they contain a single row describing the sequence.
-- To do its job, the function performs COPY TO statement, with all default parameters.
-- For table without primary key, rows are sorted on all columns.
-- There is no need for the group not to be logging.
-- As all COPY statements are executed inside a single transaction:
--   - the function can be called while other transactions are running,
--   - the snap files will present a coherent state of tables.
-- It's users responsability:
--   - to create the directory (with proper permissions allowing the cluster to write into) before the emaj_snap_group function call, and
--   - maintain its content outside E-maj.
-- Input: group name,
--        the absolute pathname of the directory where the files are to be created and the options to used in the COPY TO statements
-- Output: number of processed tables and sequences
  DECLARE
    v_nbTb                   INT = 0;
    r_tblsq                  RECORD;
    v_fullTableName          TEXT;
    v_colList                TEXT;
    v_fileName               TEXT;
    v_stmt                   TEXT;
  BEGIN
-- Insert a BEGIN event into the history.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
      VALUES ('SNAP_GROUP', 'BEGIN', p_groupName, p_dir);
-- Check the group name.
    PERFORM emaj._check_group_names(p_groupNames := ARRAY[p_groupName], p_mayBeNull := FALSE, p_lockGroups := FALSE, p_checkList := '');
-- Check the supplied directory is not null.
    IF p_dir IS NULL THEN
      RAISE EXCEPTION 'emaj_snap_group: The directory parameter cannot be NULL.';
    END IF;
-- Check the copy options parameter doesn't contain unquoted ; that could be used for sql injection.
    IF regexp_replace(p_copyOptions,'''.*''','') LIKE '%;%' THEN
      RAISE EXCEPTION 'emaj_snap_group: The COPY options parameter format is invalid.';
    END IF;
-- For each table/sequence of the emaj_relation table.
    FOR r_tblsq IN
      SELECT rel_priority, rel_schema, rel_tblseq, rel_kind
        FROM emaj.emaj_relation
        WHERE upper_inf(rel_time_range)
          AND rel_group = p_groupName
        ORDER BY rel_priority, rel_schema, rel_tblseq
    LOOP
      v_fileName = p_dir || '/' || translate(r_tblsq.rel_schema || '_' || r_tblsq.rel_tblseq || '.snap', E' /\\$<>*', '_______');
      v_fullTableName = quote_ident(r_tblsq.rel_schema) || '.' || quote_ident(r_tblsq.rel_tblseq);
      CASE r_tblsq.rel_kind
        WHEN 'r' THEN
-- It is a table.
--   Build the order by column list.
          IF EXISTS
               (SELECT 0
                  FROM pg_catalog.pg_class
                       JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                       JOIN pg_catalog.pg_constraint ON (connamespace = pg_namespace.oid AND conrelid = pg_class.oid)
                  WHERE contype = 'p'
                    AND nspname = r_tblsq.rel_schema
                    AND relname = r_tblsq.rel_tblseq
               ) THEN
--   The table has a pkey.
            SELECT string_agg(quote_ident(attname), ',') INTO v_colList
              FROM
                (SELECT attname
                   FROM pg_catalog.pg_attribute
                        JOIN pg_catalog.pg_index ON (pg_index.indrelid = pg_attribute.attrelid)
                   WHERE attnum = ANY (indkey)
                     AND indrelid = v_fullTableName::regclass
                     AND indisprimary
                     AND attnum > 0
                     AND attisdropped = FALSE
                ) AS t;
          ELSE
--   The table has no pkey.
            SELECT string_agg(quote_ident(attname), ',') INTO v_colList
              FROM
                (SELECT attname
                   FROM pg_catalog.pg_attribute
                   WHERE attrelid = v_fullTableName::regclass
                     AND attnum > 0
                     AND attisdropped = FALSE
                ) AS t;
          END IF;
--   Dump the table
          v_stmt= '(SELECT * FROM ' || v_fullTableName || ' ORDER BY ' || v_colList || ')';
          PERFORM emaj._copy_to_file(v_stmt, v_fileName, p_copyOptions);
        WHEN 'S' THEN
-- If it is a sequence, the statement has no order by.
          v_stmt = '(SELECT sequencename, rel.last_value, start_value, increment_by, max_value, '
                || 'min_value, cache_size, cycle, rel.is_called '
                || 'FROM ' || v_fullTableName || ' rel, pg_catalog.pg_sequences '
                || 'WHERE schemaname = '|| quote_literal(r_tblsq.rel_schema) || ' AND sequencename = '
                || quote_literal(r_tblsq.rel_tblseq) ||')';
--    Dump the sequence properties.
          PERFORM emaj._copy_to_file(v_stmt, v_fileName, p_copyOptions);
      END CASE;
      v_nbTb = v_nbTb + 1;
    END LOOP;
-- Create the _INFO file to keep general information about the snap operation.
    v_stmt = '(SELECT ' || quote_literal('E-Maj snap of tables group ' || p_groupName || ' at ' || transaction_timestamp()) || ')';
    PERFORM emaj._copy_to_file(v_stmt, p_dir || '/_INFO', NULL);
-- Insert a END event into the history.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
      VALUES ('SNAP_GROUP', 'END', p_groupName, v_nbTb || ' tables/sequences processed');
--
    RETURN v_nbTb;
  END;
$emaj_snap_group$;
COMMENT ON FUNCTION emaj.emaj_snap_group(TEXT,TEXT,TEXT) IS
$$Snaps all application tables and sequences of an E-Maj group into a given directory.$$;

CREATE OR REPLACE FUNCTION emaj._verify_all_groups()
RETURNS SETOF TEXT LANGUAGE plpgsql AS
$_verify_all_groups$
-- The function verifies the consistency of all E-Maj groups.
-- It returns a set of error or warning messages for discovered discrepancies.
-- If no error is detected, no row is returned.
  BEGIN
--
-- Errors detection.
--
-- Check that all application schemas referenced in the emaj_relation table still exist.
    RETURN QUERY
      SELECT 'Error: The application schema "' || rel_schema || '" does not exist any more.' AS msg
        FROM
          (  SELECT DISTINCT rel_schema
               FROM emaj.emaj_relation
               WHERE upper_inf(rel_time_range)
           EXCEPT
              SELECT nspname
                FROM pg_catalog.pg_namespace
          ) AS t
        ORDER BY msg;
-- Check that all application relations referenced in the emaj_relation table still exist.
    RETURN QUERY
      SELECT 'Error: In the group "' || r.rel_group || '", the ' ||
               CASE WHEN t.rel_kind = 'r' THEN 'table "' ELSE 'sequence "' END ||
               t.rel_schema || '"."' || t.rel_tblseq || '" does not exist any more.' AS msg
        FROM                                          -- all expected application relations
          (  SELECT rel_schema, rel_tblseq, rel_kind
               FROM emaj.emaj_relation
               WHERE upper_inf(rel_time_range)
           EXCEPT                                    -- minus relations known by postgres
             SELECT nspname, relname, relkind::TEXT
               FROM pg_catalog.pg_class
                    JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
               WHERE relkind IN ('r','S')
          ) AS t
          JOIN emaj.emaj_relation r ON (t.rel_schema = r.rel_schema AND t.rel_tblseq = r.rel_tblseq AND upper_inf(r.rel_time_range))
        ORDER BY t.rel_schema, t.rel_tblseq, 1;
-- Check that the log table for all tables referenced in the emaj_relation table still exist.
    RETURN QUERY
      SELECT 'Error: In the group "' || rel_group || '", the log table "' ||
               rel_log_schema || '"."' || rel_log_table || '" is not found.' AS msg
        FROM emaj.emaj_relation
        WHERE rel_kind = 'r'
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_log_schema
                     AND relname = rel_log_table
                )
        ORDER BY rel_schema, rel_tblseq, 1;
-- Check that the log sequence for all tables referenced in the emaj_relation table still exist.
    RETURN QUERY
      SELECT 'Error: In the group "' || rel_group || '", the log sequence "' ||
               rel_log_schema || '"."' || rel_log_sequence || '" is not found.' AS msg
        FROM emaj.emaj_relation
        WHERE upper_inf(rel_time_range)
          AND rel_kind = 'r'
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                 WHERE nspname = rel_log_schema AND relname = rel_log_sequence
                )
        ORDER BY rel_schema, rel_tblseq, 1;
-- Check the log function for each table referenced in the emaj_relation table still exist.
    RETURN QUERY
      SELECT 'Error: In the group "' || rel_group || '", the log function "' ||
               rel_log_schema || '"."' || rel_log_function || '" is not found.'
             AS msg
        FROM emaj.emaj_relation
        WHERE upper_inf(rel_time_range)
          AND rel_kind = 'r'
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_proc
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = pronamespace)
                 WHERE nspname = rel_log_schema
                   AND proname = rel_log_function
                )
        ORDER BY rel_schema, rel_tblseq, 1;
-- Check log and truncate triggers for all tables referenced in the emaj_relation table still exist.
-- Start with log triggers.
    RETURN QUERY
      SELECT 'Error: In the group "' || rel_group || '", the log trigger "emaj_log_trg" on table "' ||
               rel_schema || '"."' || rel_tblseq || '" is not found.' AS msg
        FROM emaj.emaj_relation
        WHERE upper_inf(rel_time_range)
          AND rel_kind = 'r'
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_trigger
                        JOIN pg_catalog.pg_class ON (pg_class.oid = tgrelid)
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                     AND tgname = 'emaj_log_trg'
                )
                       -- do not issue a row if the application table does not exist,
                       -- this case has been already detected
          AND EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                )
        ORDER BY rel_schema, rel_tblseq, 1;
-- Then truncate triggers.
    RETURN QUERY
      SELECT 'Error: In the group "' || rel_group || '", the truncate trigger "emaj_trunc_trg" on table "' ||
             rel_schema || '"."' || rel_tblseq || '" is not found.' AS msg
        FROM emaj.emaj_relation
        WHERE upper_inf(rel_time_range)
          AND rel_kind = 'r'
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_trigger
                        JOIN pg_catalog.pg_class ON (pg_class.oid = tgrelid)
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                     AND tgname = 'emaj_trunc_trg'
                )
                       -- do not issue a row if the application table does not exist,
                       -- this case has been already detected
          AND EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                )
        ORDER BY rel_schema, rel_tblseq, 1;
-- Check that all log tables have a structure consistent with the application tables they reference
-- (same columns and same formats). It only returns one row per faulting table.
    RETURN QUERY
      SELECT msg FROM
        (WITH cte_app_tables_columns AS                -- application table's columns
           (SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
              FROM emaj.emaj_relation
                   JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
                   JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
                   JOIN pg_catalog.pg_attribute ON (attrelid = pg_class.oid)
              WHERE attnum > 0
                AND attisdropped = FALSE
                AND upper_inf(rel_time_range)
                AND rel_kind = 'r'
           ),
              cte_log_tables_columns AS                 -- log table's columns
           (SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
              FROM emaj.emaj_relation
                   JOIN pg_catalog.pg_class ON (relname = rel_log_table)
                   JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_log_schema)
                   JOIN pg_catalog.pg_attribute ON (attrelid = pg_class.oid)
              WHERE attnum > 0
                AND attisdropped = FALSE
                AND attnum < rel_emaj_verb_attnum
                AND upper_inf(rel_time_range)
                AND rel_kind = 'r'
           )
        SELECT DISTINCT rel_schema, rel_tblseq,
               'Error: In the group "' || rel_group || '", the structure of the application table "' ||
                 rel_schema || '"."' || rel_tblseq || '" is not coherent with its log table ("' ||
               rel_log_schema || '"."' || rel_log_table || '").' AS msg
          FROM
            (                                              -- application table's columns
              (  SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                   FROM cte_app_tables_columns
               EXCEPT                                      -- minus log table's columns
                 SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                   FROM cte_log_tables_columns
              )
            UNION                                          -- log table's columns
              (  SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                   FROM cte_log_tables_columns
               EXCEPT                                      --  minus application table's columns
                 SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname, atttypid, attlen, atttypmod
                   FROM cte_app_tables_columns
              )
            ) AS t
                           -- do not issue a row if the log or application table does not exist,
                           -- these cases have been already detected
        WHERE (rel_log_schema, rel_log_table) IN
              (SELECT nspname, relname
                 FROM pg_catalog.pg_class
                      JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
              )
          AND (rel_schema, rel_tblseq) IN
              (SELECT nspname, relname
                 FROM pg_catalog.pg_class
                      JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
              )
        ORDER BY 1,2,3
        ) AS t;
-- Check that all tables of rollbackable groups have their primary key.
    RETURN QUERY
      SELECT 'Error: In the rollbackable group "' || rel_group || '", the table "' ||
             rel_schema || '"."' || rel_tblseq || '" has no primary key any more.' AS msg
        FROM emaj.emaj_relation
             JOIN emaj.emaj_group ON (group_name = rel_group)
        WHERE upper_inf(rel_time_range)
          AND rel_kind = 'r'
          AND group_is_rollbackable
          AND NOT EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                        JOIN pg_catalog.pg_constraint ON (connamespace = pg_namespace.oid AND conrelid = pg_class.oid)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                     AND contype = 'p'
                )
                       -- do not issue a row if the application table does not exist,
                       -- this case has been already detected
          AND EXISTS
                (SELECT NULL
                   FROM pg_catalog.pg_class
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                   WHERE nspname = rel_schema
                     AND relname = rel_tblseq
                )
        ORDER BY rel_schema, rel_tblseq, 1;
-- For rollbackable groups, check that no table has been altered as UNLOGGED or dropped and recreated as TEMP table after
-- tables groups creation.
    RETURN QUERY
      SELECT 'Error: In the rollbackable group "' || rel_group || '", the table "' ||
             rel_schema || '"."' || rel_tblseq || '" is UNLOGGED or TEMP.' AS msg
        FROM emaj.emaj_relation
             JOIN emaj.emaj_group ON (group_name = rel_group)
             JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
             JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
        WHERE upper_inf(rel_time_range)
          AND rel_kind = 'r'
          AND group_is_rollbackable
          AND relpersistence <> 'p'
        ORDER BY rel_schema, rel_tblseq, 1;
-- With PG 11-, check that all tables are WITHOUT OIDS (i.e. have not been altered as WITH OIDS after their tables group creation).
    IF emaj._pg_version_num() < 120000 THEN
      RETURN QUERY
        SELECT 'Error: In the rollbackable group "' || rel_group || '", the table "' ||
               rel_schema || '"."' || rel_tblseq || '" is WITH OIDS.' AS msg
          FROM emaj.emaj_relation
               JOIN emaj.emaj_group ON (group_name = rel_group)
               JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
               JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
          WHERE upper_inf(rel_time_range)
            AND rel_kind = 'r'
            AND group_is_rollbackable
            AND relhasoids
          ORDER BY rel_schema, rel_tblseq, 1;
    END IF;
-- Check the primary key structure of all tables belonging to rollbackable groups is unchanged.
    RETURN QUERY
      SELECT 'Error: In the rollbackable group "' || rel_group || '", the primary key of the table "' ||
             rel_schema || '"."' || rel_tblseq || '" has changed (' ||
             rel_sql_rlbk_pk_columns || ' => ' || current_pk_columns || ').' AS msg
        FROM
          (SELECT rel_schema, rel_tblseq, rel_group, rel_sql_rlbk_pk_columns,
                 string_agg(quote_ident(attname), ',' ORDER BY attnum) AS current_pk_columns
             FROM emaj.emaj_relation
                  JOIN emaj.emaj_group ON (group_name = rel_group)
                  JOIN pg_catalog.pg_class ON (relname = rel_tblseq)
                  JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_schema)
                  JOIN pg_catalog.pg_index ON (indrelid = pg_class.oid)
                  JOIN pg_catalog.pg_attribute ON (pg_attribute.attrelid = pg_index.indrelid)
             WHERE rel_kind = 'r'
               AND upper_inf(rel_time_range)
               AND group_is_rollbackable
               AND attnum = ANY (indkey)
               AND indisprimary
               AND attnum > 0
               AND attisdropped = FALSE
             GROUP BY rel_schema, rel_tblseq, rel_group, rel_sql_rlbk_pk_columns
          ) AS t
        WHERE rel_sql_rlbk_pk_columns <> current_pk_columns
        ORDER BY rel_schema, rel_tblseq, 1;
-- Check the array of triggers to ignore at rollback time only contains existing triggers.
    RETURN QUERY
      SELECT 'Error: In the rollbackable group "' || rel_group || '", the trigger "' || trg_name || '" for table "'
          || rel_schema || '"."' || rel_tblseq || '" is missing. '
          || 'Use the emaj_modify_table() function to adjust the list of application triggers that should not be'
          || ' automatically disabled at rollback time.'
             AS msg
        FROM
          (SELECT rel_group, rel_schema, rel_tblseq, unnest(rel_ignored_triggers) AS trg_name
             FROM emaj.emaj_relation
             WHERE upper_inf(rel_time_range)
               AND rel_ignored_triggers IS NOT NULL
          ) AS t
        WHERE NOT EXISTS
                 (SELECT NULL
                    FROM pg_catalog.pg_trigger
                         JOIN pg_catalog.pg_class ON (pg_class.oid = tgrelid)
                         JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace)
                    WHERE nspname = rel_schema
                      AND relname = rel_tblseq
                      AND tgname = trg_name
                 )
        ORDER BY rel_schema, rel_tblseq, 1;
-- Check all log tables have the 6 required technical columns.
    RETURN QUERY
      SELECT msg FROM
        (SELECT DISTINCT rel_schema, rel_tblseq,
                'Error: In the group "' || rel_group || '", the log table "' ||
                rel_log_schema || '"."' || rel_log_table || '" miss some technical columns (' ||
                string_agg(attname,', ') || ').' AS msg
           FROM
             (  SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname
                  FROM emaj.emaj_relation,
                       (VALUES ('emaj_verb'), ('emaj_tuple'), ('emaj_gid'), ('emaj_changed'), ('emaj_txid'), ('emaj_user')) AS t(attname)
                  WHERE rel_kind = 'r'
                    AND upper_inf(rel_time_range)
                    AND EXISTS
                          (SELECT NULL
                             FROM pg_catalog.pg_namespace
                                  JOIN pg_catalog.pg_class ON (relnamespace = pg_namespace.oid)
                             WHERE nspname = rel_log_schema
                               AND relname = rel_log_table
                          )
              EXCEPT
                SELECT rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table, attname
                  FROM emaj.emaj_relation
                       JOIN pg_catalog.pg_class ON (relname = rel_log_table)
                       JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = relnamespace AND nspname = rel_log_schema)
                       JOIN pg_catalog.pg_attribute ON (attrelid = pg_class.oid)
                  WHERE attnum > 0
                    AND attisdropped = FALSE
                    AND attname IN ('emaj_verb', 'emaj_tuple', 'emaj_gid', 'emaj_changed', 'emaj_txid', 'emaj_user')
                    AND rel_kind = 'r'
                    AND upper_inf(rel_time_range)
             ) AS t2
           GROUP BY rel_group, rel_schema, rel_tblseq, rel_log_schema, rel_log_table
           ORDER BY 1,2,3
         ) AS t;
--
-- Warnings detection.
--
-- Detect all sequences associated to a serial or a "generated as identity" column have their related table in the same group.
    RETURN QUERY
      SELECT msg FROM
        (WITH serial_dependencies AS
           (SELECT rs.rel_group AS seq_group, rs.rel_schema AS seq_schema, rs.rel_tblseq AS seq_name,
                   rt.rel_group AS tbl_group, nt.nspname AS tbl_schema, ct.relname AS tbl_name
              FROM emaj.emaj_relation rs
                   JOIN pg_catalog.pg_class cs ON (cs.relname = rel_tblseq)
                   JOIN pg_catalog.pg_namespace ns ON (ns.oid = cs.relnamespace AND ns.nspname = rel_schema)
                   JOIN pg_catalog.pg_depend ON (pg_depend.objid = cs.oid)
                   JOIN pg_catalog.pg_class ct ON (ct.oid = pg_depend.refobjid)
                   JOIN pg_catalog.pg_namespace nt ON (nt.oid = ct.relnamespace)
                   LEFT OUTER JOIN emaj.emaj_relation rt ON (rt.rel_schema = nt.nspname AND rt.rel_tblseq = ct.relname
                                                             AND (rt.rel_time_range IS NULL OR upper_inf(rt.rel_time_range)))
              WHERE rs.rel_kind = 'S'
                AND upper_inf(rs.rel_time_range)
                AND pg_depend.classid = pg_depend.refclassid             -- the classid et refclassid must be 'pg_class'
                AND pg_depend.classid =
                      (SELECT oid
                         FROM pg_catalog.pg_class
                         WHERE relname = 'pg_class'
                      )
           )
           SELECT DISTINCT seq_schema, seq_name,
                  'Warning: In the group "' || seq_group || '", the sequence "' || seq_schema || '"."' || seq_name ||
                  '" is linked to the table "' || tbl_schema || '"."' || tbl_name ||
                  '" but this table does not belong to any tables group.' AS msg
             FROM serial_dependencies
             WHERE tbl_group IS NULL
         UNION ALL
           SELECT DISTINCT seq_schema, seq_name,
                  'Warning: In the group "' || seq_group || '", the sequence "' || seq_schema || '"."' || seq_name ||
                  '" is linked to the table "' || tbl_schema || '"."' || tbl_name ||
                  '" but this table belongs to another tables group (' || tbl_group || ').' AS msg
             FROM serial_dependencies
             WHERE tbl_group <> seq_group
           ORDER BY 1,2,3
        ) AS t;
-- Detect tables linked by a foreign key but not belonging to the same tables group.
    RETURN QUERY
      SELECT msg FROM
        (WITH fk_dependencies AS             -- all foreign keys that link 2 tables at least one of both belongs to a tables group
           (SELECT n.nspname AS tbl_schema, t.relname AS tbl_name, c.conname, nf.nspname AS reftbl_schema, tf.relname AS reftbl_name,
                 r.rel_group AS tbl_group, g.group_is_rollbackable AS tbl_group_is_rollbackable,
                 rf.rel_group AS reftbl_group, gf.group_is_rollbackable AS reftbl_group_is_rollbackable
              FROM pg_catalog.pg_constraint c
                   JOIN pg_catalog.pg_class t      ON (t.oid = c.conrelid)
                   JOIN pg_catalog.pg_namespace n  ON (n.oid = t.relnamespace)
                   JOIN pg_catalog.pg_class tf     ON (tf.oid = c.confrelid)
                   JOIN pg_catalog.pg_namespace nf ON (nf.oid = tf.relnamespace)
                   LEFT OUTER JOIN emaj.emaj_relation r ON (r.rel_schema = n.nspname AND r.rel_tblseq = t.relname
                                                       AND upper_inf(r.rel_time_range))
                   LEFT OUTER JOIN emaj.emaj_group g ON (g.group_name = r.rel_group)
                   LEFT OUTER JOIN emaj.emaj_relation rf ON (rf.rel_schema = nf.nspname AND rf.rel_tblseq = tf.relname
                                                       AND upper_inf(rf.rel_time_range))
                   LEFT OUTER JOIN emaj.emaj_group gf ON (gf.group_name = rf.rel_group)
              WHERE contype = 'f'                                         -- FK constraints only
                AND (r.rel_group IS NOT NULL OR rf.rel_group IS NOT NULL) -- at least the table or the referenced table belongs to
                                                                          -- a tables group
                AND t.relkind = 'r'                                       -- only constraint linking true tables, ie. excluding
                AND tf.relkind = 'r'                                      --   partitionned tables
           )
           SELECT tbl_schema, tbl_name,
                  'Warning: In the group "' || tbl_group || '", the foreign key "' || conname ||
                  '" on the table "' || tbl_schema || '"."' || tbl_name ||
                  '" references the table "' || reftbl_schema || '"."' || reftbl_name || '" that does not belong to any group.' AS msg
             FROM fk_dependencies
             WHERE tbl_group IS NOT NULL
               AND tbl_group_is_rollbackable
               AND reftbl_group IS NULL
         UNION ALL
           SELECT tbl_schema, tbl_name,
                  'Warning: In the group "' || reftbl_group || '", the table "' || reftbl_schema || '"."' || reftbl_name ||
                  '" is referenced by the foreign key "' || conname ||
                  '" of the table "' || tbl_schema || '"."' || tbl_name || '" that does not belong to any group.' AS msg
             FROM fk_dependencies
             WHERE reftbl_group IS NOT NULL
               AND reftbl_group_is_rollbackable
               AND tbl_group IS NULL
        UNION ALL
          SELECT tbl_schema, tbl_name,
                 'Warning: In the group "' || tbl_group || '", the foreign key "' || conname ||
                 '" on the table "' || tbl_schema || '"."' || tbl_name ||
                 '" references the table "' || reftbl_schema || '"."' || reftbl_name || '" that belongs to another group ("' ||
                 reftbl_group || '")' AS msg
            FROM fk_dependencies
            WHERE tbl_group IS NOT NULL
              AND reftbl_group IS NOT NULL
              AND tbl_group <> reftbl_group
              AND (tbl_group_is_rollbackable OR reftbl_group_is_rollbackable)
          ORDER BY 1,2,3
        ) AS t;
--
    RETURN;
  END;
$_verify_all_groups$;

CREATE OR REPLACE FUNCTION emaj.emaj_verify_all()
RETURNS SETOF TEXT LANGUAGE plpgsql AS
$emaj_verify_all$
-- The function verifies the consistency between all emaj objects present inside emaj schema and
-- emaj objects related to tables and sequences referenced in the emaj_relation table.
-- It returns a set of warning messages for discovered discrepancies. If no error is detected, a single row is returned.
  DECLARE
    v_errorFound             BOOLEAN = FALSE;
    r_object                 RECORD;
  BEGIN
-- Global checks.
-- Detect if the current postgres version is at least 11.
    IF emaj._pg_version_num() < 110000 THEN
      RETURN NEXT 'Error: The current postgres version (' || version()
               || ') is not compatible with this E-Maj version. It should be at least 11';
      v_errorFound = TRUE;
    END IF;
-- Check all E-Maj schemas.
    FOR r_object IN
      SELECT msg
        FROM emaj._verify_all_schemas() msg
    LOOP
      RETURN NEXT r_object.msg;
      IF r_object.msg LIKE 'Error%' THEN
        v_errorFound = TRUE;
      END IF;
    END LOOP;
-- Check all groups components.
    FOR r_object IN
      SELECT msg
        FROM emaj._verify_all_groups() msg
    LOOP
      RETURN NEXT r_object.msg;
      IF r_object.msg LIKE 'Error%' THEN
        v_errorFound = TRUE;
      END IF;
    END LOOP;
-- Report a warning if the emaj_protection_trg event triggers is missing.
-- The other event triggers are protected by the emaj extension they belong to.
    PERFORM 0
      FROM pg_catalog.pg_event_trigger
      WHERE evtname = 'emaj_protection_trg';
    IF NOT FOUND THEN
      RETURN NEXT 'Warning: The "emaj_protection_trg" event triggers is missing. It can be recreated using the '
                  'emaj_enable_protection_by_event_triggers() function.';
    END IF;
-- Report a warning if some E-Maj event triggers exist but are not enabled.
    IF EXISTS
         (SELECT 0
            FROM pg_catalog.pg_event_trigger
              WHERE evtname LIKE 'emaj%'
                AND evtenabled = 'D'
         ) THEN
      RETURN NEXT 'Warning: Some E-Maj event triggers are disabled. You may enable them using the'
               || ' emaj_enable_protection_by_event_triggers() function.';
    END IF;
-- Final message if no error has been yet detected.
    IF NOT v_errorFound THEN
      RETURN NEXT 'No error detected';
    END IF;
--
    RETURN;
  END;
$emaj_verify_all$;
COMMENT ON FUNCTION emaj.emaj_verify_all() IS
$$Verifies the consistency between existing E-Maj and application objects.$$;

CREATE OR REPLACE FUNCTION emaj._event_trigger_sql_drop_fnct()
RETURNS EVENT_TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
$_event_trigger_sql_drop_fnct$
-- This function is called by the emaj_sql_drop_trg event trigger.
-- The function blocks any ddl operation that leads to a drop of
--   - an application table or a sequence registered into an active (not stopped) E-Maj group, or a schema containing such tables/sequence
--   - an E-Maj schema, a log table, a log sequence, a log function or a log trigger
-- The drop of emaj schema or extension is managed by another event trigger.
-- The function is declared SECURITY DEFINER so that non emaj roles can access the emaj internal tables when dropping their objects.
  DECLARE
    v_groupName              TEXT;
    v_tableName              TEXT;
    r_dropped                RECORD;
  BEGIN
-- Scan all dropped objects.
    FOR r_dropped IN
      SELECT object_type, schema_name, object_name, object_identity, original
        FROM pg_event_trigger_dropped_objects()
    LOOP
      CASE
        WHEN r_dropped.object_type = 'schema' THEN
-- The object is a schema.
-- Look at the emaj_relation table to verify that the schema being dropped does not belong to any active (not stopped) group.
          SELECT string_agg(DISTINCT rel_group, ', ' ORDER BY rel_group) INTO v_groupName
            FROM emaj.emaj_relation
                 JOIN emaj.emaj_group ON (group_name = rel_group)
            WHERE rel_schema = r_dropped.object_name
              AND upper_inf(rel_time_range)
              AND group_is_logging;
          IF v_groupName IS NOT NULL THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the application schema "%". But it belongs to the active tables'
                            ' groups "%".', r_dropped.object_name, v_groupName;
          END IF;
-- Look at the emaj_schema table to verify that the schema being dropped is not an E-Maj schema containing log tables.
          IF EXISTS
               (SELECT 0
                  FROM emaj.emaj_schema
                  WHERE sch_name = r_dropped.object_name
               ) THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the schema "%". But dropping an E-Maj schema is not allowed.',
              r_dropped.object_name;
          END IF;
        WHEN r_dropped.object_type = 'table' THEN
-- The object is a table.
-- Look at the emaj_relation table to verify that the table being dropped does not currently belong to any active (not stopped) group.
          SELECT rel_group INTO v_groupName
            FROM emaj.emaj_relation
                 JOIN emaj.emaj_group ON (group_name = rel_group)
            WHERE rel_schema = r_dropped.schema_name
              AND rel_tblseq = r_dropped.object_name
              AND upper_inf(rel_time_range)
              AND group_is_logging;
          IF FOUND THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the application table "%.%". But it belongs to the active tables'
                            ' group "%".', r_dropped.schema_name, r_dropped.object_name, v_groupName;
          END IF;
-- Look at the emaj_relation table to verify that the table being dropped is not a log table.
          IF EXISTS
               (SELECT 0
                  FROM emaj.emaj_relation
                  WHERE rel_log_schema = r_dropped.schema_name
                    AND rel_log_table = r_dropped.object_name
               ) THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the log table "%.%". But dropping an E-Maj log table is not allowed.',
                            r_dropped.schema_name, r_dropped.object_name;
          END IF;
        WHEN r_dropped.object_type = 'sequence' THEN
-- The object is a sequence.
-- Look at the emaj_relation table to verify that the sequence being dropped does not currently belong to any active (not stopped) group.
          SELECT rel_group INTO v_groupName
            FROM emaj.emaj_relation
                 JOIN emaj.emaj_group ON (group_name = rel_group)
            WHERE rel_schema = r_dropped.schema_name
              AND rel_tblseq = r_dropped.object_name
              AND upper_inf(rel_time_range)
              AND group_is_logging;
          IF FOUND THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the application sequence "%.%". But it belongs to the active'
                            ' tables group "%".', r_dropped.schema_name, r_dropped.object_name, v_groupName;
          END IF;
-- Look at the emaj_relation table to verify that the sequence being dropped is not a log sequence.
          IF EXISTS
               (SELECT 0
                  FROM emaj.emaj_relation
                  WHERE rel_log_schema = r_dropped.schema_name
                    AND rel_log_sequence = r_dropped.object_name
               ) THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the log sequence "%.%". But dropping an E-Maj sequence is not'
                           ' allowed.', r_dropped.schema_name, r_dropped.object_name;
          END IF;
        WHEN r_dropped.object_type = 'function' THEN
-- The object is a function.
-- Look at the emaj_relation table to verify that the function being dropped is not a log function.
          IF EXISTS
            (SELECT 0
               FROM emaj.emaj_relation
               WHERE r_dropped.object_identity = quote_ident(rel_log_schema) || '.' || quote_ident(rel_log_function) || '()'
            ) THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the log function "%". But dropping an E-Maj log function is not'
                            ' allowed.', r_dropped.object_identity;
          END IF;
-- Verify that the function is not public._emaj_protection_event_trigger_fnct() (which is intentionaly not linked to the emaj extension)
          IF r_dropped.object_identity = 'public._emaj_protection_event_trigger_fnct()' THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the public._emaj_protection_event_trigger_fnct() function. '
                            'But dropping this E-Maj technical function is not allowed.';
          END IF;
        WHEN r_dropped.object_type = 'trigger' THEN
-- The object is a trigger.
-- Look at the trigger name pattern to identify emaj trigger.
-- Do not raise an exception if the triggers drop is derived from a drop of a table or a function.
          IF r_dropped.original AND
             (r_dropped.object_identity LIKE 'emaj_log_trg%' OR r_dropped.object_identity LIKE 'emaj_trunc_trg%') THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the "%" E-Maj trigger. But dropping an E-Maj trigger is not allowed.',
              r_dropped.object_identity;
          END IF;
        WHEN r_dropped.object_type = 'table constraint' AND tg_tag = 'ALTER TABLE' THEN
-- The object is a table constraint. It may be primary key or another constraint.
-- Verify that if the targeted table belongs to a rollbackable group, its primary key still exists.
-- The table name can be found in the last part of the object_identity variable,
-- after the '.' that separates the schema and table names, and possibly between double quotes
          v_tableName = substring(r_dropped.object_identity from '\.(?:"?)(.*)(?:"?)');
          SELECT rel_group INTO v_groupName
            FROM emaj.emaj_relation
                 JOIN emaj.emaj_group ON (group_name = rel_group)
            WHERE rel_schema = r_dropped.schema_name
              AND rel_tblseq = v_tableName
              AND upper_inf(rel_time_range)
              AND group_is_rollbackable
              AND NOT EXISTS
                (SELECT 0
                   FROM pg_catalog.pg_class c
                        JOIN pg_catalog.pg_namespace ON (pg_namespace.oid = c.relnamespace)
                        JOIN pg_catalog.pg_constraint ON (connamespace = pg_namespace.oid AND conrelid = c.oid)
                             WHERE contype = 'p'
                               AND nspname = rel_schema
                               AND c.relname = rel_tblseq
                );
          IF FOUND THEN
            RAISE EXCEPTION 'E-Maj event trigger: Attempting to drop the primary key for the application table "%.%". But it belongs to'
                            ' the rollbackable tables group "%".', r_dropped.schema_name, v_tableName, v_groupName;
          END IF;
        ELSE
          CONTINUE;
      END CASE;
    END LOOP;
  END;
$_event_trigger_sql_drop_fnct$;
COMMENT ON FUNCTION emaj._event_trigger_sql_drop_fnct() IS
$$E-Maj extension: support of the emaj_sql_drop_trg event trigger.$$;

CREATE OR REPLACE FUNCTION emaj.emaj_disable_protection_by_event_triggers()
RETURNS INT LANGUAGE plpgsql AS
$emaj_disable_protection_by_event_triggers$
-- This function disables all known E-Maj event triggers that are in enabled state.
-- It may be used by an emaj_adm role.
-- Output: number of effectively disabled event triggers.
  DECLARE
    v_eventTriggers          TEXT[];
  BEGIN
-- Call the _disable_event_triggers() function and get the disabled event trigger names array.
    SELECT emaj._disable_event_triggers() INTO v_eventTriggers;
-- Keep a trace into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_wording)
      VALUES ('DISABLE_PROTECTION', 'EVENT TRIGGERS DISABLED',
              CASE WHEN v_eventTriggers <> ARRAY[]::TEXT[] THEN array_to_string(v_eventTriggers, ', ') ELSE '<none>' END);
-- Return the number of disabled event triggers.
    RETURN coalesce(array_length(v_eventTriggers,1),0);
  END;
$emaj_disable_protection_by_event_triggers$;
COMMENT ON FUNCTION emaj.emaj_disable_protection_by_event_triggers() IS
$$Disables the protection of E-Maj components by event triggers.$$;

CREATE OR REPLACE FUNCTION emaj.emaj_enable_protection_by_event_triggers()
RETURNS INT LANGUAGE plpgsql AS
$emaj_enable_protection_by_event_triggers$
-- This function enables all known E-Maj event triggers that are in disabled state.
-- It may be used by an emaj_adm role.
-- Output: number of effectively enabled event triggers.
  DECLARE
    v_eventTriggers          TEXT[];
  BEGIN
-- Build the event trigger names array from the pg_event_trigger table.
    SELECT coalesce(array_agg(evtname  ORDER BY evtname),ARRAY[]::TEXT[]) INTO v_eventTriggers
      FROM pg_catalog.pg_event_trigger
      WHERE evtname LIKE 'emaj%'
        AND evtenabled = 'D';
-- Call the _enable_event_triggers() function.
    PERFORM emaj._enable_event_triggers(v_eventTriggers);
-- Keep a trace into the emaj_hist table.
    INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_wording)
      VALUES ('ENABLE_PROTECTION', 'EVENT TRIGGERS ENABLED',
              CASE WHEN v_eventTriggers <> ARRAY[]::TEXT[] THEN array_to_string(v_eventTriggers, ', ') ELSE '<none>' END);
-- Return the number of enabled event triggers.
    RETURN coalesce(array_length(v_eventTriggers,1),0);
  END;
$emaj_enable_protection_by_event_triggers$;
COMMENT ON FUNCTION emaj.emaj_enable_protection_by_event_triggers() IS
$$Enables the protection of E-Maj components by event triggers.$$;

CREATE OR REPLACE FUNCTION emaj._enable_event_triggers(p_eventTriggers TEXT[])
RETURNS TEXT[] LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
$_enable_event_triggers$
-- This function enables all event triggers supplied as parameter.
-- It also recreates the emaj_protection_trg event trigger if it does not exist. This event trigger is the only component
-- that is not linked to the emaj extension and cannot be protected by another event trigger.
-- The function is called by functions that alter or drop E-Maj components, such as
--   _drop_group(), _alter_groups(), _delete_before_mark_group() and _reset_groups().
-- It is also called by the user emaj_enable_event_triggers_protection() function.
-- Input: array of event trigger names to enable.
-- Output: same array.
-- The function is declared as SECURITY DEFINER because only superusers can alter an event trigger
  DECLARE
    v_eventTrigger           TEXT;
  BEGIN
-- If the emaj_protection_trg event trigger does not exist, recreate it and report.
    PERFORM 0
      FROM pg_catalog.pg_event_trigger
      WHERE evtname = 'emaj_protection_trg';
    IF NOT FOUND THEN
      CREATE EVENT TRIGGER emaj_protection_trg
        ON sql_drop
        WHEN TAG IN ('DROP EXTENSION','DROP SCHEMA')
        EXECUTE PROCEDURE public._emaj_protection_event_trigger_fnct();
      COMMENT ON EVENT TRIGGER emaj_protection_trg IS
      $$Blocks the removal of the emaj extension or schema.$$;
      RAISE WARNING '_enable_event_triggers: the emaj_protection_trg event trigger has been recreated.';
      INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_wording)
        VALUES ('ENABLE_PROTECTION', 'EVENT TRIGGERS RECREATED', 'emaj_protection_trg');
    END If;
    FOREACH v_eventTrigger IN ARRAY p_eventTriggers
    LOOP
      EXECUTE format('ALTER EVENT TRIGGER %I ENABLE',
                     v_eventTrigger);
    END LOOP;
--
  RETURN p_eventTriggers;
  END;
$_enable_event_triggers$;

--<end_functions>                                pattern used by the tool that extracts and insert the functions definition
------------------------------------------
--                                      --
-- event triggers and related functions --
--                                      --
------------------------------------------

------------------------------------
--                                --
-- emaj roles and rights          --
--                                --
------------------------------------
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA emaj FROM PUBLIC;

GRANT ALL ON ALL TABLES IN SCHEMA emaj TO emaj_adm;
GRANT ALL ON ALL SEQUENCES IN SCHEMA emaj TO emaj_adm;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA emaj TO emaj_adm;

GRANT SELECT ON ALL TABLES IN SCHEMA emaj TO emaj_viewer;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA emaj TO emaj_viewer;
REVOKE SELECT ON TABLE emaj.emaj_param FROM emaj_viewer;


------------------------------------
--                                --
-- Complete the upgrade           --
--                                --
------------------------------------

-- Enable the event triggers.
DO
$tmp$
  DECLARE
    v_event_trigger_array    TEXT[];
  BEGIN
-- Build the event trigger names array from the pg_event_trigger table.
    SELECT coalesce(array_agg(evtname),ARRAY[]::TEXT[]) INTO v_event_trigger_array
      FROM pg_catalog.pg_event_trigger WHERE evtname LIKE 'emaj%' AND evtenabled = 'D';
-- Call the _enable_event_triggers() function.
    PERFORM emaj._enable_event_triggers(v_event_trigger_array);
  END;
$tmp$;

-- Set comments for all internal functions, by directly inserting a row in the pg_description table for all emaj functions
-- that do not have yet a recorded comment.
INSERT INTO pg_catalog.pg_description (objoid, classoid, objsubid, description)
  SELECT pg_proc.oid, pg_class.oid, 0 , 'E-Maj internal function'
    FROM pg_catalog.pg_proc, pg_catalog.pg_class
    WHERE pg_class.relname = 'pg_proc'
      AND pg_proc.oid IN               -- list all emaj functions that do not have yet a comment in pg_description
       (SELECT pg_proc.oid
          FROM pg_catalog.pg_proc
               JOIN pg_catalog.pg_namespace ON (pronamespace=pg_namespace.oid)
               LEFT OUTER JOIN pg_catalog.pg_description ON (pg_description.objoid = pg_proc.oid
                                     AND classoid = (SELECT oid FROM pg_catalog.pg_class WHERE relname = 'pg_proc')
                                     AND objsubid = 0)
          WHERE nspname = 'emaj' AND (proname LIKE E'emaj\\_%' OR proname LIKE E'\\_%')
            AND pg_description.description IS NULL
       );

-- Update the version id in the emaj_param table.
ALTER TABLE emaj.emaj_param DISABLE TRIGGER emaj_param_change_trg;
UPDATE emaj.emaj_param SET param_value_text = '<devel>' WHERE param_key = 'emaj_version';
ALTER TABLE emaj.emaj_param ENABLE TRIGGER emaj_param_change_trg;

-- Insert the upgrade end record in the operation history.
INSERT INTO emaj.emaj_hist (hist_function, hist_event, hist_object, hist_wording)
  VALUES ('EMAJ_INSTALL','END','E-Maj <devel>', 'Upgrade from 4.1.0 completed');

-- Post installation checks.
DO
$tmp$
  DECLARE
  BEGIN
-- Check the max_prepared_transactions GUC value.
    IF current_setting('max_prepared_transactions')::int <= 1 THEN
      RAISE WARNING 'E-Maj upgrade: as the max_prepared_transactions parameter value (%) on this cluster is too low, no parallel rollback '
                    'is possible.', current_setting('max_prepared_transactions');
    END IF;
  END;
$tmp$;

RESET default_tablespace;
SET client_min_messages TO default;
