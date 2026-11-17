-- TWELVE — initial schema.
--
-- Principles
--   * Every table that holds personal data has Row Level Security enabled and
--     only ever exposes a person's own rows.
--   * Clients get the narrowest grants that let the app work. Rewards
--     (achievements, solved puzzles, progress totals) are written only by
--     SECURITY DEFINER functions that recompute everything on the server.
--   * Unrevealed challenge content and Sudoku solutions cannot be read by
--     ordinary clients at all.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

-- ---------------------------------------------------------------- helpers

create or replace function private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Stamps server receipt time and rejects activity dated in the future
-- (anywhere on Earth), so a client clock cannot pre-date next month's work.
create or replace function private.stamp_activity() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.received_at := now();
  else
    new.received_at := old.received_at;
    new.user_id := old.user_id;
  end if;
  if new.local_day > (now() at time zone 'Pacific/Kiritimati')::date then
    raise exception 'activity cannot be dated in the future' using errcode = '22008';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------- profiles

create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  display_name        text check (char_length(display_name) <= 60),
  calendar_time_zone  text not null default 'UTC' check (char_length(calendar_time_zone) <= 64),
  joined_at           timestamptz not null default now(),
  onboarding_complete boolean not null default false,
  feeling             text check (feeling in ('curious','active','creative','balanced','surprise')),
  preferences         jsonb not null default '{}'::jsonb check (pg_column_size(preferences) < 8192),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();

create table public.user_interests (
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category    text not null check (category in ('technology','design','books','science','history','art','sports','nature','health')),
  subcategory text check (char_length(subcategory) <= 32),
  weight      numeric not null default 1 check (weight >= 0 and weight <= 10),
  updated_at  timestamptz not null default now(),
  primary key (user_id, category)
);

create table public.notification_preferences (
  user_id              uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category             text not null check (category in ('daily_spark','monthly_reveal','progress')),
  preferred_local_time time,
  enabled              boolean not null default false,
  updated_at           timestamptz not null default now(),
  primary key (user_id, category)
);

-- ------------------------------------------------------- editorial content

create table public.challenge_definitions (
  id                      text primary key,
  year                    int  not null,
  month                   int  not null check (month between 1 and 12),
  title                   text not null,
  category                text not null,
  story                   text not null,
  instructions            jsonb not null default '[]'::jsonb,
  completion_target       numeric not null check (completion_target > 0),
  unit                    text not null,
  module_type             text not null,
  metric                  text not null check (metric in ('distinctDays','count','sumMinutes','sumAmount','distinctRefs','qualifyingSessions','vocabulary')),
  entry_kind              text not null,
  minimum_amount          numeric,
  reveal_at               timestamptz not null,
  accessible_alternatives jsonb,
  editorial               jsonb not null default '{}'::jsonb,
  editorial_version       int not null default 1,
  unique (year, month)
);

-- Completion criteria are frozen once a month has been revealed.
create or replace function private.freeze_started_criteria() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.reveal_at <= now() and (
       new.completion_target is distinct from old.completion_target
    or new.metric is distinct from old.metric
    or new.entry_kind is distinct from old.entry_kind
    or new.minimum_amount is distinct from old.minimum_amount
    or new.module_type is distinct from old.module_type
    or new.reveal_at is distinct from old.reveal_at) then
    raise exception 'completion criteria cannot change after a challenge has started';
  end if;
  return new;
end $$;
create trigger challenge_definitions_freeze before update on public.challenge_definitions
  for each row execute function private.freeze_started_criteria();

create table public.discovery_cards (
  id              text primary key,
  headline        text not null,
  content         text not null,
  category        text not null,
  subcategory     text,
  source_title    text not null,
  source_url      text not null check (source_url like 'https://%'),
  interaction     jsonb not null default '{}'::jsonb,
  content_version int  not null default 1,
  status          text not null default 'draft' check (status in ('draft','published','retired'))
);

create table public.sudoku_puzzles (
  id             text primary key,
  difficulty     text not null check (difficulty in ('medium','hard')),
  givens         text not null check (givens ~ '^[0-9]{81}$'),
  puzzle_version int  not null default 1
);

