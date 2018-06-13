create table data (
  timestamp timestamptz sortkey not null,
  name varchar(max) not null,
  value real not null
)
