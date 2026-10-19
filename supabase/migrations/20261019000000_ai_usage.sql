-- Daily request counts per user for the AI edge functions (coach, progress),
-- so a leaked anon key can't run unlimited Claude calls.
-- Only the edge functions (service role) touch this table: RLS is on and
-- there are no policies, so anon/authenticated clients can't read or write it.

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  "function" text not null,
  count integer not null default 0,
  primary key (user_id, day, "function")
);

alter table public.ai_usage enable row level security;

-- Adds one request and returns whether the user is still within the limit.
create or replace function public.increment_ai_usage(p_user uuid, p_function text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count integer;
begin
  insert into public.ai_usage (user_id, day, "function", count)
  values (p_user, (now() at time zone 'utc')::date, p_function, 1)
  on conflict (user_id, day, "function")
  do update set count = public.ai_usage.count + 1
  returning count into new_count;
  return new_count <= p_limit;
end;
$$;

revoke all on function public.increment_ai_usage(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.increment_ai_usage(uuid, text, integer) to service_role;
