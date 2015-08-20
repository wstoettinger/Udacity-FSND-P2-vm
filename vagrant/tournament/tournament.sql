-- Table definitions for the tournament project.
\c tournament

-- drop tables first for repeatable script execution
drop view simple_pairings CASCADE;
drop view __pairings_helper__ CASCADE;
drop view standings CASCADE;
drop view __standings_helper__ CASCADE;
drop view __omw_helper__ CASCADE;
drop view match_participation CASCADE;
drop table match CASCADE;
drop table round CASCADE;
drop table player CASCADE;
drop table tournament CASCADE;


--------------------------
-- creating aggregate functions first(*) and last(*)
--------------------------

-- Create a function that always returns the first non-NULL item
CREATE OR REPLACE FUNCTION public.first_agg ( anyelement, anyelement )
RETURNS anyelement LANGUAGE SQL IMMUTABLE STRICT AS $$
        SELECT $1;
$$;

drop aggregate public.FIRST(anyelement);

-- And then wrap an aggregate around it
CREATE AGGREGATE public.FIRST (
        sfunc    = public.first_agg,
        basetype = anyelement,
        stype    = anyelement
);

-- Create a function that always returns the last non-NULL item
CREATE OR REPLACE FUNCTION public.last_agg ( anyelement, anyelement )
RETURNS anyelement LANGUAGE SQL IMMUTABLE STRICT AS $$
        SELECT $2;
$$;


drop aggregate public.LAST(anyelement);

-- And then wrap an aggregate around it
CREATE AGGREGATE public.LAST (
        sfunc    = public.last_agg,
        basetype = anyelement,
        stype    = anyelement
);


-----------------------
-- tournament database schema
-----------------------

-- table for tournaments
create table tournament (
  id serial primary key,
  name varchar(80) NOT NULL,
  location varchar(200),
  t_time timestamp
);

-- table for players
create table player (
  id serial primary key,
  name varchar(80) NOT NULL
);

-- table for rounds, each player can only play once per round
create table round (
  id serial primary key,
  tournament_id int references tournament(id)
);

-- table for matches
create table match (  
  id serial primary key,
  round_id int references round(id) not null,
  p1_id int references player(id) not null,
  p2_id int references player(id),
  match_datetime timestamp not null,
  played boolean DEFAULT false,
  won_player_id int,
  p1_score int,
  p2_score int 
);

-- helper view for match participation of individual players
create view match_participation as ((
    select id, round_id, p1_id as player_id, played, p1_score as score, 
    (CASE WHEN p1_id = won_player_id THEN 1 ELSE null END) as won,
    (CASE WHEN won_player_id is null and p1_score is not null THEN 1 ELSE null END) as tie,
    COALESCE(p2_id, 0) as opp_id, p2_score as opp_score,
    (CASE WHEN p2_id = won_player_id THEN 1 ELSE null END) as opp_won
    from match
    where p1_id is not null
  ) union (
    select id, round_id, p2_id as player_id, played, p2_score as score, 
    (CASE WHEN p2_id = won_player_id THEN 1 ELSE null END) as won,
    (CASE WHEN won_player_id is null and p2_score is not null THEN 1 ELSE null END) as tie,
    COALESCE(p1_id, 0) as opp_id, p1_score as opp_score,
    (CASE WHEN p1_id = won_player_id THEN 1 ELSE null END) as opp_won
    from match
    where p2_id is not null
  )
  order by id
);

-- helper function for standings
create view __standings_helper__ as (
  select p.id, p.name, count(m.won) as wins, count(m.opp_score) as matches, sum(m.score) as score, max(m.round_id) as round
  from player as p
    left join match_participation as m on (m.player_id = p.id)
  group by p.id, p.name
  order by wins desc, matches desc, score desc, id asc
);

-- counts the wins of all opponents of each player
create view __omw_helper__ as (
  select m.player_id, count(m_opp.won) as all_opps_wins 
  from match_participation as m
    inner join match_participation as m_opp on (m.id = m_opp.id)
  group by m.player_id
  order by all_opps_wins desc
);

