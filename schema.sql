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

-- Phase 7: user-created games
create table public.games (
  id text primary key,
  owner uuid not null references public.profiles(id) on delete cascade,
  owner_name text not null,
  title text not null check (char_length(title) between 1 and 40),
  data jsonb not null,
  published boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.games enable row level security;
create policy "games readable" on public.games for select using (published or auth.uid() = owner);
create policy "games insert own" on public.games for insert with check (auth.uid() = owner);
create policy "games update own" on public.games for update using (auth.uid() = owner) with check (auth.uid() = owner);
create policy "games delete own" on public.games for delete using (auth.uid() = owner);

-- Forum
create table public.forum_threads (
  id bigint generated always as identity primary key,
  category text not null check (category in ('General','Game Help','Creations','Off-Topic')),
  title text not null check (char_length(title) between 3 and 100),
  body text not null check (char_length(body) between 1 and 5000),
  author uuid not null references public.profiles(id) on delete cascade,
  author_name text not null default '',
  created_at timestamptz not null default now(),
  last_post timestamptz not null default now(),
  replies int not null default 0
);
create table public.forum_posts (
  id bigint generated always as identity primary key,
  thread_id bigint not null references public.forum_threads(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  author uuid not null references public.profiles(id) on delete cascade,
  author_name text not null default '',
  created_at timestamptz not null default now()
);
alter table public.forum_threads enable row level security;
alter table public.forum_posts enable row level security;
create policy "threads readable" on public.forum_threads for select using (true);
create policy "threads insert own" on public.forum_threads for insert with check (auth.uid() = author);
create policy "threads delete own" on public.forum_threads for delete using (auth.uid() = author);
create policy "posts readable" on public.forum_posts for select using (true);
create policy "posts insert own" on public.forum_posts for insert with check (auth.uid() = author);
create policy "posts delete own" on public.forum_posts for delete using (auth.uid() = author);

-- The server fills in the author name so nobody can post under someone else's name.
create function public.forum_set_author() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.author_name := (select username from public.profiles where id = new.author);
  return new;
end $$;
create trigger threads_author before insert on public.forum_threads for each row execute function public.forum_set_author();
create trigger posts_author before insert on public.forum_posts for each row execute function public.forum_set_author();

-- Keep reply counts and "last post" times up to date.
create function public.forum_bump() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.forum_threads set replies = replies + 1, last_post = now() where id = new.thread_id;
  return new;
end $$;
create trigger posts_bump after insert on public.forum_posts for each row execute function public.forum_bump();
