-- =========================================================================
-- BestCarWash - Supabase Schema & Database Initialization
-- ระบบฐานข้อมูลสำหรับแพลตฟอร์มค้นหาและจองบริการล้างรถ (BestCarWash)
-- คัดลอกสคริปต์นี้ไปรันใน Supabase SQL Editor ได้ทันที
-- =========================================================================

-- 0. เปิดใช้งาน Extensions ที่จำเป็น
create extension if not exists "uuid-ossp";

-- =========================================================================
-- 1. ตาราง Profiles (เก็บข้อมูลส่วนตัวของผู้ใช้ ขยายจาก auth.users)
-- =========================================================================
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  role text check (role in ('CUSTOMER', 'OWNER')) not null default 'CUSTOMER',
  full_name text,
  phone_number text,
  avatar_url text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =========================================================================
-- 2. ตาราง Vehicles (เก็บข้อมูลยานพาหนะของลูกค้า)
-- =========================================================================
create table if not exists public.vehicles (
  id uuid default uuid_generate_v4() primary key,
  customer_id uuid references public.profiles(id) on delete cascade not null,
  brand_model text not null,               -- เช่น Honda Civic, Toyota Fortuner
  plate_number text not null,              -- เช่น 9กต 9999 กทม
  car_size text check (car_size in ('S', 'M', 'L', 'XL')) default 'M', -- ขนาดรถ
  is_default boolean default false,        -- เป็นรถคันหลักหรือไม่
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =========================================================================
-- 3. ตาราง Shops (เก็บข้อมูลร้านคาร์แคร์)
-- =========================================================================
create table if not exists public.shops (
  id uuid default uuid_generate_v4() primary key,
  owner_id uuid references public.profiles(id) on delete cascade not null,
  name text not null,
  slogan text,                             -- คำโปรยร้านสั้นๆ
  description text,                        -- รายละเอียดร้าน
  address text,                            -- ที่อยู่ร้าน
  city text,                               -- จังหวัด/อำเภอ
  latitude double precision,               -- ละติจูดสำหรับแผนที่
  longitude double precision,              -- ลองจิจูดสำหรับแผนที่
  phone_number text,                       -- เบอร์โทรติดต่อร้าน
  logo_url text,                           -- รูปโลโก้ร้าน
  cover_image_url text,                    -- ภาพหน้าปกร้าน
  is_open boolean default true,            -- สถานะเปิด/ปิดร้าน
  rating numeric(3,2) default 0.0,         -- คะแนนเฉลี่ย (0.00 - 5.00)
  review_count integer default 0,          -- จำนวนรีวิวทั้งหมด
  facilities text[] default array[]::text[], -- สิ่งอำนวยความสะดวก เช่น wifi, lounge, coffee
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =========================================================================
-- 4. ตาราง Shop Operating Hours (เวลาเปิด-ปิดร้านแต่ละวัน)
-- =========================================================================
create table if not exists public.shop_operating_hours (
  id uuid default uuid_generate_v4() primary key,
  shop_id uuid references public.shops(id) on delete cascade not null,
  day_of_week integer check (day_of_week between 0 and 6) not null, -- 0=อาทิตย์, 1=จันทร์ ... 6=เสาร์
  open_time time default '08:00:00',
  close_time time default '18:00:00',
  is_closed boolean default false,         -- วันหยุดประจำสัปดาห์
  unique(shop_id, day_of_week)
);

-- =========================================================================
-- 5. ตาราง Services (บริการและราคาของแต่ละร้าน)
-- =========================================================================
create table if not exists public.services (
  id uuid default uuid_generate_v4() primary key,
  shop_id uuid references public.shops(id) on delete cascade not null,
  name text not null,                      -- ชื่อบริการ เช่น ล้างสีดูดฝุ่น, เคลือบแก้ว
  description text,
  category text default 'ล้างทำความสะอาด',
  price numeric(10,2) not null,            -- ราคาเริ่มต้น/ราคาหลัก
  price_s numeric(10,2),                   -- ราคาสำหรับรถขนาด S
  price_m numeric(10,2),                   -- ราคาสำหรับรถขนาด M
  price_l numeric(10,2),                   -- ราคาสำหรับรถขนาด L
  price_xl numeric(10,2),                  -- ราคาสำหรับรถขนาด XL
  duration_minutes integer default 30 not null, -- ระยะเวลา (นาที)
  is_active boolean default true,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =========================================================================
-- 6. ตาราง Bookings (การจองคิว)
-- =========================================================================
create table if not exists public.bookings (
  id uuid default uuid_generate_v4() primary key,
  customer_id uuid references public.profiles(id) on delete cascade not null,
  shop_id uuid references public.shops(id) on delete cascade not null,
  status text check (status in ('PENDING', 'CONFIRMED', 'COMPLETED', 'CANCELLED')) default 'PENDING' not null,
  booking_date date not null,
  booking_time time not null,
  vehicle_info text not null,              -- ข้อมูลรถที่นำมารับบริการ
  total_price numeric(10,2) not null,      -- ราคารวมทั้งหมด
  customer_phone text,                     -- เบอร์ติดต่อลูกค้า ณ วันที่จอง
  notes text,                              -- หมายเหตุเพิ่มเติมจากลูกค้า
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =========================================================================
-- 7. ตาราง Booking Services (รายการบริการในการจอง 1 ครั้ง - Many-to-Many)
-- =========================================================================
create table if not exists public.booking_services (
  booking_id uuid references public.bookings(id) on delete cascade not null,
  service_id uuid references public.services(id) on delete cascade not null,
  price numeric(10,2) not null,            -- บันทึกราคา ณ ตอนจอง
  primary key (booking_id, service_id)
);

-- =========================================================================
-- 8. ตาราง Reviews (รีวิวและการให้คะแนน)
-- =========================================================================
create table if not exists public.reviews (
  id uuid default uuid_generate_v4() primary key,
  booking_id uuid references public.bookings(id) on delete set null,
  customer_id uuid references public.profiles(id) on delete cascade not null,
  shop_id uuid references public.shops(id) on delete cascade not null,
  rating integer check (rating >= 1 and rating <= 5) not null,
  comment text,
  reply text,                              -- การตอบกลับจากร้านค้า
  replied_at timestamp with time zone,     -- วันเวลาที่ร้านค้าตอบกลับ
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =========================================================================
-- 9. ตาราง Favorite Shops (ร้านโปรดของลูกค้า)
-- =========================================================================
create table if not exists public.favorite_shops (
  customer_id uuid references public.profiles(id) on delete cascade not null,
  shop_id uuid references public.shops(id) on delete cascade not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  primary key (customer_id, shop_id)
);

-- =========================================================================
-- 10. ตาราง Notifications (การแจ้งเตือน)
-- =========================================================================
create table if not exists public.notifications (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  title text not null,
  message text not null,
  is_read boolean default false,
  type text not null default 'BOOKING_UPDATE', -- 'BOOKING_UPDATE', 'SYSTEM'
  related_booking_id uuid references public.bookings(id) on delete set null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- =========================================================================
-- 11. ออโต้ทริกเกอร์: สร้าง Profile, ร้านค้า และรถยนต์อัตโนมัติเมื่อสมัครสมาชิก
-- (เชื่อมต่อจาก auth.users มายัง public.profiles โดยตรง)
-- =========================================================================
create or replace function public.handle_new_user()
returns trigger as $$
declare
  user_role text;
  user_full_name text;
  user_phone text;
  user_shop_name text;
  user_vehicle_model text;
  user_license_plate text;
begin
  -- ดึงข้อมูลจาก user_metadata
  user_role := coalesce(new.raw_user_meta_data->>'role', 'CUSTOMER');
  user_full_name := coalesce(new.raw_user_meta_data->>'full_name', '');
  user_phone := coalesce(new.raw_user_meta_data->>'phone_number', '');
  user_shop_name := coalesce(new.raw_user_meta_data->>'shop_name', 'ร้านของฉัน');
  user_vehicle_model := new.raw_user_meta_data->>'vehicle_model';
  user_license_plate := new.raw_user_meta_data->>'license_plate';

  -- 1. สร้าง Profile
  insert into public.profiles (id, role, full_name, phone_number, avatar_url)
  values (
    new.id,
    user_role,
    user_full_name,
    user_phone,
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do update set
    role = excluded.role,
    full_name = excluded.full_name,
    phone_number = excluded.phone_number;

  -- 2. ถ้าเป็นเจ้าของร้าน (OWNER) สร้างข้อมูลร้านเริ่มต้นให้ทันที
  if user_role = 'OWNER' then
    insert into public.shops (owner_id, name, phone_number)
    values (new.id, user_shop_name, user_phone)
    on conflict do nothing;
  end if;

  -- 3. ถ้าเป็นลูกค้า (CUSTOMER) และมีข้อมูลรถที่กรอกไว้ตอนสมัคร ให้เพิ่มรถคันแรกลงตารางทันที
  if user_role = 'CUSTOMER' and user_vehicle_model is not null and user_vehicle_model <> '' then
    insert into public.vehicles (customer_id, brand_model, plate_number, is_default)
    values (
      new.id,
      user_vehicle_model,
      coalesce(user_license_plate, '-'),
      true
    )
    on conflict do nothing;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- ผูก Trigger กับตาราง auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =========================================================================
-- 12. ออโต้ทริกเกอร์: อัปเดตคะแนนดาวเฉลี่ยของร้านค้าอัตโนมัติเมื่อมีรีวิวใหม่
-- =========================================================================
create or replace function public.handle_review_stats()
returns trigger as $$
begin
  update public.shops
  set
    rating = coalesce((select round(avg(rating)::numeric, 2) from public.reviews where shop_id = coalesce(new.shop_id, old.shop_id)), 0.0),
    review_count = (select count(*) from public.reviews where shop_id = coalesce(new.shop_id, old.shop_id)),
    updated_at = timezone('utc'::text, now())
  where id = coalesce(new.shop_id, old.shop_id);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_review_changed on public.reviews;
create trigger on_review_changed
  after insert or update or delete on public.reviews
  for each row execute procedure public.handle_review_stats();

-- =========================================================================
-- 13. เปิดใช้งาน Row Level Security (RLS) เพื่อความปลอดภัยของข้อมูล
-- =========================================================================
alter table public.profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.shops enable row level security;
alter table public.shop_operating_hours enable row level security;
alter table public.services enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_services enable row level security;
alter table public.reviews enable row level security;
alter table public.favorite_shops enable row level security;
alter table public.notifications enable row level security;

-- =========================================================================
-- 14. นโยบายความปลอดภัย (RLS Policies)
-- =========================================================================

-- Profiles
drop policy if exists "Profiles viewable by everyone" on public.profiles;
create policy "Profiles viewable by everyone" on public.profiles for select using (true);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id);

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile" on public.profiles for insert with check (auth.uid() = id);

-- Vehicles
drop policy if exists "Customers can manage own vehicles" on public.vehicles;
create policy "Customers can manage own vehicles" on public.vehicles 
  for all using (auth.uid() = customer_id) with check (auth.uid() = customer_id);

-- Shops
alter table public.shops add column if not exists cover_image_url text;
alter table public.shops add column if not exists logo_url text;
alter table public.shops add column if not exists city text;
alter table public.shops add column if not exists slogan text;
alter table public.shops add column if not exists facilities text[] default array[]::text[];
alter table public.shops add column if not exists review_count integer default 0;

drop policy if exists "Shops viewable by everyone" on public.shops;
create policy "Shops viewable by everyone" on public.shops for select using (true);

drop policy if exists "Owners can manage own shop" on public.shops;
drop policy if exists "Owners can update own shop" on public.shops;
create policy "Owners can update own shop" on public.shops 
  for update 
  using (auth.uid() = owner_id or auth.uid() is null) 
  with check (auth.uid() = owner_id or auth.uid() is null);

drop policy if exists "Owners can insert own shop" on public.shops;
create policy "Owners can insert own shop" on public.shops 
  for insert 
  with check (auth.uid() = owner_id or auth.uid() is null);

-- Shop Operating Hours
drop policy if exists "Operating hours viewable by everyone" on public.shop_operating_hours;
drop policy if exists "Owners can manage operating hours" on public.shop_operating_hours;
drop policy if exists "Allow select operating hours" on public.shop_operating_hours;
drop policy if exists "Allow insert operating hours" on public.shop_operating_hours;
drop policy if exists "Allow update operating hours" on public.shop_operating_hours;
drop policy if exists "Allow delete operating hours" on public.shop_operating_hours;

create policy "Allow select operating hours" on public.shop_operating_hours for select using (true);
create policy "Allow insert operating hours" on public.shop_operating_hours for insert with check (true);
create policy "Allow update operating hours" on public.shop_operating_hours for update using (true) with check (true);
create policy "Allow delete operating hours" on public.shop_operating_hours for delete using (true);
grant all on public.shop_operating_hours to anon, authenticated, service_role;


-- Services
drop policy if exists "Services viewable by everyone" on public.services;
create policy "Services viewable by everyone" on public.services for select using (true);

drop policy if exists "Owners can manage own services" on public.services;
create policy "Owners can manage own services" on public.services
  for all using (
    exists (select 1 from public.shops where id = shop_id and owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.shops where id = shop_id and owner_id = auth.uid())
  );

-- Bookings
drop policy if exists "Users can view own bookings" on public.bookings;
create policy "Users can view own bookings" on public.bookings for select using (
  auth.uid() = customer_id or
  exists (select 1 from public.shops where id = shop_id and owner_id = auth.uid())
);

drop policy if exists "Customers can create bookings" on public.bookings;
create policy "Customers can create bookings" on public.bookings for insert with check (auth.uid() = customer_id);

drop policy if exists "Participants can update bookings" on public.bookings;
create policy "Participants can update bookings" on public.bookings for update using (
  auth.uid() = customer_id or
  exists (select 1 from public.shops where id = shop_id and owner_id = auth.uid())
);

-- Booking Services
drop policy if exists "Booking services viewable by booking participants" on public.booking_services;
create policy "Booking services viewable by booking participants" on public.booking_services for select using (
  exists (
    select 1 from public.bookings b 
    where b.id = booking_id and (
      b.customer_id = auth.uid() or
      exists (select 1 from public.shops s where s.id = b.shop_id and s.owner_id = auth.uid())
    )
  )
);

drop policy if exists "Customers can insert booking services" on public.booking_services;
create policy "Customers can insert booking services" on public.booking_services for insert with check (
  exists (select 1 from public.bookings where id = booking_id and customer_id = auth.uid())
);

-- Reviews
drop policy if exists "Reviews viewable by everyone" on public.reviews;
create policy "Reviews viewable by everyone" on public.reviews for select using (true);

drop policy if exists "Customers can write reviews" on public.reviews;
create policy "Customers can write reviews" on public.reviews for insert with check (auth.uid() = customer_id);

drop policy if exists "Customers can update own reviews" on public.reviews;
drop policy if exists "Allow review updates" on public.reviews;
create policy "Allow review updates" on public.reviews for update using (
  auth.uid() = customer_id 
  or exists (
    select 1 from public.shops 
    where shops.id = reviews.shop_id 
    and (shops.owner_id = auth.uid() or auth.uid() is null)
  )
  or auth.uid() is null
) with check (
  auth.uid() = customer_id 
  or exists (
    select 1 from public.shops 
    where shops.id = reviews.shop_id 
    and (shops.owner_id = auth.uid() or auth.uid() is null)
  )
  or auth.uid() is null
);

-- Favorite Shops
drop policy if exists "Customers can manage favorites" on public.favorite_shops;
create policy "Customers can manage favorites" on public.favorite_shops 
  for all using (auth.uid() = customer_id) with check (auth.uid() = customer_id);

-- Notifications
drop policy if exists "Users can manage own notifications" on public.notifications;
create policy "Users can manage own notifications" on public.notifications 
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