-- view for standings
-- comment: wins can actually be higher than matches when a player gets a "bye" (free win)
create view standings as (
  select i.id, i.name, i.wins, i.matches, i.score, omw.all_opps_wins, i.round, (row_number() over() +1) / 2 as swiss_pair
  from __standings_helper__ as i
    left join __omw_helper__ as omw on (i.id = omw.player_id)
);

-- helper for swiss parings to be able to assign the bye player in case of uneven numbers of plaers
create view __pairings_helper__ as ((
    select * from standings
  ) union (
    select 0, 'bye', null, null, null, null, null, (count(swiss_pair) + 2) / 2 as swiss_pair from standings
    group by 1, 2
  )
  order by 1
);

-- this view is for siwss pairings, taking into account which opponents a player has played already and if the player has gotten a "bye" already
-- however, in order for the view to work, the first result has to be inserted into the match table so that these two players are removed from the next query
-- therefore, the normal "workflow" of the test app doesn't work that way, that's why there is a simple_pairings view as well.
create view complex_pairings as (
  select s.id, opp_s.id as opp_id,
  COALESCE(s.round, 0) as round,
  COALESCE(opp_s.round, 0) as opp_round,
  abs(s.wins - COALESCE(opp_s.wins, -9999)) as dif_win, 
  s.matches - COALESCE(opp_s.matches, 0) as dif_matches, 
  abs(s.score - COALESCE(opp_s.score, 0)) as dif_score, 
  abs(s.all_opps_wins - COALESCE(opp_s.all_opps_wins, 0)) as dif_all_opps_wins
  from (__pairings_helper__ as s
    cross join __pairings_helper__ as opp_s)
      left join match_participation as par on (par.player_id = s.id and par.opp_id = opp_s.id)
  where s.id != 0 and s.id != opp_s.id and par.opp_id is null
  order by dif_win asc, dif_matches asc, s.id asc, dif_score asc, dif_all_opps_wins asc, opp_id asc
);

-- this view is for simple siwss pairings
create view simple_pairings as (
  select first(s1.id) as id1, first(s1.name) as name1, first(s2.id) as id2, first(s2.name) as name2, s1.swiss_pair
  from __pairings_helper__ s1
    inner join __pairings_helper__ s2 on (s1.swiss_pair = s2.swiss_pair and s1.id != s2.id)
  group by s1.swiss_pair
  order by s1.swiss_pair
);

-----------------------
-- test data
-----------------------
-- except for the match results, the following code works fully automatically and is based on SQL only, without any help of procedural programming

-- inserting a test tournament
insert into tournament (id, name, location, t_time) values (1, 'Udacious Tournament', 'Vienna', CURRENT_TIMESTAMP);

-- insterting test players
insert into player (id, name) values (1000, 'Joe');
insert into player (id, name) values (1001, 'Jack');
insert into player (id, name) values (1002, 'Jane');
insert into player (id, name) values (1003, 'Jenny');
insert into player (id, name) values (1004, 'Lazy Cat');


----------
-- round 1
----------

-- select standings before round
select * from standings;

-- select pairings for next round
-- select * from complex_pairings;
-- select * from simple_pairings;

insert into round (tournament_id) values (1);

