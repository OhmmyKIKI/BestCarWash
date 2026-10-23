-- =========================================================================
-- BestCarWash: ตั้งค่า Supabase Storage และตารางร้านค้า (สำหรับรูปปกร้านและแกลเลอรี)
-- รันสคริปต์นี้ใน Supabase SQL Editor (รันเพียง 1 ครั้ง)
-- =========================================================================

-- 1. เพิ่มคอลัมน์เก็บรูปภาพในตาราง shops (ถ้ายังไม่มี)
alter table public.shops add column if not exists cover_image_url text;
alter table public.shops add column if not exists logo_url text;
alter table public.shops add column if not exists gallery text[] default array[]::text[];

-- 2. สร้าง Storage Bucket ชื่อ 'shop-media' และตั้งค่าให้เป็น Public
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'shop-media',
  'shop-media',
  true,
  52428800, -- รองรับไฟล์ขนาดสูงสุด 50 MB
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml']
)
on conflict (id) do update set 
  public = true,
  file_size_limit = 52428800;

-- 3. ตั้งค่านโยบายความปลอดภัย (RLS Policies) สำหรับ Storage Bucket 'shop-media'
-- นโยบายที่ 1: อนุญาตให้ทุกคนเปิดดู/ดาวน์โหลดรูปภาพได้ (Public Read)
drop policy if exists "Public Access for shop-media" on storage.objects;
create policy "Public Access for shop-media"
on storage.objects for select
using (bucket_id = 'shop-media');

-- นโยบายที่ 2: อนุญาตให้อัปโหลดรูปภาพได้ (Upload)
drop policy if exists "Allow upload to shop-media" on storage.objects;
create policy "Allow upload to shop-media"
on storage.objects for insert
with check (bucket_id = 'shop-media');

-- นโยบายที่ 3: อนุญาตให้อัปเดตรูปภาพได้ (Update)
drop policy if exists "Allow update in shop-media" on storage.objects;
create policy "Allow update in shop-media"
on storage.objects for update
using (bucket_id = 'shop-media');

-- นโยบายที่ 4: อนุญาตให้ลบรูปภาพได้ (Delete)
drop policy if exists "Allow delete in shop-media" on storage.objects;
create policy "Allow delete in shop-media"
on storage.objects for delete
using (bucket_id = 'shop-media');

-- 4. มอบสิทธิ์การเข้าถึงข้อมูล (Permissions) ให้แก่ anon, authenticated, service_role
grant all on public.shops to anon, authenticated, service_role;
grant all on schema storage to anon, authenticated, service_role;
grant all on storage.objects to anon, authenticated, service_role;
grant all on storage.buckets to anon, authenticated, service_role;

-- 5. ตรวจสอบสถานะผลลัพธ์
select id, name, public from storage.buckets where id = 'shop-media';
