--
-- PostgreSQL database dump
--

-- Dumped from database version 17.2 (Ubuntu 17.2-1.pgdg22.04+1)
-- Dumped by pg_dump version 17.2 (Ubuntu 17.2-1.pgdg22.04+1)

-- Started on 2025-12-03 14:39:05 UTC

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 14 (class 2615 OID 16708)
-- Name: metric_helpers; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA metric_helpers;


ALTER SCHEMA metric_helpers OWNER TO postgres;

--
-- TOC entry 20 (class 2615 OID 16756)
-- Name: pooler; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA pooler;


ALTER SCHEMA pooler OWNER TO postgres;

--
-- TOC entry 208 (class 2615 OID 16641)
-- Name: user_management; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA user_management;


ALTER SCHEMA user_management OWNER TO postgres;

--
-- TOC entry 5 (class 3079 OID 16651)
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- TOC entry 4178 (class 0 OID 0)
-- Dependencies: 5
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- TOC entry 4 (class 3079 OID 16688)
-- Name: pg_stat_kcache; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_kcache WITH SCHEMA public;


--
-- TOC entry 4179 (class 0 OID 0)
-- Dependencies: 4
-- Name: EXTENSION pg_stat_kcache; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_kcache IS 'Kernel statistics gathering';


--
-- TOC entry 3 (class 3079 OID 16701)
-- Name: set_user; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS set_user WITH SCHEMA public;


--
-- TOC entry 4180 (class 0 OID 0)
-- Dependencies: 3
-- Name: EXTENSION set_user; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION set_user IS 'similar to SET ROLE but with added logging';


--
-- TOC entry 2 (class 3079 OID 18458)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- TOC entry 4181 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- TOC entry 528 (class 1255 OID 16714)
-- Name: get_btree_bloat_approx(); Type: FUNCTION; Schema: metric_helpers; Owner: postgres
--

CREATE FUNCTION metric_helpers.get_btree_bloat_approx(OUT i_database name, OUT i_schema_name name, OUT i_table_name name, OUT i_index_name name, OUT i_real_size numeric, OUT i_extra_size numeric, OUT i_extra_ratio double precision, OUT i_fill_factor integer, OUT i_bloat_size double precision, OUT i_bloat_ratio double precision, OUT i_is_na boolean) RETURNS SETOF record
    LANGUAGE sql IMMUTABLE STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
SELECT current_database(), nspname AS schemaname, tblname, idxname, bs*(relpages)::bigint AS real_size,
  bs*(relpages-est_pages)::bigint AS extra_size,
  100 * (relpages-est_pages)::float / relpages AS extra_ratio,
  fillfactor,
  CASE WHEN relpages > est_pages_ff
    THEN bs*(relpages-est_pages_ff)
    ELSE 0
  END AS bloat_size,
  100 * (relpages-est_pages_ff)::float / relpages AS bloat_ratio,
  is_na
  -- , 100-(pst).avg_leaf_density AS pst_avg_bloat, est_pages, index_tuple_hdr_bm, maxalign, pagehdr, nulldatawidth, nulldatahdrwidth, reltuples, relpages -- (DEBUG INFO)
FROM (
  SELECT coalesce(1 +
         ceil(reltuples/floor((bs-pageopqdata-pagehdr)/(4+nulldatahdrwidth)::float)), 0 -- ItemIdData size + computed avg size of a tuple (nulldatahdrwidth)
      ) AS est_pages,
      coalesce(1 +
         ceil(reltuples/floor((bs-pageopqdata-pagehdr)*fillfactor/(100*(4+nulldatahdrwidth)::float))), 0
      ) AS est_pages_ff,
      bs, nspname, tblname, idxname, relpages, fillfactor, is_na
      -- , pgstatindex(idxoid) AS pst, index_tuple_hdr_bm, maxalign, pagehdr, nulldatawidth, nulldatahdrwidth, reltuples -- (DEBUG INFO)
  FROM (
      SELECT maxalign, bs, nspname, tblname, idxname, reltuples, relpages, idxoid, fillfactor,
            ( index_tuple_hdr_bm +
                maxalign - CASE -- Add padding to the index tuple header to align on MAXALIGN
                  WHEN index_tuple_hdr_bm%maxalign = 0 THEN maxalign
                  ELSE index_tuple_hdr_bm%maxalign
                END
              + nulldatawidth + maxalign - CASE -- Add padding to the data to align on MAXALIGN
                  WHEN nulldatawidth = 0 THEN 0
                  WHEN nulldatawidth::integer%maxalign = 0 THEN maxalign
                  ELSE nulldatawidth::integer%maxalign
                END
            )::numeric AS nulldatahdrwidth, pagehdr, pageopqdata, is_na
            -- , index_tuple_hdr_bm, nulldatawidth -- (DEBUG INFO)
      FROM (
          SELECT n.nspname, ct.relname AS tblname, i.idxname, i.reltuples, i.relpages,
              i.idxoid, i.fillfactor, current_setting('block_size')::numeric AS bs,
              CASE -- MAXALIGN: 4 on 32bits, 8 on 64bits (and mingw32 ?)
                WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64' THEN 8
                ELSE 4
              END AS maxalign,
              /* per page header, fixed size: 20 for 7.X, 24 for others */
              24 AS pagehdr,
              /* per page btree opaque data */
              16 AS pageopqdata,
              /* per tuple header: add IndexAttributeBitMapData if some cols are null-able */
              CASE WHEN max(coalesce(s.stanullfrac,0)) = 0
                  THEN 2 -- IndexTupleData size
                  ELSE 2 + (( 32 + 8 - 1 ) / 8) -- IndexTupleData size + IndexAttributeBitMapData size ( max num filed per index + 8 - 1 /8)
              END AS index_tuple_hdr_bm,
              /* data len: we remove null values save space using it fractionnal part from stats */
              sum( (1-coalesce(s.stanullfrac, 0)) * coalesce(s.stawidth, 1024)) AS nulldatawidth,
              max( CASE WHEN a.atttypid = 'pg_catalog.name'::regtype THEN 1 ELSE 0 END ) > 0 AS is_na
          FROM (
              SELECT idxname, reltuples, relpages, tbloid, idxoid, fillfactor,
                  CASE WHEN indkey[i]=0 THEN idxoid ELSE tbloid END AS att_rel,
                  CASE WHEN indkey[i]=0 THEN i ELSE indkey[i] END AS att_pos
              FROM (
                  SELECT idxname, reltuples, relpages, tbloid, idxoid, fillfactor, indkey, generate_series(1,indnatts) AS i
                  FROM (
                      SELECT ci.relname AS idxname, ci.reltuples, ci.relpages, i.indrelid AS tbloid,
                          i.indexrelid AS idxoid,
                          coalesce(substring(
                              array_to_string(ci.reloptions, ' ')
                              from 'fillfactor=([0-9]+)')::smallint, 90) AS fillfactor,
                          i.indnatts,
                          string_to_array(textin(int2vectorout(i.indkey)),' ')::int[] AS indkey
                      FROM pg_index i
                      JOIN pg_class ci ON ci.oid=i.indexrelid
                      WHERE ci.relam=(SELECT oid FROM pg_am WHERE amname = 'btree')
                        AND ci.relpages > 0
                  ) AS idx_data
              ) AS idx_data_cross
          ) i
          JOIN pg_attribute a ON a.attrelid = i.att_rel
                             AND a.attnum = i.att_pos
          JOIN pg_statistic s ON s.starelid = i.att_rel
                             AND s.staattnum = i.att_pos
          JOIN pg_class ct ON ct.oid = i.tbloid
          JOIN pg_namespace n ON ct.relnamespace = n.oid
          GROUP BY 1,2,3,4,5,6,7,8,9,10
      ) AS rows_data_stats
  ) AS rows_hdr_pdg_stats
) AS relation_stats;
$$;


ALTER FUNCTION metric_helpers.get_btree_bloat_approx(OUT i_database name, OUT i_schema_name name, OUT i_table_name name, OUT i_index_name name, OUT i_real_size numeric, OUT i_extra_size numeric, OUT i_extra_ratio double precision, OUT i_fill_factor integer, OUT i_bloat_size double precision, OUT i_bloat_ratio double precision, OUT i_is_na boolean) OWNER TO postgres;

--
-- TOC entry 503 (class 1255 OID 16726)
-- Name: get_nearly_exhausted_sequences(double precision); Type: FUNCTION; Schema: metric_helpers; Owner: postgres
--

CREATE FUNCTION metric_helpers.get_nearly_exhausted_sequences(threshold double precision, OUT schemaname name, OUT sequencename name, OUT seq_percent_used numeric) RETURNS SETOF record
    LANGUAGE sql STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
SELECT *
FROM (
  SELECT 
    schemaname,
    sequencename,
    round(abs(
      ceil((abs(last_value::numeric - start_value) + 1) / increment_by) / 
        floor((CASE WHEN increment_by > 0
                    THEN (max_value::numeric - start_value)
                    ELSE (start_value::numeric - min_value)
                    END + 1) / increment_by
              ) * 100 
      ), 
    2) AS seq_percent_used
  FROM pg_sequences
  WHERE NOT CYCLE AND last_value IS NOT NULL
) AS s
WHERE seq_percent_used >= threshold;
$$;


ALTER FUNCTION metric_helpers.get_nearly_exhausted_sequences(threshold double precision, OUT schemaname name, OUT sequencename name, OUT seq_percent_used numeric) OWNER TO postgres;

--
-- TOC entry 535 (class 1255 OID 16709)
-- Name: get_table_bloat_approx(); Type: FUNCTION; Schema: metric_helpers; Owner: postgres
--

CREATE FUNCTION metric_helpers.get_table_bloat_approx(OUT t_database name, OUT t_schema_name name, OUT t_table_name name, OUT t_real_size numeric, OUT t_extra_size double precision, OUT t_extra_ratio double precision, OUT t_fill_factor integer, OUT t_bloat_size double precision, OUT t_bloat_ratio double precision, OUT t_is_na boolean) RETURNS SETOF record
    LANGUAGE sql IMMUTABLE STRICT SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
SELECT
  current_database(),
  schemaname,
  tblname,
  (bs*tblpages) AS real_size,
  ((tblpages-est_tblpages)*bs) AS extra_size,
  CASE WHEN tblpages - est_tblpages > 0
    THEN 100 * (tblpages - est_tblpages)/tblpages::float
    ELSE 0
  END AS extra_ratio,
  fillfactor,
  CASE WHEN tblpages - est_tblpages_ff > 0
    THEN (tblpages-est_tblpages_ff)*bs
    ELSE 0
  END AS bloat_size,
  CASE WHEN tblpages - est_tblpages_ff > 0
    THEN 100 * (tblpages - est_tblpages_ff)/tblpages::float
    ELSE 0
  END AS bloat_ratio,
  is_na
FROM (
  SELECT ceil( reltuples / ( (bs-page_hdr)/tpl_size ) ) + ceil( toasttuples / 4 ) AS est_tblpages,
    ceil( reltuples / ( (bs-page_hdr)*fillfactor/(tpl_size*100) ) ) + ceil( toasttuples / 4 ) AS est_tblpages_ff,
    tblpages, fillfactor, bs, tblid, schemaname, tblname, heappages, toastpages, is_na
    -- , tpl_hdr_size, tpl_data_size, pgstattuple(tblid) AS pst -- (DEBUG INFO)
  FROM (
    SELECT
      ( 4 + tpl_hdr_size + tpl_data_size + (2*ma)
        - CASE WHEN tpl_hdr_size%ma = 0 THEN ma ELSE tpl_hdr_size%ma END
        - CASE WHEN ceil(tpl_data_size)::int%ma = 0 THEN ma ELSE ceil(tpl_data_size)::int%ma END
      ) AS tpl_size, bs - page_hdr AS size_per_block, (heappages + toastpages) AS tblpages, heappages,
      toastpages, reltuples, toasttuples, bs, page_hdr, tblid, schemaname, tblname, fillfactor, is_na
      -- , tpl_hdr_size, tpl_data_size
    FROM (
      SELECT
        tbl.oid AS tblid, ns.nspname AS schemaname, tbl.relname AS tblname, tbl.reltuples,
        tbl.relpages AS heappages, coalesce(toast.relpages, 0) AS toastpages,
        coalesce(toast.reltuples, 0) AS toasttuples,
        coalesce(substring(
          array_to_string(tbl.reloptions, ' ')
          FROM 'fillfactor=([0-9]+)')::smallint, 100) AS fillfactor,
        current_setting('block_size')::numeric AS bs,
        CASE WHEN version()~'mingw32' OR version()~'64-bit|x86_64|ppc64|ia64|amd64' THEN 8 ELSE 4 END AS ma,
        24 AS page_hdr,
        23 + CASE WHEN MAX(coalesce(s.null_frac,0)) > 0 THEN ( 7 + count(s.attname) ) / 8 ELSE 0::int END
           + CASE WHEN bool_or(att.attname = 'oid' and att.attnum < 0) THEN 4 ELSE 0 END AS tpl_hdr_size,
        sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 0) ) AS tpl_data_size,
        bool_or(att.atttypid = 'pg_catalog.name'::regtype)
          OR sum(CASE WHEN att.attnum > 0 THEN 1 ELSE 0 END) <> count(s.attname) AS is_na
      FROM pg_attribute AS att
        JOIN pg_class AS tbl ON att.attrelid = tbl.oid
        JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
        LEFT JOIN pg_stats AS s ON s.schemaname=ns.nspname
          AND s.tablename = tbl.relname AND s.inherited=false AND s.attname=att.attname
        LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
      WHERE NOT att.attisdropped
        AND tbl.relkind = 'r'
      GROUP BY 1,2,3,4,5,6,7,8,9,10
      ORDER BY 2,3
    ) AS s
  ) AS s2
) AS s3 WHERE schemaname NOT LIKE 'information_schema';
$$;


ALTER FUNCTION metric_helpers.get_table_bloat_approx(OUT t_database name, OUT t_schema_name name, OUT t_table_name name, OUT t_real_size numeric, OUT t_extra_size double precision, OUT t_extra_ratio double precision, OUT t_fill_factor integer, OUT t_bloat_size double precision, OUT t_bloat_ratio double precision, OUT t_is_na boolean) OWNER TO postgres;

--
-- TOC entry 529 (class 1255 OID 16720)
-- Name: pg_stat_statements(boolean); Type: FUNCTION; Schema: metric_helpers; Owner: postgres
--

CREATE FUNCTION metric_helpers.pg_stat_statements(showtext boolean) RETURNS SETOF public.pg_stat_statements
    LANGUAGE sql IMMUTABLE STRICT SECURITY DEFINER
    AS $$
  SELECT * FROM public.pg_stat_statements(showtext);
$$;


ALTER FUNCTION metric_helpers.pg_stat_statements(showtext boolean) OWNER TO postgres;

--
-- TOC entry 530 (class 1255 OID 16757)
-- Name: user_lookup(text); Type: FUNCTION; Schema: pooler; Owner: postgres
--

CREATE FUNCTION pooler.user_lookup(i_username text, OUT uname text, OUT phash text) RETURNS record
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
		BEGIN
			SELECT usename, passwd FROM pg_catalog.pg_shadow
			WHERE usename = i_username INTO uname, phash;
			RETURN;
		END;
		$$;


ALTER FUNCTION pooler.user_lookup(i_username text, OUT uname text, OUT phash text) OWNER TO postgres;

--
-- TOC entry 531 (class 1255 OID 25193)
-- Name: increment_workflow_version(); Type: FUNCTION; Schema: public; Owner: n8n_postgres_user
--

CREATE FUNCTION public.increment_workflow_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
			BEGIN
				IF NEW."versionCounter" IS NOT DISTINCT FROM OLD."versionCounter" THEN
					NEW."versionCounter" = OLD."versionCounter" + 1;
				END IF;
				RETURN NEW;
			END;
			$$;


ALTER FUNCTION public.increment_workflow_version() OWNER TO n8n_postgres_user;

