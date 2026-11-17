-- Security and reward-integrity tests. Run by supabase/tests/run_local.sh
-- (and by CI) against a throwaway database. Any failed assertion aborts.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

-- ---------------------------------------------------------------- fixtures
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@example.com'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@example.com');

-- A revealed test month (the current one) and helpers to act as a user.
insert into public.challenge_definitions (id, year, month, title, category, story, completion_target, unit, module_type, metric, entry_kind, reveal_at)
values ('test-count', extract(year from now())::int, extract(month from now())::int, 'Test', 'Test', 'Test', 2, 'acts', 'reflection', 'count', 'kindness', now() - interval '1 day');

create schema test;
create or replace function test.expect_error(p_sql text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    return;
  end;
  raise exception 'SECURITY TEST FAILED (expected an error): %', p_label;
end $$;

create or replace function test.expect(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'TEST FAILED: %', p_label; end if;
end $$;
grant usage on schema test to anon, authenticated;
grant execute on all functions in schema test to anon, authenticated;

select test.expect((select count(*) = 2 from public.profiles), 'a profile is created for every new account');

-- ------------------------------------------------------------ as user A
set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);

insert into public.journal_entries (id, challenge_id, kind, entry_at, local_day, body)
values ('a0000000-0000-0000-0000-000000000001', 'test-count', 'kindness', now(), (now() at time zone 'UTC')::date - 0, 'private note one');

select test.expect((select count(*) = 1 from public.journal_entries), 'A sees own entry');
select test.expect((select count(*) = 0 from public.challenge_definitions where id like '2027-%'), 'future challenges cannot be read early');
select test.expect((select count(*) = 1 from public.challenge_definitions), 'revealed challenge is readable');
select test.expect_error($$ select * from private.sudoku_solutions $$, 'solutions are unreadable');
select test.expect_error($$ insert into public.achievements (user_id, year, month, challenge_id) values (auth.uid(), 2027, 1, 'test-count') $$, 'clients cannot grant themselves achievements');
select test.expect_error($$ insert into public.challenge_progress (user_id, challenge_id, numeric_progress, completed) values (auth.uid(), 'test-count', 99, true) $$, 'clients cannot write progress totals');
select test.expect_error($$ insert into public.journal_entries (id, user_id, challenge_id, kind, entry_at, local_day) values (gen_random_uuid(), 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'test-count', 'kindness', now(), current_date) $$, 'cannot insert rows for another user');
select test.expect_error($$ insert into public.journal_entries (id, challenge_id, kind, entry_at, local_day) values (gen_random_uuid(), 'test-count', 'kindness', now(), current_date + 3) $$, 'future-dated activity is rejected');
select test.expect_error($$ insert into public.activity_sessions (id, challenge_id, kind, started_at, ended_at, elapsed_seconds, local_day) values (gen_random_uuid(), 'test-count', 'plank', now() - interval '3 hours', now(), 5000, current_date - 1) $$, 'implausible plank duration is rejected');
select test.expect_error($$ insert into public.activity_sessions (id, challenge_id, kind, started_at, ended_at, elapsed_seconds, local_day) values (gen_random_uuid(), 'test-count', 'plank', now() - interval '10 seconds', now(), 600, current_date - 1) $$, 'active time longer than the session is rejected');
select test.expect_error($$ insert into public.activity_sessions (id, challenge_id, kind, started_at, ended_at, elapsed_seconds, local_day) values (gen_random_uuid(), 'test-count', 'plank', now(), now(), -5, current_date - 1) $$, 'negative duration is rejected');
select test.expect_error($$ select public.claim_month_completion('2027-12') $$, 'cannot claim an unrevealed challenge');
select test.expect_error($$ update public.profiles set joined_at = now() - interval '1 year' $$, 'joined_at is not client-writable');

-- Not complete yet: one of two.
select test.expect((public.claim_month_completion('test-count') ->> 'completed')::boolean = false, 'one entry does not complete a two-entry goal');
select test.expect((select count(*) = 0 from public.achievements), 'no achievement before completion');

insert into public.journal_entries (id, challenge_id, kind, entry_at, local_day, body)
values ('a0000000-0000-0000-0000-000000000002', 'test-count', 'kindness', now(), (now() at time zone 'UTC')::date, 'private note two');
-- Re-sending the same entry (same id) must not double count.
insert into public.journal_entries (id, challenge_id, kind, entry_at, local_day, body)
values ('a0000000-0000-0000-0000-000000000002', 'test-count', 'kindness', now(), (now() at time zone 'UTC')::date, 'private note two')
on conflict (id) do update set body = excluded.body;

select test.expect((public.claim_month_completion('test-count') ->> 'completed')::boolean, 'two entries complete the goal');
select public.claim_month_completion('test-count');
select public.claim_month_completion('test-count');
select test.expect((select count(*) = 1 from public.achievements), 'repeated claims create exactly one achievement');
select test.expect((select numeric_progress = 2 from public.challenge_progress), 'progress is recomputed on the server');

-- Sudoku: only a correct board counts, and only once.
select test.expect((public.submit_sudoku_solution('t1', repeat('1', 81), current_date - 1) ->> 'solved')::boolean = false, 'incorrect board is not accepted');
select test.expect((select count(*) = 0 from public.sudoku_attempts), 'incorrect board leaves no solved attempt');
insert into public.sudoku_attempts (puzzle_id, current_grid) values ('t1', repeat('0', 81));
-- The app saves work in progress with an upsert.
insert into public.sudoku_attempts (puzzle_id, current_grid, hint_count) values ('t1', repeat('0', 81), 1)
  on conflict (user_id, puzzle_id) do update set puzzle_id = excluded.puzzle_id, current_grid = excluded.current_grid, hint_count = excluded.hint_count;
select test.expect((select hint_count = 1 from public.sudoku_attempts), 'in-progress upsert works');
select test.expect_error($$ update public.sudoku_attempts set state = 'solved', solved_at = now() $$, 'clients cannot mark a puzzle solved');
select test.expect((public.submit_sudoku_solution('t1', '534678912672195348198342567859761423426853791713924856961537284287419635345286179', current_date - 1) ->> 'solved')::boolean, 'correct board is accepted');
select public.submit_sudoku_solution('t1', '534678912672195348198342567859761423426853791713924856961537284287419635345286179', current_date - 1);
select test.expect((select count(*) = 1 from public.sudoku_attempts where state = 'solved'), 'a puzzle is solved exactly once');
update public.sudoku_attempts set current_grid = repeat('0', 81);
select test.expect((select count(*) = 1 from public.sudoku_attempts where state = 'solved' and current_grid <> repeat('0', 81)), 'a solved attempt can no longer be edited by the client');

select test.expect((public.export_my_data() -> 'journal_entries') @> '[{"body":"private note one"}]'::jsonb, 'export contains own data');

-- ------------------------------------------------------------ as user B
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false);
select test.expect((select count(*) = 0 from public.journal_entries), 'B cannot read A''s journal');
select test.expect((select count(*) = 0 from public.achievements), 'B cannot read A''s achievements');
select test.expect((select count(*) = 0 from public.sudoku_attempts), 'B cannot read A''s attempts');
select test.expect((select count(*) = 1 from public.profiles), 'B sees only own profile');
update public.journal_entries set body = 'tampered';
delete from public.user_interests;
select test.expect_error($$ delete from public.journal_entries $$, 'hard delete of activity is not granted');
select test.expect(jsonb_array_length(public.export_my_data() -> 'journal_entries') = 0, 'B''s export contains none of A''s data');
select test.expect((public.claim_month_completion('test-count') ->> 'completed')::boolean = false, 'B does not inherit A''s progress');

