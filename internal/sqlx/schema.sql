pragma user_version = 1;

-- ┌───────────────┐
-- │ Keys          │
-- └───────────────┘
-- Types:
-- 1 - string
-- 2 - list
-- 3 - set
-- 4 - hash
-- 5 - zset (sorted set)
CREATE TABLE if NOT EXISTS rkey (
  id INTEGER PRIMARY KEY,
  KEY text NOT NULL,
  TYPE INTEGER NOT NULL,
  VERSION INTEGER NOT NULL,
  etime INTEGER,
  mtime INTEGER NOT NULL,
  len INTEGER
);

CREATE UNIQUE index if NOT EXISTS rkey_key_idx ON rkey (KEY);

CREATE index if NOT EXISTS rkey_etime_idx ON rkey (etime)
WHERE
  etime IS NOT NULL;

CREATE VIEW if NOT EXISTS vkey AS
SELECT
  id AS kid,
  KEY,
  TYPE,
  len,
  datetime(etime / 1000, 'unixepoch') AS etime,
  datetime(mtime / 1000, 'unixepoch') AS mtime
FROM
  rkey
WHERE
  rkey.etime IS NULL
  OR rkey.etime > unixepoch('subsec');

-- ┌───────────────┐
-- │ Strings       │
-- └───────────────┘
CREATE TABLE if NOT EXISTS rstring (
  kid INTEGER NOT NULL,
  VALUE BLOB NOT NULL,
  FOREIGN KEY (kid) REFERENCES rkey (id) ON
  DELETE
    CASCADE
);

CREATE UNIQUE index if NOT EXISTS rstring_pk_idx ON rstring (kid);

CREATE VIEW if NOT EXISTS vstring AS
SELECT
  rkey.id AS kid,
  rkey.key,
  rstring.value,
  datetime(etime / 1000, 'unixepoch') AS etime,
  datetime(mtime / 1000, 'unixepoch') AS mtime
FROM
  rstring
  JOIN rkey ON rstring.kid = rkey.id
  AND rkey.type = 1
WHERE
  rkey.etime IS NULL
  OR rkey.etime > unixepoch('subsec');

-- ┌───────────────┐
-- │ Lists         │
-- └───────────────┘
CREATE TABLE if NOT EXISTS rlist (
  kid INTEGER NOT NULL,
  pos REAL NOT NULL,
  elem BLOB NOT NULL,
  FOREIGN KEY (kid) REFERENCES rkey (id) ON
  DELETE
    CASCADE
);

CREATE UNIQUE index if NOT EXISTS rlist_pk_idx ON rlist (kid, pos);

CREATE TRIGGER if NOT EXISTS rlist_on_update BEFORE
UPDATE
  ON rlist FOR EACH ROW BEGIN
UPDATE
  rkey
SET
  VERSION = VERSION + 1,
  mtime = unixepoch('subsec') * 1000
WHERE
  id = OLD.kid;

END;

CREATE TRIGGER if NOT EXISTS rlist_on_delete BEFORE
DELETE
  ON rlist FOR EACH ROW BEGIN
UPDATE
  rkey
SET
  VERSION = VERSION + 1,
  mtime = unixepoch('subsec') * 1000,
  len = len - 1
WHERE
  id = OLD.kid;

END;

CREATE VIEW if NOT EXISTS vlist AS
SELECT
  rkey.id AS kid,
  rkey.key,
  ROW_NUMBER() OVER w AS idx,
  rlist.elem,
  datetime(etime / 1000, 'unixepoch') AS etime,
  datetime(mtime / 1000, 'unixepoch') AS mtime
FROM
  rlist
  JOIN rkey ON rlist.kid = rkey.id
  AND rkey.type = 2
WHERE
  rkey.etime IS NULL
  OR rkey.etime > unixepoch('subsec') WINDOW w AS (
    PARTITION BY kid
    ORDER
      BY pos
  );

