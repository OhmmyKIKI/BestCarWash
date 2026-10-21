-- =========================================================================
-- BestCarWash - Supabase RLS Fix for Bookings & Booking Services
-- รันสคริปต์นี้ใน Supabase SQL Editor เพื่อแก้ปัญหาการจองไม่เข้าฐานข้อมูล
-- และทำให้หน้าเจ้าของร้าน (owner-bookings) ดึงข้อมูลการจองได้ 100%
-- =========================================================================

-- 1. เพิ่มคอลัมน์เสริมในตาราง bookings (ถ้ายังไม่มี เพื่อความสมบูรณ์ของข้อมูล)
alter table public.bookings add column if not exists customer_phone text;
alter table public.bookings add column if not exists notes text;
alter table public.bookings add column if not exists slip_url text;
alter table public.bookings add column if not exists deposit_amount numeric(10,2) default 50.00;
alter table public.bookings add column if not exists service_name text;

-- 2. ปรับ Check Constraint ของ status ให้รองรับสถานะการทำงานครบวงจร
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check 
  check (status in ('PENDING', 'CONFIRMED', 'ARRIVED', 'WASHING', 'READY', 'COMPLETED', 'CANCELLED', 'REFUND_REQUESTED', 'REFUNDED', 'NO_SHOW'));

-- 3. ตั้งค่า Row Level Security (RLS) ของตาราง bookings
alter table public.bookings enable row level security;

-- ให้ทุกคนสามารถดูรายการจองได้ (ทั้งเจ้าของร้านและลูกค้า)
drop policy if exists "Users can view own bookings" on public.bookings;
drop policy if exists "Bookings viewable by everyone" on public.bookings;
create policy "Bookings viewable by everyone" 
  on public.bookings for select 
  using (true);

-- ให้ลูกค้าและผู้ใช้งานทุกคนสามารถกดสร้างรายการจองเข้ามาได้
drop policy if exists "Customers can create bookings" on public.bookings;
drop policy if exists "Anyone can create bookings" on public.bookings;
create policy "Anyone can create bookings" 
  on public.bookings for insert 
  with check (true);

-- ให้เจ้าของร้านและลูกค้าสามารถอัปเดตสถานะการจอง (ยืนยันคิว / ล้างรถ / คืนเงิน) ได้
drop policy if exists "Participants can update bookings" on public.bookings;
drop policy if exists "Anyone can update bookings" on public.bookings;
create policy "Anyone can update bookings" 
  on public.bookings for update 
  using (true) 
  with check (true);

-- 4. ตั้งค่า RLS ของตาราง booking_services
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'booking_services') then
    alter table public.booking_services enable row level security;

    drop policy if exists "Booking services viewable by booking participants" on public.booking_services;
    drop policy if exists "Booking services viewable by everyone" on public.booking_services;
    create policy "Booking services viewable by everyone" 
      on public.booking_services for select 
      using (true);

    drop policy if exists "Customers can insert booking services" on public.booking_services;
    drop policy if exists "Anyone can insert booking services" on public.booking_services;
    create policy "Anyone can insert booking services" 
      on public.booking_services for insert 
      with check (true);

    grant all on public.booking_services to anon, authenticated, service_role;
  end if;
end $$;

-- 5. มอบสิทธิ์การใช้งานให้ anon, authenticated, service_role เต็มรูปแบบ
grant all on public.bookings to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;

-- 6. ตรวจสอบโครงสร้างและรายการจองปัจจุบัน
select column_name, data_type from information_schema.columns where table_schema = 'public' and table_name = 'bookings';
select count(*) as total_bookings from public.bookings;
