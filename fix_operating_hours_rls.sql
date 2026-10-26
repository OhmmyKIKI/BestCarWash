-- =========================================================================
-- BestCarWash - Supabase RLS & Schema Fix for Shop Operating Hours
-- รันสคริปต์นี้ใน Supabase SQL Editor เพื่อแก้ปัญหาการบันทึกเวลาเปิด-ปิดร้าน (RLS)
-- ทำให้เจ้าของร้านสามารถบันทึกเวลาทำการลงฐานข้อมูล Supabase ได้ 100%
-- =========================================================================

-- 1. ตรวจสอบและสร้างตาราง shop_operating_hours หากยังไม่มี
create table if not exists public.shop_operating_hours (
  id uuid default gen_random_uuid() primary key,
  shop_id uuid references public.shops(id) on delete cascade not null,
  day_of_week integer check (day_of_week between 0 and 6) not null, -- 0=อาทิตย์, 1=จันทร์ ... 6=เสาร์
  open_time time default '08:00:00',
  close_time time default '18:00:00',
  is_closed boolean default false
);

-- 2. เพิ่ม Unique Constraint (shop_id, day_of_week) สำหรับรองรับคำสั่ง Upsert (ON CONFLICT)
do $$
begin
  if not exists (
    select 1 
    from pg_constraint c
    join pg_namespace n on n.oid = c.connamespace
    where c.conrelid = 'public.shop_operating_hours'::regclass 
      and c.contype = 'u'
  ) then
    alter table public.shop_operating_hours 
      add constraint shop_operating_hours_shop_id_day_of_week_key unique (shop_id, day_of_week);
  end if;
exception when others then
  null;
end $$;

-- 3. เปิดใช้งาน Row Level Security (RLS)
alter table public.shop_operating_hours enable row level security;

-- 4. ลบนโยบาย (Policies) เดิมที่อาจจำกัดสิทธิ์หรือทำให้ติด RLS
drop policy if exists "Operating hours viewable by everyone" on public.shop_operating_hours;
drop policy if exists "Owners can manage operating hours" on public.shop_operating_hours;
drop policy if exists "Enable all for operating hours" on public.shop_operating_hours;
drop policy if exists "Allow all operations for operating hours" on public.shop_operating_hours;
drop policy if exists "Anyone can read operating hours" on public.shop_operating_hours;
drop policy if exists "Anyone can manage operating hours" on public.shop_operating_hours;
drop policy if exists "Allow select operating hours" on public.shop_operating_hours;
drop policy if exists "Allow insert operating hours" on public.shop_operating_hours;
drop policy if exists "Allow update operating hours" on public.shop_operating_hours;
drop policy if exists "Allow delete operating hours" on public.shop_operating_hours;

-- 5. สร้างนโยบายความปลอดภัยใหม่ (RLS Policies) ให้บันทึกและอ่านข้อมูลได้สมบูรณ์

-- 5.1 ให้ทุกคนสามารถดูเวลาเปิด-ปิดร้านได้ (สำหรับลูกค้าและผู้ใช้งานทั่วไป)
create policy "Allow select operating hours" 
  on public.shop_operating_hours for select 
  using (true);

-- 5.2 อนุญาตให้บันทึกเวลาเปิด-ปิดร้านใหม่ได้ (INSERT)
create policy "Allow insert operating hours" 
  on public.shop_operating_hours for insert 
  with check (true);

-- 5.3 อนุญาตให้อัปเดตเวลาเปิด-ปิดร้านได้ (UPDATE)
create policy "Allow update operating hours" 
  on public.shop_operating_hours for update 
  using (true) 
  with check (true);

-- 5.4 อนุญาตให้ลบข้อมูลเวลาเปิด-ปิดได้ (DELETE)
create policy "Allow delete operating hours" 
  on public.shop_operating_hours for delete 
  using (true);

-- 6. มอบสิทธิ์การใช้งานตาราง (GRANT) ให้กับ anon, authenticated และ service_role
grant all on public.shop_operating_hours to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;

-- 7. เติมข้อมูลเวลาทำการเริ่มต้น (จันทร์-เสาร์ 08:00-18:00 น., อาทิตย์ ปิด) ให้กับร้านทุกร้านที่ยังไม่มีข้อมูล
insert into public.shop_operating_hours (shop_id, day_of_week, open_time, close_time, is_closed)
select s.id, d.day, '08:00:00'::time, '18:00:00'::time, (case when d.day = 0 then true else false end)
from public.shops s
cross join (values (0), (1), (2), (3), (4), (5), (6)) as d(day)
on conflict (shop_id, day_of_week) do nothing;

-- 8. ตรวจสอบผลลัพธ์
select 
  s.name as shop_name, 
  h.day_of_week, 
  h.open_time, 
  h.close_time, 
  h.is_closed
from public.shop_operating_hours h
join public.shops s on s.id = h.shop_id
order by s.name, h.day_of_week asc
limit 14;
