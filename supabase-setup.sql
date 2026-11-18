-- L'Escale 241 : tables, droits d'accès et données de départ
--
-- AVANT d'exécuter :
--   1. Remplacez VOTRE_EMAIL@exemple.com (ligne "insert into public.admins") par l'email
--      du compte administrateur que vous créerez dans Authentication > Users.
--   2. Collez tout le fichier dans Supabase > SQL Editor, puis cliquez sur Run.
-- Le fichier peut être relancé sans risque : il ne duplique pas les données.

-- ---------------------------------------------------------------
-- Compte administrateur
-- ---------------------------------------------------------------
create table if not exists public.admins (email text primary key);
insert into public.admins (email) values (lower('VOTRE_EMAIL@exemple.com')) on conflict do nothing;
alter table public.admins enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------
create table if not exists public.site_settings (
  key   text primary key,
  value text not null default ''
);

create table if not exists public.menu_categories (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  position     int  not null default 0,
  show_formula boolean not null default false,
  show_alcohol boolean not null default false
);

create table if not exists public.menu_items (
  id          uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.menu_categories(id) on delete cascade,
  name        text not null,
  description text not null default '',
  price       numeric(8,2),
  image_url   text not null default '',
  visible     boolean not null default true,
  position    int  not null default 0
);

create table if not exists public.opening_hours (
  day    smallint primary key check (day between 0 and 6),
  closed boolean not null default false,
  opens  time not null default '12:00',
  closes time not null default '05:00'
);

create table if not exists public.gallery_photos (
  id       uuid primary key default gen_random_uuid(),
  url      text not null,
  alt      text not null default '',
  position int  not null default 0
);