-- ------------------------------------------------------------ as anonymous
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select test.expect_error($$ select * from public.journal_entries $$, 'anon cannot read journals');
select test.expect_error($$ select * from public.profiles $$, 'anon cannot read profiles');
select test.expect_error($$ select * from public.achievements $$, 'anon cannot read achievements');
select test.expect_error($$ select public.claim_month_completion('test-count') $$, 'anon cannot claim');
select test.expect_error($$ select public.delete_my_account() $$, 'anon cannot call account deletion');
select test.expect_error($$ select * from private.sudoku_solutions $$, 'anon cannot read solutions');
select test.expect((select count(*) = 0 from public.challenge_definitions where reveal_at > now()), 'anon cannot read future challenges');

-- ------------------------------------------------------------ back as owner
reset role;
select test.expect((select body = 'private note one' from public.journal_entries where id = 'a0000000-0000-0000-0000-000000000001'), 'B''s update did not touch A''s rows');
select test.expect_error($$ update public.challenge_definitions set completion_target = 1 where id = 'test-count' $$, 'criteria are frozen once a month has started');
update public.challenge_definitions set story = 'Edited copy' where id = 'test-count';

-- Account deletion removes A's personal data and leaves B's account alone.
set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
select public.delete_my_account();
reset role;
select test.expect((select count(*) = 0 from public.journal_entries), 'deletion removes journal entries');
select test.expect((select count(*) = 0 from public.achievements), 'deletion removes achievements');
select test.expect((select count(*) = 0 from public.sudoku_attempts), 'deletion removes attempts');
select test.expect((select count(*) = 0 from public.challenge_progress where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'deletion removes progress');
select test.expect((select count(*) = 1 from public.profiles), 'only B''s profile remains');
select test.expect((select count(*) = 1 from auth.users), 'only B''s account remains');

-- Seeded content sanity.
select test.expect((select count(*) = 12 from public.challenge_definitions where year = 2027), 'twelve challenges are seeded');
select test.expect((select min(n) >= 20 from (select count(*) n from public.discovery_cards group by category) s), 'at least 20 cards per category');
select test.expect((select count(*) from public.sudoku_puzzles where id <> 't1') = (select count(*) from private.sudoku_solutions where puzzle_id <> 't1'), 'every puzzle has a stored solution');

\o
\echo ALL DATABASE TESTS PASSED
