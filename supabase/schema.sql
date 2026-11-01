-- Spiele-Wichteln: Datenbank für Supabase
-- Im Supabase-Dashboard unter "SQL Editor" einfügen und einmal ausführen.
--
-- Sicherheitsmodell: Die Tabellen sind für die Webseite gesperrt (RLS ohne Policies).
-- Die Seite spricht nur mit den Funktionen unten, und jede Funktion verlangt einen
-- geheimen Code: den Einladungscode der Runde, den persönlichen Link einer Person
-- oder den Organisations-Link. Niemand kann so die ganze Ziehung auslesen.

create table if not exists rounds (
  id uuid primary key default gen_random_uuid(),
  title text not null default 'Spiele-Wichteln',
  budget text not null default '',
  gift_date date,
  invite_code text not null unique,
  admin_token text not null unique,
  drawn_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists participants (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references rounds(id) on delete cascade,
  name text not null,
  token text not null unique,
  partner_id uuid references participants(id) on delete set null,
  games text[] not null default '{}',
  wish text not null default '',
  target_id uuid references participants(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists participants_round_idx on participants(round_id);

alter table rounds enable row level security;
alter table participants enable row level security;
revoke all on rounds, participants from anon, authenticated;

-- ---------- interne Helfer ----------

create or replace function new_token(n int) returns text
language sql volatile as $$
  select substr(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 1, n)
$$;

create or replace function _round_json(r rounds) returns json
language sql stable as $$
  select json_build_object('title', r.title, 'budget', r.budget, 'date', r.gift_date,
                           'drawn', r.drawn_at is not null, 'invite_code', r.invite_code)
$$;

create or replace function _admin(p_admin text) returns rounds
language plpgsql stable as $$
declare r rounds;
begin
  select * into r from rounds where admin_token = p_admin;
  if not found then raise exception 'Organisations-Link ungültig.'; end if;
  return r;
end $$;

create or replace function _link_partner(p_round uuid, a uuid, b uuid) returns void
language plpgsql as $$
begin
  if not exists (select 1 from participants where id = a and round_id = p_round) then
    raise exception 'Person nicht gefunden.';
  end if;
  if b is not null and (b = a or not exists (select 1 from participants where id = b and round_id = p_round)) then
    raise exception 'Ungültige Auswahl.';
  end if;
  update participants set partner_id = null
   where round_id = p_round
     and (id = a or partner_id = a or (b is not null and (id = b or partner_id = b)));
  if b is not null then
    update participants set partner_id = b where id = a;
    update participants set partner_id = a where id = b;
  end if;
end $$;

-- ---------- öffentlich: Runde erstellen und beitreten ----------

create or replace function create_round(p_title text, p_budget text, p_date date)
returns json language plpgsql security definer set search_path = public as $$
declare r rounds;
begin
  insert into rounds (title, budget, gift_date, invite_code, admin_token)
  values (coalesce(nullif(left(trim(p_title), 80), ''), 'Spiele-Wichteln'),
          left(coalesce(trim(p_budget), ''), 40), p_date, new_token(10), new_token(32))
  returning * into r;
  return json_build_object('invite_code', r.invite_code, 'admin_token', r.admin_token);
end $$;

create or replace function round_info(p_invite text)
returns json language plpgsql security definer set search_path = public as $$
declare r rounds;
begin
  select * into r from rounds where invite_code = p_invite;
  if not found then raise exception 'Diese Runde gibt es nicht. Prüf den Einladungslink.'; end if;
  return json_build_object('round', _round_json(r),
    'names', coalesce((select json_agg(name order by created_at) from participants where round_id = r.id), '[]'));
end $$;

create or replace function join_round(p_invite text, p_name text)
returns json language plpgsql security definer set search_path = public as $$
declare r rounds; t text; n text := left(trim(coalesce(p_name, '')), 40);
begin
  select * into r from rounds where invite_code = p_invite for update;
  if not found then raise exception 'Diese Runde gibt es nicht. Prüf den Einladungslink.'; end if;
  if r.drawn_at is not null then raise exception 'Es wurde schon gezogen. Frag die Organisation, ob sie die Ziehung zurücksetzt.'; end if;
  if n = '' then raise exception 'Bitte gib deinen Namen ein.'; end if;
  if exists (select 1 from participants where round_id = r.id and lower(name) = lower(n)) then
    raise exception 'Den Namen % gibt es schon in dieser Runde. Nimm z. B. noch den Anfangsbuchstaben des Nachnamens dazu.', n;
  end if;
  t := new_token(24);
  insert into participants (round_id, name, token) values (r.id, n, t);
  return json_build_object('token', t);
end $$;

-- ---------- persönlicher Link ----------

create or replace function me(p_token text)
returns json language plpgsql security definer set search_path = public as $$
declare p participants; r rounds; tg participants;
begin
  select * into p from participants where token = p_token;
  if not found then raise exception 'Dieser persönliche Link ist ungültig.'; end if;
  select * into r from rounds where id = p.round_id;
  if p.target_id is not null then select * into tg from participants where id = p.target_id; end if;
  return json_build_object(
    'id', p.id, 'name', p.name, 'partner_id', p.partner_id, 'games', p.games, 'wish', p.wish,
    'round', _round_json(r),
    'others', coalesce((select json_agg(json_build_object('id', o.id, 'name', o.name, 'partner_id', o.partner_id) order by o.created_at)
                          from participants o where o.round_id = r.id and o.id <> p.id), '[]'),
    'target', case when r.drawn_at is not null and tg.id is not null
                   then json_build_object('name', tg.name, 'games', tg.games, 'wish', tg.wish) end);
end $$;

create or replace function update_me(p_token text, p_games text[], p_wish text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update participants
     set games = coalesce((select array_agg(left(trim(g), 60) order by i)
                             from unnest(coalesce(p_games, '{}')) with ordinality u(g, i)
                            where trim(g) <> '' and i <= 150), '{}'),
         wish = left(coalesce(p_wish, ''), 500)
   where token = p_token;
  if not found then raise exception 'Dieser persönliche Link ist ungültig.'; end if;
  return true;
end $$;

create or replace function set_partner(p_token text, p_partner uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare p participants;
begin
  select * into p from participants where token = p_token;
  if not found then raise exception 'Dieser persönliche Link ist ungültig.'; end if;
  if exists (select 1 from rounds where id = p.round_id and drawn_at is not null) then
    raise exception 'Nach der Ziehung lassen sich Paare nicht mehr ändern.';
  end if;
  perform _link_partner(p.round_id, p.id, p_partner);
  return true;
end $$;

-- ---------- Organisation ----------

create or replace function admin_overview(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare r rounds;
begin
  r := _admin(p_admin);
  return json_build_object('round', _round_json(r),
    'people', coalesce((select json_agg(json_build_object('id', id, 'name', name, 'partner_id', partner_id,
                                                          'games', cardinality(games), 'token', token) order by created_at)
                          from participants where round_id = r.id), '[]'));
end $$;

create or replace function admin_update_round(p_admin text, p_title text, p_budget text, p_date date)
returns boolean language plpgsql security definer set search_path = public as $$
declare r rounds;
begin
  r := _admin(p_admin);
  update rounds set title = coalesce(nullif(left(trim(p_title), 80), ''), 'Spiele-Wichteln'),
                    budget = left(coalesce(trim(p_budget), ''), 40), gift_date = p_date
   where id = r.id;
  return true;
end $$;

create or replace function admin_set_partner(p_admin text, p_person uuid, p_partner uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare r rounds;
begin
  r := _admin(p_admin);
  if r.drawn_at is not null then raise exception 'Setz zuerst die Ziehung zurück.'; end if;
  perform _link_partner(r.id, p_person, p_partner);
  return true;
end $$;

create or replace function admin_remove(p_admin text, p_person uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare r rounds;
begin
  r := _admin(p_admin);
  if r.drawn_at is not null then raise exception 'Setz zuerst die Ziehung zurück.'; end if;
  delete from participants where id = p_person and round_id = r.id;
  return true;
end $$;

create or replace function admin_reset_draw(p_admin text)
returns boolean language plpgsql security definer set search_path = public as $$
declare r rounds;
begin
  r := _admin(p_admin);
  update participants set target_id = null where round_id = r.id;
  update rounds set drawn_at = null where id = r.id;
  return true;
end $$;

-- p_draw: {"<id der schenkenden Person>": "<id der beschenkten Person>", ...}
create or replace function admin_save_draw(p_admin text, p_draw json)
returns boolean language plpgsql security definer set search_path = public as $$
declare r rounds; n int; ok int;
begin
  select * into r from rounds where admin_token = p_admin for update;
  if not found then raise exception 'Organisations-Link ungültig.'; end if;
  if r.drawn_at is not null then raise exception 'Es wurde schon gezogen.'; end if;
  select count(*) into n from participants where round_id = r.id;
  if n < 3 then raise exception 'Für eine Ziehung braucht ihr mindestens drei Personen.'; end if;
  select count(*) into ok
    from json_each_text(p_draw) d
    join participants g on g.id = d.key::uuid and g.round_id = r.id
    join participants t on t.id = d.value::uuid and t.round_id = r.id
   where g.id <> t.id and g.partner_id is distinct from t.id;
  if ok <> n
     or (select count(*) from json_each_text(p_draw)) <> n
     or (select count(distinct value) from json_each_text(p_draw)) <> n then
    raise exception 'Die Ziehung passt nicht mehr zur Runde (vielleicht ist gerade jemand beigetreten). Bitte nochmals ziehen.';
  end if;
  update participants p set target_id = d.value::uuid
    from json_each_text(p_draw) d
   where p.id = d.key::uuid and p.round_id = r.id;
  update rounds set drawn_at = now() where id = r.id;
  return true;
end $$;

-- ---------- Rechte ----------

revoke execute on function new_token(int), _round_json(rounds), _admin(text), _link_partner(uuid, uuid, uuid)
  from public, anon, authenticated;

revoke execute on function
  create_round(text, text, date), round_info(text), join_round(text, text),
  me(text), update_me(text, text[], text), set_partner(text, uuid),
  admin_overview(text), admin_update_round(text, text, text, date), admin_set_partner(text, uuid, uuid),
  admin_remove(text, uuid), admin_reset_draw(text), admin_save_draw(text, json)
  from public;

grant execute on function
  create_round(text, text, date), round_info(text), join_round(text, text),
  me(text), update_me(text, text[], text), set_partner(text, uuid),
  admin_overview(text), admin_update_round(text, text, text, date), admin_set_partner(text, uuid, uuid),
  admin_remove(text, uuid), admin_reset_draw(text), admin_save_draw(text, json)
  to anon, authenticated;