-- Solutions live outside the exposed schema. No client role can read them.
create table private.sudoku_solutions (
  puzzle_id text primary key references public.sudoku_puzzles (id) on delete cascade,
  solution  text not null check (solution ~ '^[1-9]{81}$')
);

-- ------------------------------------------------------------ user activity

create table public.activity_sessions (
  id              uuid primary key,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  challenge_id    text not null references public.challenge_definitions (id),
  kind            text not null check (kind in ('plank','walk','focus')),
  started_at      timestamptz not null,
  ended_at        timestamptz not null,
  elapsed_seconds numeric not null check (elapsed_seconds >= 0),
  events          jsonb not null default '[]'::jsonb check (pg_column_size(events) < 16384),
  local_day       date not null,
  variant         text check (char_length(variant) <= 32),
  metadata        jsonb not null default '{}'::jsonb check (pg_column_size(metadata) < 4096),
  deleted         boolean not null default false,
  received_at     timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- The same ceilings the app enforces. Paused time is never included, so
  -- active time can never exceed the wall-clock span of the session.
  constraint plausible_duration check (
        (kind = 'plank' and elapsed_seconds <= 1200)
     or (kind = 'walk'  and elapsed_seconds <= 21600)
     or (kind = 'focus' and elapsed_seconds <= 601)),
  constraint within_wall_clock check (
        ended_at >= started_at
    and elapsed_seconds <= extract(epoch from (ended_at - started_at)) + 2)
);
create index activity_sessions_user_updated on public.activity_sessions (user_id, updated_at);
create trigger activity_sessions_stamp before insert or update on public.activity_sessions
  for each row execute function private.stamp_activity();

