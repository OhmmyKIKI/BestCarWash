-- =========================================================================
-- BestCarWash - Supabase RLS & Schema Fix for Reviews & Shop Replies
-- รันสคริปต์นี้ใน Supabase SQL Editor เพื่อเปิดใช้งานการบันทึกการตอบกลับของร้านค้าลงฐานข้อมูล
-- =========================================================================

-- 1. เพิ่มคอลัมน์สำหรับการตอบกลับของร้านค้า (reply และ replied_at) และคอลัมน์รูปภาพรีวิว (images) ในตาราง reviews
alter table public.reviews 
  add column if not exists reply text,
  add column if not exists replied_at timestamp with time zone,
  add column if not exists images text[] default array[]::text[];

-- 2. เพิ่มคอลัมน์ review_count ในตาราง shops (ป้องกัน Error กรณีมี Trigger คำนวณจำนวนรีวิว)
alter table public.shops 
  add column if not exists review_count integer default 0;

-- 3. ตรวจสอบและเปิดใช้งาน Row Level Security (RLS) บนตาราง reviews
alter table public.reviews enable row level security;

-- 4. ให้ทุกคนสามารถอ่านรีวิวและการตอบกลับได้ (SELECT)
drop policy if exists "Reviews viewable by everyone" on public.reviews;
drop policy if exists "Public reviews are viewable by everyone" on public.reviews;
drop policy if exists "Allow select for all" on public.reviews;
drop policy if exists "Enable read access for all users" on public.reviews;

create policy "Reviews viewable by everyone" 
  on public.reviews for select 
  using (true);

-- 5. อนุญาตให้ลูกค้าสามารถเพิ่มรีวิวใหม่ได้ (INSERT)
drop policy if exists "Customers can insert reviews" on public.reviews;
drop policy if exists "Users can insert own reviews" on public.reviews;
drop policy if exists "Allow insert for authenticated users only" on public.reviews;
drop policy if exists "Enable insert for authenticated users only" on public.reviews;

create policy "Customers can insert reviews" 
  on public.reviews for insert 
  with check (auth.uid() = customer_id or auth.uid() is null or customer_id is not null);

-- 6. อนุญาตให้ลูกค้าแก้ไขรีวิวตนเอง และอนุญาตให้เจ้าของร้านตอบกลับรีวิวของร้านตนเองได้ (UPDATE)
drop policy if exists "Customers can update own reviews" on public.reviews;
drop policy if exists "Users can update own reviews" on public.reviews;
drop policy if exists "Enable update for users based on customer_id" on public.reviews;
drop policy if exists "Shop owners can reply to reviews" on public.reviews;
drop policy if exists "Allow review updates" on public.reviews;
drop policy if exists "Anyone can update reviews" on public.reviews;

create policy "Allow review updates" 
  on public.reviews for update 
  using (
    auth.uid() = customer_id 
    or exists (
      select 1 from public.shops 
      where shops.id = reviews.shop_id 
      and (shops.owner_id = auth.uid() or auth.uid() is null)
    )
    or auth.uid() is null
  )
  with check (
    auth.uid() = customer_id 
    or exists (
      select 1 from public.shops 
      where shops.id = reviews.shop_id 
      and (shops.owner_id = auth.uid() or auth.uid() is null)
    )
    or auth.uid() is null
  );

-- 7. มอบสิทธิ์การใช้งาน (Permissions) ให้แก่ anon, authenticated, service_role
grant all on public.reviews to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;

-- 8. สั่งให้ Supabase PostgREST รีโหลด Schema Cache ทันที
notify pgrst, 'reload schema';

-- 9. ตรวจสอบโครงสร้างคอลัมน์ของตาราง reviews
select column_name, data_type, is_nullable
from information_schema.columns 
where table_schema = 'public' and table_name = 'reviews'
order by ordinal_position;
