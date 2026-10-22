-- =========================================================================
-- BestCarWash - Supabase RLS & Schema Fix for Reviews
-- รันสคริปต์นี้ใน Supabase SQL Editor เพื่อแก้ปัญหา RLS ตาราง reviews
-- =========================================================================

-- 1. ตรวจสอบและเปิดใช้งาน Row Level Security (RLS) บนตาราง reviews
alter table public.reviews enable row level security;

-- 2. ให้ทุกคนสามารถอ่านรีวิวได้ (เพื่อแสดงในหน้ารายละเอียดร้านและหน้าประวัติการจอง)
drop policy if exists "Reviews viewable by everyone" on public.reviews;
drop policy if exists "Public reviews are viewable by everyone" on public.reviews;
drop policy if exists "Allow select for all" on public.reviews;
drop policy if exists "Enable read access for all users" on public.reviews;
create policy "Reviews viewable by everyone" 
  on public.reviews for select 
  using (true);

-- 3. อนุญาตให้ลูกค้าสามารถเพิ่มรีวิวได้ (รองรับทั้งผู้ใช้ที่ล็อกอินและลูกค้าทั่วไป)
drop policy if exists "Customers can insert reviews" on public.reviews;
drop policy if exists "Users can insert own reviews" on public.reviews;
drop policy if exists "Allow insert for authenticated users only" on public.reviews;
drop policy if exists "Enable insert for authenticated users only" on public.reviews;
create policy "Customers can insert reviews" 
  on public.reviews for insert 
  with check (auth.uid() = customer_id or auth.uid() is null or customer_id is not null);

-- 4. อนุญาตให้ลูกค้าแก้ไขรีวิวของตนเองได้
drop policy if exists "Customers can update own reviews" on public.reviews;
drop policy if exists "Users can update own reviews" on public.reviews;
drop policy if exists "Enable update for users based on customer_id" on public.reviews;
create policy "Customers can update own reviews" 
  on public.reviews for update 
  using (auth.uid() = customer_id or auth.uid() is null) 
  with check (auth.uid() = customer_id or auth.uid() is null);

-- 5. มอบสิทธิ์การใช้งาน (Permissions) ให้แก่ anon, authenticated, service_role
grant all on public.reviews to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;

-- 6. ตรวจสอบผลลัพธ์
select count(*) as total_reviews from public.reviews;