-- ┌───────────────┐
-- │ Sets          │
-- └───────────────┘
CREATE TABLE if NOT EXISTS rset (
  kid INTEGER NOT NULL,
  elem BLOB NOT NULL,
  FOREIGN KEY (kid) REFERENCES rkey (id) ON
  DELETE
    CASCADE
);

CREATE UNIQUE index if NOT EXISTS rset_pk_idx ON rset (kid, elem);

CREATE TRIGGER if NOT EXISTS rset_on_insert
AFTER
INSERT
  ON rset FOR EACH ROW BEGIN
UPDATE
  rkey
SET
  len = len + 1
WHERE
  id = NEW.kid;

END;

CREATE VIEW if NOT EXISTS vset AS
SELECT
  rkey.id AS kid,
  rkey.key,
  rset.elem,
  datetime(etime / 1000, 'unixepoch') AS etime,
  datetime(mtime / 1000, 'unixepoch') AS mtime
FROM
  rset
  JOIN rkey ON rset.kid = rkey.id
  AND rkey.type = 3
WHERE
  rkey.etime IS NULL
  OR rkey.etime > unixepoch('subsec');

-- ┌───────────────┐
-- │ Hashes        │
-- └───────────────┘
CREATE TABLE if NOT EXISTS rhash (
  kid INTEGER NOT NULL,
  field text NOT NULL,
  VALUE BLOB NOT NULL,
  FOREIGN KEY (kid) REFERENCES rkey (id) ON
  DELETE
    CASCADE
);

CREATE UNIQUE index if NOT EXISTS rhash_pk_idx ON rhash (kid, field);

CREATE TRIGGER if NOT EXISTS rhash_on_insert BEFORE
INSERT
  ON rhash FOR EACH ROW
  WHEN (
    SELECT
      COUNT(*)
    FROM
      rhash
    WHERE
      kid = NEW.kid
      AND field = NEW.field
  ) = 0 BEGIN
UPDATE
  rkey
SET
  len = len + 1
WHERE
  id = NEW.kid;

END;

CREATE VIEW if NOT EXISTS vhash AS
SELECT
  rkey.id AS kid,
  rkey.key,
  rhash.field,
  rhash.value,
  datetime(etime / 1000, 'unixepoch') AS etime,
  datetime(mtime / 1000, 'unixepoch') AS mtime
FROM
  rhash
  JOIN rkey ON rhash.kid = rkey.id
  AND rkey.type = 4
WHERE
  rkey.etime IS NULL
  OR rkey.etime > unixepoch('subsec');

-- ┌───────────────┐
-- │ Sorted sets   │
-- └───────────────┘
CREATE TABLE if NOT EXISTS rzset (
  kid INTEGER NOT NULL,
  elem BLOB NOT NULL,
  score REAL NOT NULL,
  FOREIGN KEY (kid) REFERENCES rkey (id) ON
  DELETE
    CASCADE
);

CREATE UNIQUE index if NOT EXISTS rzset_pk_idx ON rzset (kid, elem);

CREATE index if NOT EXISTS rzset_score_idx ON rzset (kid, score, elem);

CREATE TRIGGER if NOT EXISTS rzset_on_insert BEFORE
INSERT
  ON rzset FOR EACH ROW
  WHEN (
    SELECT
      COUNT(*)
    FROM
      rzset
    WHERE
      kid = NEW.kid
      AND elem = NEW.elem
  ) = 0 BEGIN
UPDATE
  rkey
SET
  len = len + 1
WHERE
  id = NEW.kid;

END;

CREATE VIEW if NOT EXISTS vzset AS
SELECT
  rkey.id AS kid,
  rkey.key,
  rzset.elem,
  rzset.score,
  datetime(etime / 1000, 'unixepoch') AS etime,
  datetime(mtime / 1000, 'unixepoch') AS mtime
FROM
  rzset
  JOIN rkey ON rzset.kid = rkey.id
  AND rkey.type = 5
WHERE
  rkey.etime IS NULL
  OR rkey.etime > unixepoch('subsec');