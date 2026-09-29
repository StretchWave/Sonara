-- ==============================================================================
-- Migration: Delete Inactive Anonymous Users (Inactive for 5+ Days)
-- ==============================================================================
-- Automatically purges anonymous accounts that haven't been active for 5 days.
-- Cascade deletes all linked rows in public.playlists, public.playlist_tracks,
-- and public.user_preferences without orphaned rows or manual intervention.

-- 1. Create cleanup function with SECURITY DEFINER
create or replace function public.delete_inactive_anonymous_users()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    deleted_count integer := 0;
begin
    with deleted_users as (
        delete from auth.users
        where is_anonymous is true
          and coalesce(last_sign_in_at, created_at) < (now() - interval '5 days')
        returning id
    )
    select count(*) into deleted_count from deleted_users;

    return deleted_count;
end;
$$;

-- 2. Grant permissions
revoke execute on function public.delete_inactive_anonymous_users() from public;
grant execute on function public.delete_inactive_anonymous_users() to postgres, service_role, authenticated, anon;

-- 3. Schedule daily automated job using pg_cron (at 03:00 UTC every day)
do $$
begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
        perform cron.unschedule('delete-inactive-anonymous-users-daily');
        perform cron.schedule(
            'delete-inactive-anonymous-users-daily',
            '0 3 * * *',
            'select public.delete_inactive_anonymous_users();'
        );
    end if;
exception
    when others then
        raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end;
$$;