-- ---------------------------------------------------------------
-- Droits : tout le monde lit, seul l'administrateur écrit
-- ---------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['site_settings','menu_categories','menu_items','opening_hours','gallery_photos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "lecture publique" on public.%I', t);
    execute format('create policy "lecture publique" on public.%I for select to anon, authenticated using (true)', t);
    execute format('drop policy if exists "ecriture admin" on public.%I', t);
    execute format('create policy "ecriture admin" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
    execute format('grant select on public.%I to anon, authenticated', t);
    execute format('grant insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------
-- Stockage des photos
-- ---------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-images', 'site-images', true, 5242880, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = true;

drop policy if exists "images lecture" on storage.objects;
create policy "images lecture" on storage.objects
  for select to anon, authenticated using (bucket_id = 'site-images');

drop policy if exists "images ecriture admin" on storage.objects;
create policy "images ecriture admin" on storage.objects
  for all to authenticated
  using (bucket_id = 'site-images' and public.is_admin())
  with check (bucket_id = 'site-images' and public.is_admin());

-- ---------------------------------------------------------------
-- Données de départ (contenu actuel du site)
-- ---------------------------------------------------------------
insert into public.site_settings (key, value) values
  ('hero_tag', 'Restaurant · Bar · Ambiance de nuit'),
  ('hero_title', 'L''Escale 241'),
  ('hero_sub', 'Folong, bouillon de tripes et crabes, poisson au four, et des soirées avec DJ. Ouvert à Poitiers de midi à 05h du matin.'),
  ('hero_image', 'image_28.png'),
  ('menu_title', 'Nos spécialités et boissons'),
  ('formula_title', 'La formule'),
  ('formula_text', '4 boissons au choix, bières en bouteille ou jus, mélange libre.'),
  ('formula_price', '10'),
  ('alcohol_note', 'L''abus d''alcool est dangereux pour la santé, à consommer avec modération. La vente d''alcool aux mineurs de moins de 18 ans est interdite.'),
  ('events_title', 'La scène et les soirées'),
  ('events_text', 'L''Escale 241 change d''ambiance à la tombée de la nuit. Le week-end et lors des grandes occasions, la salle accueille des soirées avec DJ et des artistes invités.'),
  ('event1_title', 'DJ Mozes aux platines'),
  ('event1_text', 'Tous les week-ends, du son afro, hip-hop et généraliste.'),
  ('event2_title', 'Fêtes et artistes invités'),
  ('event2_text', 'Noël, Saint-Sylvestre, showcases. La programmation évolue au fil de l''année.'),
  ('events_badge', 'À venir'),
  ('events_overlay_title', 'Programmation bientôt disponible'),
  ('events_image', ''),
  ('galerie_title', 'L''ambiance en images'),
  ('infos_title', 'Horaires et accès'),
  ('phone', '07 55 23 22 45'),
  ('address_line1', '44 Rue de la Provence'),
  ('address_line2', '86000 Poitiers'),
  ('footer_text', 'Restaurant-bar de nuit à Poitiers. Spécialités africaines, bières et soirées avec DJ, du mardi au dimanche.'),
  ('legal_publisher', '[nom à compléter]'),
  ('legal_siret', '[numéro à compléter]')
on conflict (key) do nothing;

insert into public.opening_hours (day, closed, opens, closes) values
  (0, false, '12:00', '05:00'),
  (1, true,  '12:00', '05:00'),
  (2, false, '12:00', '05:00'),
  (3, false, '12:00', '05:00'),
  (4, false, '12:00', '05:00'),
  (5, false, '12:00', '05:00'),
  (6, false, '12:00', '05:00')
on conflict (day) do nothing;

do $$
declare
  c_plats uuid;
  c_acc   uuid;
  c_bois  uuid;
begin
  if not exists (select 1 from public.menu_categories) then
    insert into public.menu_categories (name, position, show_formula, show_alcohol)
      values ('Les plats', 0, false, false) returning id into c_plats;
    insert into public.menu_categories (name, position, show_formula, show_alcohol)
      values ('Accompagnements', 1, false, false) returning id into c_acc;
    insert into public.menu_categories (name, position, show_formula, show_alcohol)
      values ('Boissons et vins', 2, true, true) returning id into c_bois;

    insert into public.menu_items (category_id, name, description, price, image_url, position) values
      (c_plats, 'Folong aux crevettes et poisson fumé', 'Feuilles de folong mijotées, crevettes, morceaux de poisson fumé.', 15, 'image_26.png', 0),
      (c_plats, 'Bouillon tripes et crabes', 'Un bouillon piquant à base de tripes et de crabes.', 15, '', 1),
      (c_plats, 'Poisson au four', 'Poisson entier préparé et cuit au four.', 15, '', 2),
      (c_plats, 'Mouton (simple)', '', 15, '', 3),
      (c_plats, 'Ailes de poulet (simple)', '', 10, '', 4),

      (c_acc, 'Boule d''attiéké', '', 5, '', 0),
      (c_acc, 'Banane plantain', '', 2.5, '', 1),
      (c_acc, 'Manioc', '', 1.5, '', 2),

      (c_bois, 'Bières en bouteille', 'Leffe, Desperados, Heineken, Guinness.', 3, '', 0),
      (c_bois, 'Jus et softs', 'Coca-Cola, Fanta, Orangina, Red Bull, Sprite, Caraïbos litchi.', 2, '', 1),
      (c_bois, 'Eau', '', 1, '', 2),
      (c_bois, 'Régab', '', 6, '', 3),
      (c_bois, 'Booster', 'Whisky cola, Zombie, Banana mana.', 8, '', 4),
      (c_bois, 'Beaufort', '', 4, '', 5),
      (c_bois, 'Alcools Flash', '', 15, '', 6),
      (c_bois, 'Petit vin', '', 5, '', 7),
      (c_bois, 'Muscador', '', 10, '', 8),
      (c_bois, 'Grands vins (rosé et blanc)', '', 20, '', 9),
      (c_bois, 'Chardonnay', '', 20, '', 10),
      (c_bois, 'Clairette de Die', '', 25, '', 11),
      (c_bois, 'Baileys', '', 30, '', 12),
      (c_bois, 'Ballantine', '', 60, '', 13),
      (c_bois, 'Champagne Nicolas Feuillatte', '', 60, '', 14),
      (c_bois, 'Vodka', '', 70, '', 15),
      (c_bois, 'Chivas 18 ans', '', 90, '', 16),
      (c_bois, 'Champagne Veuve Clicquot', '', 100, '', 17);
  end if;

  if not exists (select 1 from public.gallery_photos) then
    insert into public.gallery_photos (url, alt, position)
      values ('image_26.png', 'Folong aux crevettes et poisson fumé', 0);
  end if;
end $$;