-- insert matches according to standings 
-- this kind of works like registering the match, the scores get update later.
insert into match (round_id, p1_id, p2_id, match_datetime) select 1, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 1 and opp_round < 1;
insert into match (round_id, p1_id, p2_id, match_datetime) select 1, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 1 and opp_round < 1;
insert into match (round_id, p1_id, p2_id, match_datetime) select 1, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 1 and opp_round < 1;
-- the inserts above should have the following values:
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (1, 1000, 1001, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (1, 1002, 1003, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (1, 1004, null, CURRENT_TIMESTAMP);

-- updating scores afer games (last is a "bye")
update match set played = true, won_player_id = 1000, p1_score = 3, p2_score = 0 where id = 1;
update match set played = true, won_player_id = 1002, p1_score = 3, p2_score = 0 where id = 2;
update match set played = true, won_player_id = 1004, p1_score = 3 where id = 3;


----------
-- round 2
----------

-- select standings before round
select * from standings;

-- select pairings for next round
-- select * from complex_pairings;
-- select * from simple_pairings;

insert into round (tournament_id) values (1);

-- insert matches according to standings
insert into match (round_id, p1_id, p2_id, match_datetime) select 2, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 2 and opp_round < 2;
insert into match (round_id, p1_id, p2_id, match_datetime) select 2, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 2 and opp_round < 2;
insert into match (round_id, p1_id, p2_id, match_datetime) select 2, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 2 and opp_round < 2;
-- the inserts above should have the following values:
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (2, 1004, 1000, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (2, 1001, 1003, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (2, 1002, null, CURRENT_TIMESTAMP);

-- updating scores afer games of round 2 (second is a tie, last is a "bye")
update match set played = true, won_player_id = 1000, p1_score = 0, p2_score = 3 where id = 4;
update match set played = true, p1_score = 1, p2_score = 1 where id = 5;
update match set played = true, won_player_id = 1002, p1_score = 3 where id = 6;


----------
-- round 3
----------

-- select standings before round
select * from standings;

-- select pairings for next round
-- select * from complex_pairings;
-- select * from simple_pairings;

insert into round (tournament_id) values (1);

-- insert matches according to standings
insert into match (round_id, p1_id, p2_id, match_datetime) select 3, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 3 and opp_round < 3;
insert into match (round_id, p1_id, p2_id, match_datetime) select 3, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 3 and opp_round < 3;
insert into match (round_id, p1_id, p2_id, match_datetime) select 3, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 3 and opp_round < 3;
-- the inserts above should have the following values:
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (2, 1002, 1000, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (2, 1004, 1001, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (2, 1003, null, CURRENT_TIMESTAMP);

-- updating scores afer games of round 3 (second is a tie, last is a "bye")
update match set played = true, won_player_id = 1002, p1_score = 3, p2_score = 0 where id = 7;
update match set played = true, p1_score = 1, p2_score = 1 where id = 8;
update match set played = true, won_player_id = 1003, p1_score = 3 where id = 9;


----------
-- round 4
----------

-- select standings before round
select * from standings;

-- select pairings for next round
-- select * from complex_pairings;
-- select * from simple_pairings;

insert into round (tournament_id) values (1);

-- insert matches according to standings
insert into match (round_id, p1_id, p2_id, match_datetime) select 4, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 4 and opp_round < 4;
insert into match (round_id, p1_id, p2_id, match_datetime) select 4, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 4 and opp_round < 4;
insert into match (round_id, p1_id, p2_id, match_datetime) select 4, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 4 and opp_round < 4;
-- the inserts above should have the following values:
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (3, 1003, 1004, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (3, 1002, 1001, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (3, 1000, null, CURRENT_TIMESTAMP);

-- updating scores afer games of round 4 (second is a tie, last is a "bye")
update match set played = true, won_player_id = 1003, p1_score = 3, p2_score = 0 where id = 10;
update match set played = true, p1_score = 1, p2_score = 1 where id = 11;
update match set played = true, won_player_id = 1000, p1_score = 3 where id = 12;


----------
-- round 5
----------

-- select standings before round
select * from standings;

-- select pairings for next round
-- select * from complex_pairings;
-- select * from simple_pairings;

insert into round (tournament_id) values (1);

-- insert matches according to standings
insert into match (round_id, p1_id, p2_id, match_datetime) select 5, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 5 and opp_round < 5;
insert into match (round_id, p1_id, p2_id, match_datetime) select 5, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 5 and opp_round < 5;
insert into match (round_id, p1_id, p2_id, match_datetime) select 5, first(id), CASE WHEN first(opp_id) = 0 THEN null ELSE first(opp_id) END, CURRENT_TIMESTAMP from complex_pairings where round < 5 and opp_round < 5;
-- the inserts above should have the following values:
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (4, 1000, 1003, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (4, 1002, 1004, CURRENT_TIMESTAMP);
-- insert into match (round_id, p1_id, p2_id, match_datetime) values (4, 1001, null, CURRENT_TIMESTAMP);

-- updating scores afer games of round 5 (first is a tie, last is a "bye")
update match set played = true, p1_score = 1, p2_score = 2 where id = 13;
update match set played = true, won_player_id = 1002, p1_score = 3, p2_score = 0 where id = 14;
update match set played = true, won_player_id = 1001, p1_score = 3 where id = 15;


-----------
-- Game finished
-----------

-- select standings after round 5
  select * from standings;