create table public.journal_entries (
  id              uuid primary key,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  challenge_id    text not null references public.challenge_definitions (id),
  kind            text not null check (kind in ('observation','kindness','dish','moment','photo','reading','word_learned','quiz_pass','creative_stage','reflection')),
  entry_at        timestamptz not null,
  local_day       date not null,
  title           text check (char_length(title) <= 200),
  body            text check (char_length(body) <= 4000),
  amount          numeric not null default 1 check (amount >= 0 and amount <= 500),
  ref             text check (char_length(ref) <= 64),
  has_local_photo boolean not null default false,
  privacy         jsonb not null default '{"photo_storage":"device_only"}'::jsonb check (pg_column_size(privacy) < 1024),
  deleted         boolean not null default false,
  received_at     timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index journal_entries_user_updated on public.journal_entries (user_id, updated_at);
create trigger journal_entries_stamp before insert or update on public.journal_entries
  for each row execute function private.stamp_activity();

create table public.sudoku_attempts (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  puzzle_id    text not null references public.sudoku_puzzles (id),
  challenge_id text references public.challenge_definitions (id),
  current_grid text not null check (current_grid ~ '^[0-9]{81}$'),
  pencil_notes jsonb not null default '[]'::jsonb check (pg_column_size(pencil_notes) < 4096),
  state        text not null default 'in_progress' check (state in ('in_progress','solved')),
  solved_at    timestamptz,
  local_day    date,
  hint_count   int not null default 0 check (hint_count between 0 and 81),
  updated_at   timestamptz not null default now(),
  primary key (user_id, puzzle_id)
);
create trigger sudoku_attempts_touch before update on public.sudoku_attempts
  for each row execute function private.touch_updated_at();

create table public.discovery_interactions (
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  card_id          text not null references public.discovery_cards (id),
  interaction_type text not null check (interaction_type in ('viewed','answered','saved','dismissed')),
  completed_at     timestamptz not null default now(),
  saved            boolean not null default false,
  updated_at       timestamptz not null default now(),
  primary key (user_id, card_id, interaction_type)
);

-- Server-computed totals. Clients can read their own row, never write it.
create table public.challenge_progress (
  user_id          uuid not null references auth.users (id) on delete cascade,
  challenge_id     text not null references public.challenge_definitions (id),
  numeric_progress numeric not null default 0,
  completed        boolean not null default false,
  completed_at     timestamptz,
  selected_variant text,
  updated_at       timestamptz not null default now(),
  primary key (user_id, challenge_id)
);

-- One row per person per month, ever. The primary key is what makes
-- completion idempotent: a second claim for the same month changes nothing.
create table public.achievements (
  user_id      uuid not null references auth.users (id) on delete cascade,
  year         int  not null,
  month        int  not null check (month between 1 and 12),
  challenge_id text not null references public.challenge_definitions (id),
  verified_at  timestamptz not null default now(),
  primary key (user_id, year, month)
);

create table private.rate_limits (
  user_id      uuid not null,
  action       text not null,
  window_start timestamptz not null,
  hits         int not null default 1,
  primary key (user_id, action, window_start)
);

-- ------------------------------------------------------- row level security

alter table public.profiles                 enable row level security;
alter table public.user_interests           enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.challenge_definitions    enable row level security;
alter table public.discovery_cards          enable row level security;
alter table public.sudoku_puzzles           enable row level security;
alter table public.activity_sessions        enable row level security;
alter table public.journal_entries          enable row level security;
alter table public.sudoku_attempts          enable row level security;
alter table public.discovery_interactions   enable row level security;
alter table public.challenge_progress       enable row level security;
alter table public.achievements             enable row level security;
alter table private.sudoku_solutions        enable row level security;
alter table private.rate_limits             enable row level security;

-- Start from nothing, then grant only what each role needs.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all tables in schema private from anon, authenticated, public;

-- Content: readable by anyone using the app, but only what is live.
grant select on public.challenge_definitions, public.discovery_cards, public.sudoku_puzzles to anon, authenticated;
create policy "revealed challenges only" on public.challenge_definitions
  for select to anon, authenticated using (reveal_at <= now());
create policy "published cards only" on public.discovery_cards
  for select to anon, authenticated using (status = 'published');
create policy "puzzles are readable" on public.sudoku_puzzles
  for select to anon, authenticated using (true);

-- Profile: read own; update only the editable columns.
grant select on public.profiles to authenticated;
grant insert (id, display_name, calendar_time_zone, onboarding_complete, feeling, preferences) on public.profiles to authenticated;
grant update (display_name, calendar_time_zone, onboarding_complete, feeling, preferences) on public.profiles to authenticated;
create policy "own profile: read" on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "own profile: insert" on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy "own profile: update" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

grant select, insert, update, delete on public.user_interests, public.notification_preferences, public.discovery_interactions to authenticated;
create policy "own interests" on public.user_interests for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own notification preferences" on public.notification_preferences for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own discovery interactions" on public.discovery_interactions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Activity: own rows only. Rows are soft-deleted (deleted = true) so other
-- devices learn about the removal; hard deletion happens with the account.
grant select, insert, update on public.activity_sessions, public.journal_entries to authenticated;
create policy "own sessions" on public.activity_sessions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own journal" on public.journal_entries for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Sudoku attempts: a client may save work in progress, but can never mark a
-- puzzle solved or edit a solved row. Only submit_sudoku_solution() can.
grant select on public.sudoku_attempts to authenticated;
grant insert (user_id, puzzle_id, current_grid, pencil_notes, hint_count) on public.sudoku_attempts to authenticated;
-- puzzle_id is included because an upsert re-states the key it matched on.
grant update (puzzle_id, current_grid, pencil_notes, hint_count) on public.sudoku_attempts to authenticated;
create policy "own attempts: read" on public.sudoku_attempts for select to authenticated
  using (user_id = (select auth.uid()));
create policy "own attempts: insert in progress" on public.sudoku_attempts for insert to authenticated
  with check (user_id = (select auth.uid()) and state = 'in_progress' and solved_at is null);
create policy "own attempts: update in progress" on public.sudoku_attempts for update to authenticated
  using (user_id = (select auth.uid()) and state = 'in_progress')
  with check (user_id = (select auth.uid()) and state = 'in_progress' and solved_at is null);

-- Rewards: read-only for their owner.
grant select on public.challenge_progress, public.achievements to authenticated;
create policy "own progress: read" on public.challenge_progress for select to authenticated
  using (user_id = (select auth.uid()));
create policy "own achievements: read" on public.achievements for select to authenticated
  using (user_id = (select auth.uid()));

-- ------------------------------------------------------- server-side logic

create or replace function private.check_rate_limit(p_action text, p_max int) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_window timestamptz := date_trunc('hour', now());
  v_hits int;
begin
  insert into private.rate_limits (user_id, action, window_start)
  values (auth.uid(), p_action, v_window)
  on conflict (user_id, action, window_start) do update set hits = private.rate_limits.hits + 1
  returning hits into v_hits;
  if v_hits > p_max then
    raise exception 'rate limit exceeded' using errcode = '54000';
  end if;
  delete from private.rate_limits where window_start < now() - interval '2 days';
end $$;

-- The single source of truth for progress. Mirrors TwelveCore.ProgressCalculator.
create or replace function private.compute_progress(p_user uuid, p_challenge text) returns numeric
language plpgsql stable security definer set search_path = '' as $$
declare
  d public.challenge_definitions%rowtype;
  v_first date;
  v_last date;
  v numeric := 0;
  v_pass boolean;
begin
  select * into d from public.challenge_definitions where id = p_challenge;
  if not found then return 0; end if;
  v_first := make_date(d.year, d.month, 1);
  v_last := (v_first + interval '1 month' - interval '1 day')::date;

  with facts as (
    select kind, local_day, elapsed_seconds as amount, null::text as ref
      from public.activity_sessions
     where user_id = p_user and challenge_id = p_challenge and not deleted
    union all
    select kind, local_day, amount, ref
      from public.journal_entries
     where user_id = p_user and challenge_id = p_challenge and not deleted
    union all
    select 'sudoku_solved', local_day, 1, puzzle_id
      from public.sudoku_attempts
     where user_id = p_user and challenge_id = p_challenge and state = 'solved'
  ), f as (
    select * from facts where local_day between v_first and v_last
  )
  select case d.metric
    when 'distinctDays'       then (select count(distinct local_day) from f where kind = d.entry_kind)
    when 'count'              then (select count(*) from f where kind = d.entry_kind)
    when 'sumMinutes'         then (select coalesce(sum(amount), 0) / 60.0 from f where kind = d.entry_kind)
    when 'sumAmount'          then (select coalesce(sum(amount), 0) from f where kind = d.entry_kind and amount >= 1)
    when 'distinctRefs'       then (select count(distinct ref) from f where kind = d.entry_kind and ref is not null and ref <> '')
    when 'qualifyingSessions' then (select count(*) from f where kind = d.entry_kind and amount >= coalesce(d.minimum_amount, 0))
    when 'vocabulary'         then (select least(d.completion_target, count(distinct ref)) from f where kind = d.entry_kind and ref is not null and ref <> '')
    else 0 end,
    exists (select 1 from f where kind = 'quiz_pass')
  into v, v_pass;

  -- Vocabulary only completes with a passed recall exercise.
  if d.metric = 'vocabulary' and v >= d.completion_target and not v_pass then
    v := d.completion_target - 0.5;
  end if;
  return coalesce(v, 0);
end $$;

-- Recomputes a person's progress and, if the goal is met inside the month
-- (plus a short grace period for offline devices), records the achievement.
-- Safe to call any number of times.
create or replace function public.claim_month_completion(p_challenge_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  d public.challenge_definitions%rowtype;
  v_progress numeric;
  v_complete boolean;
  v_close timestamptz;
  v_verified timestamptz;
  v_variant text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform private.check_rate_limit('claim', 120);

  select * into d from public.challenge_definitions where id = p_challenge_id and reveal_at <= now();
  if not found then
    raise exception 'challenge is not available' using errcode = '42501';
  end if;

  v_progress := private.compute_progress(v_user, d.id);
  v_complete := v_progress >= d.completion_target;
  -- The month closes when it has ended everywhere on Earth; devices that were
  -- offline get seven further days to deliver what was done in time.
  v_close := make_timestamptz(d.year, d.month, 1, 0, 0, 0, 'Etc/GMT+12') + interval '1 month' + interval '7 days';

  select variant into v_variant from public.activity_sessions
   where user_id = v_user and challenge_id = d.id and not deleted and variant is not null
   order by started_at desc limit 1;

  insert into public.challenge_progress (user_id, challenge_id, numeric_progress, completed, completed_at, selected_variant, updated_at)
  values (v_user, d.id, v_progress, v_complete, case when v_complete then now() end, v_variant, now())
  on conflict (user_id, challenge_id) do update
     set numeric_progress = excluded.numeric_progress,
         completed = public.challenge_progress.completed or excluded.completed,
         completed_at = coalesce(public.challenge_progress.completed_at, excluded.completed_at),
         selected_variant = excluded.selected_variant,
         updated_at = now();

  if v_complete and now() <= v_close then
    insert into public.achievements (user_id, year, month, challenge_id)
    values (v_user, d.year, d.month, d.id)
    on conflict (user_id, year, month) do nothing;
  end if;

  select verified_at into v_verified from public.achievements
   where user_id = v_user and year = d.year and month = d.month;

  return jsonb_build_object(
    'challenge_id', d.id, 'progress', v_progress, 'target', d.completion_target,
    'completed', v_complete, 'verified_at', v_verified);
end $$;

-- Checks a finished board against the stored solution. A wrong board is
-- rejected; a right one is recorded once, however many times it is sent.
create or replace function public.submit_sudoku_solution(p_puzzle_id text, p_grid text, p_local_day date, p_hints int default 0)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_solution text;
  v_challenge text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform private.check_rate_limit('sudoku', 240);
  if p_grid is null or p_grid !~ '^[1-9]{81}$' then
    return jsonb_build_object('solved', false, 'reason', 'incomplete');
  end if;
  if p_local_day is null or p_local_day > (now() at time zone 'Pacific/Kiritimati')::date then
    raise exception 'invalid day' using errcode = '22008';
  end if;

  select solution into v_solution from private.sudoku_solutions where puzzle_id = p_puzzle_id;
  if v_solution is null then
    raise exception 'unknown puzzle' using errcode = '22023';
  end if;
  if v_solution <> p_grid then
    return jsonb_build_object('solved', false, 'reason', 'incorrect');
  end if;

  select id into v_challenge from public.challenge_definitions
   where module_type = 'sudoku' and year = extract(year from p_local_day)::int
     and month = extract(month from p_local_day)::int and reveal_at <= now();

  insert into public.sudoku_attempts (user_id, puzzle_id, challenge_id, current_grid, state, solved_at, local_day, hint_count)
  values (v_user, p_puzzle_id, v_challenge, p_grid, 'solved', now(), p_local_day, greatest(0, least(81, coalesce(p_hints, 0))))
  on conflict (user_id, puzzle_id) do update
     set current_grid = excluded.current_grid,
         state = 'solved',
         solved_at = coalesce(public.sudoku_attempts.solved_at, excluded.solved_at),
         local_day = coalesce(public.sudoku_attempts.local_day, excluded.local_day),
         challenge_id = coalesce(public.sudoku_attempts.challenge_id, excluded.challenge_id),
         hint_count = greatest(public.sudoku_attempts.hint_count, excluded.hint_count)
   where public.sudoku_attempts.state <> 'solved';

  return jsonb_build_object('solved', true);
end $$;

-- In-app account deletion. Removing the auth user cascades to every table.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from private.rate_limits where user_id = v_user;
  delete from auth.users where id = v_user;
end $$;

-- Everything a person has stored, as one JSON document (data export).
create or replace function public.export_my_data() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'interests', (select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb) from public.user_interests i where i.user_id = auth.uid()),
    'notification_preferences', (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb) from public.notification_preferences n where n.user_id = auth.uid()),
    'activity_sessions', (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) from public.activity_sessions s where s.user_id = auth.uid()),
    'journal_entries', (select coalesce(jsonb_agg(to_jsonb(j)), '[]'::jsonb) from public.journal_entries j where j.user_id = auth.uid()),
    'sudoku_attempts', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from public.sudoku_attempts a where a.user_id = auth.uid()),
    'discovery_interactions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.discovery_interactions x where x.user_id = auth.uid()),
    'challenge_progress', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.challenge_progress c where c.user_id = auth.uid()),
    'achievements', (select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb) from public.achievements h where h.user_id = auth.uid())
  );
$$;

-- A profile row for every new account.
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- Functions are not callable by default; grant exactly the public API.
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function public.claim_month_completion(text) to authenticated;
grant execute on function public.submit_sudoku_solution(text, text, date, int) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.export_my_data() to authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