--
-- TOC entry 534 (class 1255 OID 16643)
-- Name: create_application_user(text); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.create_application_user(username text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $_$
DECLARE
    pw text;
BEGIN
    SELECT user_management.random_password(20) INTO pw;
    EXECUTE format($$ CREATE USER %I WITH PASSWORD %L $$, username, pw);
    RETURN pw;
END
$_$;


ALTER FUNCTION user_management.create_application_user(username text) OWNER TO postgres;

--
-- TOC entry 4190 (class 0 OID 0)
-- Dependencies: 534
-- Name: FUNCTION create_application_user(username text); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.create_application_user(username text) IS 'Creates a user that can login, sets the password to a strong random one,
which is then returned';


--
-- TOC entry 508 (class 1255 OID 16646)
-- Name: create_application_user_or_change_password(text, text); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.create_application_user_or_change_password(username text, password text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $_$
BEGIN
    PERFORM 1 FROM pg_roles WHERE rolname = username;

    IF FOUND
    THEN
        EXECUTE format($$ ALTER ROLE %I WITH PASSWORD %L $$, username, password);
    ELSE
        EXECUTE format($$ CREATE USER %I WITH PASSWORD %L $$, username, password);
    END IF;
END
$_$;


ALTER FUNCTION user_management.create_application_user_or_change_password(username text, password text) OWNER TO postgres;

--
-- TOC entry 4192 (class 0 OID 0)
-- Dependencies: 508
-- Name: FUNCTION create_application_user_or_change_password(username text, password text); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.create_application_user_or_change_password(username text, password text) IS 'USE THIS ONLY IN EMERGENCY!  The password will appear in the DB logs.
Creates a user that can login, sets the password to the one provided.
If the user already exists, sets its password.';


--
-- TOC entry 506 (class 1255 OID 16645)
-- Name: create_role(text); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.create_role(rolename text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $_$
BEGIN
    -- set ADMIN to the admin user, so every member of admin can GRANT these roles to each other
    EXECUTE format($$ CREATE ROLE %I WITH ADMIN admin $$, rolename);
END;
$_$;


ALTER FUNCTION user_management.create_role(rolename text) OWNER TO postgres;

--
-- TOC entry 4194 (class 0 OID 0)
-- Dependencies: 506
-- Name: FUNCTION create_role(rolename text); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.create_role(rolename text) IS 'Creates a role that cannot log in, but can be used to set up fine-grained privileges';


--
-- TOC entry 488 (class 1255 OID 16644)
-- Name: create_user(text); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.create_user(username text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $_$
BEGIN
    EXECUTE format($$ CREATE USER %I IN ROLE zalandos, admin $$, username);
    EXECUTE format($$ ALTER ROLE %I SET log_statement TO 'all' $$, username);
END;
$_$;


ALTER FUNCTION user_management.create_user(username text) OWNER TO postgres;

--
-- TOC entry 4196 (class 0 OID 0)
-- Dependencies: 488
-- Name: FUNCTION create_user(username text); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.create_user(username text) IS 'Creates a user that is supposed to be a human, to be authenticated without a password';


--
-- TOC entry 490 (class 1255 OID 16649)
-- Name: drop_role(text); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.drop_role(username text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
SELECT user_management.drop_user(username);
$$;


ALTER FUNCTION user_management.drop_role(username text) OWNER TO postgres;

--
-- TOC entry 4198 (class 0 OID 0)
-- Dependencies: 490
-- Name: FUNCTION drop_role(username text); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.drop_role(username text) IS 'Drop a human or application user.  Intended for cleanup (either after team changes or mistakes in role setup).
Roles (= users) that own database objects cannot be dropped.';


--
-- TOC entry 504 (class 1255 OID 16648)
-- Name: drop_user(text); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.drop_user(username text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $_$
BEGIN
    EXECUTE format($$ DROP ROLE %I $$, username);
END
$_$;


ALTER FUNCTION user_management.drop_user(username text) OWNER TO postgres;

--
-- TOC entry 4200 (class 0 OID 0)
-- Dependencies: 504
-- Name: FUNCTION drop_user(username text); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.drop_user(username text) IS 'Drop a human or application user.  Intended for cleanup (either after team changes or mistakes in role setup).
Roles (= users) that own database objects cannot be dropped.';


--
-- TOC entry 505 (class 1255 OID 16642)
-- Name: random_password(integer); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.random_password(length integer) RETURNS text
    LANGUAGE sql
    SET search_path TO 'pg_catalog'
    AS $$
WITH chars (c) AS (
    SELECT chr(33)
    UNION ALL
    SELECT chr(i) FROM generate_series (35, 38) AS t (i)
    UNION ALL
    SELECT chr(i) FROM generate_series (42, 90) AS t (i)
    UNION ALL
    SELECT chr(i) FROM generate_series (97, 122) AS t (i)
),
bricks (b) AS (
    -- build a pool of chars (the size will be the number of chars above times length)
    -- and shuffle it
    SELECT c FROM chars, generate_series(1, length) ORDER BY random()
)
SELECT substr(string_agg(b, ''), 1, length) FROM bricks;
$$;


ALTER FUNCTION user_management.random_password(length integer) OWNER TO postgres;

--
-- TOC entry 507 (class 1255 OID 16647)
-- Name: revoke_admin(text); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.revoke_admin(username text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $_$
BEGIN
    EXECUTE format($$ REVOKE admin FROM %I $$, username);
END
$_$;


ALTER FUNCTION user_management.revoke_admin(username text) OWNER TO postgres;

--
-- TOC entry 4202 (class 0 OID 0)
-- Dependencies: 507
-- Name: FUNCTION revoke_admin(username text); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.revoke_admin(username text) IS 'Use this function to make a human user less privileged,
ie. when you want to grant someone read privileges only';


--
-- TOC entry 532 (class 1255 OID 16650)
-- Name: terminate_backend(integer); Type: FUNCTION; Schema: user_management; Owner: postgres
--

CREATE FUNCTION user_management.terminate_backend(pid integer) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
SELECT pg_terminate_backend(pid);
$$;


ALTER FUNCTION user_management.terminate_backend(pid integer) OWNER TO postgres;

--
-- TOC entry 4204 (class 0 OID 0)
-- Dependencies: 532
-- Name: FUNCTION terminate_backend(pid integer); Type: COMMENT; Schema: user_management; Owner: postgres
--

COMMENT ON FUNCTION user_management.terminate_backend(pid integer) IS 'When there is a process causing harm, you can kill it using this function.  Get the pid from pg_stat_activity
(be careful to match the user name (usename) and the query, in order not to kill innocent kittens) and pass it to terminate_backend()';


--
-- TOC entry 425 (class 1259 OID 16716)
-- Name: index_bloat; Type: VIEW; Schema: metric_helpers; Owner: postgres
--

CREATE VIEW metric_helpers.index_bloat AS
 SELECT i_database,
    i_schema_name,
    i_table_name,
    i_index_name,
    i_real_size,
    i_extra_size,
    i_extra_ratio,
    i_fill_factor,
    i_bloat_size,
    i_bloat_ratio,
    i_is_na
   FROM metric_helpers.get_btree_bloat_approx() get_btree_bloat_approx(i_database, i_schema_name, i_table_name, i_index_name, i_real_size, i_extra_size, i_extra_ratio, i_fill_factor, i_bloat_size, i_bloat_ratio, i_is_na);


ALTER VIEW metric_helpers.index_bloat OWNER TO postgres;

--
-- TOC entry 427 (class 1259 OID 16727)
-- Name: nearly_exhausted_sequences; Type: VIEW; Schema: metric_helpers; Owner: postgres
--

CREATE VIEW metric_helpers.nearly_exhausted_sequences AS
 SELECT schemaname,
    sequencename,
    seq_percent_used
   FROM metric_helpers.get_nearly_exhausted_sequences((0.8)::double precision) get_nearly_exhausted_sequences(schemaname, sequencename, seq_percent_used);


ALTER VIEW metric_helpers.nearly_exhausted_sequences OWNER TO postgres;

--
-- TOC entry 426 (class 1259 OID 16721)
-- Name: pg_stat_statements; Type: VIEW; Schema: metric_helpers; Owner: postgres
--

CREATE VIEW metric_helpers.pg_stat_statements AS
 SELECT userid,
    dbid,
    toplevel,
    queryid,
    query,
    plans,
    total_plan_time,
    min_plan_time,
    max_plan_time,
    mean_plan_time,
    stddev_plan_time,
    calls,
    total_exec_time,
    min_exec_time,
    max_exec_time,
    mean_exec_time,
    stddev_exec_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    shared_blks_dirtied,
    shared_blks_written,
    local_blks_hit,
    local_blks_read,
    local_blks_dirtied,
    local_blks_written,
    temp_blks_read,
    temp_blks_written,
    shared_blk_read_time,
    shared_blk_write_time,
    local_blk_read_time,
    local_blk_write_time,
    temp_blk_read_time,
    temp_blk_write_time,
    wal_records,
    wal_fpi,
    wal_bytes,
    jit_functions,
    jit_generation_time,
    jit_inlining_count,
    jit_inlining_time,
    jit_optimization_count,
    jit_optimization_time,
    jit_emission_count,
    jit_emission_time,
    jit_deform_count,
    jit_deform_time,
    stats_since,
    minmax_stats_since
   FROM metric_helpers.pg_stat_statements(true) pg_stat_statements(userid, dbid, toplevel, queryid, query, plans, total_plan_time, min_plan_time, max_plan_time, mean_plan_time, stddev_plan_time, calls, total_exec_time, min_exec_time, max_exec_time, mean_exec_time, stddev_exec_time, rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied, local_blks_written, temp_blks_read, temp_blks_written, shared_blk_read_time, shared_blk_write_time, local_blk_read_time, local_blk_write_time, temp_blk_read_time, temp_blk_write_time, wal_records, wal_fpi, wal_bytes, jit_functions, jit_generation_time, jit_inlining_count, jit_inlining_time, jit_optimization_count, jit_optimization_time, jit_emission_count, jit_emission_time, jit_deform_count, jit_deform_time, stats_since, minmax_stats_since);


ALTER VIEW metric_helpers.pg_stat_statements OWNER TO postgres;

--
-- TOC entry 424 (class 1259 OID 16710)
-- Name: table_bloat; Type: VIEW; Schema: metric_helpers; Owner: postgres
--

CREATE VIEW metric_helpers.table_bloat AS
 SELECT t_database,
    t_schema_name,
    t_table_name,
    t_real_size,
    t_extra_size,
    t_extra_ratio,
    t_fill_factor,
    t_bloat_size,
    t_bloat_ratio,
    t_is_na
   FROM metric_helpers.get_table_bloat_approx() get_table_bloat_approx(t_database, t_schema_name, t_table_name, t_real_size, t_extra_size, t_extra_ratio, t_fill_factor, t_bloat_size, t_bloat_ratio, t_is_na);


ALTER VIEW metric_helpers.table_bloat OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 458 (class 1259 OID 19249)
-- Name: annotation_tag_entity; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.annotation_tag_entity (
    id character varying(16) NOT NULL,
    name character varying(24) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.annotation_tag_entity OWNER TO n8n_postgres_user;

--
-- TOC entry 443 (class 1259 OID 18766)
-- Name: auth_identity; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.auth_identity (
    "userId" uuid,
    "providerId" character varying(64) NOT NULL,
    "providerType" character varying(32) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.auth_identity OWNER TO n8n_postgres_user;

--
-- TOC entry 445 (class 1259 OID 18779)
-- Name: auth_provider_sync_history; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.auth_provider_sync_history (
    id integer NOT NULL,
    "providerType" character varying(32) NOT NULL,
    "runMode" text NOT NULL,
    status text NOT NULL,
    "startedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "endedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    scanned integer NOT NULL,
    created integer NOT NULL,
    updated integer NOT NULL,
    disabled integer NOT NULL,
    error text
);


ALTER TABLE public.auth_provider_sync_history OWNER TO n8n_postgres_user;

--
-- TOC entry 444 (class 1259 OID 18778)
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

CREATE SEQUENCE public.auth_provider_sync_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auth_provider_sync_history_id_seq OWNER TO n8n_postgres_user;

--
-- TOC entry 4211 (class 0 OID 0)
-- Dependencies: 444
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n_postgres_user
--

ALTER SEQUENCE public.auth_provider_sync_history_id_seq OWNED BY public.auth_provider_sync_history.id;


--
-- TOC entry 481 (class 1259 OID 25216)
-- Name: chat_hub_agents; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.chat_hub_agents (
    id uuid NOT NULL,
    name character varying(256) NOT NULL,
    description character varying(512),
    "systemPrompt" text NOT NULL,
    "ownerId" uuid NOT NULL,
    "credentialId" character varying(36),
    provider character varying(16) NOT NULL,
    model character varying(64) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.chat_hub_agents OWNER TO n8n_postgres_user;

--
-- TOC entry 4212 (class 0 OID 0)
-- Dependencies: 481
-- Name: COLUMN chat_hub_agents.provider; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_agents.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- TOC entry 4213 (class 0 OID 0)
-- Dependencies: 481
-- Name: COLUMN chat_hub_agents.model; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_agents.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- TOC entry 478 (class 1259 OID 21025)
-- Name: chat_hub_messages; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.chat_hub_messages (
    id uuid NOT NULL,
    "sessionId" uuid NOT NULL,
    "previousMessageId" uuid,
    "revisionOfMessageId" uuid,
    "retryOfMessageId" uuid,
    type character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    content text NOT NULL,
    provider character varying(16),
    model character varying(64),
    "workflowId" character varying(36),
    "executionId" integer,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    status character varying(16) DEFAULT 'success'::character varying NOT NULL,
    "agentId" character varying(36)
);


ALTER TABLE public.chat_hub_messages OWNER TO n8n_postgres_user;

--
-- TOC entry 4214 (class 0 OID 0)
-- Dependencies: 478
-- Name: COLUMN chat_hub_messages.type; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_messages.type IS 'ChatHubMessageType enum: "human", "ai", "system", "tool", "generic"';


--
-- TOC entry 4215 (class 0 OID 0)
-- Dependencies: 478
-- Name: COLUMN chat_hub_messages.provider; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_messages.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- TOC entry 4216 (class 0 OID 0)
-- Dependencies: 478
-- Name: COLUMN chat_hub_messages.model; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_messages.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- TOC entry 4217 (class 0 OID 0)
-- Dependencies: 478
-- Name: COLUMN chat_hub_messages.status; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_messages.status IS 'ChatHubMessageStatus enum, eg. "success", "error", "running", "cancelled"';


--
-- TOC entry 4218 (class 0 OID 0)
-- Dependencies: 478
-- Name: COLUMN chat_hub_messages."agentId"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_messages."agentId" IS 'ID of the custom agent (if provider is "custom-agent")';


--
-- TOC entry 477 (class 1259 OID 21003)
-- Name: chat_hub_sessions; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.chat_hub_sessions (
    id uuid NOT NULL,
    title character varying(256) NOT NULL,
    "ownerId" uuid NOT NULL,
    "lastMessageAt" timestamp(3) with time zone,
    "credentialId" character varying(36),
    provider character varying(16),
    model character varying(64),
    "workflowId" character varying(36),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "agentId" character varying(36),
    "agentName" character varying(128)
);


ALTER TABLE public.chat_hub_sessions OWNER TO n8n_postgres_user;

--
-- TOC entry 4219 (class 0 OID 0)
-- Dependencies: 477
-- Name: COLUMN chat_hub_sessions.provider; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_sessions.provider IS 'ChatHubProvider enum: "openai", "anthropic", "google", "n8n"';


--
-- TOC entry 4220 (class 0 OID 0)
-- Dependencies: 477
-- Name: COLUMN chat_hub_sessions.model; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_sessions.model IS 'Model name used at the respective Model node, ie. "gpt-4"';


--
-- TOC entry 4221 (class 0 OID 0)
-- Dependencies: 477
-- Name: COLUMN chat_hub_sessions."agentId"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_sessions."agentId" IS 'ID of the custom agent (if provider is "custom-agent")';


--
-- TOC entry 4222 (class 0 OID 0)
-- Dependencies: 477
-- Name: COLUMN chat_hub_sessions."agentName"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.chat_hub_sessions."agentName" IS 'Cached name of the custom agent (if provider is "custom-agent")';


--
-- TOC entry 430 (class 1259 OID 18479)
-- Name: credentials_entity; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.credentials_entity (
    name character varying(128) NOT NULL,
    data text NOT NULL,
    type character varying(128) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    id character varying(36) NOT NULL,
    "isManaged" boolean DEFAULT false NOT NULL
);


ALTER TABLE public.credentials_entity OWNER TO n8n_postgres_user;

--
-- TOC entry 475 (class 1259 OID 19635)
-- Name: data_table; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.data_table (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.data_table OWNER TO n8n_postgres_user;

--
-- TOC entry 476 (class 1259 OID 19649)
-- Name: data_table_column; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.data_table_column (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    type character varying(32) NOT NULL,
    index integer NOT NULL,
    "dataTableId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.data_table_column OWNER TO n8n_postgres_user;

--
-- TOC entry 4223 (class 0 OID 0)
-- Dependencies: 476
-- Name: COLUMN data_table_column.type; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.data_table_column.type IS 'Expected: string, number, boolean, or date (not enforced as a constraint)';


--
-- TOC entry 4224 (class 0 OID 0)
-- Dependencies: 476
-- Name: COLUMN data_table_column.index; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.data_table_column.index IS 'Column order, starting from 0 (0 = first column)';


--
-- TOC entry 442 (class 1259 OID 18734)
-- Name: event_destinations; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.event_destinations (
    id uuid NOT NULL,
    destination jsonb NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.event_destinations OWNER TO n8n_postgres_user;

--
-- TOC entry 459 (class 1259 OID 19257)
-- Name: execution_annotation_tags; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.execution_annotation_tags (
    "annotationId" integer NOT NULL,
    "tagId" character varying(24) NOT NULL
);


ALTER TABLE public.execution_annotation_tags OWNER TO n8n_postgres_user;

--
-- TOC entry 457 (class 1259 OID 19226)
-- Name: execution_annotations; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.execution_annotations (
    id integer NOT NULL,
    "executionId" integer NOT NULL,
    vote character varying(6),
    note text,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.execution_annotations OWNER TO n8n_postgres_user;

--
-- TOC entry 456 (class 1259 OID 19225)
-- Name: execution_annotations_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

CREATE SEQUENCE public.execution_annotations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.execution_annotations_id_seq OWNER TO n8n_postgres_user;

--
-- TOC entry 4225 (class 0 OID 0)
-- Dependencies: 456
-- Name: execution_annotations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n_postgres_user
--

ALTER SEQUENCE public.execution_annotations_id_seq OWNED BY public.execution_annotations.id;


--
-- TOC entry 447 (class 1259 OID 18874)
-- Name: execution_data; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.execution_data (
    "executionId" integer NOT NULL,
    "workflowData" json NOT NULL,
    data text NOT NULL
);


ALTER TABLE public.execution_data OWNER TO n8n_postgres_user;

--
-- TOC entry 432 (class 1259 OID 18489)
-- Name: execution_entity; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.execution_entity (
    id integer NOT NULL,
    finished boolean NOT NULL,
    mode character varying NOT NULL,
    "retryOf" character varying,
    "retrySuccessId" character varying,
    "startedAt" timestamp(3) with time zone,
    "stoppedAt" timestamp(3) with time zone,
    "waitTill" timestamp(3) with time zone,
    status character varying NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "deletedAt" timestamp(3) with time zone,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.execution_entity OWNER TO n8n_postgres_user;

--
-- TOC entry 431 (class 1259 OID 18488)
-- Name: execution_entity_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

CREATE SEQUENCE public.execution_entity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.execution_entity_id_seq OWNER TO n8n_postgres_user;

--
-- TOC entry 4226 (class 0 OID 0)
-- Dependencies: 431
-- Name: execution_entity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n_postgres_user
--

ALTER SEQUENCE public.execution_entity_id_seq OWNED BY public.execution_entity.id;


--
-- TOC entry 454 (class 1259 OID 19201)
-- Name: execution_metadata; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.execution_metadata (
    id integer NOT NULL,
    "executionId" integer NOT NULL,
    key character varying(255) NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.execution_metadata OWNER TO n8n_postgres_user;

--
-- TOC entry 453 (class 1259 OID 19200)
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

CREATE SEQUENCE public.execution_metadata_temp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.execution_metadata_temp_id_seq OWNER TO n8n_postgres_user;

--
-- TOC entry 4227 (class 0 OID 0)
-- Dependencies: 453
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n_postgres_user
--

ALTER SEQUENCE public.execution_metadata_temp_id_seq OWNED BY public.execution_metadata.id;


--
-- TOC entry 462 (class 1259 OID 19401)
-- Name: folder; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.folder (
    id character varying(36) NOT NULL,
    name character varying(128) NOT NULL,
    "parentFolderId" character varying(36),
    "projectId" character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.folder OWNER TO n8n_postgres_user;

--
-- TOC entry 463 (class 1259 OID 19419)
-- Name: folder_tag; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.folder_tag (
    "folderId" character varying(36) NOT NULL,
    "tagId" character varying(36) NOT NULL
);


ALTER TABLE public.folder_tag OWNER TO n8n_postgres_user;

--
-- TOC entry 469 (class 1259 OID 19515)
-- Name: insights_by_period; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.insights_by_period (
    id integer NOT NULL,
    "metaId" integer NOT NULL,
    type integer NOT NULL,
    value bigint NOT NULL,
    "periodUnit" integer NOT NULL,
    "periodStart" timestamp(0) with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.insights_by_period OWNER TO n8n_postgres_user;

--
-- TOC entry 4228 (class 0 OID 0)
-- Dependencies: 469
-- Name: COLUMN insights_by_period.type; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.insights_by_period.type IS '0: time_saved_minutes, 1: runtime_milliseconds, 2: success, 3: failure';


--
-- TOC entry 4229 (class 0 OID 0)
-- Dependencies: 469
-- Name: COLUMN insights_by_period."periodUnit"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.insights_by_period."periodUnit" IS '0: hour, 1: day, 2: week';


--
-- TOC entry 468 (class 1259 OID 19514)
-- Name: insights_by_period_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE public.insights_by_period ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insights_by_period_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 465 (class 1259 OID 19486)
-- Name: insights_metadata; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.insights_metadata (
    "metaId" integer NOT NULL,
    "workflowId" character varying(16),
    "projectId" character varying(36),
    "workflowName" character varying(128) NOT NULL,
    "projectName" character varying(255) NOT NULL
);


ALTER TABLE public.insights_metadata OWNER TO n8n_postgres_user;

--
-- TOC entry 464 (class 1259 OID 19485)
-- Name: insights_metadata_metaId_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE public.insights_metadata ALTER COLUMN "metaId" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."insights_metadata_metaId_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 467 (class 1259 OID 19503)
-- Name: insights_raw; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.insights_raw (
    id integer NOT NULL,
    "metaId" integer NOT NULL,
    type integer NOT NULL,
    value bigint NOT NULL,
    "timestamp" timestamp(0) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.insights_raw OWNER TO n8n_postgres_user;

--
-- TOC entry 4230 (class 0 OID 0)
-- Dependencies: 467
-- Name: COLUMN insights_raw.type; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.insights_raw.type IS '0: time_saved_minutes, 1: runtime_milliseconds, 2: success, 3: failure';


--
-- TOC entry 466 (class 1259 OID 19502)
-- Name: insights_raw_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE public.insights_raw ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.insights_raw_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 440 (class 1259 OID 18682)
-- Name: installed_nodes; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.installed_nodes (
    name character varying(200) NOT NULL,
    type character varying(200) NOT NULL,
    "latestVersion" integer DEFAULT 1 NOT NULL,
    package character varying(241) NOT NULL
);


ALTER TABLE public.installed_nodes OWNER TO n8n_postgres_user;

--
-- TOC entry 439 (class 1259 OID 18675)
-- Name: installed_packages; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.installed_packages (
    "packageName" character varying(214) NOT NULL,
    "installedVersion" character varying(50) NOT NULL,
    "authorName" character varying(70),
    "authorEmail" character varying(70),
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.installed_packages OWNER TO n8n_postgres_user;

--
-- TOC entry 455 (class 1259 OID 19215)
-- Name: invalid_auth_token; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.invalid_auth_token (
    token character varying(512) NOT NULL,
    "expiresAt" timestamp(3) with time zone NOT NULL
);


ALTER TABLE public.invalid_auth_token OWNER TO n8n_postgres_user;

--
-- TOC entry 429 (class 1259 OID 18470)
-- Name: migrations; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    "timestamp" bigint NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.migrations OWNER TO n8n_postgres_user;

--
-- TOC entry 428 (class 1259 OID 18469)
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.migrations_id_seq OWNER TO n8n_postgres_user;

--
-- TOC entry 4231 (class 0 OID 0)
-- Dependencies: 428
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: n8n_postgres_user
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- TOC entry 484 (class 1259 OID 34998)
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.oauth_access_tokens (
    token character varying NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL
);


ALTER TABLE public.oauth_access_tokens OWNER TO n8n_postgres_user;

--
-- TOC entry 483 (class 1259 OID 34978)
-- Name: oauth_authorization_codes; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.oauth_authorization_codes (
    code character varying(255) NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL,
    "redirectUri" character varying(255) NOT NULL,
    "codeChallenge" character varying(255) NOT NULL,
    "codeChallengeMethod" character varying(255) NOT NULL,
    "expiresAt" bigint NOT NULL,
    state character varying(255),
    used boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.oauth_authorization_codes OWNER TO n8n_postgres_user;

--
-- TOC entry 4232 (class 0 OID 0)
-- Dependencies: 483
-- Name: COLUMN oauth_authorization_codes."expiresAt"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.oauth_authorization_codes."expiresAt" IS 'Unix timestamp in milliseconds';


--
-- TOC entry 482 (class 1259 OID 34968)
-- Name: oauth_clients; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.oauth_clients (
    id character varying NOT NULL,
    name character varying(255) NOT NULL,
    "redirectUris" json NOT NULL,
    "grantTypes" json NOT NULL,
    "clientSecret" character varying(255),
    "clientSecretExpiresAt" bigint,
    "tokenEndpointAuthMethod" character varying(255) DEFAULT 'none'::character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.oauth_clients OWNER TO n8n_postgres_user;

--
-- TOC entry 4233 (class 0 OID 0)
-- Dependencies: 482
-- Name: COLUMN oauth_clients."tokenEndpointAuthMethod"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.oauth_clients."tokenEndpointAuthMethod" IS 'Possible values: none, client_secret_basic or client_secret_post';


--
-- TOC entry 485 (class 1259 OID 35015)
-- Name: oauth_refresh_tokens; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.oauth_refresh_tokens (
    token character varying(255) NOT NULL,
    "clientId" character varying NOT NULL,
    "userId" uuid NOT NULL,
    "expiresAt" bigint NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.oauth_refresh_tokens OWNER TO n8n_postgres_user;

--
-- TOC entry 4234 (class 0 OID 0)
-- Dependencies: 485
-- Name: COLUMN oauth_refresh_tokens."expiresAt"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.oauth_refresh_tokens."expiresAt" IS 'Unix timestamp in milliseconds';


--
-- TOC entry 487 (class 1259 OID 35035)
-- Name: oauth_user_consents; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.oauth_user_consents (
    id integer NOT NULL,
    "userId" uuid NOT NULL,
    "clientId" character varying NOT NULL,
    "grantedAt" bigint NOT NULL
);


ALTER TABLE public.oauth_user_consents OWNER TO n8n_postgres_user;

--
-- TOC entry 4235 (class 0 OID 0)
-- Dependencies: 487
-- Name: COLUMN oauth_user_consents."grantedAt"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.oauth_user_consents."grantedAt" IS 'Unix timestamp in milliseconds';


--
-- TOC entry 486 (class 1259 OID 35034)
-- Name: oauth_user_consents_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE public.oauth_user_consents ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.oauth_user_consents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 461 (class 1259 OID 19290)
-- Name: processed_data; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.processed_data (
    "workflowId" character varying(36) NOT NULL,
    context character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.processed_data OWNER TO n8n_postgres_user;

--
-- TOC entry 449 (class 1259 OID 19117)
-- Name: project; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.project (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(36) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    icon json,
    description character varying(512)
);


ALTER TABLE public.project OWNER TO n8n_postgres_user;

--
-- TOC entry 450 (class 1259 OID 19124)
-- Name: project_relation; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.project_relation (
    "projectId" character varying(36) NOT NULL,
    "userId" uuid NOT NULL,
    role character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.project_relation OWNER TO n8n_postgres_user;

--
-- TOC entry 473 (class 1259 OID 19571)
-- Name: role; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.role (
    slug character varying(128) NOT NULL,
    "displayName" text,
    description text,
    "roleType" text,
    "systemRole" boolean DEFAULT false NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.role OWNER TO n8n_postgres_user;

--
-- TOC entry 4236 (class 0 OID 0)
-- Dependencies: 473
-- Name: COLUMN role.slug; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.role.slug IS 'Unique identifier of the role for example: "global:owner"';


--
-- TOC entry 4237 (class 0 OID 0)
-- Dependencies: 473
-- Name: COLUMN role."displayName"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.role."displayName" IS 'Name used to display in the UI';


--
-- TOC entry 4238 (class 0 OID 0)
-- Dependencies: 473
-- Name: COLUMN role.description; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.role.description IS 'Text describing the scope in more detail of users';


--
-- TOC entry 4239 (class 0 OID 0)
-- Dependencies: 473
-- Name: COLUMN role."roleType"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.role."roleType" IS 'Type of the role, e.g., global, project, or workflow';


--
-- TOC entry 4240 (class 0 OID 0)
-- Dependencies: 473
-- Name: COLUMN role."systemRole"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.role."systemRole" IS 'Indicates if the role is managed by the system and cannot be edited';


--
-- TOC entry 474 (class 1259 OID 19579)
-- Name: role_scope; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.role_scope (
    "roleSlug" character varying(128) NOT NULL,
    "scopeSlug" character varying(128) NOT NULL
);


ALTER TABLE public.role_scope OWNER TO n8n_postgres_user;

--
-- TOC entry 472 (class 1259 OID 19564)
-- Name: scope; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.scope (
    slug character varying(128) NOT NULL,
    "displayName" text,
    description text
);


ALTER TABLE public.scope OWNER TO n8n_postgres_user;

--
-- TOC entry 4241 (class 0 OID 0)
-- Dependencies: 472
-- Name: COLUMN scope.slug; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.scope.slug IS 'Unique identifier of the scope for example: "project:create"';


--
-- TOC entry 4242 (class 0 OID 0)
-- Dependencies: 472
-- Name: COLUMN scope."displayName"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.scope."displayName" IS 'Name used to display in the UI';


--
-- TOC entry 4243 (class 0 OID 0)
-- Dependencies: 472
-- Name: COLUMN scope.description; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.scope.description IS 'Text describing the scope in more detail of users';


--
-- TOC entry 438 (class 1259 OID 18667)
-- Name: settings; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.settings (
    key character varying(255) NOT NULL,
    value text NOT NULL,
    "loadOnStartup" boolean DEFAULT false NOT NULL
);


ALTER TABLE public.settings OWNER TO n8n_postgres_user;

--
-- TOC entry 451 (class 1259 OID 19155)
-- Name: shared_credentials; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.shared_credentials (
    "credentialsId" character varying(36) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    role text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.shared_credentials OWNER TO n8n_postgres_user;

--
-- TOC entry 452 (class 1259 OID 19181)
-- Name: shared_workflow; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.shared_workflow (
    "workflowId" character varying(36) NOT NULL,
    "projectId" character varying(36) NOT NULL,
    role text NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.shared_workflow OWNER TO n8n_postgres_user;

--
-- TOC entry 435 (class 1259 OID 18517)
-- Name: tag_entity; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.tag_entity (
    name character varying(24) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    id character varying(36) NOT NULL
);


ALTER TABLE public.tag_entity OWNER TO n8n_postgres_user;

--
-- TOC entry 471 (class 1259 OID 19542)
-- Name: test_case_execution; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.test_case_execution (
    id character varying(36) NOT NULL,
    "testRunId" character varying(36) NOT NULL,
    "executionId" integer,
    status character varying NOT NULL,
    "runAt" timestamp(3) with time zone,
    "completedAt" timestamp(3) with time zone,
    "errorCode" character varying,
    "errorDetails" json,
    metrics json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    inputs json,
    outputs json
);


ALTER TABLE public.test_case_execution OWNER TO n8n_postgres_user;

--
-- TOC entry 470 (class 1259 OID 19527)
-- Name: test_run; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.test_run (
    id character varying(36) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    status character varying NOT NULL,
    "errorCode" character varying,
    "errorDetails" json,
    "runAt" timestamp(3) with time zone,
    "completedAt" timestamp(3) with time zone,
    metrics json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.test_run OWNER TO n8n_postgres_user;

--
-- TOC entry 437 (class 1259 OID 18604)
-- Name: user; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public."user" (
    id uuid DEFAULT uuid_in((OVERLAY(OVERLAY(md5((((random())::text || ':'::text) || (clock_timestamp())::text)) PLACING '4'::text FROM 13) PLACING to_hex((floor(((random() * (((11 - 8) + 1))::double precision) + (8)::double precision)))::integer) FROM 17))::cstring) NOT NULL,
    email character varying(255),
    "firstName" character varying(32),
    "lastName" character varying(32),
    password character varying(255),
    "personalizationAnswers" json,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    settings json,
    disabled boolean DEFAULT false NOT NULL,
    "mfaEnabled" boolean DEFAULT false NOT NULL,
    "mfaSecret" text,
    "mfaRecoveryCodes" text,
    "lastActiveAt" date,
    "roleSlug" character varying(128) DEFAULT 'global:member'::character varying NOT NULL
);


ALTER TABLE public."user" OWNER TO n8n_postgres_user;

--
-- TOC entry 460 (class 1259 OID 19274)
-- Name: user_api_keys; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.user_api_keys (
    id character varying(36) NOT NULL,
    "userId" uuid NOT NULL,
    label character varying(100) NOT NULL,
    "apiKey" character varying NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    scopes json,
    audience character varying DEFAULT 'public-api'::character varying NOT NULL
);


ALTER TABLE public.user_api_keys OWNER TO n8n_postgres_user;

--
-- TOC entry 446 (class 1259 OID 18790)
-- Name: variables; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.variables (
    key character varying(50) NOT NULL,
    type character varying(50) DEFAULT 'string'::character varying NOT NULL,
    value character varying(255),
    id character varying(36) NOT NULL,
    "projectId" character varying(36)
);


ALTER TABLE public.variables OWNER TO n8n_postgres_user;

--
-- TOC entry 434 (class 1259 OID 18507)
-- Name: webhook_entity; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.webhook_entity (
    "webhookPath" character varying NOT NULL,
    method character varying NOT NULL,
    node character varying NOT NULL,
    "webhookId" character varying,
    "pathLength" integer,
    "workflowId" character varying(36) NOT NULL
);


ALTER TABLE public.webhook_entity OWNER TO n8n_postgres_user;

--
-- TOC entry 480 (class 1259 OID 21073)
-- Name: workflow_dependency; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.workflow_dependency (
    id integer NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "workflowVersionId" integer NOT NULL,
    "dependencyType" character varying(32) NOT NULL,
    "dependencyKey" character varying(255) NOT NULL,
    "dependencyInfo" json,
    "indexVersionId" smallint DEFAULT 1 NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL
);


ALTER TABLE public.workflow_dependency OWNER TO n8n_postgres_user;

--
-- TOC entry 4244 (class 0 OID 0)
-- Dependencies: 480
-- Name: COLUMN workflow_dependency."workflowVersionId"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.workflow_dependency."workflowVersionId" IS 'Version of the workflow';


--
-- TOC entry 4245 (class 0 OID 0)
-- Dependencies: 480
-- Name: COLUMN workflow_dependency."dependencyType"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.workflow_dependency."dependencyType" IS 'Type of dependency: "credential", "nodeType", "webhookPath", or "workflowCall"';


--
-- TOC entry 4246 (class 0 OID 0)
-- Dependencies: 480
-- Name: COLUMN workflow_dependency."dependencyKey"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.workflow_dependency."dependencyKey" IS 'ID or name of the dependency';


--
-- TOC entry 4247 (class 0 OID 0)
-- Dependencies: 480
-- Name: COLUMN workflow_dependency."dependencyInfo"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.workflow_dependency."dependencyInfo" IS 'Additional info about the dependency, interpreted based on type';


--
-- TOC entry 4248 (class 0 OID 0)
-- Dependencies: 480
-- Name: COLUMN workflow_dependency."indexVersionId"; Type: COMMENT; Schema: public; Owner: n8n_postgres_user
--

COMMENT ON COLUMN public.workflow_dependency."indexVersionId" IS 'Version of the index structure';


--
-- TOC entry 479 (class 1259 OID 21072)
-- Name: workflow_dependency_id_seq; Type: SEQUENCE; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE public.workflow_dependency ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.workflow_dependency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 433 (class 1259 OID 18499)
-- Name: workflow_entity; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.workflow_entity (
    name character varying(128) NOT NULL,
    active boolean NOT NULL,
    nodes json NOT NULL,
    connections json NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    settings json,
    "staticData" json,
    "pinData" json,
    "versionId" character(36),
    "triggerCount" integer DEFAULT 0 NOT NULL,
    id character varying(36) NOT NULL,
    meta json,
    "parentFolderId" character varying(36) DEFAULT NULL::character varying,
    "isArchived" boolean DEFAULT false NOT NULL,
    "versionCounter" integer DEFAULT 1 NOT NULL,
    description text
);


ALTER TABLE public.workflow_entity OWNER TO n8n_postgres_user;

--
-- TOC entry 448 (class 1259 OID 18888)
-- Name: workflow_history; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.workflow_history (
    "versionId" character varying(36) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    authors character varying(255) NOT NULL,
    "createdAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    "updatedAt" timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    nodes json NOT NULL,
    connections json NOT NULL
);


ALTER TABLE public.workflow_history OWNER TO n8n_postgres_user;

--
-- TOC entry 441 (class 1259 OID 18704)
-- Name: workflow_statistics; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.workflow_statistics (
    count integer DEFAULT 0,
    "latestEvent" timestamp(3) with time zone,
    name character varying(128) NOT NULL,
    "workflowId" character varying(36) NOT NULL,
    "rootCount" integer DEFAULT 0
);


ALTER TABLE public.workflow_statistics OWNER TO n8n_postgres_user;

--
-- TOC entry 436 (class 1259 OID 18524)
-- Name: workflows_tags; Type: TABLE; Schema: public; Owner: n8n_postgres_user
--

CREATE TABLE public.workflows_tags (
    "workflowId" character varying(36) NOT NULL,
    "tagId" character varying(36) NOT NULL
);


ALTER TABLE public.workflows_tags OWNER TO n8n_postgres_user;

--
-- TOC entry 3694 (class 2604 OID 18782)
-- Name: auth_provider_sync_history id; Type: DEFAULT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.auth_provider_sync_history ALTER COLUMN id SET DEFAULT nextval('public.auth_provider_sync_history_id_seq'::regclass);


--
-- TOC entry 3709 (class 2604 OID 19229)
-- Name: execution_annotations id; Type: DEFAULT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_annotations ALTER COLUMN id SET DEFAULT nextval('public.execution_annotations_id_seq'::regclass);


--
-- TOC entry 3668 (class 2604 OID 18492)
-- Name: execution_entity id; Type: DEFAULT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_entity ALTER COLUMN id SET DEFAULT nextval('public.execution_entity_id_seq'::regclass);


--
-- TOC entry 3708 (class 2604 OID 19204)
-- Name: execution_metadata id; Type: DEFAULT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_metadata ALTER COLUMN id SET DEFAULT nextval('public.execution_metadata_temp_id_seq'::regclass);


--
-- TOC entry 3664 (class 2604 OID 18473)
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- TOC entry 4140 (class 0 OID 19249)
-- Dependencies: 458
-- Data for Name: annotation_tag_entity; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.annotation_tag_entity (id, name, "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4125 (class 0 OID 18766)
-- Dependencies: 443
-- Data for Name: auth_identity; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.auth_identity ("userId", "providerId", "providerType", "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4127 (class 0 OID 18779)
-- Dependencies: 445
-- Data for Name: auth_provider_sync_history; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.auth_provider_sync_history (id, "providerType", "runMode", status, "startedAt", "endedAt", scanned, created, updated, disabled, error) FROM stdin;
\.


--
-- TOC entry 4163 (class 0 OID 25216)
-- Dependencies: 481
-- Data for Name: chat_hub_agents; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.chat_hub_agents (id, name, description, "systemPrompt", "ownerId", "credentialId", provider, model, "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4160 (class 0 OID 21025)
-- Dependencies: 478
-- Data for Name: chat_hub_messages; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.chat_hub_messages (id, "sessionId", "previousMessageId", "revisionOfMessageId", "retryOfMessageId", type, name, content, provider, model, "workflowId", "executionId", "createdAt", "updatedAt", status, "agentId") FROM stdin;
\.


--
-- TOC entry 4159 (class 0 OID 21003)
-- Dependencies: 477
-- Data for Name: chat_hub_sessions; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.chat_hub_sessions (id, title, "ownerId", "lastMessageAt", "credentialId", provider, model, "workflowId", "createdAt", "updatedAt", "agentId", "agentName") FROM stdin;
\.


--
-- TOC entry 4112 (class 0 OID 18479)
-- Dependencies: 430
-- Data for Name: credentials_entity; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.credentials_entity (name, data, type, "createdAt", "updatedAt", id, "isManaged") FROM stdin;
Perplexity API	U2FsdGVkX1+LqCjgBs4OBBBUk8+Y6kg7r3P/4nxuOu3PsfdBJzLINCNfLHr0D6TyaQ6HRUBMwlqNdOUuq+FRL8/VhdxQ+4tVFjHDdsFTNl1+B4J1ue8xvQkOjW6AuQM1LgH05D8OVSksl9DuebJkMg==	httpHeaderAuth	2025-11-04 03:18:36.48+00	2025-11-04 03:18:51.1+00	mcMfxx1mub2XimHN	f
AgentRouter API	U2FsdGVkX19TjbG8rwhGrIhCWiE9mWta35iDnyZuhGq5iaF8VsJ3yPRqIcbCRVUYSKHR9LdOkINvuDbS+g/S9pdQn5zgdmgHdMtGkkHvPcOfDa/vJ/uoiSIC9piXCypnQ88Zc1DuOXPZCsoHohi+uA==	httpHeaderAuth	2025-11-04 03:31:18.084+00	2025-11-04 03:31:18.076+00	yIHqRqm0mV1LLjtR	f
Unsplash API	U2FsdGVkX18UmsxM19x1LBsh6z4epz0BnTnto+q7+P96B1sevqF7e19o0cH2Jj3wWi9vWgdAX3gTE3wkzVAha9mEP8zsUhJGTlWwwLAQaksPV7EyPIMavMNOll1iV4FVVSXLfZ2te/oG/YrKKkd3RQ==	httpHeaderAuth	2025-11-04 03:34:40.297+00	2025-11-04 03:34:40.296+00	z5U3WTHeGbLkO8CL	f
Wordpress account	U2FsdGVkX188RlXeELLnIfAWJIilDtuOeFsZVapVZ1SYWENCSWM37d6FMI0r8fKp8LSMJsiobIMNN0h1J4u53SDeNVXw6cfqVB+lI1O5bfdBJ7BtD44WNquBldfAQnGjABF90D03mKEj5hG899vkOuzHvSW98O/twffQNsLMcWHNAxAXmJTXSVGX1AUzaeqx	wordpressApi	2025-11-04 03:40:25.94+00	2025-11-04 03:43:31.318+00	KRNE3nXewO8fnuDU	f
\.


--
-- TOC entry 4157 (class 0 OID 19635)
-- Dependencies: 475
-- Data for Name: data_table; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.data_table (id, name, "projectId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4158 (class 0 OID 19649)
-- Dependencies: 476
-- Data for Name: data_table_column; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.data_table_column (id, name, type, index, "dataTableId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4124 (class 0 OID 18734)
-- Dependencies: 442
-- Data for Name: event_destinations; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.event_destinations (id, destination, "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4141 (class 0 OID 19257)
-- Dependencies: 459
-- Data for Name: execution_annotation_tags; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.execution_annotation_tags ("annotationId", "tagId") FROM stdin;
\.


--
-- TOC entry 4139 (class 0 OID 19226)
-- Dependencies: 457
-- Data for Name: execution_annotations; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.execution_annotations (id, "executionId", vote, note, "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4129 (class 0 OID 18874)
-- Dependencies: 447
-- Data for Name: execution_data; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.execution_data ("executionId", "workflowData", data) FROM stdin;
13	{"id":"7InRmYUhABudg55m","name":"GMB Auto-Post - Phase 2: Multi-Location + Sheets","active":false,"nodes":[{"parameters":{"notice":""},"id":"5ec7ab18-2aeb-4348-bbc9-42fff95d8dee","name":"Manual Trigger","type":"n8n-nodes-base.manualTrigger","typeVersion":1,"position":[-2864,-368]},{"parameters":{"mode":"manual","duplicateItem":false,"assignments":{},"includeOtherFields":false,"options":{}},"id":"dec0a3fc-ba91-4b83-961b-7fe25e6f0184","name":"Set Post Data","type":"n8n-nodes-base.set","typeVersion":3.3,"position":[-2640,-368]},{"parameters":{"preBuiltAgentsCalloutHttpRequest":"","curlImport":"","method":"GET","url":"https://mybusinessbusinessinformation.googleapis.com/v1/accounts","authentication":"oAuth2","provideSslCertificates":false,"sendQuery":false,"sendHeaders":false,"sendBody":false,"options":{},"infoMessage":""},"id":"e2cd52c5-dfe3-4cb5-a36d-54630b3d00cf","name":"Get GMB Account ID","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-2416,-368]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Extract account ID from GMB API response\\nconst response = $input.first().json;\\n\\n// Check if accounts exist\\nif (!response.accounts || response.accounts.length === 0) {\\n  throw new Error('No GMB accounts found. Please check your Google Business Profile access.');\\n}\\n\\n// Get first account\\nconst accountId = response.accounts[0].name;\\n\\nconsole.log('Found GMB Account:', accountId);\\n\\nreturn {\\n  json: {\\n    accountId: accountId,\\n    accountName: response.accounts[0].accountName || 'Unknown'\\n  }\\n};","notice":""},"id":"a4c722ad-4f05-4e1b-b4b4-dcbfbd59aaaf","name":"Extract Account ID","type":"n8n-nodes-base.code","typeVersion":2,"position":[-2192,-368]},{"parameters":{"preBuiltAgentsCalloutHttpRequest":"","curlImport":"","method":"GET","url":"=https://mybusinessbusinessinformation.googleapis.com/v1/{{$json.accountId}}/locations?pageSize=100&readMask=name,title,storefrontAddress","authentication":"oAuth2","provideSslCertificates":false,"sendQuery":false,"sendHeaders":false,"sendBody":false,"options":{},"infoMessage":""},"id":"64d5bcdc-c111-444a-a354-c202ae85dc59","name":"Get GMB Locations","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1968,-368]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Extract location ID from GMB API response\\nconst response = $input.first().json;\\n\\n// Check if locations exist\\nif (!response.locations || response.locations.length === 0) {\\n  throw new Error('No GMB locations found. Please add a location to your Google Business Profile.');\\n}\\n\\n// Get first location for MVP\\nconst location = response.locations[0];\\nconst locationId = location.name;\\nconst locationTitle = location.title || 'Unknown Location';\\nconst address = location.storefrontAddress || {};\\n\\nconsole.log('Found GMB Location:', locationTitle, locationId);\\n\\nreturn {\\n  json: {\\n    locationId: locationId,\\n    locationTitle: locationTitle,\\n    locationAddress: address.addressLines ? address.addressLines.join(', ') : 'N/A'\\n  }\\n};","notice":""},"id":"760121e7-780a-4967-870a-629922a80310","name":"Extract Location ID","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1744,-368]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Format payload for GMB API\\nconst postData = $('Set Post Data').first().json;\\nconst locationData = $input.first().json;\\n\\n// Build GMB API payload\\nconst payload = {\\n  languageCode: \\"en\\",\\n  summary: postData.content,\\n  topicType: postData.post_type\\n};\\n\\n// Add CTA if provided\\nif (postData.cta_type && postData.cta_url) {\\n  payload.callToAction = {\\n    actionType: postData.cta_type,\\n    url: postData.cta_url\\n  };\\n}\\n\\n// Build API URL\\nconst postUrl = `https://mybusiness.googleapis.com/v4/${locationData.locationId}/localPosts`;\\n\\nconsole.log('GMB API URL:', postUrl);\\nconsole.log('Payload:', JSON.stringify(payload, null, 2));\\n\\nreturn {\\n  json: {\\n    payload: payload,\\n    locationId: locationData.locationId,\\n    locationTitle: locationData.locationTitle,\\n    postUrl: postUrl\\n  }\\n};","notice":""},"id":"c432354a-0246-4af4-b1c1-2456aa380ecb","name":"Format GMB Payload","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1520,-368]},{"parameters":{"preBuiltAgentsCalloutHttpRequest":"","curlImport":"","method":"GET","url":"={{$json.postUrl}}","authentication":"oAuth2","provideSslCertificates":false,"sendQuery":false,"sendHeaders":false,"sendBody":true,"contentType":"json","specifyBody":"keypair","bodyParameters":{"parameters":[{"name":"languageCode","value":"={{$json.payload.languageCode}}"},{"name":"summary","value":"={{$json.payload.summary}}"},{"name":"topicType","value":"={{$json.payload.topicType}}"},{"name":"callToAction","value":"={{$json.payload.callToAction}}"}]},"options":{"response":{"response":{"fullResponse":true,"neverError":false,"responseFormat":"autodetect"}}},"infoMessage":""},"id":"4ea45a97-2c6c-4977-b25d-11f47a95dd6f","name":"Create GMB Post","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1296,-368]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Parse success response\\nconst response = $input.first().json;\\nconst body = response.body || response;\\n\\nconsole.log('GMB Post Created Successfully!');\\nconsole.log('Response:', JSON.stringify(body, null, 2));\\n\\nreturn {\\n  json: {\\n    status: 'success',\\n    postId: body.name || 'Unknown',\\n    postState: body.state || 'PROCESSING',\\n    searchUrl: body.searchUrl || 'N/A',\\n    createTime: body.createTime || new Date().toISOString(),\\n    message: '✅ GMB post created successfully!'\\n  }\\n};","notice":""},"id":"8bd9d7c0-fc05-4f7c-87ea-b11c361fca82","name":"Success Handler","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1072,-368]},{"parameters":{"mode":"manual","duplicateItem":false,"assignments":{},"includeOtherFields":false,"options":{}},"id":"365ef4d4-23c0-4e07-a2fb-4d8b1bcd5e99","name":"Error Handler","type":"n8n-nodes-base.set","typeVersion":3.3,"position":[-1072,-176]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Display final result\\nconst data = $input.first().json;\\n\\nif (data.status === 'success') {\\n  console.log('========================================');\\n  console.log('✅ GMB POST CREATED SUCCESSFULLY');\\n  console.log('========================================');\\n  console.log('Post ID:', data.postId);\\n  console.log('State:', data.postState);\\n  console.log('Search URL:', data.searchUrl);\\n  console.log('Created:', data.createTime);\\n  console.log('========================================');\\n} else {\\n  console.log('========================================');\\n  console.log('❌ GMB POST FAILED');\\n  console.log('========================================');\\n  console.log('Error Code:', data.error_code);\\n  console.log('Error Message:', data.error_message);\\n  console.log('Timestamp:', data.timestamp);\\n  console.log('========================================');\\n}\\n\\nreturn $input.all();","notice":""},"id":"1efa3797-4fd8-4538-b411-76a301eeb71b","name":"Display Result","type":"n8n-nodes-base.code","typeVersion":2,"position":[-848,-272]},{"parameters":{"notice":"","rule":{"interval":[{"field":"cronExpression","notice":"","expression":"0 9 * * *"}]}},"id":"ee1b2fb5-76a0-4a22-8abd-9b89ac2b6424","name":"Schedule Trigger","type":"n8n-nodes-base.scheduleTrigger","typeVersion":1.2,"position":[-2864,144],"notesInFlow":true,"notes":"Daily at 9 AM (Asia/Ho_Chi_Minh timezone)"},{"parameters":{"preBuiltAgentsCalloutGoogleSheets":"","authentication":"oAuth2","resource":"sheet","operation":"read","documentId":{"__rl":true,"mode":"list","value":""},"sheetName":{"__rl":true,"mode":"list","value":""}},"id":"2454b1b6-b926-49d7-8f3a-943a1de11c0e","name":"Read Google Sheets","type":"n8n-nodes-base.googleSheets","typeVersion":4.4,"position":[-2640,144],"notesInFlow":true,"notes":"Columns: content | location_id | post_type | cta_type | cta_url | image_url | status"},{"parameters":{"conditions":{"options":{"leftValue":"","caseSensitive":true,"typeValidation":"strict"},"conditions":[{"id":"filter-pending-001","leftValue":"={{ $json.status }}","rightValue":"pending","operator":{"type":"string","operation":"equals"}}],"combinator":"and"},"options":{}},"id":"f90a1329-1aed-4593-9a3b-d7de48acae27","name":"Filter Pending Posts","type":"n8n-nodes-base.if","typeVersion":2,"position":[-2416,144],"notesInFlow":true,"notes":"Only process posts with status='pending'"},{"parameters":{"preBuiltAgentsCalloutHttpRequest":"","curlImport":"","method":"GET","url":"https://mybusinessbusinessinformation.googleapis.com/v1/accounts","authentication":"oAuth2","provideSslCertificates":false,"sendQuery":false,"sendHeaders":false,"sendBody":false,"options":{},"infoMessage":""},"id":"a4c45594-ba25-4c3b-9d0d-8aa51f1df1fa","name":"Get GMB Account","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-2192,48]},{"parameters":{"preBuiltAgentsCalloutHttpRequest":"","curlImport":"","method":"GET","url":"=https://mybusinessbusinessinformation.googleapis.com/v1/{{$json.accountId}}/locations?pageSize=100&readMask=name,title,storefrontAddress","authentication":"oAuth2","provideSslCertificates":false,"sendQuery":false,"sendHeaders":false,"sendBody":false,"options":{},"infoMessage":""},"id":"46d4dd75-3701-4b9d-bb95-1b59a2680ed8","name":"Get All Locations","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1744,48]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Store locations for later lookup\\nconst response = $input.first().json;\\n\\nif (!response.locations || response.locations.length === 0) {\\n  throw new Error('No locations found');\\n}\\n\\nconsole.log(`Found ${response.locations.length} locations`);\\n\\n// Return locations as array for downstream nodes\\nreturn {\\n  json: {\\n    locations: response.locations,\\n    locationCount: response.locations.length\\n  }\\n};","notice":""},"id":"59ad242e-9b67-485a-a4ed-ebb2cc2c2542","name":"Store Locations","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1520,48]},{"parameters":{"splitInBatchesNotice":"","batchSize":1,"options":{}},"id":"2ea7a697-7834-4434-bfaf-7f6a0a080bc3","name":"Loop Over Posts","type":"n8n-nodes-base.splitInBatches","typeVersion":3,"position":[-2192,240],"notesInFlow":true,"notes":"Process posts one by one (batch size = 1)"},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Match post with location\\nconst postData = $input.first().json;\\nconst allLocations = $('Store Locations').first().json.locations;\\n\\n// Find matching location\\nconst location = allLocations.find(loc => \\n  loc.name === postData.location_id || \\n  loc.name.endsWith(postData.location_id)\\n);\\n\\nif (!location) {\\n  throw new Error(`Location not found: ${postData.location_id}`);\\n}\\n\\nconsole.log('Posting to:', location.title);\\n\\nreturn {\\n  json: {\\n    ...postData,\\n    locationId: location.name,\\n    locationTitle: location.title\\n  }\\n};","notice":""},"id":"0dadc42c-07bf-4841-91ed-bd296b929493","name":"Match Location","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1968,240]},{"parameters":{"resume":"timeInterval","amount":6,"unit":"seconds"},"id":"d743ccfb-be60-4e92-bd0e-47a482165737","name":"Wait 6 Seconds","type":"n8n-nodes-base.wait","typeVersion":1.1,"position":[-1744,240],"webhookId":"wait-rate-limit-webhook","notesInFlow":true,"notes":"Rate limit: 10 posts/min per location"},{"parameters":{"conditions":{"options":{"leftValue":"","caseSensitive":true,"typeValidation":"strict"},"conditions":[{"id":"check-success-001","leftValue":"={{ $json.statusCode }}","rightValue":"201","operator":{"type":"number","operation":"equals"}}],"combinator":"or"},"options":{}},"id":"a0ac83ad-7a54-41e5-8366-2300dfa1320b","name":"Check Success","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1072,240]},{"parameters":{"resource":"database","operation":"executeQuery","query":"INSERT INTO post_logs (execution_id, location_id, location_name, post_id, content, status, created_at) VALUES ($1, $2, $3, $4, $5, $6, NOW())","options":{}},"id":"1ffad912-41fe-4d41-96be-f5ed313c5bef","name":"Log Success to DB","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[-400,144]},{"parameters":{"resource":"database","operation":"executeQuery","query":"INSERT INTO post_logs (execution_id, location_id, location_name, content, status, error_message, created_at) VALUES ($1, $2, $3, $4, $5, $6, NOW())","options":{}},"id":"c615d1a3-3435-4993-85de-0200c6944a0c","name":"Log Error to DB","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[-848,336]},{"parameters":{"preBuiltAgentsCalloutGoogleSheets":"","authentication":"oAuth2","resource":"sheet","operation":"read","documentId":{"__rl":true,"mode":"list","value":""},"sheetName":{"__rl":true,"mode":"list","value":""}},"id":"35ecc4af-736e-4589-9bfc-89b7d0d2cfbc","name":"Mark as Posted","type":"n8n-nodes-base.googleSheets","typeVersion":4.4,"position":[-176,144]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Count errors\\nconst allErrors = $input.all();\\nconst errorCount = allErrors.length;\\n\\nconsole.log(`Total errors: ${errorCount}`);\\n\\nreturn {\\n  json: {\\n    errorCount,\\n    errors: allErrors.map(e => ({\\n      location: e.json.locationTitle,\\n      error: e.json.body?.error?.message || 'Unknown'\\n    }))\\n  }\\n};","notice":""},"id":"c2956ef8-e0eb-45a3-bbb6-9d572f74f753","name":"Count Errors","type":"n8n-nodes-base.code","typeVersion":2,"position":[-624,336]},{"parameters":{"conditions":{"options":{"leftValue":"","caseSensitive":true,"typeValidation":"strict"},"conditions":[{"id":"check-alert-threshold-001","leftValue":"={{ $json.errorCount }}","rightValue":"3","operator":{"type":"number","operation":"largerEqual"}}],"combinator":"and"},"options":{}},"id":"8b2f6bcd-183c-47a7-904a-eb9ee4092fbc","name":"Alert Threshold","type":"n8n-nodes-base.if","typeVersion":2,"position":[-400,336]},{"parameters":{"authentication":"accessToken","resource":"message","operation":"post","select":"channel","channelId":{"__rl":true,"mode":"list","value":""},"messageType":"text","text":"=⚠️ *GMB Posting Errors*\\\\n\\\\nExecution: {{$execution.id}}\\\\nFailed posts: {{$json.errorCount}}\\\\n\\\\nErrors:\\\\n{{$json.errors.map(e => `- ${e.location}: ${e.error}`).join('\\\\n')}}","otherOptions":{}},"id":"b89ceb9e-e45b-461e-a40e-8e5d355dc9b6","name":"Send Slack Alert","type":"n8n-nodes-base.slack","typeVersion":2.2,"position":[-176,336],"webhookId":"d8d5d42f-3916-4573-b0cf-42d51cc41dda"},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Final summary\\nconst successLogs = $('Log Success to DB').all();\\nconst errorLogs = $('Log Error to DB').all();\\n\\nconst summary = {\\n  total: successLogs.length + errorLogs.length,\\n  success: successLogs.length,\\n  failed: errorLogs.length,\\n  successRate: ((successLogs.length / (successLogs.length + errorLogs.length)) * 100).toFixed(2) + '%'\\n};\\n\\nconsole.log('===============================');\\nconsole.log('GMB POSTING COMPLETE');\\nconsole.log('===============================');\\nconsole.log('Total posts:', summary.total);\\nconsole.log('Successful:', summary.success);\\nconsole.log('Failed:', summary.failed);\\nconsole.log('Success rate:', summary.successRate);\\nconsole.log('===============================');\\n\\nreturn { json: summary };","notice":""},"id":"f2cbd2d0-e1b6-4652-9ee4-7218cdc3065b","name":"Display Summary","type":"n8n-nodes-base.code","typeVersion":2,"position":[48,240]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"const response = $input.first().json;\\n\\nif (!response.accounts || response.accounts.length === 0) {\\n  throw new Error('No GMB accounts found');\\n}\\n\\nconst accountId = response.accounts[0].name;\\nconsole.log('Account ID:', accountId);\\n\\nreturn {\\n  json: {\\n    accountId: accountId\\n  }\\n};","notice":""},"id":"73450134-7b46-460c-ba14-9f2c1a1bf905","name":"Extract Account ID1","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1968,48]},{"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"// Build GMB post payload\\nconst data = $input.first().json;\\n\\nconst payload = {\\n  languageCode: \\"en\\",\\n  summary: data.content,\\n  topicType: data.post_type || \\"STANDARD\\"\\n};\\n\\n// Add CTA if provided\\nif (data.cta_type && data.cta_url) {\\n  payload.callToAction = {\\n    actionType: data.cta_type,\\n    url: data.cta_url\\n  };\\n}\\n\\n// Add image if provided\\nif (data.image_url) {\\n  payload.media = [{\\n    mediaFormat: \\"PHOTO\\",\\n    sourceUrl: data.image_url\\n  }];\\n}\\n\\nconst postUrl = `https://mybusiness.googleapis.com/v4/${data.locationId}/localPosts`;\\n\\nreturn {\\n  json: {\\n    payload,\\n    postUrl,\\n    locationId: data.locationId,\\n    locationTitle: data.locationTitle,\\n    originalContent: data.content,\\n    sheetRowId: data.__rowNum\\n  }\\n};","notice":""},"id":"0e1cab64-402f-4b6a-8700-f4336d5bffe0","name":"Format GMB Payload1","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1520,240]},{"parameters":{"preBuiltAgentsCalloutHttpRequest":"","curlImport":"","method":"GET","url":"={{$json.postUrl}}","authentication":"oAuth2","provideSslCertificates":false,"sendQuery":false,"sendHeaders":false,"sendBody":true,"contentType":"json","specifyBody":"keypair","bodyParameters":{"parameters":[{"name":"","value":""}]},"options":{"response":{"response":{"fullResponse":true,"neverError":true,"responseFormat":"autodetect"}}},"infoMessage":""},"id":"0561c164-0ba5-4c91-9a8e-a7856f74bd86","name":"Create GMB Post1","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1296,240]}],"connections":{"Manual Trigger":{"main":[[{"node":"Set Post Data","type":"main","index":0}]]},"Set Post Data":{"main":[[{"node":"Get GMB Account ID","type":"main","index":0}]]},"Get GMB Account ID":{"main":[[{"node":"Extract Account ID","type":"main","index":0}]]},"Extract Account ID":{"main":[[{"node":"Get GMB Locations","type":"main","index":0}]]},"Get GMB Locations":{"main":[[{"node":"Extract Location ID","type":"main","index":0}]]},"Extract Location ID":{"main":[[{"node":"Format GMB Payload","type":"main","index":0}]]},"Format GMB Payload":{"main":[[{"node":"Create GMB Post","type":"main","index":0}]]},"Create GMB Post":{"main":[[{"node":"Success Handler","type":"main","index":0}]]},"Success Handler":{"main":[[{"node":"Display Result","type":"main","index":0}]]},"Error Handler":{"main":[[{"node":"Display Result","type":"main","index":0}]]},"Schedule Trigger":{"main":[[{"node":"Read Google Sheets","type":"main","index":0}]]},"Read Google Sheets":{"main":[[{"node":"Filter Pending Posts","type":"main","index":0}]]},"Filter Pending Posts":{"main":[[{"node":"Get GMB Account","type":"main","index":0},{"node":"Loop Over Posts","type":"main","index":0}]]},"Get GMB Account":{"main":[[{"node":"Extract Account ID1","type":"main","index":0}]]},"Get All Locations":{"main":[[{"node":"Store Locations","type":"main","index":0}]]},"Loop Over Posts":{"main":[[{"node":"Match Location","type":"main","index":0}]]},"Match Location":{"main":[[{"node":"Wait 6 Seconds","type":"main","index":0}]]},"Wait 6 Seconds":{"main":[[{"node":"Format GMB Payload1","type":"main","index":0}]]},"Check Success":{"main":[[{"node":"Log Success to DB","type":"main","index":0}],[{"node":"Log Error to DB","type":"main","index":0}]]},"Log Success to DB":{"main":[[{"node":"Mark as Posted","type":"main","index":0}]]},"Log Error to DB":{"main":[[{"node":"Count Errors","type":"main","index":0}]]},"Mark as Posted":{"main":[[{"node":"Display Summary","type":"main","index":0}]]},"Count Errors":{"main":[[{"node":"Alert Threshold","type":"main","index":0}]]},"Alert Threshold":{"main":[[{"node":"Send Slack Alert","type":"main","index":0}]]},"Send Slack Alert":{"main":[[{"node":"Display Summary","type":"main","index":0}]]},"Extract Account ID1":{"main":[[{"node":"Get All Locations","type":"main","index":0}]]},"Format GMB Payload1":{"main":[[{"node":"Create GMB Post1","type":"main","index":0}]]},"Create GMB Post1":{"main":[[{"node":"Check Success","type":"main","index":0}]]}},"settings":{"executionOrder":"v1"},"pinData":{}}	[{"resultData":"1"},{"error":"2","runData":"3"},{"level":"4","tags":"5","timestamp":1764066278168,"context":"6","functionality":"7","name":"8","message":"9","stack":"10"},{},"warning",{},{},"regular","WorkflowHasIssuesError","The workflow has issues and cannot be executed for that reason. Please fix them first.","WorkflowHasIssuesError: The workflow has issues and cannot be executed for that reason. Please fix them first.\\n    at WorkflowExecute.checkForWorkflowIssues (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+sdk-trace-base@1.30_08b575bec2313d5d8a4cc75358971443/node_modules/n8n-core/src/execution-engine/workflow-execute.ts:1382:10)\\n    at WorkflowExecute.processRunExecutionData (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+sdk-trace-base@1.30_08b575bec2313d5d8a4cc75358971443/node_modules/n8n-core/src/execution-engine/workflow-execute.ts:1461:8)\\n    at WorkflowExecute.run (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file+packages+core_@opentelemetry+api@1.9.0_@opentelemetry+sdk-trace-base@1.30_08b575bec2313d5d8a4cc75358971443/node_modules/n8n-core/src/execution-engine/workflow-execute.ts:176:15)\\n    at ManualExecutionService.runManually (/usr/local/lib/node_modules/n8n/src/manual-execution.service.ts:157:27)\\n    at WorkflowRunner.runMainProcess (/usr/local/lib/node_modules/n8n/src/workflow-runner.ts:298:53)\\n    at processTicksAndRejections (node:internal/process/task_queues:105:5)\\n    at WorkflowRunner.run (/usr/local/lib/node_modules/n8n/src/workflow-runner.ts:175:4)\\n    at WorkflowExecutionService.executeManually (/usr/local/lib/node_modules/n8n/src/workflows/workflow-execution.service.ts:229:23)\\n    at WorkflowsController.runManually (/usr/local/lib/node_modules/n8n/src/workflows/workflows.controller.ts:465:10)\\n    at handler (/usr/local/lib/node_modules/n8n/src/controller.registry.ts:79:12)"]
\.


--
-- TOC entry 4114 (class 0 OID 18489)
-- Dependencies: 432
-- Data for Name: execution_entity; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.execution_entity (id, finished, mode, "retryOf", "retrySuccessId", "startedAt", "stoppedAt", "waitTill", status, "workflowId", "deletedAt", "createdAt") FROM stdin;
13	f	manual	\N	\N	2025-11-25 10:24:38.151+00	2025-11-25 10:24:38.198+00	\N	error	7InRmYUhABudg55m	\N	2025-11-25 10:24:38.106+00
\.


--
-- TOC entry 4136 (class 0 OID 19201)
-- Dependencies: 454
-- Data for Name: execution_metadata; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.execution_metadata (id, "executionId", key, value) FROM stdin;
\.


--
-- TOC entry 4144 (class 0 OID 19401)
-- Dependencies: 462
-- Data for Name: folder; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.folder (id, name, "parentFolderId", "projectId", "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4145 (class 0 OID 19419)
-- Dependencies: 463
-- Data for Name: folder_tag; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.folder_tag ("folderId", "tagId") FROM stdin;
\.


--
-- TOC entry 4151 (class 0 OID 19515)
-- Dependencies: 469
-- Data for Name: insights_by_period; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.insights_by_period (id, "metaId", type, value, "periodUnit", "periodStart") FROM stdin;
\.


--
-- TOC entry 4147 (class 0 OID 19486)
-- Dependencies: 465
-- Data for Name: insights_metadata; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.insights_metadata ("metaId", "workflowId", "projectId", "workflowName", "projectName") FROM stdin;
\.


--
-- TOC entry 4149 (class 0 OID 19503)
-- Dependencies: 467
-- Data for Name: insights_raw; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.insights_raw (id, "metaId", type, value, "timestamp") FROM stdin;
\.


--
-- TOC entry 4122 (class 0 OID 18682)
-- Dependencies: 440
-- Data for Name: installed_nodes; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.installed_nodes (name, type, "latestVersion", package) FROM stdin;
\.


--
-- TOC entry 4121 (class 0 OID 18675)
-- Dependencies: 439
-- Data for Name: installed_packages; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.installed_packages ("packageName", "installedVersion", "authorName", "authorEmail", "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4137 (class 0 OID 19215)
-- Dependencies: 455
-- Data for Name: invalid_auth_token; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.invalid_auth_token (token, "expiresAt") FROM stdin;
\.


--
-- TOC entry 4111 (class 0 OID 18470)
-- Dependencies: 429
-- Data for Name: migrations; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.migrations (id, "timestamp", name) FROM stdin;
1	1587669153312	InitialMigration1587669153312
2	1589476000887	WebhookModel1589476000887
3	1594828256133	CreateIndexStoppedAt1594828256133
4	1607431743768	MakeStoppedAtNullable1607431743768
5	1611144599516	AddWebhookId1611144599516
6	1617270242566	CreateTagEntity1617270242566
7	1620824779533	UniqueWorkflowNames1620824779533
8	1626176912946	AddwaitTill1626176912946
9	1630419189837	UpdateWorkflowCredentials1630419189837
10	1644422880309	AddExecutionEntityIndexes1644422880309
11	1630419189837	UpdateWorkflowCredentials1630419189837
12	1646834195327	IncreaseTypeVarcharLimit1646834195327
13	1646992772331	CreateUserManagement1646992772331
14	1648740597343	LowerCaseUserEmail1648740597343
15	1652254514002	CommunityNodes1652254514002
16	1644422880309	AddExecutionEntityIndexes1644422880309
17	1652367743993	AddUserSettings1652367743993
18	1652905585850	AddAPIKeyColumn1652905585850
19	1654090467022	IntroducePinData1654090467022
20	1658932090381	AddNodeIds1658932090381
21	1659902242948	AddJsonKeyPinData1659902242948
22	1660062385367	CreateCredentialsUserRole1660062385367
23	1663755770893	CreateWorkflowsEditorRole1663755770893
24	1664196174001	WorkflowStatistics1664196174001
25	1646834195327	IncreaseTypeVarcharLimit1646834195327
26	1665484192212	CreateCredentialUsageTable1665484192212
27	1665754637025	RemoveCredentialUsageTable1665754637025
28	1669739707126	AddWorkflowVersionIdColumn1669739707126
29	1669823906995	AddTriggerCountColumn1669823906995
30	1671535397530	MessageEventBusDestinations1671535397530
31	1671726148421	RemoveWorkflowDataLoadedFlag1671726148421
32	1673268682475	DeleteExecutionsWithWorkflows1673268682475
33	1674138566000	AddStatusToExecutions1674138566000
34	1674509946020	CreateLdapEntities1674509946020
35	1675940580449	PurgeInvalidWorkflowConnections1675940580449
36	1676996103000	MigrateExecutionStatus1676996103000
37	1677236854063	UpdateRunningExecutionStatus1677236854063
38	1677501636754	CreateVariables1677501636754
39	1679416281778	CreateExecutionMetadataTable1679416281778
40	1681134145996	AddUserActivatedProperty1681134145996
41	1681134145997	RemoveSkipOwnerSetup1681134145997
42	1690000000000	MigrateIntegerKeysToString1690000000000
43	1690000000020	SeparateExecutionData1690000000020
44	1690000000030	RemoveResetPasswordColumns1690000000030
45	1690000000030	AddMfaColumns1690000000030
46	1690787606731	AddMissingPrimaryKeyOnExecutionData1690787606731
47	1691088862123	CreateWorkflowNameIndex1691088862123
48	1692967111175	CreateWorkflowHistoryTable1692967111175
49	1693491613982	ExecutionSoftDelete1693491613982
50	1693554410387	DisallowOrphanExecutions1693554410387
51	1694091729095	MigrateToTimestampTz1694091729095
52	1695128658538	AddWorkflowMetadata1695128658538
53	1695829275184	ModifyWorkflowHistoryNodesAndConnections1695829275184
54	1700571993961	AddGlobalAdminRole1700571993961
55	1705429061930	DropRoleMapping1705429061930
56	1711018413374	RemoveFailedExecutionStatus1711018413374
57	1711390882123	MoveSshKeysToDatabase1711390882123
58	1712044305787	RemoveNodesAccess1712044305787
59	1714133768519	CreateProject1714133768519
60	1714133768521	MakeExecutionStatusNonNullable1714133768521
61	1717498465931	AddActivatedAtUserSetting1717498465931
62	1714133768521	MakeExecutionStatusNonNullable1714133768521
63	1720101653148	AddConstraintToExecutionMetadata1720101653148
64	1721377157740	FixExecutionMetadataSequence1721377157740
65	1717498465931	AddActivatedAtUserSetting1717498465931
66	1723627610222	CreateInvalidAuthTokenTable1723627610222
67	1723796243146	RefactorExecutionIndices1723796243146
68	1724753530828	CreateAnnotationTables1724753530828
69	1724951148974	AddApiKeysTable1724951148974
70	1726606152711	CreateProcessedDataTable1726606152711
71	1727427440136	SeparateExecutionCreationFromStart1727427440136
72	1728659839644	AddMissingPrimaryKeyOnAnnotationTagMapping1728659839644
73	1729607673464	UpdateProcessedDataValueColumnToText1729607673464
74	1729607673469	AddProjectIcons1729607673469
75	1730386903556	CreateTestDefinitionTable1730386903556
76	1731404028106	AddDescriptionToTestDefinition1731404028106
77	1731582748663	MigrateTestDefinitionKeyToString1731582748663
78	1732271325258	CreateTestMetricTable1732271325258
79	1732549866705	CreateTestRun1732549866705
80	1733133775640	AddMockedNodesColumnToTestDefinition1733133775640
81	1734479635324	AddManagedColumnToCredentialsTable1734479635324
82	1736172058779	AddStatsColumnsToTestRun1736172058779
83	1736947513045	CreateTestCaseExecutionTable1736947513045
84	1737715421462	AddErrorColumnsToTestRuns1737715421462
85	1738709609940	CreateFolderTable1738709609940
86	1739549398681	CreateAnalyticsTables1739549398681
87	1740445074052	UpdateParentFolderIdColumn1740445074052
88	1741167584277	RenameAnalyticsToInsights1741167584277
89	1742918400000	AddScopesColumnToApiKeys1742918400000
90	1745322634000	ClearEvaluation1745322634000
91	1745587087521	AddWorkflowStatisticsRootCount1745587087521
92	1745934666076	AddWorkflowArchivedColumn1745934666076
93	1745934666077	DropRoleTable1745934666077
94	1747824239000	AddProjectDescriptionColumn1747824239000
95	1750252139166	AddLastActiveAtColumnToUser1750252139166
96	1750252139166	AddScopeTables1750252139166
97	1750252139167	AddRolesTables1750252139167
98	1750252139168	LinkRoleToUserTable1750252139168
99	1750252139170	RemoveOldRoleColumn1750252139170
100	1752669793000	AddInputsOutputsToTestCaseExecution1752669793000
101	1753953244168	LinkRoleToProjectRelationTable1753953244168
102	1754475614601	CreateDataStoreTables1754475614601
103	1754475614602	ReplaceDataStoreTablesWithDataTables1754475614602
104	1756906557570	AddTimestampsToRoleAndRoleIndexes1756906557570
105	1758731786132	AddAudienceColumnToApiKeys1758731786132
106	1758794506893	AddProjectIdToVariableTable1758794506893
107	1759399811000	ChangeValueTypesForInsights1759399811000
108	1760019379982	CreateChatHubTables1760019379982
109	1760020838000	UniqueRoleNames1760020838000
110	1760314000000	CreateWorkflowDependencyTable1760314000000
111	1760965142113	DropUnusedChatHubColumns1760965142113
141	1761047826451	AddWorkflowVersionColumn1761047826451
142	1760020000000	CreateChatHubAgentTable1760020000000
143	1761655473000	ChangeDependencyInfoToJson1761655473000
144	1760116750277	CreateOAuthEntities1760116750277
145	1762177736257	AddWorkflowDescriptionColumn1762177736257
\.


--
-- TOC entry 4166 (class 0 OID 34998)
-- Dependencies: 484
-- Data for Name: oauth_access_tokens; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.oauth_access_tokens (token, "clientId", "userId") FROM stdin;
\.


--
-- TOC entry 4165 (class 0 OID 34978)
-- Dependencies: 483
-- Data for Name: oauth_authorization_codes; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.oauth_authorization_codes (code, "clientId", "userId", "redirectUri", "codeChallenge", "codeChallengeMethod", "expiresAt", state, used, "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4164 (class 0 OID 34968)
-- Dependencies: 482
-- Data for Name: oauth_clients; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.oauth_clients (id, name, "redirectUris", "grantTypes", "clientSecret", "clientSecretExpiresAt", "tokenEndpointAuthMethod", "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4167 (class 0 OID 35015)
-- Dependencies: 485
-- Data for Name: oauth_refresh_tokens; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.oauth_refresh_tokens (token, "clientId", "userId", "expiresAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4169 (class 0 OID 35035)
-- Dependencies: 487
-- Data for Name: oauth_user_consents; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.oauth_user_consents (id, "userId", "clientId", "grantedAt") FROM stdin;
\.


--
-- TOC entry 4143 (class 0 OID 19290)
-- Dependencies: 461
-- Data for Name: processed_data; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.processed_data ("workflowId", context, "createdAt", "updatedAt", value) FROM stdin;
\.


--
-- TOC entry 4131 (class 0 OID 19117)
-- Dependencies: 449
-- Data for Name: project; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.project (id, name, type, "createdAt", "updatedAt", icon, description) FROM stdin;
stWTabchmcytaHXv	Hieu Do <admin@docaohieu.com>	personal	2025-10-26 12:07:08.924+00	2025-10-26 12:17:09.234+00	\N	\N
Eal7aYKZDndjBzjn	<duyhung203@gmail.com>	personal	2025-11-21 08:31:28.797+00	2025-11-21 08:31:28.797+00	\N	\N
\.


--
-- TOC entry 4132 (class 0 OID 19124)
-- Dependencies: 450
-- Data for Name: project_relation; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.project_relation ("projectId", "userId", role, "createdAt", "updatedAt") FROM stdin;
stWTabchmcytaHXv	9b4b27cc-47b2-464b-8c0f-7224b2d7f37d	project:personalOwner	2025-10-26 12:07:08.924+00	2025-10-26 12:07:08.924+00
Eal7aYKZDndjBzjn	234313d1-b8ef-4e30-b7ae-c14af189627f	project:personalOwner	2025-11-21 08:31:28.797+00	2025-11-21 08:31:28.797+00
\.


--
-- TOC entry 4155 (class 0 OID 19571)
-- Dependencies: 473
-- Data for Name: role; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.role (slug, "displayName", description, "roleType", "systemRole", "createdAt", "updatedAt") FROM stdin;
global:owner	Owner	Owner	global	t	2025-10-26 12:07:13.517+00	2025-10-26 12:07:13.963+00
global:admin	Admin	Admin	global	t	2025-10-26 12:07:13.517+00	2025-10-26 12:07:13.963+00
global:member	Member	Member	global	t	2025-10-26 12:07:13.517+00	2025-10-26 12:07:13.963+00
project:admin	Project Admin	Full control of settings, members, workflows, credentials and executions	project	t	2025-10-26 12:07:13.517+00	2025-10-26 12:07:14.033+00
project:personalOwner	Project Owner	Project Owner	project	t	2025-10-26 12:07:13.517+00	2025-10-26 12:07:14.033+00
project:editor	Project Editor	Create, edit, and delete workflows, credentials, and executions	project	t	2025-10-26 12:07:13.517+00	2025-10-26 12:07:14.033+00
project:viewer	Project Viewer	Read-only access to workflows, credentials, and executions	project	t	2025-10-26 12:07:13.517+00	2025-10-26 12:07:14.033+00
credential:owner	Credential Owner	Credential Owner	credential	t	2025-10-26 12:07:14.065+00	2025-10-26 12:07:14.065+00
credential:user	Credential User	Credential User	credential	t	2025-10-26 12:07:14.065+00	2025-10-26 12:07:14.065+00
workflow:owner	Workflow Owner	Workflow Owner	workflow	t	2025-10-26 12:07:14.083+00	2025-10-26 12:07:14.083+00
workflow:editor	Workflow Editor	Workflow Editor	workflow	t	2025-10-26 12:07:14.083+00	2025-10-26 12:07:14.083+00
\.


--
-- TOC entry 4156 (class 0 OID 19579)
-- Dependencies: 474
-- Data for Name: role_scope; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.role_scope ("roleSlug", "scopeSlug") FROM stdin;
global:owner	annotationTag:create
global:owner	annotationTag:read
global:owner	annotationTag:update
global:owner	annotationTag:delete
global:owner	annotationTag:list
global:owner	auditLogs:manage
global:owner	banner:dismiss
global:owner	community:register
global:owner	communityPackage:install
global:owner	communityPackage:uninstall
global:owner	communityPackage:update
global:owner	communityPackage:list
global:owner	credential:share
global:owner	credential:move
global:owner	credential:create
global:owner	credential:read
global:owner	credential:update
global:owner	credential:delete
global:owner	credential:list
global:owner	externalSecretsProvider:sync
global:owner	externalSecretsProvider:create
global:owner	externalSecretsProvider:read
global:owner	externalSecretsProvider:update
global:owner	externalSecretsProvider:delete
global:owner	externalSecretsProvider:list
global:owner	externalSecret:list
global:owner	externalSecret:use
global:owner	eventBusDestination:test
global:owner	eventBusDestination:create
global:owner	eventBusDestination:read
global:owner	eventBusDestination:update
global:owner	eventBusDestination:delete
global:owner	eventBusDestination:list
global:owner	ldap:sync
global:owner	ldap:manage
global:owner	license:manage
global:owner	logStreaming:manage
global:owner	orchestration:read
global:owner	project:create
global:owner	project:read
global:owner	project:update
global:owner	project:delete
global:owner	project:list
global:owner	saml:manage
global:owner	securityAudit:generate
global:owner	sourceControl:pull
global:owner	sourceControl:push
global:owner	sourceControl:manage
global:owner	tag:create
global:owner	tag:read
global:owner	tag:update
global:owner	tag:delete
global:owner	tag:list
global:owner	user:resetPassword
global:owner	user:changeRole
global:owner	user:enforceMfa
global:owner	user:create
global:owner	user:read
global:owner	user:update
global:owner	user:delete
global:owner	user:list
global:owner	variable:create
global:owner	variable:read
global:owner	variable:update
global:owner	variable:delete
global:owner	variable:list
global:owner	projectVariable:create
global:owner	projectVariable:read
global:owner	projectVariable:update
global:owner	projectVariable:delete
global:owner	projectVariable:list
global:owner	workersView:manage
global:owner	workflow:share
global:owner	workflow:execute
global:owner	workflow:move
global:owner	workflow:create
global:owner	workflow:read
global:owner	workflow:update
global:owner	workflow:delete
global:owner	workflow:list
global:owner	folder:create
global:owner	folder:read
global:owner	folder:update
global:owner	folder:delete
global:owner	folder:list
global:owner	folder:move
global:owner	insights:list
global:owner	oidc:manage
global:owner	dataTable:list
global:owner	role:manage
global:owner	mcp:manage
global:owner	mcpApiKey:create
global:owner	mcpApiKey:rotate
global:owner	chatHub:manage
global:owner	chatHub:message
global:admin	annotationTag:create
global:admin	annotationTag:read
global:admin	annotationTag:update
global:admin	annotationTag:delete
global:admin	annotationTag:list
global:admin	auditLogs:manage
global:admin	banner:dismiss
global:admin	community:register
global:admin	communityPackage:install
global:admin	communityPackage:uninstall
global:admin	communityPackage:update
global:admin	communityPackage:list
global:admin	credential:share
global:admin	credential:move
global:admin	credential:create
global:admin	credential:read
global:admin	credential:update
global:admin	credential:delete
global:admin	credential:list
global:admin	externalSecretsProvider:sync
global:admin	externalSecretsProvider:create
global:admin	externalSecretsProvider:read
global:admin	externalSecretsProvider:update
global:admin	externalSecretsProvider:delete
global:admin	externalSecretsProvider:list
global:admin	externalSecret:list
global:admin	externalSecret:use
global:admin	eventBusDestination:test
global:admin	eventBusDestination:create
global:admin	eventBusDestination:read
global:admin	eventBusDestination:update
global:admin	eventBusDestination:delete
global:admin	eventBusDestination:list
global:admin	ldap:sync
global:admin	ldap:manage
global:admin	license:manage
global:admin	logStreaming:manage
global:admin	orchestration:read
global:admin	project:create
global:admin	project:read
global:admin	project:update
global:admin	project:delete
global:admin	project:list
global:admin	saml:manage
global:admin	securityAudit:generate
global:admin	sourceControl:pull
global:admin	sourceControl:push
global:admin	sourceControl:manage
global:admin	tag:create
global:admin	tag:read
global:admin	tag:update
global:admin	tag:delete
global:admin	tag:list
global:admin	user:resetPassword
global:admin	user:changeRole
global:admin	user:enforceMfa
global:admin	user:create
global:admin	user:read
global:admin	user:update
global:admin	user:delete
global:admin	user:list
global:admin	variable:create
global:admin	variable:read
global:admin	variable:update
global:admin	variable:delete
global:admin	variable:list
global:admin	projectVariable:create
global:admin	projectVariable:read
global:admin	projectVariable:update
global:admin	projectVariable:delete
global:admin	projectVariable:list
global:admin	workersView:manage
global:admin	workflow:share
global:admin	workflow:execute
global:admin	workflow:move
global:admin	workflow:create
global:admin	workflow:read
global:admin	workflow:update
global:admin	workflow:delete
global:admin	workflow:list
global:admin	folder:create
global:admin	folder:read
global:admin	folder:update
global:admin	folder:delete
global:admin	folder:list
global:admin	folder:move
global:admin	insights:list
global:admin	oidc:manage
global:admin	dataTable:list
global:admin	role:manage
global:admin	mcp:manage
global:admin	mcpApiKey:create
global:admin	mcpApiKey:rotate
global:admin	chatHub:manage
global:admin	chatHub:message
global:member	annotationTag:create
global:member	annotationTag:read
global:member	annotationTag:update
global:member	annotationTag:delete
global:member	annotationTag:list
global:member	eventBusDestination:test
global:member	eventBusDestination:list
global:member	tag:create
global:member	tag:read
global:member	tag:update
global:member	tag:list
global:member	user:list
global:member	variable:read
global:member	variable:list
global:member	dataTable:list
global:member	mcpApiKey:create
global:member	mcpApiKey:rotate
global:member	chatHub:message
project:admin	credential:share
project:admin	credential:move
project:admin	credential:create
project:admin	credential:read
project:admin	credential:update
project:admin	credential:delete
project:admin	credential:list
project:admin	project:read
project:admin	project:update
project:admin	project:delete
project:admin	project:list
project:admin	sourceControl:push
project:admin	projectVariable:create
project:admin	projectVariable:read
project:admin	projectVariable:update
project:admin	projectVariable:delete
project:admin	projectVariable:list
project:admin	workflow:execute
project:admin	workflow:move
project:admin	workflow:create
project:admin	workflow:read
project:admin	workflow:update
project:admin	workflow:delete
project:admin	workflow:list
project:admin	folder:create
project:admin	folder:read
project:admin	folder:update
project:admin	folder:delete
project:admin	folder:list
project:admin	folder:move
project:admin	dataTable:create
project:admin	dataTable:read
project:admin	dataTable:update
project:admin	dataTable:delete
project:admin	dataTable:readRow
project:admin	dataTable:writeRow
project:admin	dataTable:listProject
project:personalOwner	credential:share
project:personalOwner	credential:move
project:personalOwner	credential:create
project:personalOwner	credential:read
project:personalOwner	credential:update
project:personalOwner	credential:delete
project:personalOwner	credential:list
project:personalOwner	project:read
project:personalOwner	project:list
project:personalOwner	workflow:share
project:personalOwner	workflow:execute
project:personalOwner	workflow:move
project:personalOwner	workflow:create
project:personalOwner	workflow:read
project:personalOwner	workflow:update
project:personalOwner	workflow:delete
project:personalOwner	workflow:list
project:personalOwner	folder:create
project:personalOwner	folder:read
project:personalOwner	folder:update
project:personalOwner	folder:delete
project:personalOwner	folder:list
project:personalOwner	folder:move
project:personalOwner	dataTable:create
project:personalOwner	dataTable:read
project:personalOwner	dataTable:update
project:personalOwner	dataTable:delete
project:personalOwner	dataTable:readRow
project:personalOwner	dataTable:writeRow
project:personalOwner	dataTable:listProject
project:editor	credential:create
project:editor	credential:read
project:editor	credential:update
project:editor	credential:delete
project:editor	credential:list
project:editor	project:read
project:editor	project:list
project:editor	projectVariable:create
project:editor	projectVariable:read
project:editor	projectVariable:update
project:editor	projectVariable:delete
project:editor	projectVariable:list
project:editor	workflow:execute
project:editor	workflow:create
project:editor	workflow:read
project:editor	workflow:update
project:editor	workflow:delete
project:editor	workflow:list
project:editor	folder:create
project:editor	folder:read
project:editor	folder:update
project:editor	folder:delete
project:editor	folder:list
project:editor	dataTable:create
project:editor	dataTable:read
project:editor	dataTable:update
project:editor	dataTable:delete
project:editor	dataTable:readRow
project:editor	dataTable:writeRow
project:editor	dataTable:listProject
project:viewer	credential:read
project:viewer	credential:list
project:viewer	project:read
project:viewer	project:list
project:viewer	projectVariable:read
project:viewer	projectVariable:list
project:viewer	workflow:read
project:viewer	workflow:list
project:viewer	folder:read
project:viewer	folder:list
project:viewer	dataTable:read
project:viewer	dataTable:readRow
project:viewer	dataTable:listProject
credential:owner	credential:share
credential:owner	credential:move
credential:owner	credential:read
credential:owner	credential:update
credential:owner	credential:delete
credential:user	credential:read
workflow:owner	workflow:share
workflow:owner	workflow:execute
workflow:owner	workflow:move
workflow:owner	workflow:read
workflow:owner	workflow:update
workflow:owner	workflow:delete
workflow:editor	workflow:execute
workflow:editor	workflow:read
workflow:editor	workflow:update
global:owner	provisioning:manage
global:admin	provisioning:manage
global:owner	dataTable:create
global:owner	dataTable:read
global:owner	dataTable:update
global:owner	dataTable:delete
global:owner	dataTable:readRow
global:owner	dataTable:writeRow
global:owner	dataTable:listProject
global:owner	chatHubAgent:create
global:owner	chatHubAgent:read
global:owner	chatHubAgent:update
global:owner	chatHubAgent:delete
global:owner	chatHubAgent:list
global:owner	breakingChanges:list
global:admin	dataTable:create
global:admin	dataTable:read
global:admin	dataTable:update
global:admin	dataTable:delete
global:admin	dataTable:readRow
global:admin	dataTable:writeRow
global:admin	dataTable:listProject
global:admin	chatHubAgent:create
global:admin	chatHubAgent:read
global:admin	chatHubAgent:update
global:admin	chatHubAgent:delete
global:admin	chatHubAgent:list
global:admin	breakingChanges:list
global:member	chatHubAgent:create
global:member	chatHubAgent:read
global:member	chatHubAgent:update
global:member	chatHubAgent:delete
global:member	chatHubAgent:list
global:owner	mcp:oauth
global:admin	mcp:oauth
global:member	mcp:oauth
\.


--
-- TOC entry 4154 (class 0 OID 19564)
-- Dependencies: 472
-- Data for Name: scope; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.scope (slug, "displayName", description) FROM stdin;
annotationTag:create	Create Annotation Tag	Allows creating new annotation tags.
annotationTag:read	annotationTag:read	\N
annotationTag:update	annotationTag:update	\N
annotationTag:delete	annotationTag:delete	\N
annotationTag:list	annotationTag:list	\N
annotationTag:*	annotationTag:*	\N
auditLogs:manage	auditLogs:manage	\N
auditLogs:*	auditLogs:*	\N
banner:dismiss	banner:dismiss	\N
banner:*	banner:*	\N
community:register	community:register	\N
community:*	community:*	\N
communityPackage:install	communityPackage:install	\N
communityPackage:uninstall	communityPackage:uninstall	\N
communityPackage:update	communityPackage:update	\N
communityPackage:list	communityPackage:list	\N
communityPackage:manage	communityPackage:manage	\N
communityPackage:*	communityPackage:*	\N
credential:share	credential:share	\N
credential:move	credential:move	\N
credential:create	credential:create	\N
credential:read	credential:read	\N
credential:update	credential:update	\N
credential:delete	credential:delete	\N
credential:list	credential:list	\N
credential:*	credential:*	\N
externalSecretsProvider:sync	externalSecretsProvider:sync	\N
externalSecretsProvider:create	externalSecretsProvider:create	\N
externalSecretsProvider:read	externalSecretsProvider:read	\N
externalSecretsProvider:update	externalSecretsProvider:update	\N
externalSecretsProvider:delete	externalSecretsProvider:delete	\N
externalSecretsProvider:list	externalSecretsProvider:list	\N
externalSecretsProvider:*	externalSecretsProvider:*	\N
externalSecret:list	externalSecret:list	\N
externalSecret:use	externalSecret:use	\N
externalSecret:*	externalSecret:*	\N
eventBusDestination:test	eventBusDestination:test	\N
eventBusDestination:create	eventBusDestination:create	\N
eventBusDestination:read	eventBusDestination:read	\N
eventBusDestination:update	eventBusDestination:update	\N
eventBusDestination:delete	eventBusDestination:delete	\N
eventBusDestination:list	eventBusDestination:list	\N
eventBusDestination:*	eventBusDestination:*	\N
ldap:sync	ldap:sync	\N
ldap:manage	ldap:manage	\N
ldap:*	ldap:*	\N
license:manage	license:manage	\N
license:*	license:*	\N
logStreaming:manage	logStreaming:manage	\N
logStreaming:*	logStreaming:*	\N
orchestration:read	orchestration:read	\N
orchestration:list	orchestration:list	\N
orchestration:*	orchestration:*	\N
project:create	project:create	\N
project:read	project:read	\N
project:update	project:update	\N
project:delete	project:delete	\N
project:list	project:list	\N
project:*	project:*	\N
saml:manage	saml:manage	\N
saml:*	saml:*	\N
securityAudit:generate	securityAudit:generate	\N
securityAudit:*	securityAudit:*	\N
sourceControl:pull	sourceControl:pull	\N
sourceControl:push	sourceControl:push	\N
sourceControl:manage	sourceControl:manage	\N
sourceControl:*	sourceControl:*	\N
tag:create	tag:create	\N
tag:read	tag:read	\N
tag:update	tag:update	\N
tag:delete	tag:delete	\N
tag:list	tag:list	\N
tag:*	tag:*	\N
user:resetPassword	user:resetPassword	\N
user:changeRole	user:changeRole	\N
user:enforceMfa	user:enforceMfa	\N
user:create	user:create	\N
user:read	user:read	\N
user:update	user:update	\N
user:delete	user:delete	\N
user:list	user:list	\N
user:*	user:*	\N
variable:create	variable:create	\N
variable:read	variable:read	\N
variable:update	variable:update	\N
variable:delete	variable:delete	\N
variable:list	variable:list	\N
variable:*	variable:*	\N
projectVariable:create	projectVariable:create	\N
projectVariable:read	projectVariable:read	\N
projectVariable:update	projectVariable:update	\N
projectVariable:delete	projectVariable:delete	\N
projectVariable:list	projectVariable:list	\N
projectVariable:*	projectVariable:*	\N
workersView:manage	workersView:manage	\N
workersView:*	workersView:*	\N
workflow:share	workflow:share	\N
workflow:execute	workflow:execute	\N
workflow:move	workflow:move	\N
workflow:activate	workflow:activate	\N
workflow:deactivate	workflow:deactivate	\N
workflow:create	workflow:create	\N
workflow:read	workflow:read	\N
workflow:update	workflow:update	\N
workflow:delete	workflow:delete	\N
workflow:list	workflow:list	\N
workflow:*	workflow:*	\N
folder:create	folder:create	\N
folder:read	folder:read	\N
folder:update	folder:update	\N
folder:delete	folder:delete	\N
folder:list	folder:list	\N
folder:move	folder:move	\N
folder:*	folder:*	\N
insights:list	insights:list	\N
insights:*	insights:*	\N
oidc:manage	oidc:manage	\N
oidc:*	oidc:*	\N
dataTable:create	dataTable:create	\N
dataTable:read	dataTable:read	\N
dataTable:update	dataTable:update	\N
dataTable:delete	dataTable:delete	\N
dataTable:list	dataTable:list	\N
dataTable:readRow	dataTable:readRow	\N
dataTable:writeRow	dataTable:writeRow	\N
dataTable:listProject	dataTable:listProject	\N
dataTable:*	dataTable:*	\N
execution:delete	execution:delete	\N
execution:read	execution:read	\N
execution:retry	execution:retry	\N
execution:list	execution:list	\N
execution:get	execution:get	\N
execution:*	execution:*	\N
workflowTags:update	workflowTags:update	\N
workflowTags:list	workflowTags:list	\N
workflowTags:*	workflowTags:*	\N
role:manage	role:manage	\N
role:*	role:*	\N
mcp:manage	mcp:manage	\N
mcp:*	mcp:*	\N
mcpApiKey:create	mcpApiKey:create	\N
mcpApiKey:rotate	mcpApiKey:rotate	\N
mcpApiKey:*	mcpApiKey:*	\N
chatHub:manage	chatHub:manage	\N
chatHub:message	chatHub:message	\N
chatHub:*	chatHub:*	\N
*	*	\N
provisioning:manage	provisioning:manage	\N
provisioning:*	provisioning:*	\N
chatHubAgent:create	chatHubAgent:create	\N
chatHubAgent:read	chatHubAgent:read	\N
chatHubAgent:update	chatHubAgent:update	\N
chatHubAgent:delete	chatHubAgent:delete	\N
chatHubAgent:list	chatHubAgent:list	\N
chatHubAgent:*	chatHubAgent:*	\N
breakingChanges:list	breakingChanges:list	\N
breakingChanges:*	breakingChanges:*	\N
mcp:oauth	mcp:oauth	\N
\.


--
-- TOC entry 4120 (class 0 OID 18667)
-- Dependencies: 438
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.settings (key, value, "loadOnStartup") FROM stdin;
ui.banners.dismissed	["V1"]	t
features.ldap	{"loginEnabled":false,"loginLabel":"","connectionUrl":"","allowUnauthorizedCerts":false,"connectionSecurity":"none","connectionPort":389,"baseDn":"","bindingAdminDn":"","bindingAdminPassword":"","firstNameAttribute":"","lastNameAttribute":"","emailAttribute":"","loginIdAttribute":"","ldapIdAttribute":"","userFilter":"","synchronizationEnabled":false,"synchronizationInterval":60,"searchPageSize":0,"searchTimeout":60}	t
userManagement.authenticationMethod	email	t
features.sourceControl.sshKeys	{"encryptedPrivateKey":"U2FsdGVkX19YHt5aBkeIOqvwc96FwvvFnO4XZ6cEu6lVZDRUwwn6A6O64sGfFCR2IUEdlS50O0F4z7FvhA76wKT9+iN2H1IW8+JUUGHxxSsyDyeM27lyqwuCxojUFxqjIzONIAqinQxgP/JlulN45CRwEGWsCOji4ZH/UV2GJ3ov6yg/8qEbP+CWD9ppk/3nWkA9h/zNxhs8j1fC2LeH7dTzrgie1pHZkIH2U0kYke5wuD8LZ0rKCcZH0uwwdVLE06n0BMPGQKjDdwqqpmIqyUQ1LY9/UfMRj78+05TLCDpXAjZ1peW8YEIy3IVGlu/hq1oAaftlYHHdV+YfNGtDY626zPSSZbeZ6FNJ/86ymdZy1VtGujNnD0OTkgwN7r1y0kRX6l8Duyhbc4t1oDMbUiZ9jIOACLc2Jv35AF33zvdtkY5Y057bMBB3b3Ju8/hMc0LDu9uwyNw09NSbM+m2U5HEnnUDN3g/RynM0UR6OMdsMNGubU80HiyymhzhYT+ugDp+5abLnoJcC4Fmn2AJfqwi5O7ABbPvo2d3DNxUZ+SdDdvMK+Eyk15gO58WjPxF","publicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrlDa1xJWYLpnw1Z8dCptqytIneQePvn9XVDL8RsLmL n8n deploy key"}	t
features.sourceControl	{"branchName":"main","connectionType":"ssh","keyGeneratorType":"ed25519"}	t
userManagement.isInstanceOwnerSetUp	true	t
license.cert	eyJsaWNlbnNlS2V5IjoiLS0tLS1CRUdJTiBMSUNFTlNFIEtFWS0tLS0tXG5qcWxENTJ4VE4zRXVJR254cDVxZkF0bzI1Qlhac2VsK0grMnljdmFZWWNSOC95YjVKcGRVdG5IUWNiaW1MVS9hXG5WVnNPdklXbG5veS9aQUN0R0QrK05KWXJIcGk3ZndoQjFFTjJKOTJva2NIdlRXL250alFyK2lMYldnQytRVVVPXG5SNGh6RGNmaXBiRWl1NHdVakMwL3o3VmhiYTNUN2U3d0V6Qm5ub3ZVS2k3b01IOWdPaEwxWitUL01FTjhHay91XG4yODM0ZUROTzRpcldJVHlIUG52ZW9KYUNQZ3dQMnpvRmlCb2dNU1p0dlpDMWtVK3l1T1BNY0ZZQ1BxZ2oxazFXXG55Sm9ud2ZrbVRqU3k0OVoyVDllZE5uQ1FHdEgxNWJ1Rk5sMDZ5VGFzUE93V0VzUGNVK3Z0MTFQM2RYVU9nTytWXG5RYXErTzh2QnpUdGdMYmQ3VFdyUk5RPT18fFUyRnNkR1ZrWDErcmQ2RE03c0VRTnVZWUlsSzVWOXpiY1R4Ymp3XG5oaHhmR1J2L1AyOTI0SXYyQWdNbm4yK2F2Nk5uNW0rY1RWaW9sbWpQdFhXUUJnU1cxYjJ6OGJxWGxMaDJhTEhpXG5vS3lmdEZOYkpxUFEwbC8vMXN4SHhQTFlEb2M3U3BhdjVtSTJmMkxaUjg2YXBnY1RTZzY2V3lkKzdtdUdkWVhwXG51a2VaK2tWejJBS1pnT2d1TDJEYXhRTnorMjhWbGNSVlNRZzJMbWpDVHRDWDFSWmJSZWJ3S2NRS0NKNHNWdTF3XG5PN1F5Q01LRjB6L2swcldSSnRaN3FXQ3p3N2xvUGhrUVNCa0x1eGZ2U2hPMzdPdDhnV2V2VjZ1NzJNdVZKckFhXG4yRTZzNkVkd0ZQbDlIdmtKQmYrWmkrNkJnditQZHpiaVNrTG05VytObG9FM3dMdXEvOU5aTXNFbzQvc01oVnFNXG5udnVaaHVMbE1JYklYa3Rta3hYeldad01jdm5vTDBsL0ZMSGFWNnI0YUUrTHdBNEE1bEdzVGgxR05zQmhQNm8zXG51ZDhoazg3MGNSYmRxOWlhWlpKSTRDQzFESnBNdnFrSzJVbFhMMGRjd3VpVmNubGF1M2dmU3g2RlFqUERIZnBDXG5JeTJPMk5yQmtHYVZ3ZWhtRTJ1c2x4b0VWVnExM0FqUThMMnZIQ3U4N0FkYk8vU2NmdENQM0ZsWHI4Nk5ZOUNtXG5oRVlrV2I0aFFFVkNPb0NBRS9na3kyMCtPc2hTQ0NyU0wycmJrUmI5ejRzL29xczVXWnZ3NFBDcnIvVkxHbk9DXG5NMXNlNWQwalNDallkeXJuWERxekRrNS9udzlHcVpROXBuVEZqUXdzTkt0RzFxakNzbzZLaWV3RkRLKzAxaEtmXG4xdE52c1BXTEhkNVk0Y1Y0MmtBRWdGbFBOb1NKZFBUY3V3NkdzOXd1UUtIaTkyRGNPdDdIN1J6Mytxa0NGOGtoXG5DT3B6RHphbTJLOUpNQkNuMUFjSjZobi9JRXhDVFptdE9KNUtHa21wdUMxcmdBcGdGaDFLRWtESlVVWmJtR1VHXG5Fb3J4SE1CZVRDcHRNZDFuZjY3UEVNUmNvRlNOemFkM09FMkcySHFxTlNUR05RZUE5Qy9sbVAwS3BtUXltdFRzXG5PSGk3NWYxbU1vb1ZraXZldzZKaVFQd09BYmM2UDZqSVdXT1RXL1c1MmxaOHlycEhHZWc4SHJROU9yQ2dWdUNSXG53Q3J1Rk9qUEtvUjBSYm85SDlDbTBuVFBWSmtRUklBWDVHN1V5ZllleFhoRzMwdTE2LzFtYlN6WWpLcXdySzVrXG5OL05panlZb2QzR0p2UE1GakVhVXpoeFBFTVpieW56aTdpalJQZmxKV0tWbkRxWVA0amJQdXJENVlib3VyZkd1XG55TWlvRmhVdVB5ZlpCWk1jSnVjUzl2RTdhUndZNWd1bE54YWVrRVF3aU5UeEtLV0lVUUtvNWxNcU4zdTZTcGpLXG5URk9qY3N0M3VRQ0NodjM5Slh0MlBVeURxSEZsRXgxNUN5bFdob2ZNNDlqbTl3ZmdpNVd3WGlEMnB4aGtWMDA5XG5EemxZREJET3I2eXlENDVPVHR2ZEc4NnJ5NC9sY0ExMk1MWEF6dVFWT2daUC9hdjB2KzFzZkYrazVGZ0d2Sk5TXG5aYWE4YTFwRG90QUtMbHNINjNodDlZdS91WDVhcWtCc0NOM1FVQzBpWG1nQWV1WjkrWTc3NDlHRlB6Zi9QeFdsXG4zQWlOd2VKZVJvMDhVa3IyOE1RRWNIemN3dDVCaUNZZ3Rld3cwQ2N2bzRLbGY5ZkNrQXVBSklucmdyMC9ZYjJPXG5xbVVxTXl4aklNT3F5MXNwc0tIeWtFWG1YdFBZTEpjMVkrUUZiU29xWkJNVUlKdkJ1SU90YURqZ1lkbm9GTXhoXG5Oc2ZoYVhXQ0VvYmJsekpNZSs1SXFJb1pKaUhLcDQzQytOTm9VVUhiOGk5YU1aN3l0VnZYVFRNS1dVYi8vNkpDXG50QWZXa0NnTE1nOXFZTTdRMVNzbFFUbTN3K3IzSTRPd2hqUjNpZ3N3ZG9lem5YVlRYZ0RibEc2dmtpazdTQjB5XG5yTGhRVjd4UU1BTmxUR1plVjlWZ2M5cG53V3N1LzJjdUFvWnZ2WXJFUmNVeWpjd1JLWWNuRHI4RGhOenBxa21SXG40ZlNjVjJCV3hUK0NqWXArRjV2N25hdVRZVDdySDlpSktiR29CQU42bU1xd3BNWjd6aCtYNlBKeE8xU081MndiXG5BTDQyNmtFRVFqVXg1WGVBUmczRjBGajU5TWxEaFVhaWFDMjlLSW5jRFZmNDJjeU1IR3ZLazVlSEp1Wk82eGtjXG5FVkNqQXpRVmNlMS9YUEQ1VUw3RllRNFh4ZVh4aFhRTDFPODJXemV3QkRzcjhlTCtjdVFuZzVDL2RQUjZRNWtSXG5yMnpNU3NNR2NtTE5yaTdaSTNWSWFuL3hIWTA1VitzWGpDSUVrTjRyQUxCeUovdDExRzVJbktZeWdWTFlvWUFQXG5UQ3pWVkkybjljVEJ4QU1JUmIwQ215c1J5RUhVZGhrZHJCK051TUp0SWZ5QXJyTVAwdmtqT3RscFhpQVdXVXUxXG5Oek1BZ3B0Nk9uSTVIaldnMjdlN3FKWWFhQzRLYnE5VE40dXZDNTdXanlvTm9INVZBWEdST0dSaGxHTStlN0xHXG56WjM2Y3NUeUVmNVZQQ2xrejhFclJ6ZjVyYkxUa1NqK2cyUW14anQ2SkpncGF4OFNBRjZUcHU1OWpKNkNnMzdOXG5kYlp4WHRrc2ZyaThBemlnRll4Y2tTcmRIdU5GYThncXlTeEtaWGI3TjZuUDh6UllDMTl2Uk9OMTRTNkQzVk03XG5kZUlOSGFVVWZYdXI2bkoxTUhNemZqVnNkenR0aVVCcEMwQ0VMcytRcEJqMk5nUnRTejJQRjQxZmxHQld1L011XG45OVlYK1J1Q1dXNlVTWVZSb0dWY2R4djBEdU1xdHJpUkNpTFkrZnAzdUVzZEVoVm84OFcyb0dmNEZiQnY4R1hoXG5QNmxRbjZnWnJ0YkpiTENac0hnYU9MUm9EakxtaWNBM09zYmcxK0NPOGxYbUxSSlE9PXx8T3llSHdIRjN4dDc5XG5ZUXhhVUt3STRQamgzOTlUR0VTSlI0dHU5VVhlL0wwUnBrdWt2aTJ6N0NLWnhodEVicStuMWxSTEg4VUc5clcrXG5Id0E0c2ZraENJVEpFU2kzblByVnNRbE1vc1VwczVPd3B5T24vcHJBT3JsMnhmY0lhWnZaaHljVEkxZkd3cEtmXG5VK2tzOFFrcTROMWxKT25KaDd1ckdmbmVBUG5MQytyYzZhSVlONTJ3ek85dkloNUVLYWF4OEZXRzk5SGVrZmM4XG4zU2taSDVNc1FkaFB1YnRkS1NucUxGdytJdSswN0VJUnMrM0tkM0NseTk1WlVoZWpyZ3RkZ1ZNZnJpd2tXeXdIXG5jbXdPOThkMU5UNTZ1c0RLWUVrOEVlVHY5aUxEckE2SUliNmJVbEVnODZRT2N1T2VvRUgyb1dyWnEzdUs2aEtLXG52aWxlV1lHL2xBPT1cbi0tLS0tRU5EIExJQ0VOU0UgS0VZLS0tLS0iLCJ4NTA5IjoiLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tXG5NSUlFRERDQ0FmUUNDUUNxZzJvRFQ4MHh3akFOQmdrcWhraUc5dzBCQVFVRkFEQklNUXN3Q1FZRFZRUUdFd0pFXG5SVEVQTUEwR0ExVUVDQXdHUW1WeWJHbHVNUTh3RFFZRFZRUUhEQVpDWlhKc2FXNHhGekFWQmdOVkJBTU1EbXhwXG5ZMlZ1YzJVdWJqaHVMbWx2TUI0WERUSXlNRFl5TkRBME1UQTBNRm9YRFRJek1EWXlOREEwTVRBME1Gb3dTREVMXG5NQWtHQTFVRUJoTUNSRVV4RHpBTkJnTlZCQWdNQmtKbGNteHBiakVQTUEwR0ExVUVCd3dHUW1WeWJHbHVNUmN3XG5GUVlEVlFRRERBNXNhV05sYm5ObExtNDRiaTVwYnpDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDXG5BUW9DZ2dFQkFNQk0wNVhCNDRnNXhmbUNMd2RwVVR3QVQ4K0NCa3lMS0ZzZXprRDVLLzZXaGFYL1hyc2QvUWQwXG4yMEo3d2w1V2RIVTRjVkJtRlJqVndWemtsQ0syeVlKaThtang4c1hzR3E5UTFsYlVlTUtmVjlkc2dmdWhubEFTXG50blFaZ2x1Z09uRjJGZ1JoWGIvakswdHhUb2FvK2JORTZyNGdJRXpwa3RITEJUWXZ2aXVKbXJlZjdXYlBSdDRJXG5uZDlEN2xoeWJlYnloVjdrdXpqUUEvcFBLSFRGczhNVEhaOGhZVXhSeXJwbTMrTVl6UUQrYmpBMlUxRkljdGFVXG53UVhZV2FON3QydVR3Q3Q5ekFLc21ZL1dlT2J2bDNUWk41T05MQXp5V0dDdWxtNWN3S1IzeGJsQlp6WG5CNmdzXG5Pbk4yT0FkU3RjelRWQ3ljbThwY0ZVcnl0S1NLa0dFQ0F3RUFBVEFOQmdrcWhraUc5dzBCQVFVRkFBT0NBZ0VBXG5sSjAxd2NuMXZqWFhDSHVvaTdSMERKMWxseDErZGFmcXlFcVBBMjdKdStMWG1WVkdYUW9yUzFiOHhqVXFVa2NaXG5UQndiV0ZPNXo1ZFptTnZuYnlqYXptKzZvT2cwUE1hWXhoNlRGd3NJMlBPYmM3YkZ2MmVheXdQdC8xQ3BuYzQwXG5xVU1oZnZSeC9HQ1pQQ1d6My8yUlBKV1g5alFEU0hYQ1hxOEJXK0kvM2N1TERaeVkzZkVZQkIwcDNEdlZtYWQ2XG42V0hRYVVyaU4wL0xxeVNPcC9MWmdsbC90MDI5Z1dWdDA1WmliR29LK2NWaFpFY3NMY1VJaHJqMnVGR0ZkM0ltXG5KTGcxSktKN2pLU0JVUU9kSU1EdnNGVUY3WWRNdk11ckNZQTJzT05OOENaK0k1eFFWMUtTOWV2R0hNNWZtd2dTXG5PUEZ2UHp0RENpMC8xdVc5dE9nSHBvcnVvZGFjdCtFWk5rQVRYQ3ZaaXUydy9xdEtSSkY0VTRJVEVtNWFXMGt3XG42enVDOHh5SWt0N3ZoZHM0OFV1UlNHSDlqSnJBZW1sRWl6dEdJTGhHRHF6UUdZYmxoVVFGR01iQmI3amhlTHlDXG5MSjFXT0c2MkYxc3B4Q0tCekVXNXg2cFIxelQxbWhFZ2Q0TWtMYTZ6UFRwYWNyZDk1QWd4YUdLRUxhMVJXU0ZwXG5NdmRoR2s0TnY3aG5iOHIrQnVNUkM2aWVkUE1DelhxL001MGNOOEFnOGJ3K0oxYUZvKzBFSzJoV0phN2tpRStzXG45R3ZGalNkekNGbFVQaEtra1Vaa1NvNWFPdGNRcTdKdTZrV0JoTG9GWUtncHJscDFRVkIwc0daQTZvNkR0cWphXG5HNy9SazZ2YmFZOHdzTllLMnpCWFRUOG5laDVab1JaL1BKTFV0RUV0YzdZPVxuLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLSJ9	f
mcp.access.enabled	true	t
\.


--
-- TOC entry 4133 (class 0 OID 19155)
-- Dependencies: 451
-- Data for Name: shared_credentials; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.shared_credentials ("credentialsId", "projectId", role, "createdAt", "updatedAt") FROM stdin;
mcMfxx1mub2XimHN	stWTabchmcytaHXv	credential:owner	2025-11-04 03:18:36.48+00	2025-11-04 03:18:36.48+00
yIHqRqm0mV1LLjtR	stWTabchmcytaHXv	credential:owner	2025-11-04 03:31:18.084+00	2025-11-04 03:31:18.084+00
z5U3WTHeGbLkO8CL	stWTabchmcytaHXv	credential:owner	2025-11-04 03:34:40.297+00	2025-11-04 03:34:40.297+00
KRNE3nXewO8fnuDU	stWTabchmcytaHXv	credential:owner	2025-11-04 03:40:25.94+00	2025-11-04 03:40:25.94+00
\.


--
-- TOC entry 4134 (class 0 OID 19181)
-- Dependencies: 452
-- Data for Name: shared_workflow; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.shared_workflow ("workflowId", "projectId", role, "createdAt", "updatedAt") FROM stdin;
NnqZbfATi88ZRVYl	stWTabchmcytaHXv	workflow:owner	2025-11-04 03:12:01.434+00	2025-11-04 03:12:01.434+00
7InRmYUhABudg55m	stWTabchmcytaHXv	workflow:owner	2025-11-25 10:24:36.433+00	2025-11-25 10:24:36.433+00
\.


--
-- TOC entry 4117 (class 0 OID 18517)
-- Dependencies: 435
-- Data for Name: tag_entity; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.tag_entity (name, "createdAt", "updatedAt", id) FROM stdin;
\.


--
-- TOC entry 4153 (class 0 OID 19542)
-- Dependencies: 471
-- Data for Name: test_case_execution; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.test_case_execution (id, "testRunId", "executionId", status, "runAt", "completedAt", "errorCode", "errorDetails", metrics, "createdAt", "updatedAt", inputs, outputs) FROM stdin;
\.


--
-- TOC entry 4152 (class 0 OID 19527)
-- Dependencies: 470
-- Data for Name: test_run; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.test_run (id, "workflowId", status, "errorCode", "errorDetails", "runAt", "completedAt", metrics, "createdAt", "updatedAt") FROM stdin;
\.


--
-- TOC entry 4119 (class 0 OID 18604)
-- Dependencies: 437
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public."user" (id, email, "firstName", "lastName", password, "personalizationAnswers", "createdAt", "updatedAt", settings, disabled, "mfaEnabled", "mfaSecret", "mfaRecoveryCodes", "lastActiveAt", "roleSlug") FROM stdin;
234313d1-b8ef-4e30-b7ae-c14af189627f	duyhung203@gmail.com	\N	\N	\N	\N	2025-11-21 08:31:28.797+00	2025-11-21 08:31:28.797+00	\N	f	f	\N	\N	\N	global:member
9b4b27cc-47b2-464b-8c0f-7224b2d7f37d	admin@docaohieu.com	Hieu	Do	$2a$10$xZdMVrn/q6pp6yUh969sZu9BVrtTQmz7ecgbykF1/rxn9z9jzPwou	{"version":"v4","personalization_survey_submitted_at":"2025-10-26T12:17:36.154Z","personalization_survey_n8n_version":"1.116.2","automationGoalDevops":["ci-cd","cloud-infrastructure-orchestration","data-syncing","incident-response","monitoring-alerting","reporting","ticketing-systems-integrations"],"companySize":"<20","companyType":"saas","role":"devops","reportedSource":"google"}	2025-10-26 12:07:02.574+00	2025-11-28 10:40:56.109+00	{"userActivated": false}	f	f	\N	\N	2025-11-28	global:owner
\.


--
-- TOC entry 4142 (class 0 OID 19274)
-- Dependencies: 460
-- Data for Name: user_api_keys; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.user_api_keys (id, "userId", label, "apiKey", "createdAt", "updatedAt", scopes, audience) FROM stdin;
9NIgkBeJm5Nml5a0	9b4b27cc-47b2-464b-8c0f-7224b2d7f37d	MCP Server API Key	eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5YjRiMjdjYy00N2IyLTQ2NGItOGMwZi03MjI0YjJkN2YzN2QiLCJpc3MiOiJuOG4iLCJhdWQiOiJtY3Atc2VydmVyLWFwaSIsImp0aSI6ImZiMjU4ZTcxLWFmYjQtNDAxZi05YzQ1LWE2ZGM2NDRlMTcyNSIsImlhdCI6MTc2NDA2NzIyOH0.yyvRlsz-BZ74ALqm_AZjl7Sg3x0TspUzngK_Bqmg2-E	2025-11-25 10:40:28.577+00	2025-11-25 10:40:28.577+00	[]	mcp-server-api
\.


--
-- TOC entry 4128 (class 0 OID 18790)
-- Dependencies: 446
-- Data for Name: variables; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.variables (key, type, value, id, "projectId") FROM stdin;
\.


--
-- TOC entry 4116 (class 0 OID 18507)
-- Dependencies: 434
-- Data for Name: webhook_entity; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.webhook_entity ("webhookPath", method, node, "webhookId", "pathLength", "workflowId") FROM stdin;
\.


--
-- TOC entry 4162 (class 0 OID 21073)
-- Dependencies: 480
-- Data for Name: workflow_dependency; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.workflow_dependency (id, "workflowId", "workflowVersionId", "dependencyType", "dependencyKey", "dependencyInfo", "indexVersionId", "createdAt") FROM stdin;
\.


--
-- TOC entry 4115 (class 0 OID 18499)
-- Dependencies: 433
-- Data for Name: workflow_entity; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.workflow_entity (name, active, nodes, connections, "createdAt", "updatedAt", settings, "staticData", "pinData", "versionId", "triggerCount", id, meta, "parentFolderId", "isArchived", "versionCounter", description) FROM stdin;
WordPress Auto Publisher (Perplexity + Claude)	f	[{"parameters":{},"id":"ca0f138f-20f6-4264-a937-bf1e7fd8b46e","name":"Manual Trigger","type":"n8n-nodes-base.manualTrigger","typeVersion":1,"position":[-2336,-384],"notesInFlow":true,"notes":"Bắt đầu workflow thủ công. Có thể thay bằng Webhook hoặc Schedule Trigger."},{"parameters":{"assignments":{"assignments":[{"id":"field-keyword","name":"keyword","value":"cách làm bánh mì ngon","type":"string"},{"id":"field-language","name":"language","value":"vi","type":"string"},{"id":"field-wordcount","name":"wordCount","value":1500,"type":"number"},{"id":"field-tone","name":"tone","value":"professional","type":"string"},{"id":"field-wordpress-url","name":"wordpressUrl","value":"https://wellingtondecorators.com","type":"string"}]},"options":{}},"id":"bd7de974-2a91-4784-960f-a738d140df74","name":"Config - Input Parameters","type":"n8n-nodes-base.set","typeVersion":3.3,"position":[-2112,-384],"notesInFlow":true,"notes":"Cấu hình tham số đầu vào:\\n- keyword: Từ khóa chính cần viết bài\\n- language: Ngôn ngữ (vi/en)\\n- wordCount: Số từ mục tiêu\\n- tone: Giọng văn (professional/casual/friendly)\\n- wordpressUrl: URL của WordPress site"},{"parameters":{"method":"POST","url":"https://api.perplexity.ai/chat/completions","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"sonar-pro\\",\\n  \\"messages\\": [\\n    {\\n      \\"role\\": \\"system\\",\\n      \\"content\\": \\"Bạn là chuyên gia SEO và nghiên cứu thị trường với 10 năm kinh nghiệm. Bạn giỏi phân tích từ khóa, tìm LSI keywords, nghiên cứu xu hướng tìm kiếm và xây dựng outline bài viết chuẩn SEO dựa trên dữ liệu thực tế từ internet.\\"\\n    },\\n    {\\n      \\"role\\": \\"user\\",\\n      \\"content\\": \\"Hãy nghiên cứu và phân tích từ khóa: \\\\\\"{{ $json.keyword }}\\\\\\" (ngôn ngữ: {{ $json.language }})\\\\n\\\\nTìm kiếm thông tin mới nhất từ internet và cung cấp phân tích chi tiết dưới dạng JSON:\\\\n\\\\n1. **search_intent**: Ý định tìm kiếm chính (informational/commercial/transactional/navigational)\\\\n\\\\n2. **trending_topics**: Mảng 5-7 chủ đề đang trending liên quan đến từ khóa\\\\n\\\\n3. **lsi_keywords**: Mảng 15-20 từ khóa LSI (Latent Semantic Indexing) liên quan, bao gồm cả từ khóa longtail\\\\n\\\\n4. **outline**: Object chứa cấu trúc bài viết chi tiết:\\\\n   - h1: Tiêu đề chính hấp dẫn, có từ khóa, tối đa 60 ký tự\\\\n   - sections: Array 5-8 sections, mỗi section có:\\\\n     * h2: Tiêu đề section (bao gồm LSI keywords tự nhiên)\\\\n     * h3_list: Array 3-5 tiêu đề h3 con\\\\n     * key_points: Array 4-6 điểm chính cần đề cập\\\\n     * references: Gợi ý nguồn tham khảo hoặc ví dụ thực tế\\\\n\\\\n5. **faq**: Mảng 7-10 objects câu hỏi thường gặp, mỗi object có:\\\\n   - question: Câu hỏi (dựa trên People Also Ask từ Google)\\\\n   - answer_hint: Gợi ý trả lời chi tiết (2-3 câu)\\\\n   - search_volume: Ước tính volume (high/medium/low)\\\\n\\\\n6. **image_suggestions**: Mảng 6-8 gợi ý hình ảnh:\\\\n   - description: Mô tả chi tiết hình ảnh cần tìm\\\\n   - placement: Vị trí đề xuất (intro/section1/section2/faq/conclusion)\\\\n   - alt_text: Alt text tối ưu cho SEO\\\\n   - image_type: Loại ảnh (infographic/photo/diagram/screenshot)\\\\n\\\\n7. **seo_tips**: Object chứa:\\\\n   - meta_description: Meta description hấp dẫn (150-160 ký tự)\\\\n   - focus_keyphrase: Cụm từ khóa chính\\\\n   - secondary_keywords: Array 3-5 từ khóa phụ\\\\n   - keyword_density_target: Mật độ từ khóa mục tiêu (%)\\\\n   - internal_link_suggestions: Gợi ý anchor text cho internal links\\\\n\\\\n8. **content_tips**: Object chứa:\\\\n   - target_audience: Đối tượng mục tiêu\\\\n   - content_angle: Góc độ viết bài (how-to/listicle/guide/comparison)\\\\n   - unique_selling_points: 3-5 điểm độc đáo cần nhấn mạnh\\\\n   - competitor_gaps: Điểm yếu của đối thủ có thể khai thác\\\\n\\\\nTrả về ONLY valid JSON, không có markdown code blocks hay giải thích thêm.\\"\\n    }\\n  ],\\n  \\"temperature\\": 0.2,\\n  \\"max_tokens\\": 4000,\\n  \\"return_images\\": false,\\n  \\"return_related_questions\\": true,\\n  \\"search_recency_filter\\": \\"month\\"\\n}","options":{}},"id":"530dff20-61c2-4930-97dd-6855dba580ea","name":"Step 1 - Perplexity Research","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1888,-384],"notesInFlow":true,"credentials":{"httpHeaderAuth":{"id":"mcMfxx1mub2XimHN","name":"Perplexity API"}},"notes":"Bước 1: Dùng Perplexity Sonar Pro để:\\n- Tìm kiếm thông tin real-time từ internet\\n- Phân tích search intent & trending topics\\n- Tìm 15-20 LSI keywords\\n- Tạo outline chi tiết với references\\n- Tạo 7-10 câu hỏi FAQ từ People Also Ask\\n- Gợi ý 6-8 hình ảnh\\n- SEO tips & content strategy\\n\\nModel: sonar-pro (online search + AI)\\nChi phí: ~$0.005-0.01/request\\n\\nCần credential: Header Auth\\n- Name: Authorization\\n- Value: Bearer pplx-YOUR_API_KEY"},{"parameters":{"jsCode":"// Parse Perplexity response\\nconst perplexityResponse = $input.first().json;\\nconst content = perplexityResponse.choices[0].message.content;\\n\\n// Try to parse JSON (remove markdown code blocks if any)\\nlet research;\\ntry {\\n  // Remove markdown code blocks\\n  const cleanContent = content.replace(/```json\\\\n?/g, '').replace(/```\\\\n?/g, '').trim();\\n  research = JSON.parse(cleanContent);\\n} catch (e) {\\n  console.error('Failed to parse Perplexity response as JSON:', e);\\n  console.log('Raw content:', content);\\n  \\n  // Fallback with basic structure\\n  research = {\\n    search_intent: \\"informational\\",\\n    trending_topics: [],\\n    lsi_keywords: [],\\n    outline: {\\n      h1: $('Config - Input Parameters').first().json.keyword,\\n      sections: []\\n    },\\n    faq: [],\\n    image_suggestions: [],\\n    seo_tips: {\\n      meta_description: \\"\\",\\n      focus_keyphrase: $('Config - Input Parameters').first().json.keyword,\\n      secondary_keywords: [],\\n      keyword_density_target: 1.5\\n    },\\n    content_tips: {\\n      target_audience: \\"general\\",\\n      content_angle: \\"how-to\\",\\n      unique_selling_points: [],\\n      competitor_gaps: []\\n    }\\n  };\\n}\\n\\n// Store related questions if available\\nconst relatedQuestions = perplexityResponse.related_questions || [];\\n\\nreturn {\\n  json: {\\n    keyword: $('Config - Input Parameters').first().json.keyword,\\n    research: research,\\n    related_questions: relatedQuestions,\\n    research_raw: content\\n  }\\n};"},"id":"c58b3dcb-6d5a-4bad-9aed-60f35334cf44","name":"Parse Research JSON","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1664,-384],"notesInFlow":true,"notes":"Parse JSON response từ Perplexity.\\nXử lý trường hợp có markdown code blocks hoặc JSON không hợp lệ.\\nLưu related_questions từ Perplexity nếu có."},{"parameters":{"method":"POST","url":"https://agentrouter.org/v1/messages","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"},{"name":"anthropic-version","value":"2023-06-01"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"model\\": \\"claude-sonnet-4.5\\",\\n  \\"max_tokens\\": 8000,\\n  \\"temperature\\": 0.7,\\n  \\"system\\": \\"Bạn là một copywriter SEO chuyên nghiệp hàng đầu với hơn 10 năm kinh nghiệm. Bạn viết content theo chuẩn E-E-A-T của Google (Experience, Expertise, Authoritativeness, Trustworthiness). Phong cách viết của bạn tự nhiên, dễ đọc, có chiều sâu chuyên môn, giàu ví dụ thực tế và tránh spam từ khóa. Bạn luôn đảm bảo nội dung có giá trị cao cho người đọc.\\",\\n  \\"messages\\": [\\n    {\\n      \\"role\\": \\"user\\",\\n      \\"content\\": \\"Dựa trên kết quả nghiên cứu từ Perplexity AI:\\\\n\\\\n```json\\\\n{{ JSON.stringify($json.research, null, 2) }}\\\\n```\\\\n\\\\n---\\\\n\\\\n**NHIỆM VỤ:** Viết BÀI VIẾT HOÀN CHỈNH về \\\\\\"{{ $json.keyword }}\\\\\\" theo các yêu cầu sau:\\\\n\\\\n## 📋 CẤU TRÚC BÀI VIẾT\\\\n\\\\n### 1. Tiêu đề H1\\\\n- Hấp dẫn, có từ khóa chính\\\\n- Tối đa 60 ký tự\\\\n- Tạo curiosity gap để khuyến khích click\\\\n\\\\n### 2. Đoạn mở bài (200-250 từ)\\\\n- **Hook mạnh mẽ:** Bắt đầu bằng câu hỏi, thống kê gây sốc, hoặc tình huống thực tế\\\\n- **Identify pain point:** Nêu vấn đề người đọc đang gặp phải\\\\n- **Promise value:** Cam kết giá trị người đọc sẽ nhận được\\\\n- **Preview nội dung:** Tóm tắt ngắn gọn những gì bài viết sẽ đề cập\\\\n\\\\n### 3. Mục lục (Table of Contents)\\\\n- Tạo danh sách các H2 chính\\\\n- Format: HTML unordered list với ID anchors\\\\n\\\\n### 4. Nội dung chính theo outline đã cho\\\\n**Cho mỗi section:**\\\\n- **H2:** Tiêu đề section rõ ràng, có LSI keywords tự nhiên\\\\n- **Intro paragraph:** 2-3 câu giới thiệu section\\\\n- **H3 subsections:** Chia nhỏ nội dung với H3\\\\n- **Nội dung chi tiết:**\\\\n  * Độ dài: 300-500 từ/section\\\\n  * Có ví dụ cụ thể, số liệu, case study nếu phù hợp\\\\n  * Dùng bullet points/numbered lists khi cần\\\\n  * Highlight key terms bằng **bold** (tag <strong>)\\\\n  * Thêm tips/notes quan trọng\\\\n- **Transition:** Câu chuyển tiếp tự nhiên sang section tiếp theo\\\\n\\\\n### 5. Phần FAQ (H2: \\\\\\"Câu hỏi thường gặp\\\\\\")\\\\n- Mỗi câu hỏi là một H3\\\\n- Trả lời đầy đủ, chi tiết (100-150 từ/câu)\\\\n- Dùng schema markup format nếu có thể\\\\n- Thêm value, không chỉ trả lời ngắn gọn\\\\n\\\\n### 6. Kết luận (150-200 từ)\\\\n- **Tóm tắt key takeaways:** 3-5 điểm chính\\\\n- **Reinforce value:** Nhắc lại lợi ích người đọc nhận được\\\\n- **CTA nhẹ nhàng:** Khuyến khích hành động tiếp theo (không quá salesy)\\\\n- **Future outlook:** Hint về xu hướng tương lai hoặc bài viết liên quan\\\\n\\\\n---\\\\n\\\\n## 🎯 YÊU CẦU NỘI DUNG\\\\n\\\\n### Độ dài & Ngôn ngữ\\\\n- **Target word count:** {{ $('Config - Input Parameters').item.json.wordCount }} từ (±10%)\\\\n- **Ngôn ngữ:** {{ $('Config - Input Parameters').item.json.language }}\\\\n- **Tone:** {{ $('Config - Input Parameters').item.json.tone }}\\\\n\\\\n### Chất lượng nội dung (E-E-A-T)\\\\n✅ **Experience (Kinh nghiệm):**\\\\n- Viết như người có kinh nghiệm thực tế\\\\n- Thêm personal insights, lessons learned\\\\n- Đề cập common mistakes và cách tránh\\\\n\\\\n✅ **Expertise (Chuyên môn):**\\\\n- Thể hiện hiểu biết sâu về chủ đề\\\\n- Dùng thuật ngữ chuyên ngành (có giải thích)\\\\n- Cite số liệu, nghiên cứu khi có thể\\\\n\\\\n✅ **Authoritativeness (Uy tín):**\\\\n- Confident tone, không dùng \\\\\\"có lẽ\\\\\\", \\\\\\"có thể\\\\\\"\\\\n- Đưa ra khuyến nghị rõ ràng\\\\n- Back up claims bằng logic/evidence\\\\n\\\\n✅ **Trustworthiness (Đáng tin):**\\\\n- Trung thực, cân bằng pros/cons\\\\n- Thừa nhận limitations khi có\\\\n- Không hứa hẹn quá mức\\\\n\\\\n### SEO On-page\\\\n✅ **Từ khóa:**\\\\n- Focus keyword trong H1, first paragraph, conclusion\\\\n- LSI keywords phân bố tự nhiên trong bài\\\\n- Keyword density: {{ $json.research.seo_tips.keyword_density_target }}%\\\\n- KHÔNG spam từ khóa, ưu tiên tự nhiên\\\\n\\\\n✅ **Internal linking:**\\\\n- Đánh dấu vị trí cần internal link: `[INTERNAL_LINK:anchor text tự nhiên]`\\\\n- Dùng 5-8 internal links\\\\n- Anchor text phải tự nhiên trong ngữ cảnh\\\\n\\\\n✅ **Hình ảnh:**\\\\n- Đánh dấu vị trí cần ảnh: `[IMAGE:mô tả chi tiết ảnh cần tìm]`\\\\n- Vị trí: sau intro, giữa sections dài, trong FAQ\\\\n- 5-7 ảnh cho bài {{ $('Config - Input Parameters').item.json.wordCount }} từ\\\\n\\\\n### Formatting & Readability\\\\n✅ **Paragraph length:**\\\\n- 2-4 câu/đoạn\\\\n- Không quá 150 từ/đoạn\\\\n- Thêm white space để dễ đọc\\\\n\\\\n✅ **Lists:**\\\\n- Dùng bullet points cho items không có thứ tự\\\\n- Dùng numbered lists cho steps/rankings\\\\n- Mỗi list item là 1 câu hoàn chỉnh hoặc phrase ngắn gọn\\\\n\\\\n✅ **Emphasis:**\\\\n- **Bold** (<strong>) cho key terms, important points\\\\n- *Italic* (<em>) cho emphasis nhẹ, foreign terms\\\\n- Không overuse formatting\\\\n\\\\n✅ **HTML structure:**\\\\n- Sử dụng semantic HTML5 tags\\\\n- Hierarchy đúng: H1 → H2 → H3 (không skip levels)\\\\n- Properly nested tags\\\\n\\\\n---\\\\n\\\\n## 📤 FORMAT OUTPUT\\\\n\\\\n**Trả về HTML thuần túy với:**\\\\n\\\\n```html\\\\n<h1>Tiêu đề chính</h1>\\\\n\\\\n<p>Đoạn mở bài với hook mạnh...</p>\\\\n\\\\n<div class=\\\\\\"table-of-contents\\\\\\">\\\\n<h2>Mục lục</h2>\\\\n<ul>\\\\n  <li><a href=\\\\\\"#section1\\\\\\">Section 1</a></li>\\\\n  ...\\\\n</ul>\\\\n</div>\\\\n\\\\n<h2 id=\\\\\\"section1\\\\\\">Section 1 Title</h2>\\\\n<p>Nội dung section 1...</p>\\\\n\\\\n[IMAGE:mô tả ảnh chi tiết]\\\\n\\\\n<h3>Subsection 1.1</h3>\\\\n<p>Nội dung...</p>\\\\n\\\\n<ul>\\\\n  <li>Bullet point 1</li>\\\\n  <li>Bullet point 2</li>\\\\n</ul>\\\\n\\\\n<p>Đoạn văn có <strong>từ khóa quan trọng</strong> và <a href=\\\\\\"#\\\\\\">internal link</a> hoặc [INTERNAL_LINK:anchor text].</p>\\\\n\\\\n...\\\\n\\\\n<h2>Câu hỏi thường gặp</h2>\\\\n\\\\n<h3>Câu hỏi 1?</h3>\\\\n<p>Trả lời chi tiết...</p>\\\\n\\\\n...\\\\n\\\\n<h2>Kết luận</h2>\\\\n<p>Tóm tắt và CTA...</p>\\\\n```\\\\n\\\\n**LƯU Ý:**\\\\n- Chỉ trả về HTML content, KHÔNG có markdown wrapper (```html)\\\\n- Không thêm CSS classes phức tạp (chỉ dùng table-of-contents)\\\\n- Không dùng <div> ngoại trừ table of contents\\\\n- Đảm bảo valid HTML5\\\\n- Không thêm comments hay explanations\\\\n\\\\n---\\\\n\\\\n🚀 **BẮT ĐẦU VIẾT BÀI NGAY!**\\"\\n    }\\n  ]\\n}","options":{}},"id":"5d4bdf90-fed0-47c6-9918-73760323cdaa","name":"Step 2 - Claude Write Article","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1456,-384],"notesInFlow":true,"credentials":{"httpHeaderAuth":{"id":"yIHqRqm0mV1LLjtR","name":"AgentRouter API"}},"notes":"Bước 2: Viết bài hoàn chỉnh với Claude Sonnet 4.5:\\n\\nModel: claude-sonnet-4.5 (via AgentRouter)\\n- Context window: 200k tokens\\n- Output: 8000 tokens max\\n- Chất lượng: Rất cao, E-E-A-T compliant\\n- Reasoning: Deep understanding\\n\\nĐộ dài: {{ $('Config - Input Parameters').item.json.wordCount }}+ từ\\nCấu trúc: H1, TOC, H2, H3, intro, body, FAQ, conclusion\\nFormat: HTML chuẩn, semantic\\nSEO: Có LSI keywords, internal link placeholders, image placeholders\\n\\nChi phí: ~$0.03-0.06/request (cao hơn GPT-4o-mini nhưng chất lượng tốt hơn)\\n\\nCần credential: Header Auth\\n- Name: x-api-key\\n- Value: YOUR_AGENTROUTER_API_KEY"},{"parameters":{"jsCode":"// Parse Claude response from AgentRouter\\nconst claudeResponse = $input.first().json;\\n\\n// AgentRouter returns Anthropic API format\\nlet articleHTML = '';\\n\\nif (claudeResponse.content && Array.isArray(claudeResponse.content)) {\\n  // Anthropic API format: content is array of blocks\\n  const textBlocks = claudeResponse.content.filter(block => block.type === 'text');\\n  articleHTML = textBlocks.map(block => block.text).join('\\\\n\\\\n');\\n} else if (claudeResponse.content && typeof claudeResponse.content === 'string') {\\n  // Fallback: content as string\\n  articleHTML = claudeResponse.content;\\n} else if (claudeResponse.completion) {\\n  // Old format fallback\\n  articleHTML = claudeResponse.completion;\\n} else {\\n  throw new Error('Unable to extract article content from Claude response');\\n}\\n\\n// Remove markdown code blocks if any\\narticleHTML = articleHTML.replace(/```html\\\\n?/g, '').replace(/```\\\\n?/g, '').trim();\\n\\n// Return for next step\\nreturn {\\n  json: {\\n    article_html: articleHTML,\\n    article_raw: JSON.stringify(claudeResponse),\\n    model_used: claudeResponse.model || 'claude-sonnet-4.5',\\n    usage: claudeResponse.usage || {}\\n  }\\n};"},"id":"b9ee57a4-c54e-488f-a28f-9abc10ef569e","name":"Parse Claude Response","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1456,-192],"notesInFlow":true,"notes":"Parse response từ Claude via AgentRouter.\\n\\nAgentRouter trả về Anthropic API format:\\n- content: array of content blocks\\n- usage: token usage stats\\n- model: model name used\\n\\nExtract HTML từ text blocks."},{"parameters":{"url":"=https://api.unsplash.com/search/photos","authentication":"genericCredentialType","genericAuthType":"httpHeaderAuth","sendQuery":true,"queryParameters":{"parameters":[{"name":"query","value":"={{ $('Config - Input Parameters').item.json.keyword }}"},{"name":"per_page","value":"8"},{"name":"orientation","value":"landscape"},{"name":"content_filter","value":"high"}]},"options":{}},"id":"972f3d4a-7fa2-4bb1-9e1b-d098cea7484b","name":"Step 3 - Search Unsplash Images","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1456,16],"notesInFlow":true,"credentials":{"httpHeaderAuth":{"id":"z5U3WTHeGbLkO8CL","name":"Unsplash API"}},"notes":"Bước 3: Tìm ảnh từ Unsplash API:\\n- Query: từ khóa chính\\n- Lấy 8 ảnh landscape\\n- High quality filter\\n- Free tier: 50 requests/hour\\n\\nCần credential: Header Auth\\n- Name: Authorization\\n- Value: Client-ID YOUR_UNSPLASH_ACCESS_KEY"},{"parameters":{"url":"={{ $('Config - Input Parameters').item.json.wordpressUrl }}/wp-json/wp/v2/posts","authentication":"predefinedCredentialType","nodeCredentialType":"wordpressApi","sendQuery":true,"queryParameters":{"parameters":[{"name":"per_page","value":"100"},{"name":"orderby","value":"date"},{"name":"status","value":"publish"},{"name":"_fields","value":"id,title,link,slug"}]},"options":{}},"id":"14ebb518-73e0-4b46-9f15-1dc40780f0b6","name":"Step 4 - Get WordPress Posts","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1456,224],"notesInFlow":true,"credentials":{"wordpressApi":{"id":"KRNE3nXewO8fnuDU","name":"Wordpress account"}},"notes":"Bước 4: Lấy danh sách bài đã đăng:\\n- Lấy 100 bài gần nhất\\n- Chỉ lấy status=publish\\n- Dùng để tạo internal links\\n\\nCần credential: WordPress API"},{"parameters":{"jsCode":"// ========================================\\n// MERGE DATA FROM ALL PREVIOUS NODES\\n// ========================================\\n\\n// Get data from all nodes\\nconst config = $('Config - Input Parameters').first().json;\\nconst research = $('Parse Research JSON').first().json;\\nconst articleData = $('Parse Claude Response').first().json;\\nconst unsplashData = $('Step 3 - Search Unsplash Images').first().json;\\nconst wordpressPosts = $('Step 4 - Get WordPress Posts').all();\\n\\n// Extract article content\\nlet articleHTML = articleData.article_html;\\n\\n// ========================================\\n// PROCESS IMAGES\\n// ========================================\\n\\nconst images = unsplashData.results || [];\\nlet imageIndex = 0;\\n\\n// Replace [IMAGE:description] with actual image HTML\\narticleHTML = articleHTML.replace(/\\\\[IMAGE:([^\\\\]]+)\\\\]/gi, (match, description) => {\\n  if (imageIndex < images.length) {\\n    const img = images[imageIndex];\\n    const photographer = img.user.name;\\n    const photographerUrl = img.user.links.html;\\n    \\n    const imageHtml = `\\n<figure class=\\"wp-block-image size-large\\">\\n  <img src=\\"${img.urls.regular}\\" alt=\\"${description}\\" loading=\\"lazy\\" width=\\"${img.width}\\" height=\\"${img.height}\\" />\\n  <figcaption>${description}. Photo by <a href=\\"${photographerUrl}?utm_source=wordpress_automation&utm_medium=referral\\" target=\\"_blank\\" rel=\\"noopener\\">${photographer}</a> on <a href=\\"https://unsplash.com?utm_source=wordpress_automation&utm_medium=referral\\" target=\\"_blank\\" rel=\\"noopener\\">Unsplash</a></figcaption>\\n</figure>`;\\n    \\n    imageIndex++;\\n    return imageHtml;\\n  }\\n  return `<!-- No image available for: ${description} -->`;\\n});\\n\\n// ========================================\\n// PROCESS INTERNAL LINKS\\n// ========================================\\n\\nconst keyword = config.keyword;\\nconst keywordParts = keyword.toLowerCase().split(' ').filter(k => k.length > 3);\\n\\n// Get LSI keywords for better matching\\nconst lsiKeywords = (research.research?.lsi_keywords || []).map(k => k.toLowerCase());\\nconst allKeywords = [...keywordParts, ...lsiKeywords];\\n\\n// Find related posts based on keywords\\nconst relatedPosts = wordpressPosts\\n  .map(item => item.json)\\n  .filter(post => {\\n    const title = post.title?.rendered?.toLowerCase() || '';\\n    const slug = post.slug?.toLowerCase() || '';\\n    const searchText = title + ' ' + slug;\\n    \\n    // Check if any keyword exists in title or slug\\n    return allKeywords.some(kw => searchText.includes(kw));\\n  })\\n  .slice(0, 10); // Max 10 related posts\\n\\nlet linkIndex = 0;\\n\\n// Replace [INTERNAL_LINK:anchor] with actual links\\narticleHTML = articleHTML.replace(/\\\\[INTERNAL_LINK:([^\\\\]]+)\\\\]/gi, (match, anchorText) => {\\n  if (linkIndex < relatedPosts.length) {\\n    const post = relatedPosts[linkIndex];\\n    const linkHtml = `<a href=\\"${post.link}\\" title=\\"${post.title.rendered}\\">${anchorText}</a>`;\\n    linkIndex++;\\n    return linkHtml;\\n  }\\n  // If no more related posts, just return anchor text without link\\n  return anchorText;\\n});\\n\\n// ========================================\\n// EXTRACT METADATA\\n// ========================================\\n\\n// Extract H1 title\\nconst h1Match = articleHTML.match(/<h1[^>]*>([^<]+)<\\\\/h1>/i);\\nconst title = h1Match ? h1Match[1].trim() : keyword;\\n\\n// Remove H1 from content (WordPress will add it as post title)\\narticleHTML = articleHTML.replace(/<h1[^>]*>([^<]+)<\\\\/h1>/i, '');\\n\\n// Create excerpt from first paragraph\\nconst firstPMatch = articleHTML.match(/<p[^>]*>([^<]+)<\\\\/p>/i);\\nlet excerpt = '';\\nif (firstPMatch) {\\n  const firstParagraph = firstPMatch[1].replace(/<[^>]+>/g, '').trim();\\n  const words = firstParagraph.split(' ');\\n  excerpt = words.slice(0, 30).join(' ');\\n  if (words.length > 30) excerpt += '...';\\n} else {\\n  // Fallback: get first 30 words from any text\\n  const textOnly = articleHTML.replace(/<[^>]+>/g, ' ').replace(/\\\\s+/g, ' ').trim();\\n  const words = textOnly.split(' ');\\n  excerpt = words.slice(0, 30).join(' ') + '...';\\n}\\n\\n// Get featured image (first image from Unsplash)\\nconst featuredImage = images.length > 0 ? {\\n  url: images[0].urls.regular,\\n  alt: title,\\n  description: images[0].description || title,\\n  photographer: images[0].user.name,\\n  photographer_url: images[0].user.links.html\\n} : null;\\n\\n// Get meta description from research\\nconst metaDescription = research.research?.seo_tips?.meta_description || excerpt;\\n\\n// Count stats\\nconst textOnly = articleHTML.replace(/<[^>]+>/g, ' ').replace(/\\\\s+/g, ' ').trim();\\nconst wordCount = textOnly.split(' ').filter(w => w.length > 0).length;\\nconst h2Count = (articleHTML.match(/<h2[^>]*>/gi) || []).length;\\nconst h3Count = (articleHTML.match(/<h3[^>]*>/gi) || []).length;\\n\\n// ========================================\\n// RETURN PROCESSED DATA\\n// ========================================\\n\\nreturn [{\\n  json: {\\n    // Post data for WordPress\\n    title: title,\\n    content: articleHTML,\\n    excerpt: excerpt,\\n    status: 'draft', // Change to 'publish' for auto-publish\\n    \\n    // SEO metadata\\n    meta: {\\n      description: metaDescription,\\n      focus_keyword: keyword,\\n      secondary_keywords: research.research?.seo_tips?.secondary_keywords || [],\\n      canonical_url: ''\\n    },\\n    \\n    // Featured image\\n    featured_image: featuredImage,\\n    \\n    // Original data for reference\\n    keyword: keyword,\\n    research_data: research.research,\\n    \\n    // Statistics\\n    stats: {\\n      word_count: wordCount,\\n      images_inserted: imageIndex,\\n      internal_links_added: linkIndex,\\n      h2_count: h2Count,\\n      h3_count: h3Count,\\n      related_posts_found: relatedPosts.length,\\n      model_used: articleData.model_used,\\n      ai_tokens_used: articleData.usage\\n    },\\n    \\n    // WordPress URL for next steps\\n    wordpress_url: config.wordpressUrl\\n  }\\n}];"},"id":"1bf9ee71-9bf2-4d71-a764-b5a78107c641","name":"Step 5 - Process & Format Content","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1232,-384],"notesInFlow":true,"notes":"Bước 5: Xử lý và format nội dung:\\n\\n1. Chèn ảnh vào vị trí [IMAGE:...]\\n2. Chèn internal links vào [INTERNAL_LINK:...]\\n3. Extract metadata (title, excerpt, meta description)\\n4. Thống kê (word count, H2/H3, images, links)\\n5. Remove H1 khỏi content"},{"parameters":{"method":"POST","url":"={{ $json.wordpress_url }}/wp-json/wp/v2/posts","authentication":"predefinedCredentialType","nodeCredentialType":"wordpressApi","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"title\\": \\"{{ $json.title }}\\",\\n  \\"content\\": {{ JSON.stringify($json.content) }},\\n  \\"excerpt\\": \\"{{ $json.excerpt }}\\",\\n  \\"status\\": \\"{{ $json.status }}\\",\\n  \\"comment_status\\": \\"open\\",\\n  \\"ping_status\\": \\"open\\",\\n  \\"format\\": \\"standard\\"\\n}","options":{}},"id":"29edb093-9305-49ae-9fc1-aa71acd55e15","name":"Step 6 - Create WordPress Post","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1008,-384],"notesInFlow":true,"credentials":{"wordpressApi":{"id":"KRNE3nXewO8fnuDU","name":"Wordpress account"}},"notes":"Bước 6: Tạo bài viết mới trên WordPress:\\n- Title, Content, Excerpt\\n- Status: draft\\n- Comments & pings: open\\n\\nTrả về: Post ID, link, status"},{"parameters":{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict"},"conditions":[{"id":"condition-has-featured-image","leftValue":"={{ $('Step 5 - Process & Format Content').item.json.featured_image }}","rightValue":"","operator":{"type":"object","operation":"notEmpty","singleValue":true}}],"combinator":"and"},"options":{}},"id":"219cd2c6-a6e5-45ce-b19c-91c3e454c4a3","name":"If - Has Featured Image?","type":"n8n-nodes-base.if","typeVersion":2,"position":[-784,-384],"notesInFlow":true,"notes":"Kiểm tra xem có featured image không.\\nNếu có → Upload và set featured image."},{"parameters":{"method":"POST","url":"={{ $('Step 5 - Process & Format Content').item.json.wordpress_url }}/wp-json/wp/v2/media","authentication":"predefinedCredentialType","nodeCredentialType":"wordpressApi","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Disposition","value":"=attachment; filename=\\"{{ $('Step 5 - Process & Format Content').item.json.keyword.replace(/\\\\s+/g, '-') }}-featured.jpg\\""}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"url\\": \\"{{ $('Step 5 - Process & Format Content').item.json.featured_image.url }}\\",\\n  \\"title\\": \\"{{ $('Step 5 - Process & Format Content').item.json.title }}\\",\\n  \\"alt_text\\": \\"{{ $('Step 5 - Process & Format Content').item.json.featured_image.alt }}\\",\\n  \\"caption\\": \\"Photo by {{ $('Step 5 - Process & Format Content').item.json.featured_image.photographer }}\\",\\n  \\"description\\": \\"{{ $('Step 5 - Process & Format Content').item.json.featured_image.description }}\\"\\n}","options":{}},"id":"4a825ea6-ea02-40a1-a131-e037165021ab","name":"Step 7a - Upload Featured Image","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-576,-496],"notesInFlow":true,"credentials":{"wordpressApi":{"id":"KRNE3nXewO8fnuDU","name":"Wordpress account"}},"notes":"Bước 7a: Upload featured image lên WordPress Media Library"},{"parameters":{"method":"POST","url":"={{ $('Step 5 - Process & Format Content').item.json.wordpress_url }}/wp-json/wp/v2/posts/{{ $('Step 6 - Create WordPress Post').item.json.id }}","authentication":"predefinedCredentialType","nodeCredentialType":"wordpressApi","sendHeaders":true,"headerParameters":{"parameters":[{"name":"Content-Type","value":"application/json"}]},"sendBody":true,"specifyBody":"json","jsonBody":"={\\n  \\"featured_media\\": {{ $json.id }}\\n}","options":{}},"id":"50d44163-b12c-426d-8667-78b778763d3a","name":"Step 7b - Set Featured Image","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-352,-496],"notesInFlow":true,"credentials":{"wordpressApi":{"id":"KRNE3nXewO8fnuDU","name":"Wordpress account"}},"notes":"Bước 7b: Set featured image cho post"},{"parameters":{"assignments":{"assignments":[{"id":"summary-field","name":"summary","value":"=✅ **BÀI VIẾT ĐÃ ĐƯỢC TẠO THÀNH CÔNG!**\\n\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n\\n📝 **THÔNG TIN BÀI VIẾT**\\n\\n🔖 Tiêu đề: {{ $('Step 5 - Process & Format Content').item.json.title }}\\n🔑 Từ khóa: {{ $('Step 5 - Process & Format Content').item.json.keyword }}\\n🌐 Link: {{ $('Step 6 - Create WordPress Post').item.json.link }}\\n📌 Trạng thái: {{ $('Step 6 - Create WordPress Post').item.json.status }}\\n🆔 Post ID: {{ $('Step 6 - Create WordPress Post').item.json.id }}\\n\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n\\n📊 **THỐNG KÊ**\\n\\n📝 Số từ: {{ $('Step 5 - Process & Format Content').item.json.stats.word_count }}\\n📑 Số H2: {{ $('Step 5 - Process & Format Content').item.json.stats.h2_count }}\\n📑 Số H3: {{ $('Step 5 - Process & Format Content').item.json.stats.h3_count }}\\n🖼️ Ảnh đã chèn: {{ $('Step 5 - Process & Format Content').item.json.stats.images_inserted }}\\n🔗 Internal links: {{ $('Step 5 - Process & Format Content').item.json.stats.internal_links_added }}\\n📚 Bài liên quan: {{ $('Step 5 - Process & Format Content').item.json.stats.related_posts_found }}\\n🤖 Model: {{ $('Step 5 - Process & Format Content').item.json.stats.model_used }}\\n\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n\\n🎯 **SEO**\\n\\n📝 Meta description: {{ $('Step 5 - Process & Format Content').item.json.meta.description }}\\n🎯 Focus keyword: {{ $('Step 5 - Process & Format Content').item.json.meta.focus_keyword }}\\n🔑 Secondary keywords: {{ $('Step 5 - Process & Format Content').item.json.meta.secondary_keywords.join(', ') }}\\n\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n\\n🖼️ **FEATURED IMAGE**\\n\\n{{ $('Step 5 - Process & Format Content').item.json.featured_image ? '✅ Đã upload featured image' : '⚠️ Không có featured image' }}\\n\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n\\n💡 **NEXT STEPS**\\n\\n1. Review bài viết: {{ $('Step 6 - Create WordPress Post').item.json.link }}\\n2. Chỉnh sửa nếu cần\\n3. Thêm categories và tags\\n4. Kiểm tra SEO (Yoast/Rank Math)\\n5. Preview\\n6. Publish!\\n\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\\n\\n🚀 Powered by Perplexity AI + Claude Sonnet 4.5","type":"string"},{"id":"post-url-field","name":"post_url","value":"={{ $('Step 6 - Create WordPress Post').item.json.link }}","type":"string"},{"id":"post-id-field","name":"post_id","value":"={{ $('Step 6 - Create WordPress Post').item.json.id }}","type":"number"}]},"options":{}},"id":"eb4ecfb8-7c67-4f70-b46a-09f1e23e210d","name":"Final - Summary Result","type":"n8n-nodes-base.set","typeVersion":3.3,"position":[-128,-384],"notesInFlow":true,"notes":"Tổng hợp kết quả cuối cùng với thống kê đầy đủ"}]	{"Manual Trigger":{"main":[[{"node":"Config - Input Parameters","type":"main","index":0}]]},"Config - Input Parameters":{"main":[[{"node":"Step 1 - Perplexity Research","type":"main","index":0}]]},"Step 1 - Perplexity Research":{"main":[[{"node":"Parse Research JSON","type":"main","index":0}]]},"Parse Research JSON":{"main":[[{"node":"Step 2 - Claude Write Article","type":"main","index":0},{"node":"Step 3 - Search Unsplash Images","type":"main","index":0},{"node":"Step 4 - Get WordPress Posts","type":"main","index":0}]]},"Step 2 - Claude Write Article":{"main":[[{"node":"Parse Claude Response","type":"main","index":0}]]},"Parse Claude Response":{"main":[[{"node":"Step 5 - Process & Format Content","type":"main","index":0}]]},"Step 3 - Search Unsplash Images":{"main":[[{"node":"Step 5 - Process & Format Content","type":"main","index":0}]]},"Step 4 - Get WordPress Posts":{"main":[[{"node":"Step 5 - Process & Format Content","type":"main","index":0}]]},"Step 5 - Process & Format Content":{"main":[[{"node":"Step 6 - Create WordPress Post","type":"main","index":0}]]},"Step 6 - Create WordPress Post":{"main":[[{"node":"If - Has Featured Image?","type":"main","index":0}]]},"If - Has Featured Image?":{"main":[[{"node":"Step 7a - Upload Featured Image","type":"main","index":0}],[{"node":"Final - Summary Result","type":"main","index":0}]]},"Step 7a - Upload Featured Image":{"main":[[{"node":"Step 7b - Set Featured Image","type":"main","index":0}]]},"Step 7b - Set Featured Image":{"main":[[{"node":"Final - Summary Result","type":"main","index":0}]]}}	2025-11-04 03:12:01.434+00	2025-11-04 17:07:58.79+00	{"executionOrder":"v1"}	\N	{"Manual Trigger":[{"json":{}}]}	aa0afa99-8039-48c1-802d-3571ad7afeb1	0	NnqZbfATi88ZRVYl	\N	\N	f	4	\N
GMB Auto-Post - Phase 2: Multi-Location + Sheets	f	[{"parameters":{},"id":"5ec7ab18-2aeb-4348-bbc9-42fff95d8dee","name":"Manual Trigger","type":"n8n-nodes-base.manualTrigger","typeVersion":1,"position":[-2864,-368]},{"parameters":{"options":{}},"id":"dec0a3fc-ba91-4b83-961b-7fe25e6f0184","name":"Set Post Data","type":"n8n-nodes-base.set","typeVersion":3.3,"position":[-2640,-368]},{"parameters":{"url":"https://mybusinessbusinessinformation.googleapis.com/v1/accounts","authentication":"oAuth2","options":{}},"id":"e2cd52c5-dfe3-4cb5-a36d-54630b3d00cf","name":"Get GMB Account ID","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-2416,-368]},{"parameters":{"jsCode":"// Extract account ID from GMB API response\\nconst response = $input.first().json;\\n\\n// Check if accounts exist\\nif (!response.accounts || response.accounts.length === 0) {\\n  throw new Error('No GMB accounts found. Please check your Google Business Profile access.');\\n}\\n\\n// Get first account\\nconst accountId = response.accounts[0].name;\\n\\nconsole.log('Found GMB Account:', accountId);\\n\\nreturn {\\n  json: {\\n    accountId: accountId,\\n    accountName: response.accounts[0].accountName || 'Unknown'\\n  }\\n};"},"id":"a4c722ad-4f05-4e1b-b4b4-dcbfbd59aaaf","name":"Extract Account ID","type":"n8n-nodes-base.code","typeVersion":2,"position":[-2192,-368]},{"parameters":{"url":"=https://mybusinessbusinessinformation.googleapis.com/v1/{{$json.accountId}}/locations?pageSize=100&readMask=name,title,storefrontAddress","authentication":"oAuth2","options":{}},"id":"64d5bcdc-c111-444a-a354-c202ae85dc59","name":"Get GMB Locations","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1968,-368]},{"parameters":{"jsCode":"// Extract location ID from GMB API response\\nconst response = $input.first().json;\\n\\n// Check if locations exist\\nif (!response.locations || response.locations.length === 0) {\\n  throw new Error('No GMB locations found. Please add a location to your Google Business Profile.');\\n}\\n\\n// Get first location for MVP\\nconst location = response.locations[0];\\nconst locationId = location.name;\\nconst locationTitle = location.title || 'Unknown Location';\\nconst address = location.storefrontAddress || {};\\n\\nconsole.log('Found GMB Location:', locationTitle, locationId);\\n\\nreturn {\\n  json: {\\n    locationId: locationId,\\n    locationTitle: locationTitle,\\n    locationAddress: address.addressLines ? address.addressLines.join(', ') : 'N/A'\\n  }\\n};"},"id":"760121e7-780a-4967-870a-629922a80310","name":"Extract Location ID","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1744,-368]},{"parameters":{"jsCode":"// Format payload for GMB API\\nconst postData = $('Set Post Data').first().json;\\nconst locationData = $input.first().json;\\n\\n// Build GMB API payload\\nconst payload = {\\n  languageCode: \\"en\\",\\n  summary: postData.content,\\n  topicType: postData.post_type\\n};\\n\\n// Add CTA if provided\\nif (postData.cta_type && postData.cta_url) {\\n  payload.callToAction = {\\n    actionType: postData.cta_type,\\n    url: postData.cta_url\\n  };\\n}\\n\\n// Build API URL\\nconst postUrl = `https://mybusiness.googleapis.com/v4/${locationData.locationId}/localPosts`;\\n\\nconsole.log('GMB API URL:', postUrl);\\nconsole.log('Payload:', JSON.stringify(payload, null, 2));\\n\\nreturn {\\n  json: {\\n    payload: payload,\\n    locationId: locationData.locationId,\\n    locationTitle: locationData.locationTitle,\\n    postUrl: postUrl\\n  }\\n};"},"id":"c432354a-0246-4af4-b1c1-2456aa380ecb","name":"Format GMB Payload","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1520,-368]},{"parameters":{"url":"={{$json.postUrl}}","authentication":"oAuth2","sendBody":true,"bodyParameters":{"parameters":[{"name":"languageCode","value":"={{$json.payload.languageCode}}"},{"name":"summary","value":"={{$json.payload.summary}}"},{"name":"topicType","value":"={{$json.payload.topicType}}"},{"name":"callToAction","value":"={{$json.payload.callToAction}}"}]},"options":{"response":{"response":{"fullResponse":true}}}},"id":"4ea45a97-2c6c-4977-b25d-11f47a95dd6f","name":"Create GMB Post","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1296,-368]},{"parameters":{"jsCode":"// Parse success response\\nconst response = $input.first().json;\\nconst body = response.body || response;\\n\\nconsole.log('GMB Post Created Successfully!');\\nconsole.log('Response:', JSON.stringify(body, null, 2));\\n\\nreturn {\\n  json: {\\n    status: 'success',\\n    postId: body.name || 'Unknown',\\n    postState: body.state || 'PROCESSING',\\n    searchUrl: body.searchUrl || 'N/A',\\n    createTime: body.createTime || new Date().toISOString(),\\n    message: '✅ GMB post created successfully!'\\n  }\\n};"},"id":"8bd9d7c0-fc05-4f7c-87ea-b11c361fca82","name":"Success Handler","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1072,-368]},{"parameters":{"options":{}},"id":"365ef4d4-23c0-4e07-a2fb-4d8b1bcd5e99","name":"Error Handler","type":"n8n-nodes-base.set","typeVersion":3.3,"position":[-1072,-176]},{"parameters":{"jsCode":"// Display final result\\nconst data = $input.first().json;\\n\\nif (data.status === 'success') {\\n  console.log('========================================');\\n  console.log('✅ GMB POST CREATED SUCCESSFULLY');\\n  console.log('========================================');\\n  console.log('Post ID:', data.postId);\\n  console.log('State:', data.postState);\\n  console.log('Search URL:', data.searchUrl);\\n  console.log('Created:', data.createTime);\\n  console.log('========================================');\\n} else {\\n  console.log('========================================');\\n  console.log('❌ GMB POST FAILED');\\n  console.log('========================================');\\n  console.log('Error Code:', data.error_code);\\n  console.log('Error Message:', data.error_message);\\n  console.log('Timestamp:', data.timestamp);\\n  console.log('========================================');\\n}\\n\\nreturn $input.all();"},"id":"1efa3797-4fd8-4538-b411-76a301eeb71b","name":"Display Result","type":"n8n-nodes-base.code","typeVersion":2,"position":[-848,-272]},{"parameters":{"rule":{"interval":[{"field":"cronExpression","expression":"0 9 * * *"}]}},"id":"ee1b2fb5-76a0-4a22-8abd-9b89ac2b6424","name":"Schedule Trigger","type":"n8n-nodes-base.scheduleTrigger","typeVersion":1.2,"position":[-2864,144],"notesInFlow":true,"notes":"Daily at 9 AM (Asia/Ho_Chi_Minh timezone)"},{"parameters":{"documentId":{"__rl":true,"mode":"list","value":""},"sheetName":{"__rl":true,"mode":"list","value":""}},"id":"2454b1b6-b926-49d7-8f3a-943a1de11c0e","name":"Read Google Sheets","type":"n8n-nodes-base.googleSheets","typeVersion":4.4,"position":[-2640,144],"notesInFlow":true,"notes":"Columns: content | location_id | post_type | cta_type | cta_url | image_url | status"},{"parameters":{"conditions":{"options":{"leftValue":"","caseSensitive":true,"typeValidation":"strict"},"conditions":[{"id":"filter-pending-001","leftValue":"={{ $json.status }}","rightValue":"pending","operator":{"type":"string","operation":"equals"}}],"combinator":"and"},"options":{}},"id":"f90a1329-1aed-4593-9a3b-d7de48acae27","name":"Filter Pending Posts","type":"n8n-nodes-base.if","typeVersion":2,"position":[-2416,144],"notesInFlow":true,"notes":"Only process posts with status='pending'"},{"parameters":{"url":"https://mybusinessbusinessinformation.googleapis.com/v1/accounts","authentication":"oAuth2","options":{}},"id":"a4c45594-ba25-4c3b-9d0d-8aa51f1df1fa","name":"Get GMB Account","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-2192,48]},{"parameters":{"url":"=https://mybusinessbusinessinformation.googleapis.com/v1/{{$json.accountId}}/locations?pageSize=100&readMask=name,title,storefrontAddress","authentication":"oAuth2","options":{}},"id":"46d4dd75-3701-4b9d-bb95-1b59a2680ed8","name":"Get All Locations","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1744,48]},{"parameters":{"jsCode":"// Store locations for later lookup\\nconst response = $input.first().json;\\n\\nif (!response.locations || response.locations.length === 0) {\\n  throw new Error('No locations found');\\n}\\n\\nconsole.log(`Found ${response.locations.length} locations`);\\n\\n// Return locations as array for downstream nodes\\nreturn {\\n  json: {\\n    locations: response.locations,\\n    locationCount: response.locations.length\\n  }\\n};"},"id":"59ad242e-9b67-485a-a4ed-ebb2cc2c2542","name":"Store Locations","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1520,48]},{"parameters":{"options":{}},"id":"2ea7a697-7834-4434-bfaf-7f6a0a080bc3","name":"Loop Over Posts","type":"n8n-nodes-base.splitInBatches","typeVersion":3,"position":[-2192,240],"notesInFlow":true,"notes":"Process posts one by one (batch size = 1)"},{"parameters":{"jsCode":"// Match post with location\\nconst postData = $input.first().json;\\nconst allLocations = $('Store Locations').first().json.locations;\\n\\n// Find matching location\\nconst location = allLocations.find(loc => \\n  loc.name === postData.location_id || \\n  loc.name.endsWith(postData.location_id)\\n);\\n\\nif (!location) {\\n  throw new Error(`Location not found: ${postData.location_id}`);\\n}\\n\\nconsole.log('Posting to:', location.title);\\n\\nreturn {\\n  json: {\\n    ...postData,\\n    locationId: location.name,\\n    locationTitle: location.title\\n  }\\n};"},"id":"0dadc42c-07bf-4841-91ed-bd296b929493","name":"Match Location","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1968,240]},{"parameters":{"amount":6},"id":"d743ccfb-be60-4e92-bd0e-47a482165737","name":"Wait 6 Seconds","type":"n8n-nodes-base.wait","typeVersion":1.1,"position":[-1744,240],"webhookId":"wait-rate-limit-webhook","notesInFlow":true,"notes":"Rate limit: 10 posts/min per location"},{"parameters":{"conditions":{"options":{"leftValue":"","caseSensitive":true,"typeValidation":"strict"},"conditions":[{"id":"check-success-001","leftValue":"={{ $json.statusCode }}","rightValue":"201","operator":{"type":"number","operation":"equals"}}],"combinator":"or"},"options":{}},"id":"a0ac83ad-7a54-41e5-8366-2300dfa1320b","name":"Check Success","type":"n8n-nodes-base.if","typeVersion":2,"position":[-1072,240]},{"parameters":{"operation":"executeQuery","query":"INSERT INTO post_logs (execution_id, location_id, location_name, post_id, content, status, created_at) VALUES ($1, $2, $3, $4, $5, $6, NOW())","options":{}},"id":"1ffad912-41fe-4d41-96be-f5ed313c5bef","name":"Log Success to DB","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[-400,144]},{"parameters":{"operation":"executeQuery","query":"INSERT INTO post_logs (execution_id, location_id, location_name, content, status, error_message, created_at) VALUES ($1, $2, $3, $4, $5, $6, NOW())","options":{}},"id":"c615d1a3-3435-4993-85de-0200c6944a0c","name":"Log Error to DB","type":"n8n-nodes-base.postgres","typeVersion":2.4,"position":[-848,336]},{"parameters":{"documentId":{"__rl":true,"mode":"list","value":""},"sheetName":{"__rl":true,"mode":"list","value":""}},"id":"35ecc4af-736e-4589-9bfc-89b7d0d2cfbc","name":"Mark as Posted","type":"n8n-nodes-base.googleSheets","typeVersion":4.4,"position":[-176,144]},{"parameters":{"jsCode":"// Count errors\\nconst allErrors = $input.all();\\nconst errorCount = allErrors.length;\\n\\nconsole.log(`Total errors: ${errorCount}`);\\n\\nreturn {\\n  json: {\\n    errorCount,\\n    errors: allErrors.map(e => ({\\n      location: e.json.locationTitle,\\n      error: e.json.body?.error?.message || 'Unknown'\\n    }))\\n  }\\n};"},"id":"c2956ef8-e0eb-45a3-bbb6-9d572f74f753","name":"Count Errors","type":"n8n-nodes-base.code","typeVersion":2,"position":[-624,336]},{"parameters":{"conditions":{"options":{"leftValue":"","caseSensitive":true,"typeValidation":"strict"},"conditions":[{"id":"check-alert-threshold-001","leftValue":"={{ $json.errorCount }}","rightValue":"3","operator":{"type":"number","operation":"largerEqual"}}],"combinator":"and"},"options":{}},"id":"8b2f6bcd-183c-47a7-904a-eb9ee4092fbc","name":"Alert Threshold","type":"n8n-nodes-base.if","typeVersion":2,"position":[-400,336]},{"parameters":{"select":"channel","channelId":{"__rl":true,"mode":"list","value":""},"text":"=⚠️ *GMB Posting Errors*\\\\n\\\\nExecution: {{$execution.id}}\\\\nFailed posts: {{$json.errorCount}}\\\\n\\\\nErrors:\\\\n{{$json.errors.map(e => `- ${e.location}: ${e.error}`).join('\\\\n')}}","otherOptions":{}},"id":"b89ceb9e-e45b-461e-a40e-8e5d355dc9b6","name":"Send Slack Alert","type":"n8n-nodes-base.slack","typeVersion":2.2,"position":[-176,336],"webhookId":"d8d5d42f-3916-4573-b0cf-42d51cc41dda"},{"parameters":{"jsCode":"// Final summary\\nconst successLogs = $('Log Success to DB').all();\\nconst errorLogs = $('Log Error to DB').all();\\n\\nconst summary = {\\n  total: successLogs.length + errorLogs.length,\\n  success: successLogs.length,\\n  failed: errorLogs.length,\\n  successRate: ((successLogs.length / (successLogs.length + errorLogs.length)) * 100).toFixed(2) + '%'\\n};\\n\\nconsole.log('===============================');\\nconsole.log('GMB POSTING COMPLETE');\\nconsole.log('===============================');\\nconsole.log('Total posts:', summary.total);\\nconsole.log('Successful:', summary.success);\\nconsole.log('Failed:', summary.failed);\\nconsole.log('Success rate:', summary.successRate);\\nconsole.log('===============================');\\n\\nreturn { json: summary };"},"id":"f2cbd2d0-e1b6-4652-9ee4-7218cdc3065b","name":"Display Summary","type":"n8n-nodes-base.code","typeVersion":2,"position":[48,240]},{"parameters":{"jsCode":"const response = $input.first().json;\\n\\nif (!response.accounts || response.accounts.length === 0) {\\n  throw new Error('No GMB accounts found');\\n}\\n\\nconst accountId = response.accounts[0].name;\\nconsole.log('Account ID:', accountId);\\n\\nreturn {\\n  json: {\\n    accountId: accountId\\n  }\\n};"},"id":"73450134-7b46-460c-ba14-9f2c1a1bf905","name":"Extract Account ID1","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1968,48]},{"parameters":{"jsCode":"// Build GMB post payload\\nconst data = $input.first().json;\\n\\nconst payload = {\\n  languageCode: \\"en\\",\\n  summary: data.content,\\n  topicType: data.post_type || \\"STANDARD\\"\\n};\\n\\n// Add CTA if provided\\nif (data.cta_type && data.cta_url) {\\n  payload.callToAction = {\\n    actionType: data.cta_type,\\n    url: data.cta_url\\n  };\\n}\\n\\n// Add image if provided\\nif (data.image_url) {\\n  payload.media = [{\\n    mediaFormat: \\"PHOTO\\",\\n    sourceUrl: data.image_url\\n  }];\\n}\\n\\nconst postUrl = `https://mybusiness.googleapis.com/v4/${data.locationId}/localPosts`;\\n\\nreturn {\\n  json: {\\n    payload,\\n    postUrl,\\n    locationId: data.locationId,\\n    locationTitle: data.locationTitle,\\n    originalContent: data.content,\\n    sheetRowId: data.__rowNum\\n  }\\n};"},"id":"0e1cab64-402f-4b6a-8700-f4336d5bffe0","name":"Format GMB Payload1","type":"n8n-nodes-base.code","typeVersion":2,"position":[-1520,240]},{"parameters":{"url":"={{$json.postUrl}}","authentication":"oAuth2","sendBody":true,"bodyParameters":{"parameters":[{}]},"options":{"response":{"response":{"fullResponse":true,"neverError":true}}}},"id":"0561c164-0ba5-4c91-9a8e-a7856f74bd86","name":"Create GMB Post1","type":"n8n-nodes-base.httpRequest","typeVersion":4.2,"position":[-1296,240]}]	{"Manual Trigger":{"main":[[{"node":"Set Post Data","type":"main","index":0}]]},"Set Post Data":{"main":[[{"node":"Get GMB Account ID","type":"main","index":0}]]},"Get GMB Account ID":{"main":[[{"node":"Extract Account ID","type":"main","index":0}]]},"Extract Account ID":{"main":[[{"node":"Get GMB Locations","type":"main","index":0}]]},"Get GMB Locations":{"main":[[{"node":"Extract Location ID","type":"main","index":0}]]},"Extract Location ID":{"main":[[{"node":"Format GMB Payload","type":"main","index":0}]]},"Format GMB Payload":{"main":[[{"node":"Create GMB Post","type":"main","index":0}]]},"Create GMB Post":{"main":[[{"node":"Success Handler","type":"main","index":0}]]},"Success Handler":{"main":[[{"node":"Display Result","type":"main","index":0}]]},"Error Handler":{"main":[[{"node":"Display Result","type":"main","index":0}]]},"Schedule Trigger":{"main":[[{"node":"Read Google Sheets","type":"main","index":0}]]},"Read Google Sheets":{"main":[[{"node":"Filter Pending Posts","type":"main","index":0}]]},"Filter Pending Posts":{"main":[[{"node":"Get GMB Account","type":"main","index":0},{"node":"Loop Over Posts","type":"main","index":0}]]},"Get GMB Account":{"main":[[{"node":"Extract Account ID1","type":"main","index":0}]]},"Get All Locations":{"main":[[{"node":"Store Locations","type":"main","index":0}]]},"Loop Over Posts":{"main":[[{"node":"Match Location","type":"main","index":0}]]},"Match Location":{"main":[[{"node":"Wait 6 Seconds","type":"main","index":0}]]},"Wait 6 Seconds":{"main":[[{"node":"Format GMB Payload1","type":"main","index":0}]]},"Check Success":{"main":[[{"node":"Log Success to DB","type":"main","index":0}],[{"node":"Log Error to DB","type":"main","index":0}]]},"Log Success to DB":{"main":[[{"node":"Mark as Posted","type":"main","index":0}]]},"Log Error to DB":{"main":[[{"node":"Count Errors","type":"main","index":0}]]},"Mark as Posted":{"main":[[{"node":"Display Summary","type":"main","index":0}]]},"Count Errors":{"main":[[{"node":"Alert Threshold","type":"main","index":0}]]},"Alert Threshold":{"main":[[{"node":"Send Slack Alert","type":"main","index":0}]]},"Send Slack Alert":{"main":[[{"node":"Display Summary","type":"main","index":0}]]},"Extract Account ID1":{"main":[[{"node":"Get All Locations","type":"main","index":0}]]},"Format GMB Payload1":{"main":[[{"node":"Create GMB Post1","type":"main","index":0}]]},"Create GMB Post1":{"main":[[{"node":"Check Success","type":"main","index":0}]]}}	2025-11-25 10:24:36.433+00	2025-11-25 10:24:36.433+00	{"executionOrder":"v1"}	\N	{}	cd95d510-8a09-4056-beef-cdc9a30c50b9	0	7InRmYUhABudg55m	\N	\N	f	1	\N
\.


--
-- TOC entry 4130 (class 0 OID 18888)
-- Dependencies: 448
-- Data for Name: workflow_history; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.workflow_history ("versionId", "workflowId", authors, "createdAt", "updatedAt", nodes, connections) FROM stdin;
\.


--
-- TOC entry 4123 (class 0 OID 18704)
-- Dependencies: 441
-- Data for Name: workflow_statistics; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.workflow_statistics (count, "latestEvent", name, "workflowId", "rootCount") FROM stdin;
1	2025-11-04 03:19:47.327+00	data_loaded	NnqZbfATi88ZRVYl	1
2	2025-11-04 03:34:47.186+00	manual_success	NnqZbfATi88ZRVYl	0
9	2025-11-04 03:48:10.643+00	manual_error	NnqZbfATi88ZRVYl	0
1	2025-11-25 10:24:38.227+00	manual_error	7InRmYUhABudg55m	0
\.


--
-- TOC entry 4118 (class 0 OID 18524)
-- Dependencies: 436
-- Data for Name: workflows_tags; Type: TABLE DATA; Schema: public; Owner: n8n_postgres_user
--

COPY public.workflows_tags ("workflowId", "tagId") FROM stdin;
\.


--
-- TOC entry 4249 (class 0 OID 0)
-- Dependencies: 444
-- Name: auth_provider_sync_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.auth_provider_sync_history_id_seq', 1, false);


--
-- TOC entry 4250 (class 0 OID 0)
-- Dependencies: 456
-- Name: execution_annotations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.execution_annotations_id_seq', 1, false);


--
-- TOC entry 4251 (class 0 OID 0)
-- Dependencies: 431
-- Name: execution_entity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.execution_entity_id_seq', 45, true);


--
-- TOC entry 4252 (class 0 OID 0)
-- Dependencies: 453
-- Name: execution_metadata_temp_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.execution_metadata_temp_id_seq', 1, false);


--
-- TOC entry 4253 (class 0 OID 0)
-- Dependencies: 468
-- Name: insights_by_period_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.insights_by_period_id_seq', 1, false);


--
-- TOC entry 4254 (class 0 OID 0)
-- Dependencies: 464
-- Name: insights_metadata_metaId_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public."insights_metadata_metaId_seq"', 1, false);


--
-- TOC entry 4255 (class 0 OID 0)
-- Dependencies: 466
-- Name: insights_raw_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.insights_raw_id_seq', 1, false);


--
-- TOC entry 4256 (class 0 OID 0)
-- Dependencies: 428
-- Name: migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.migrations_id_seq', 176, true);


--
-- TOC entry 4257 (class 0 OID 0)
-- Dependencies: 486
-- Name: oauth_user_consents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.oauth_user_consents_id_seq', 1, false);


--
-- TOC entry 4258 (class 0 OID 0)
-- Dependencies: 479
-- Name: workflow_dependency_id_seq; Type: SEQUENCE SET; Schema: public; Owner: n8n_postgres_user
--

SELECT pg_catalog.setval('public.workflow_dependency_id_seq', 1, false);


--
-- TOC entry 3853 (class 2606 OID 19535)
-- Name: test_run PK_011c050f566e9db509a0fadb9b9; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.test_run
    ADD CONSTRAINT "PK_011c050f566e9db509a0fadb9b9" PRIMARY KEY (id);


--
-- TOC entry 3785 (class 2606 OID 18681)
-- Name: installed_packages PK_08cc9197c39b028c1e9beca225940576fd1a5804; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.installed_packages
    ADD CONSTRAINT "PK_08cc9197c39b028c1e9beca225940576fd1a5804" PRIMARY KEY ("packageName");


--
-- TOC entry 3819 (class 2606 OID 19208)
-- Name: execution_metadata PK_17a0b6284f8d626aae88e1c16e4; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_metadata
    ADD CONSTRAINT "PK_17a0b6284f8d626aae88e1c16e4" PRIMARY KEY (id);


--
-- TOC entry 3810 (class 2606 OID 19132)
-- Name: project_relation PK_1caaa312a5d7184a003be0f0cb6; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "PK_1caaa312a5d7184a003be0f0cb6" PRIMARY KEY ("projectId", "userId");


--
-- TOC entry 3874 (class 2606 OID 21009)
-- Name: chat_hub_sessions PK_1eafef1273c70e4464fec703412; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "PK_1eafef1273c70e4464fec703412" PRIMARY KEY (id);


--
-- TOC entry 3842 (class 2606 OID 19423)
-- Name: folder_tag PK_27e4e00852f6b06a925a4d83a3e; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.folder_tag
    ADD CONSTRAINT "PK_27e4e00852f6b06a925a4d83a3e" PRIMARY KEY ("folderId", "tagId");


--
-- TOC entry 3861 (class 2606 OID 19578)
-- Name: role PK_35c9b140caaf6da09cfabb0d675; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT "PK_35c9b140caaf6da09cfabb0d675" PRIMARY KEY (slug);


--
-- TOC entry 3806 (class 2606 OID 19123)
-- Name: project PK_4d68b1358bb5b766d3e78f32f57; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT "PK_4d68b1358bb5b766d3e78f32f57" PRIMARY KEY (id);


--
-- TOC entry 3881 (class 2606 OID 21081)
-- Name: workflow_dependency PK_52325e34cd7a2f0f67b0f3cad65; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_dependency
    ADD CONSTRAINT "PK_52325e34cd7a2f0f67b0f3cad65" PRIMARY KEY (id);


--
-- TOC entry 3821 (class 2606 OID 19221)
-- Name: invalid_auth_token PK_5779069b7235b256d91f7af1a15; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.invalid_auth_token
    ADD CONSTRAINT "PK_5779069b7235b256d91f7af1a15" PRIMARY KEY (token);


--
-- TOC entry 3816 (class 2606 OID 19189)
-- Name: shared_workflow PK_5ba87620386b847201c9531c58f; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.shared_workflow
    ADD CONSTRAINT "PK_5ba87620386b847201c9531c58f" PRIMARY KEY ("workflowId", "projectId");


--
-- TOC entry 3840 (class 2606 OID 19407)
-- Name: folder PK_6278a41a706740c94c02e288df8; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.folder
    ADD CONSTRAINT "PK_6278a41a706740c94c02e288df8" PRIMARY KEY (id);


--
-- TOC entry 3870 (class 2606 OID 19655)
-- Name: data_table_column PK_673cb121ee4a8a5e27850c72c51; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.data_table_column
    ADD CONSTRAINT "PK_673cb121ee4a8a5e27850c72c51" PRIMARY KEY (id);


--
-- TOC entry 3827 (class 2606 OID 19255)
-- Name: annotation_tag_entity PK_69dfa041592c30bbc0d4b84aa00; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.annotation_tag_entity
    ADD CONSTRAINT "PK_69dfa041592c30bbc0d4b84aa00" PRIMARY KEY (id);


--
-- TOC entry 3891 (class 2606 OID 35023)
-- Name: oauth_refresh_tokens PK_74abaed0b30711b6532598b0392; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_refresh_tokens
    ADD CONSTRAINT "PK_74abaed0b30711b6532598b0392" PRIMARY KEY (token);


--
-- TOC entry 3876 (class 2606 OID 21035)
-- Name: chat_hub_messages PK_7704a5add6baed43eef835f0bfb; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "PK_7704a5add6baed43eef835f0bfb" PRIMARY KEY (id);


--
-- TOC entry 3824 (class 2606 OID 19241)
-- Name: execution_annotations PK_7afcf93ffa20c4252869a7c6a23; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_annotations
    ADD CONSTRAINT "PK_7afcf93ffa20c4252869a7c6a23" PRIMARY KEY (id);


--
-- TOC entry 3893 (class 2606 OID 35041)
-- Name: oauth_user_consents PK_85b9ada746802c8993103470f05; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "PK_85b9ada746802c8993103470f05" PRIMARY KEY (id);


--
-- TOC entry 3752 (class 2606 OID 18477)
-- Name: migrations PK_8c82d7f526340ab734260ea46be; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT "PK_8c82d7f526340ab734260ea46be" PRIMARY KEY (id);


--
-- TOC entry 3787 (class 2606 OID 18689)
-- Name: installed_nodes PK_8ebd28194e4f792f96b5933423fc439df97d9689; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.installed_nodes
    ADD CONSTRAINT "PK_8ebd28194e4f792f96b5933423fc439df97d9689" PRIMARY KEY (name);


--
-- TOC entry 3814 (class 2606 OID 19163)
-- Name: shared_credentials PK_8ef3a59796a228913f251779cff; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.shared_credentials
    ADD CONSTRAINT "PK_8ef3a59796a228913f251779cff" PRIMARY KEY ("credentialsId", "projectId");


--
-- TOC entry 3856 (class 2606 OID 19550)
-- Name: test_case_execution PK_90c121f77a78a6580e94b794bce; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.test_case_execution
    ADD CONSTRAINT "PK_90c121f77a78a6580e94b794bce" PRIMARY KEY (id);


--
-- TOC entry 3835 (class 2606 OID 19282)
-- Name: user_api_keys PK_978fa5caa3468f463dac9d92e69; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.user_api_keys
    ADD CONSTRAINT "PK_978fa5caa3468f463dac9d92e69" PRIMARY KEY (id);


--
-- TOC entry 3831 (class 2606 OID 19261)
-- Name: execution_annotation_tags PK_979ec03d31294cca484be65d11f; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_annotation_tags
    ADD CONSTRAINT "PK_979ec03d31294cca484be65d11f" PRIMARY KEY ("annotationId", "tagId");


--
-- TOC entry 3768 (class 2606 OID 18513)
-- Name: webhook_entity PK_b21ace2e13596ccd87dc9bf4ea6; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.webhook_entity
    ADD CONSTRAINT "PK_b21ace2e13596ccd87dc9bf4ea6" PRIMARY KEY ("webhookPath", method);


--
-- TOC entry 3850 (class 2606 OID 19520)
-- Name: insights_by_period PK_b606942249b90cc39b0265f0575; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.insights_by_period
    ADD CONSTRAINT "PK_b606942249b90cc39b0265f0575" PRIMARY KEY (id);


--
-- TOC entry 3804 (class 2606 OID 18896)
-- Name: workflow_history PK_b6572dd6173e4cd06fe79937b58; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_history
    ADD CONSTRAINT "PK_b6572dd6173e4cd06fe79937b58" PRIMARY KEY ("versionId");


--
-- TOC entry 3858 (class 2606 OID 19570)
-- Name: scope PK_bfc45df0481abd7f355d6187da1; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.scope
    ADD CONSTRAINT "PK_bfc45df0481abd7f355d6187da1" PRIMARY KEY (slug);


--
-- TOC entry 3885 (class 2606 OID 34977)
-- Name: oauth_clients PK_c4759172d3431bae6f04e678e0d; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_clients
    ADD CONSTRAINT "PK_c4759172d3431bae6f04e678e0d" PRIMARY KEY (id);


--
-- TOC entry 3837 (class 2606 OID 19298)
-- Name: processed_data PK_ca04b9d8dc72de268fe07a65773; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.processed_data
    ADD CONSTRAINT "PK_ca04b9d8dc72de268fe07a65773" PRIMARY KEY ("workflowId", context);


--
-- TOC entry 3783 (class 2606 OID 18674)
-- Name: settings PK_dc0fe14e6d9943f268e7b119f69ab8bd; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT "PK_dc0fe14e6d9943f268e7b119f69ab8bd" PRIMARY KEY (key);


--
-- TOC entry 3889 (class 2606 OID 35004)
-- Name: oauth_access_tokens PK_dcd71f96a5d5f4bf79e67d322bf; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT "PK_dcd71f96a5d5f4bf79e67d322bf" PRIMARY KEY (token);


--
-- TOC entry 3866 (class 2606 OID 19641)
-- Name: data_table PK_e226d0001b9e6097cbfe70617cb; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.data_table
    ADD CONSTRAINT "PK_e226d0001b9e6097cbfe70617cb" PRIMARY KEY (id);


--
-- TOC entry 3778 (class 2606 OID 18613)
-- Name: user PK_ea8f538c94b6e352418254ed6474a81f; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT "PK_ea8f538c94b6e352418254ed6474a81f" PRIMARY KEY (id);


--
-- TOC entry 3847 (class 2606 OID 19508)
-- Name: insights_raw PK_ec15125755151e3a7e00e00014f; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.insights_raw
    ADD CONSTRAINT "PK_ec15125755151e3a7e00e00014f" PRIMARY KEY (id);


--
-- TOC entry 3883 (class 2606 OID 25224)
-- Name: chat_hub_agents PK_f39a3b36bbdf0e2979ddb21cf78; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_agents
    ADD CONSTRAINT "PK_f39a3b36bbdf0e2979ddb21cf78" PRIMARY KEY (id);


--
-- TOC entry 3845 (class 2606 OID 19490)
-- Name: insights_metadata PK_f448a94c35218b6208ce20cf5a1; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.insights_metadata
    ADD CONSTRAINT "PK_f448a94c35218b6208ce20cf5a1" PRIMARY KEY ("metaId");


--
-- TOC entry 3887 (class 2606 OID 34987)
-- Name: oauth_authorization_codes PK_fb91ab932cfbd694061501cc20f; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_authorization_codes
    ADD CONSTRAINT "PK_fb91ab932cfbd694061501cc20f" PRIMARY KEY (code);


--
-- TOC entry 3864 (class 2606 OID 19583)
-- Name: role_scope PK_role_scope; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.role_scope
    ADD CONSTRAINT "PK_role_scope" PRIMARY KEY ("roleSlug", "scopeSlug");


--
-- TOC entry 3895 (class 2606 OID 35043)
-- Name: oauth_user_consents UQ_083721d99ce8db4033e2958ebb4; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "UQ_083721d99ce8db4033e2958ebb4" UNIQUE ("userId", "clientId");


--
-- TOC entry 3872 (class 2606 OID 19657)
-- Name: data_table_column UQ_8082ec4890f892f0bc77473a123; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.data_table_column
    ADD CONSTRAINT "UQ_8082ec4890f892f0bc77473a123" UNIQUE ("dataTableId", name);


--
-- TOC entry 3868 (class 2606 OID 19643)
-- Name: data_table UQ_b23096ef747281ac944d28e8b0d; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.data_table
    ADD CONSTRAINT "UQ_b23096ef747281ac944d28e8b0d" UNIQUE ("projectId", name);


--
-- TOC entry 3780 (class 2606 OID 18615)
-- Name: user UQ_e12875dfb3b1d92d7d7c5377e2; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT "UQ_e12875dfb3b1d92d7d7c5377e2" UNIQUE (email);


--
-- TOC entry 3793 (class 2606 OID 18772)
-- Name: auth_identity auth_identity_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.auth_identity
    ADD CONSTRAINT auth_identity_pkey PRIMARY KEY ("providerId", "providerType");


--
-- TOC entry 3795 (class 2606 OID 18788)
-- Name: auth_provider_sync_history auth_provider_sync_history_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.auth_provider_sync_history
    ADD CONSTRAINT auth_provider_sync_history_pkey PRIMARY KEY (id);


--
-- TOC entry 3754 (class 2606 OID 18870)
-- Name: credentials_entity credentials_entity_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.credentials_entity
    ADD CONSTRAINT credentials_entity_pkey PRIMARY KEY (id);


--
-- TOC entry 3791 (class 2606 OID 18742)
-- Name: event_destinations event_destinations_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.event_destinations
    ADD CONSTRAINT event_destinations_pkey PRIMARY KEY (id);


--
-- TOC entry 3801 (class 2606 OID 18886)
-- Name: execution_data execution_data_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_data
    ADD CONSTRAINT execution_data_pkey PRIMARY KEY ("executionId");


--
-- TOC entry 3762 (class 2606 OID 18496)
-- Name: execution_entity pk_e3e63bbf986767844bbe1166d4e; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_entity
    ADD CONSTRAINT pk_e3e63bbf986767844bbe1166d4e PRIMARY KEY (id);


--
-- TOC entry 3789 (class 2606 OID 18839)
-- Name: workflow_statistics pk_workflow_statistics; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_statistics
    ADD CONSTRAINT pk_workflow_statistics PRIMARY KEY ("workflowId", name);


--
-- TOC entry 3776 (class 2606 OID 18818)
-- Name: workflows_tags pk_workflows_tags; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflows_tags
    ADD CONSTRAINT pk_workflows_tags PRIMARY KEY ("workflowId", "tagId");


--
-- TOC entry 3773 (class 2606 OID 18859)
-- Name: tag_entity tag_entity_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.tag_entity
    ADD CONSTRAINT tag_entity_pkey PRIMARY KEY (id);


--
-- TOC entry 3798 (class 2606 OID 18873)
-- Name: variables variables_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.variables
    ADD CONSTRAINT variables_pkey PRIMARY KEY (id);


--
-- TOC entry 3766 (class 2606 OID 18857)
-- Name: workflow_entity workflow_entity_pkey; Type: CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_entity
    ADD CONSTRAINT workflow_entity_pkey PRIMARY KEY (id);


--
-- TOC entry 3838 (class 1259 OID 19418)
-- Name: IDX_14f68deffaf858465715995508; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_14f68deffaf858465715995508" ON public.folder USING btree ("projectId", id);


--
-- TOC entry 3843 (class 1259 OID 19501)
-- Name: IDX_1d8ab99d5861c9388d2dc1cf73; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_1d8ab99d5861c9388d2dc1cf73" ON public.insights_metadata USING btree ("workflowId");


--
-- TOC entry 3802 (class 1259 OID 18902)
-- Name: IDX_1e31657f5fe46816c34be7c1b4; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_1e31657f5fe46816c34be7c1b4" ON public.workflow_history USING btree ("workflowId");


--
-- TOC entry 3832 (class 1259 OID 19289)
-- Name: IDX_1ef35bac35d20bdae979d917a3; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_1ef35bac35d20bdae979d917a3" ON public.user_api_keys USING btree ("apiKey");


--
-- TOC entry 3807 (class 1259 OID 19145)
-- Name: IDX_5f0643f6717905a05164090dde; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_5f0643f6717905a05164090dde" ON public.project_relation USING btree ("userId");


--
-- TOC entry 3848 (class 1259 OID 19526)
-- Name: IDX_60b6a84299eeb3f671dfec7693; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_60b6a84299eeb3f671dfec7693" ON public.insights_by_period USING btree ("periodStart", type, "periodUnit", "metaId");


--
-- TOC entry 3808 (class 1259 OID 19143)
-- Name: IDX_61448d56d61802b5dfde5cdb00; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_61448d56d61802b5dfde5cdb00" ON public.project_relation USING btree ("projectId");


--
-- TOC entry 3833 (class 1259 OID 19288)
-- Name: IDX_63d7bbae72c767cf162d459fcc; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_63d7bbae72c767cf162d459fcc" ON public.user_api_keys USING btree ("userId", label);


--
-- TOC entry 3854 (class 1259 OID 19561)
-- Name: IDX_8e4b4774db42f1e6dda3452b2a; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_8e4b4774db42f1e6dda3452b2a" ON public.test_case_execution USING btree ("testRunId");


--
-- TOC entry 3822 (class 1259 OID 19248)
-- Name: IDX_97f863fa83c4786f1956508496; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_97f863fa83c4786f1956508496" ON public.execution_annotations USING btree ("executionId");


--
-- TOC entry 3859 (class 1259 OID 21071)
-- Name: IDX_UniqueRoleDisplayName; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_UniqueRoleDisplayName" ON public.role USING btree ("displayName");


--
-- TOC entry 3828 (class 1259 OID 19272)
-- Name: IDX_a3697779b366e131b2bbdae297; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_a3697779b366e131b2bbdae297" ON public.execution_annotation_tags USING btree ("tagId");


--
-- TOC entry 3877 (class 1259 OID 21087)
-- Name: IDX_a4ff2d9b9628ea988fa9e7d0bf; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_a4ff2d9b9628ea988fa9e7d0bf" ON public.workflow_dependency USING btree ("workflowId");


--
-- TOC entry 3825 (class 1259 OID 19256)
-- Name: IDX_ae51b54c4bb430cf92f48b623f; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_ae51b54c4bb430cf92f48b623f" ON public.annotation_tag_entity USING btree (name);


--
-- TOC entry 3829 (class 1259 OID 19273)
-- Name: IDX_c1519757391996eb06064f0e7c; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_c1519757391996eb06064f0e7c" ON public.execution_annotation_tags USING btree ("annotationId");


--
-- TOC entry 3817 (class 1259 OID 19214)
-- Name: IDX_cec8eea3bf49551482ccb4933e; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX "IDX_cec8eea3bf49551482ccb4933e" ON public.execution_metadata USING btree ("executionId", key);


--
-- TOC entry 3851 (class 1259 OID 19541)
-- Name: IDX_d6870d3b6e4c185d33926f423c; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_d6870d3b6e4c185d33926f423c" ON public.test_run USING btree ("workflowId");


--
-- TOC entry 3878 (class 1259 OID 21089)
-- Name: IDX_e48a201071ab85d9d09119d640; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_e48a201071ab85d9d09119d640" ON public.workflow_dependency USING btree ("dependencyKey");


--
-- TOC entry 3879 (class 1259 OID 21088)
-- Name: IDX_e7fe1cfda990c14a445937d0b9; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_e7fe1cfda990c14a445937d0b9" ON public.workflow_dependency USING btree ("dependencyType");


--
-- TOC entry 3757 (class 1259 OID 18903)
-- Name: IDX_execution_entity_deletedAt; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_execution_entity_deletedAt" ON public.execution_entity USING btree ("deletedAt");


--
-- TOC entry 3862 (class 1259 OID 19594)
-- Name: IDX_role_scope_scopeSlug; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_role_scope_scopeSlug" ON public.role_scope USING btree ("scopeSlug");


--
-- TOC entry 3763 (class 1259 OID 18887)
-- Name: IDX_workflow_entity_name; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX "IDX_workflow_entity_name" ON public.workflow_entity USING btree (name);


--
-- TOC entry 3755 (class 1259 OID 18703)
-- Name: idx_07fde106c0b471d8cc80a64fc8; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX idx_07fde106c0b471d8cc80a64fc8 ON public.credentials_entity USING btree (type);


--
-- TOC entry 3769 (class 1259 OID 18515)
-- Name: idx_16f4436789e804e3e1c9eeb240; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX idx_16f4436789e804e3e1c9eeb240 ON public.webhook_entity USING btree ("webhookId", method, "pathLength");


--
-- TOC entry 3770 (class 1259 OID 18523)
-- Name: idx_812eb05f7451ca757fb98444ce; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX idx_812eb05f7451ca757fb98444ce ON public.tag_entity USING btree (name);


--
-- TOC entry 3758 (class 1259 OID 19224)
-- Name: idx_execution_entity_stopped_at_status_deleted_at; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX idx_execution_entity_stopped_at_status_deleted_at ON public.execution_entity USING btree ("stoppedAt", status, "deletedAt") WHERE (("stoppedAt" IS NOT NULL) AND ("deletedAt" IS NULL));


--
-- TOC entry 3759 (class 1259 OID 19223)
-- Name: idx_execution_entity_wait_till_status_deleted_at; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX idx_execution_entity_wait_till_status_deleted_at ON public.execution_entity USING btree ("waitTill", status, "deletedAt") WHERE (("waitTill" IS NOT NULL) AND ("deletedAt" IS NULL));


--
-- TOC entry 3760 (class 1259 OID 19222)
-- Name: idx_execution_entity_workflow_id_started_at; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX idx_execution_entity_workflow_id_started_at ON public.execution_entity USING btree ("workflowId", "startedAt") WHERE (("startedAt" IS NOT NULL) AND ("deletedAt" IS NULL));


--
-- TOC entry 3774 (class 1259 OID 18819)
-- Name: idx_workflows_tags_workflow_id; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX idx_workflows_tags_workflow_id ON public.workflows_tags USING btree ("workflowId");


--
-- TOC entry 3756 (class 1259 OID 18860)
-- Name: pk_credentials_entity_id; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX pk_credentials_entity_id ON public.credentials_entity USING btree (id);


--
-- TOC entry 3771 (class 1259 OID 18816)
-- Name: pk_tag_entity_id; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX pk_tag_entity_id ON public.tag_entity USING btree (id);


--
-- TOC entry 3764 (class 1259 OID 18815)
-- Name: pk_workflow_entity_id; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX pk_workflow_entity_id ON public.workflow_entity USING btree (id);


--
-- TOC entry 3811 (class 1259 OID 19665)
-- Name: project_relation_role_idx; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX project_relation_role_idx ON public.project_relation USING btree (role);


--
-- TOC entry 3812 (class 1259 OID 19666)
-- Name: project_relation_role_project_idx; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX project_relation_role_project_idx ON public.project_relation USING btree ("projectId", role);


--
-- TOC entry 3781 (class 1259 OID 19667)
-- Name: user_role_idx; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE INDEX user_role_idx ON public."user" USING btree ("roleSlug");


--
-- TOC entry 3796 (class 1259 OID 19675)
-- Name: variables_global_key_unique; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX variables_global_key_unique ON public.variables USING btree (key) WHERE ("projectId" IS NULL);


--
-- TOC entry 3799 (class 1259 OID 19674)
-- Name: variables_project_key_unique; Type: INDEX; Schema: public; Owner: n8n_postgres_user
--

CREATE UNIQUE INDEX variables_project_key_unique ON public.variables USING btree ("projectId", key) WHERE ("projectId" IS NOT NULL);


--
-- TOC entry 3956 (class 2620 OID 25194)
-- Name: workflow_entity workflow_version_increment; Type: TRIGGER; Schema: public; Owner: n8n_postgres_user
--

CREATE TRIGGER workflow_version_increment BEFORE UPDATE ON public.workflow_entity FOR EACH ROW EXECUTE FUNCTION public.increment_workflow_version();


--
-- TOC entry 3920 (class 2606 OID 19299)
-- Name: processed_data FK_06a69a7032c97a763c2c7599464; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.processed_data
    ADD CONSTRAINT "FK_06a69a7032c97a763c2c7599464" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3925 (class 2606 OID 19491)
-- Name: insights_metadata FK_1d8ab99d5861c9388d2dc1cf733; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.insights_metadata
    ADD CONSTRAINT "FK_1d8ab99d5861c9388d2dc1cf733" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE SET NULL;


--
-- TOC entry 3907 (class 2606 OID 18897)
-- Name: workflow_history FK_1e31657f5fe46816c34be7c1b4b; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_history
    ADD CONSTRAINT "FK_1e31657f5fe46816c34be7c1b4b" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3939 (class 2606 OID 21061)
-- Name: chat_hub_messages FK_1f4998c8a7dec9e00a9ab15550e; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_1f4998c8a7dec9e00a9ab15550e" FOREIGN KEY ("revisionOfMessageId") REFERENCES public.chat_hub_messages(id) ON DELETE CASCADE;


--
-- TOC entry 3954 (class 2606 OID 35049)
-- Name: oauth_user_consents FK_21e6c3c2d78a097478fae6aaefa; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "FK_21e6c3c2d78a097478fae6aaefa" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3926 (class 2606 OID 19496)
-- Name: insights_metadata FK_2375a1eda085adb16b24615b69c; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.insights_metadata
    ADD CONSTRAINT "FK_2375a1eda085adb16b24615b69c" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE SET NULL;


--
-- TOC entry 3940 (class 2606 OID 21056)
-- Name: chat_hub_messages FK_25c9736e7f769f3a005eef4b372; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_25c9736e7f769f3a005eef4b372" FOREIGN KEY ("retryOfMessageId") REFERENCES public.chat_hub_messages(id) ON DELETE CASCADE;


--
-- TOC entry 3915 (class 2606 OID 19209)
-- Name: execution_metadata FK_31d0b4c93fb85ced26f6005cda3; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_metadata
    ADD CONSTRAINT "FK_31d0b4c93fb85ced26f6005cda3" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3911 (class 2606 OID 19164)
-- Name: shared_credentials FK_416f66fc846c7c442970c094ccf; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.shared_credentials
    ADD CONSTRAINT "FK_416f66fc846c7c442970c094ccf" FOREIGN KEY ("credentialsId") REFERENCES public.credentials_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3905 (class 2606 OID 19669)
-- Name: variables FK_42f6c766f9f9d2edcc15bdd6e9b; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.variables
    ADD CONSTRAINT "FK_42f6c766f9f9d2edcc15bdd6e9b" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- TOC entry 3946 (class 2606 OID 25225)
-- Name: chat_hub_agents FK_441ba2caba11e077ce3fbfa2cd8; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_agents
    ADD CONSTRAINT "FK_441ba2caba11e077ce3fbfa2cd8" FOREIGN KEY ("ownerId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3908 (class 2606 OID 19138)
-- Name: project_relation FK_5f0643f6717905a05164090dde7; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "FK_5f0643f6717905a05164090dde7" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3909 (class 2606 OID 19133)
-- Name: project_relation FK_61448d56d61802b5dfde5cdb002; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "FK_61448d56d61802b5dfde5cdb002" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- TOC entry 3928 (class 2606 OID 19521)
-- Name: insights_by_period FK_6414cfed98daabbfdd61a1cfbc0; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.insights_by_period
    ADD CONSTRAINT "FK_6414cfed98daabbfdd61a1cfbc0" FOREIGN KEY ("metaId") REFERENCES public.insights_metadata("metaId") ON DELETE CASCADE;


--
-- TOC entry 3948 (class 2606 OID 34988)
-- Name: oauth_authorization_codes FK_64d965bd072ea24fb6da55468cd; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_authorization_codes
    ADD CONSTRAINT "FK_64d965bd072ea24fb6da55468cd" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- TOC entry 3941 (class 2606 OID 21066)
-- Name: chat_hub_messages FK_6afb260449dd7a9b85355d4e0c9; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_6afb260449dd7a9b85355d4e0c9" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE SET NULL;


--
-- TOC entry 3927 (class 2606 OID 19509)
-- Name: insights_raw FK_6e2e33741adef2a7c5d66befa4e; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.insights_raw
    ADD CONSTRAINT "FK_6e2e33741adef2a7c5d66befa4e" FOREIGN KEY ("metaId") REFERENCES public.insights_metadata("metaId") ON DELETE CASCADE;


--
-- TOC entry 3950 (class 2606 OID 35010)
-- Name: oauth_access_tokens FK_7234a36d8e49a1fa85095328845; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT "FK_7234a36d8e49a1fa85095328845" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3902 (class 2606 OID 18690)
-- Name: installed_nodes FK_73f857fc5dce682cef8a99c11dbddbc969618951; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.installed_nodes
    ADD CONSTRAINT "FK_73f857fc5dce682cef8a99c11dbddbc969618951" FOREIGN KEY (package) REFERENCES public.installed_packages("packageName") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3951 (class 2606 OID 35005)
-- Name: oauth_access_tokens FK_78b26968132b7e5e45b75876481; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT "FK_78b26968132b7e5e45b75876481" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- TOC entry 3936 (class 2606 OID 21015)
-- Name: chat_hub_sessions FK_7bc13b4c7e6afbfaf9be326c189; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "FK_7bc13b4c7e6afbfaf9be326c189" FOREIGN KEY ("credentialId") REFERENCES public.credentials_entity(id) ON DELETE SET NULL;


--
-- TOC entry 3921 (class 2606 OID 19413)
-- Name: folder FK_804ea52f6729e3940498bd54d78; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.folder
    ADD CONSTRAINT "FK_804ea52f6729e3940498bd54d78" FOREIGN KEY ("parentFolderId") REFERENCES public.folder(id) ON DELETE CASCADE;


--
-- TOC entry 3912 (class 2606 OID 19169)
-- Name: shared_credentials FK_812c2852270da1247756e77f5a4; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.shared_credentials
    ADD CONSTRAINT "FK_812c2852270da1247756e77f5a4" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- TOC entry 3930 (class 2606 OID 19551)
-- Name: test_case_execution FK_8e4b4774db42f1e6dda3452b2af; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.test_case_execution
    ADD CONSTRAINT "FK_8e4b4774db42f1e6dda3452b2af" FOREIGN KEY ("testRunId") REFERENCES public.test_run(id) ON DELETE CASCADE;


--
-- TOC entry 3935 (class 2606 OID 19658)
-- Name: data_table_column FK_930b6e8faaf88294cef23484160; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.data_table_column
    ADD CONSTRAINT "FK_930b6e8faaf88294cef23484160" FOREIGN KEY ("dataTableId") REFERENCES public.data_table(id) ON DELETE CASCADE;


--
-- TOC entry 3923 (class 2606 OID 19424)
-- Name: folder_tag FK_94a60854e06f2897b2e0d39edba; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.folder_tag
    ADD CONSTRAINT "FK_94a60854e06f2897b2e0d39edba" FOREIGN KEY ("folderId") REFERENCES public.folder(id) ON DELETE CASCADE;


--
-- TOC entry 3916 (class 2606 OID 19243)
-- Name: execution_annotations FK_97f863fa83c4786f19565084960; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_annotations
    ADD CONSTRAINT "FK_97f863fa83c4786f19565084960" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3947 (class 2606 OID 25230)
-- Name: chat_hub_agents FK_9c61ad497dcbae499c96a6a78ba; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_agents
    ADD CONSTRAINT "FK_9c61ad497dcbae499c96a6a78ba" FOREIGN KEY ("credentialId") REFERENCES public.credentials_entity(id) ON DELETE SET NULL;


--
-- TOC entry 3937 (class 2606 OID 21020)
-- Name: chat_hub_sessions FK_9f9293d9f552496c40e0d1a8f80; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "FK_9f9293d9f552496c40e0d1a8f80" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE SET NULL;


--
-- TOC entry 3917 (class 2606 OID 19267)
-- Name: execution_annotation_tags FK_a3697779b366e131b2bbdae2976; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_annotation_tags
    ADD CONSTRAINT "FK_a3697779b366e131b2bbdae2976" FOREIGN KEY ("tagId") REFERENCES public.annotation_tag_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3913 (class 2606 OID 19195)
-- Name: shared_workflow FK_a45ea5f27bcfdc21af9b4188560; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.shared_workflow
    ADD CONSTRAINT "FK_a45ea5f27bcfdc21af9b4188560" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- TOC entry 3945 (class 2606 OID 21082)
-- Name: workflow_dependency FK_a4ff2d9b9628ea988fa9e7d0bf8; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_dependency
    ADD CONSTRAINT "FK_a4ff2d9b9628ea988fa9e7d0bf8" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3955 (class 2606 OID 35044)
-- Name: oauth_user_consents FK_a651acea2f6c97f8c4514935486; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_user_consents
    ADD CONSTRAINT "FK_a651acea2f6c97f8c4514935486" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- TOC entry 3952 (class 2606 OID 35029)
-- Name: oauth_refresh_tokens FK_a699f3ed9fd0c1b19bc2608ac53; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_refresh_tokens
    ADD CONSTRAINT "FK_a699f3ed9fd0c1b19bc2608ac53" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3922 (class 2606 OID 19408)
-- Name: folder FK_a8260b0b36939c6247f385b8221; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.folder
    ADD CONSTRAINT "FK_a8260b0b36939c6247f385b8221" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- TOC entry 3949 (class 2606 OID 34993)
-- Name: oauth_authorization_codes FK_aa8d3560484944c19bdf79ffa16; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_authorization_codes
    ADD CONSTRAINT "FK_aa8d3560484944c19bdf79ffa16" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3942 (class 2606 OID 21046)
-- Name: chat_hub_messages FK_acf8926098f063cdbbad8497fd1; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_acf8926098f063cdbbad8497fd1" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE SET NULL;


--
-- TOC entry 3953 (class 2606 OID 35024)
-- Name: oauth_refresh_tokens FK_b388696ce4d8be7ffbe8d3e4b69; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.oauth_refresh_tokens
    ADD CONSTRAINT "FK_b388696ce4d8be7ffbe8d3e4b69" FOREIGN KEY ("clientId") REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- TOC entry 3918 (class 2606 OID 19262)
-- Name: execution_annotation_tags FK_c1519757391996eb06064f0e7c8; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_annotation_tags
    ADD CONSTRAINT "FK_c1519757391996eb06064f0e7c8" FOREIGN KEY ("annotationId") REFERENCES public.execution_annotations(id) ON DELETE CASCADE;


--
-- TOC entry 3934 (class 2606 OID 19644)
-- Name: data_table FK_c2a794257dee48af7c9abf681de; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.data_table
    ADD CONSTRAINT "FK_c2a794257dee48af7c9abf681de" FOREIGN KEY ("projectId") REFERENCES public.project(id) ON DELETE CASCADE;


--
-- TOC entry 3910 (class 2606 OID 19601)
-- Name: project_relation FK_c6b99592dc96b0d836d7a21db91; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.project_relation
    ADD CONSTRAINT "FK_c6b99592dc96b0d836d7a21db91" FOREIGN KEY (role) REFERENCES public.role(slug);


--
-- TOC entry 3929 (class 2606 OID 19536)
-- Name: test_run FK_d6870d3b6e4c185d33926f423c8; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.test_run
    ADD CONSTRAINT "FK_d6870d3b6e4c185d33926f423c8" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3914 (class 2606 OID 19190)
-- Name: shared_workflow FK_daa206a04983d47d0a9c34649ce; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.shared_workflow
    ADD CONSTRAINT "FK_daa206a04983d47d0a9c34649ce" FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3924 (class 2606 OID 19429)
-- Name: folder_tag FK_dc88164176283de80af47621746; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.folder_tag
    ADD CONSTRAINT "FK_dc88164176283de80af47621746" FOREIGN KEY ("tagId") REFERENCES public.tag_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3919 (class 2606 OID 19283)
-- Name: user_api_keys FK_e131705cbbc8fb589889b02d457; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.user_api_keys
    ADD CONSTRAINT "FK_e131705cbbc8fb589889b02d457" FOREIGN KEY ("userId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3943 (class 2606 OID 21036)
-- Name: chat_hub_messages FK_e22538eb50a71a17954cd7e076c; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_e22538eb50a71a17954cd7e076c" FOREIGN KEY ("sessionId") REFERENCES public.chat_hub_sessions(id) ON DELETE CASCADE;


--
-- TOC entry 3931 (class 2606 OID 19556)
-- Name: test_case_execution FK_e48965fac35d0f5b9e7f51d8c44; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.test_case_execution
    ADD CONSTRAINT "FK_e48965fac35d0f5b9e7f51d8c44" FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE SET NULL;


--
-- TOC entry 3944 (class 2606 OID 21041)
-- Name: chat_hub_messages FK_e5d1fa722c5a8d38ac204746662; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_messages
    ADD CONSTRAINT "FK_e5d1fa722c5a8d38ac204746662" FOREIGN KEY ("previousMessageId") REFERENCES public.chat_hub_messages(id) ON DELETE CASCADE;


--
-- TOC entry 3938 (class 2606 OID 21010)
-- Name: chat_hub_sessions FK_e9ecf8ede7d989fcd18790fe36a; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.chat_hub_sessions
    ADD CONSTRAINT "FK_e9ecf8ede7d989fcd18790fe36a" FOREIGN KEY ("ownerId") REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3901 (class 2606 OID 19596)
-- Name: user FK_eaea92ee7bfb9c1b6cd01505d56; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT "FK_eaea92ee7bfb9c1b6cd01505d56" FOREIGN KEY ("roleSlug") REFERENCES public.role(slug);


--
-- TOC entry 3932 (class 2606 OID 19584)
-- Name: role_scope FK_role; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.role_scope
    ADD CONSTRAINT "FK_role" FOREIGN KEY ("roleSlug") REFERENCES public.role(slug) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3933 (class 2606 OID 19589)
-- Name: role_scope FK_scope; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.role_scope
    ADD CONSTRAINT "FK_scope" FOREIGN KEY ("scopeSlug") REFERENCES public.scope(slug) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3904 (class 2606 OID 18773)
-- Name: auth_identity auth_identity_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.auth_identity
    ADD CONSTRAINT "auth_identity_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."user"(id);


--
-- TOC entry 3906 (class 2606 OID 18879)
-- Name: execution_data execution_data_fk; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_data
    ADD CONSTRAINT execution_data_fk FOREIGN KEY ("executionId") REFERENCES public.execution_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3896 (class 2606 OID 18851)
-- Name: execution_entity fk_execution_entity_workflow_id; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.execution_entity
    ADD CONSTRAINT fk_execution_entity_workflow_id FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3898 (class 2606 OID 18845)
-- Name: webhook_entity fk_webhook_entity_workflow_id; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.webhook_entity
    ADD CONSTRAINT fk_webhook_entity_workflow_id FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3897 (class 2606 OID 19480)
-- Name: workflow_entity fk_workflow_parent_folder; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_entity
    ADD CONSTRAINT fk_workflow_parent_folder FOREIGN KEY ("parentFolderId") REFERENCES public.folder(id) ON DELETE CASCADE;


--
-- TOC entry 3903 (class 2606 OID 18840)
-- Name: workflow_statistics fk_workflow_statistics_workflow_id; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflow_statistics
    ADD CONSTRAINT fk_workflow_statistics_workflow_id FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3899 (class 2606 OID 18825)
-- Name: workflows_tags fk_workflows_tags_tag_id; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflows_tags
    ADD CONSTRAINT fk_workflows_tags_tag_id FOREIGN KEY ("tagId") REFERENCES public.tag_entity(id) ON DELETE CASCADE;


--
-- TOC entry 3900 (class 2606 OID 18820)
-- Name: workflows_tags fk_workflows_tags_workflow_id; Type: FK CONSTRAINT; Schema: public; Owner: n8n_postgres_user
--

ALTER TABLE ONLY public.workflows_tags
    ADD CONSTRAINT fk_workflows_tags_workflow_id FOREIGN KEY ("workflowId") REFERENCES public.workflow_entity(id) ON DELETE CASCADE;


--
-- TOC entry 4175 (class 0 OID 0)
-- Dependencies: 14
-- Name: SCHEMA metric_helpers; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA metric_helpers TO admin;
GRANT USAGE ON SCHEMA metric_helpers TO robot_zmon;


--
-- TOC entry 4176 (class 0 OID 0)
-- Dependencies: 20
-- Name: SCHEMA pooler; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA pooler TO pooler;


--
-- TOC entry 4177 (class 0 OID 0)
-- Dependencies: 208
-- Name: SCHEMA user_management; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA user_management TO admin;


--
-- TOC entry 4182 (class 0 OID 0)
-- Dependencies: 528
-- Name: FUNCTION get_btree_bloat_approx(OUT i_database name, OUT i_schema_name name, OUT i_table_name name, OUT i_index_name name, OUT i_real_size numeric, OUT i_extra_size numeric, OUT i_extra_ratio double precision, OUT i_fill_factor integer, OUT i_bloat_size double precision, OUT i_bloat_ratio double precision, OUT i_is_na boolean); Type: ACL; Schema: metric_helpers; Owner: postgres
--

REVOKE ALL ON FUNCTION metric_helpers.get_btree_bloat_approx(OUT i_database name, OUT i_schema_name name, OUT i_table_name name, OUT i_index_name name, OUT i_real_size numeric, OUT i_extra_size numeric, OUT i_extra_ratio double precision, OUT i_fill_factor integer, OUT i_bloat_size double precision, OUT i_bloat_ratio double precision, OUT i_is_na boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION metric_helpers.get_btree_bloat_approx(OUT i_database name, OUT i_schema_name name, OUT i_table_name name, OUT i_index_name name, OUT i_real_size numeric, OUT i_extra_size numeric, OUT i_extra_ratio double precision, OUT i_fill_factor integer, OUT i_bloat_size double precision, OUT i_bloat_ratio double precision, OUT i_is_na boolean) TO admin;
GRANT ALL ON FUNCTION metric_helpers.get_btree_bloat_approx(OUT i_database name, OUT i_schema_name name, OUT i_table_name name, OUT i_index_name name, OUT i_real_size numeric, OUT i_extra_size numeric, OUT i_extra_ratio double precision, OUT i_fill_factor integer, OUT i_bloat_size double precision, OUT i_bloat_ratio double precision, OUT i_is_na boolean) TO robot_zmon;


--
-- TOC entry 4183 (class 0 OID 0)
-- Dependencies: 503
-- Name: FUNCTION get_nearly_exhausted_sequences(threshold double precision, OUT schemaname name, OUT sequencename name, OUT seq_percent_used numeric); Type: ACL; Schema: metric_helpers; Owner: postgres
--

REVOKE ALL ON FUNCTION metric_helpers.get_nearly_exhausted_sequences(threshold double precision, OUT schemaname name, OUT sequencename name, OUT seq_percent_used numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION metric_helpers.get_nearly_exhausted_sequences(threshold double precision, OUT schemaname name, OUT sequencename name, OUT seq_percent_used numeric) TO admin;
GRANT ALL ON FUNCTION metric_helpers.get_nearly_exhausted_sequences(threshold double precision, OUT schemaname name, OUT sequencename name, OUT seq_percent_used numeric) TO robot_zmon;


--
-- TOC entry 4184 (class 0 OID 0)
-- Dependencies: 535
-- Name: FUNCTION get_table_bloat_approx(OUT t_database name, OUT t_schema_name name, OUT t_table_name name, OUT t_real_size numeric, OUT t_extra_size double precision, OUT t_extra_ratio double precision, OUT t_fill_factor integer, OUT t_bloat_size double precision, OUT t_bloat_ratio double precision, OUT t_is_na boolean); Type: ACL; Schema: metric_helpers; Owner: postgres
--

REVOKE ALL ON FUNCTION metric_helpers.get_table_bloat_approx(OUT t_database name, OUT t_schema_name name, OUT t_table_name name, OUT t_real_size numeric, OUT t_extra_size double precision, OUT t_extra_ratio double precision, OUT t_fill_factor integer, OUT t_bloat_size double precision, OUT t_bloat_ratio double precision, OUT t_is_na boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION metric_helpers.get_table_bloat_approx(OUT t_database name, OUT t_schema_name name, OUT t_table_name name, OUT t_real_size numeric, OUT t_extra_size double precision, OUT t_extra_ratio double precision, OUT t_fill_factor integer, OUT t_bloat_size double precision, OUT t_bloat_ratio double precision, OUT t_is_na boolean) TO admin;
GRANT ALL ON FUNCTION metric_helpers.get_table_bloat_approx(OUT t_database name, OUT t_schema_name name, OUT t_table_name name, OUT t_real_size numeric, OUT t_extra_size double precision, OUT t_extra_ratio double precision, OUT t_fill_factor integer, OUT t_bloat_size double precision, OUT t_bloat_ratio double precision, OUT t_is_na boolean) TO robot_zmon;


--
-- TOC entry 4185 (class 0 OID 0)
-- Dependencies: 529
-- Name: FUNCTION pg_stat_statements(showtext boolean); Type: ACL; Schema: metric_helpers; Owner: postgres
--

REVOKE ALL ON FUNCTION metric_helpers.pg_stat_statements(showtext boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION metric_helpers.pg_stat_statements(showtext boolean) TO admin;
GRANT ALL ON FUNCTION metric_helpers.pg_stat_statements(showtext boolean) TO robot_zmon;


--
-- TOC entry 4186 (class 0 OID 0)
-- Dependencies: 489
-- Name: FUNCTION pg_switch_wal(); Type: ACL; Schema: pg_catalog; Owner: postgres
--

GRANT ALL ON FUNCTION pg_catalog.pg_switch_wal() TO admin;


--
-- TOC entry 4187 (class 0 OID 0)
-- Dependencies: 530
-- Name: FUNCTION user_lookup(i_username text, OUT uname text, OUT phash text); Type: ACL; Schema: pooler; Owner: postgres
--

REVOKE ALL ON FUNCTION pooler.user_lookup(i_username text, OUT uname text, OUT phash text) FROM PUBLIC;
GRANT ALL ON FUNCTION pooler.user_lookup(i_username text, OUT uname text, OUT phash text) TO pooler;


--
-- TOC entry 4188 (class 0 OID 0)
-- Dependencies: 533
-- Name: FUNCTION pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) TO admin;


--
-- TOC entry 4189 (class 0 OID 0)
-- Dependencies: 520
-- Name: FUNCTION set_user(text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.set_user(text) TO admin;


--
-- TOC entry 4191 (class 0 OID 0)
-- Dependencies: 534
-- Name: FUNCTION create_application_user(username text); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.create_application_user(username text) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.create_application_user(username text) TO admin;


--
-- TOC entry 4193 (class 0 OID 0)
-- Dependencies: 508
-- Name: FUNCTION create_application_user_or_change_password(username text, password text); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.create_application_user_or_change_password(username text, password text) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.create_application_user_or_change_password(username text, password text) TO admin;


--
-- TOC entry 4195 (class 0 OID 0)
-- Dependencies: 506
-- Name: FUNCTION create_role(rolename text); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.create_role(rolename text) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.create_role(rolename text) TO admin;


--
-- TOC entry 4197 (class 0 OID 0)
-- Dependencies: 488
-- Name: FUNCTION create_user(username text); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.create_user(username text) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.create_user(username text) TO admin;


--
-- TOC entry 4199 (class 0 OID 0)
-- Dependencies: 490
-- Name: FUNCTION drop_role(username text); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.drop_role(username text) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.drop_role(username text) TO admin;


--
-- TOC entry 4201 (class 0 OID 0)
-- Dependencies: 504
-- Name: FUNCTION drop_user(username text); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.drop_user(username text) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.drop_user(username text) TO admin;


--
-- TOC entry 4203 (class 0 OID 0)
-- Dependencies: 507
-- Name: FUNCTION revoke_admin(username text); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.revoke_admin(username text) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.revoke_admin(username text) TO admin;


--
-- TOC entry 4205 (class 0 OID 0)
-- Dependencies: 532
-- Name: FUNCTION terminate_backend(pid integer); Type: ACL; Schema: user_management; Owner: postgres
--

REVOKE ALL ON FUNCTION user_management.terminate_backend(pid integer) FROM PUBLIC;
GRANT ALL ON FUNCTION user_management.terminate_backend(pid integer) TO admin;


--
-- TOC entry 4206 (class 0 OID 0)
-- Dependencies: 425
-- Name: TABLE index_bloat; Type: ACL; Schema: metric_helpers; Owner: postgres
--

GRANT SELECT ON TABLE metric_helpers.index_bloat TO admin;
GRANT SELECT ON TABLE metric_helpers.index_bloat TO robot_zmon;


--
-- TOC entry 4207 (class 0 OID 0)
-- Dependencies: 427
-- Name: TABLE nearly_exhausted_sequences; Type: ACL; Schema: metric_helpers; Owner: postgres
--

GRANT SELECT ON TABLE metric_helpers.nearly_exhausted_sequences TO admin;
GRANT SELECT ON TABLE metric_helpers.nearly_exhausted_sequences TO robot_zmon;


--
-- TOC entry 4208 (class 0 OID 0)
-- Dependencies: 426
-- Name: TABLE pg_stat_statements; Type: ACL; Schema: metric_helpers; Owner: postgres
--

GRANT SELECT ON TABLE metric_helpers.pg_stat_statements TO admin;
GRANT SELECT ON TABLE metric_helpers.pg_stat_statements TO robot_zmon;


--
-- TOC entry 4209 (class 0 OID 0)
-- Dependencies: 424
-- Name: TABLE table_bloat; Type: ACL; Schema: metric_helpers; Owner: postgres
--

GRANT SELECT ON TABLE metric_helpers.table_bloat TO admin;
GRANT SELECT ON TABLE metric_helpers.table_bloat TO robot_zmon;


--
-- TOC entry 4210 (class 0 OID 0)
-- Dependencies: 322
-- Name: TABLE pg_stat_activity; Type: ACL; Schema: pg_catalog; Owner: postgres
--

GRANT SELECT ON TABLE pg_catalog.pg_stat_activity TO admin;


-- Completed on 2025-12-03 14:39:06 UTC

--
-- PostgreSQL database dump complete
--

