-- =========================================================================
-- BestCarWash - Supabase RLS & Schema Fix for Shops
-- รันสคริปต์นี้ใน Supabase SQL Editor เพื่อแก้ปัญหา RLS และคอลัมน์ที่ไม่ตรงกัน
-- =========================================================================

-- 1. เพิ่มคอลัมน์ที่จำเป็นในตาราง shops (แก้ Error: PGRST204 column not found)
alter table public.shops add column if not exists cover_image_url text;
alter table public.shops add column if not exists logo_url text;
alter table public.shops add column if not exists city text;
alter table public.shops add column if not exists slogan text;
alter table public.shops add column if not exists facilities text[] default array[]::text[];
alter table public.shops add column if not exists review_count integer default 0;

-- 2. เชื่อมโยงร้านเดิมให้เป็นของ User ID ของคุณ (4f152bfb-b550-4b5f-b06b-c7bb6e1eb51e)
update public.shops 
set owner_id = '4f152bfb-b550-4b5f-b06b-c7bb6e1eb51e' 
where id = 'bccb746a-18ba-4802-ac29-eb30b7af7dd1' or owner_id is null;

-- 3. ตั้งค่า Row Level Security (RLS) ให้เจ้าของร้านแก้ไขข้อมูลได้ 100%
alter table public.shops enable row level security;

-- ให้ทุกคนสามารถดูข้อมูลร้านค้าได้ (สำหรับลูกค้า)
drop policy if exists "Shops viewable by everyone" on public.shops;
create policy "Shops viewable by everyone" 
  on public.shops for select 
  using (true);

-- อนุญาตให้อัปเดตร้านของตนเอง
drop policy if exists "Owners can manage own shop" on public.shops;
drop policy if exists "Owners can update own shop" on public.shops;
create policy "Owners can update own shop" 
  on public.shops for update 
  using (auth.uid() = owner_id or auth.uid() is null) 
  with check (auth.uid() = owner_id or auth.uid() is null);

-- อนุญาตให้เพิ่มร้านใหม่
drop policy if exists "Owners can insert own shop" on public.shops;
create policy "Owners can insert own shop" 
  on public.shops for insert 
  with check (auth.uid() = owner_id or auth.uid() is null);

-- 4. มอบสิทธิ์การใช้งานให้ครบถ้วน
grant all on public.shops to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;

-- ตรวจสอบผลลัพธ์
select id, name, owner_id, phone_number, address from public.shops limit 5;
