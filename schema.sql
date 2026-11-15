-- BLOCKLAND Phase 6 schema. Run once in Supabase: SQL Editor > New query > paste > Run.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  avatar jsonb,
  created_at timestamptz not null default now()
);
create unique index profiles_username_lower on public.profiles (lower(username));

create table public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_id text not null,
  primary key (user_id, game_id)
);

create table public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table public.recent_plays (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_id text not null,
  played_at timestamptz not null default now(),
  primary key (user_id, game_id)
);

alter table public.profiles enable row level security;
alter table public.favorites enable row level security;
alter table public.friendships enable row level security;
alter table public.recent_plays enable row level security;

-- Anyone can look up usernames; only you can edit your own profile.
create policy "profiles readable" on public.profiles for select using (true);
create policy "profiles update own" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- Private per-user lists.
create policy "favorites own" on public.favorites for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "friendships own" on public.friendships for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "recent own" on public.recent_plays for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Create the profile automatically at registration (username comes from signup metadata).
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username) values (new.id, new.raw_user_meta_data->>'username');
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();
