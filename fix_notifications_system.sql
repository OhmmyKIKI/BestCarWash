-- =========================================================================
-- BestCarWash - Supabase RLS Fix & Auto Notifications Trigger
-- รันสคริปต์นี้ใน Supabase SQL Editor เพื่อเปิดใช้งานระบบการแจ้งเตือนอัตโนมัติ
-- =========================================================================

-- 1. ตรวจสอบตาราง notifications และคอลัมน์ที่จำเป็น
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

-- 2. เปิดใช้งาน Row Level Security (RLS)
alter table public.notifications enable row level security;

-- 3. กำหนด RLS Policies สำหรับ notifications
drop policy if exists "Users can manage own notifications" on public.notifications;
drop policy if exists "Users can read own notifications" on public.notifications;
drop policy if exists "Users can view own notifications" on public.notifications;
drop policy if exists "Allow select notifications" on public.notifications;
drop policy if exists "Allow insert notifications" on public.notifications;
drop policy if exists "Allow update notifications" on public.notifications;
drop policy if exists "Allow delete notifications" on public.notifications;

-- 3.1 สิทธิ์ในการอ่าน (SELECT): ผู้ใช้สามารถอ่านการแจ้งเตือนของตนเองได้
create policy "Allow select notifications"
  on public.notifications for select
  using (
    auth.uid() = user_id 
    or auth.uid() is null
  );

-- 3.2 สิทธิ์ในการเพิ่มข้อมูล (INSERT): อนุญาตให้ทั้งระบบ, ลูกค้า และเจ้าของร้านสร้างแจ้งเตือนได้
create policy "Allow insert notifications"
  on public.notifications for insert
  with check (true);

-- 3.3 สิทธิ์ในการแก้ไขข้อมูล (UPDATE): อนุญาตให้อัปเดตสถานะ เช่น is_read = true
create policy "Allow update notifications"
  on public.notifications for update
  using (
    auth.uid() = user_id 
    or auth.uid() is null
  );

-- 3.4 สิทธิ์ในการลบ (DELETE):
create policy "Allow delete notifications"
  on public.notifications for delete
  using (
    auth.uid() = user_id 
    or auth.uid() is null
  );

-- =========================================================================
-- 4. PostgreSQL Trigger: สร้างการแจ้งเตือนอัตโนมัติเมื่อเกิดการจอง หรือเปลี่ยนสถานะ
-- =========================================================================

create or replace function public.handle_booking_notification()
returns trigger
language plpgsql
security definer
as $$
declare
  v_shop_name text;
  v_owner_id uuid;
  v_date_str text;
  v_time_str text;
begin
  -- ดึงชื่อร้านค้า และ owner_id
  select name, owner_id into v_shop_name, v_owner_id 
  from public.shops 
  where id = NEW.shop_id;
  
  if v_shop_name is null then
    v_shop_name := 'ร้านคาร์แคร์';
  end if;

  v_date_str := to_char(NEW.booking_date, 'DD/MM/YYYY');
  v_time_str := coalesce(NEW.booking_time, '-');

  -- กรณี 1: มีการจองคิวใหม่เข้ามา (INSERT)
  if (TG_OP = 'INSERT') then
    -- ส่งแจ้งเตือนให้ลูกค้า (Customer)
    if NEW.customer_id is not null then
      insert into public.notifications (user_id, title, message, type, related_booking_id, is_read)
      values (
        NEW.customer_id,
        'การจองคิวสำเร็จ',
        'คุณได้ทำการจองคิวที่ ' || v_shop_name || ' วันที่ ' || v_date_str || ' เวลา ' || v_time_str || ' น. เรียบร้อยแล้ว กรุณารอทางร้านค้ายืนยัน',
        'BOOKING_UPDATE',
        NEW.id,
        false
      );
    end if;

    -- ส่งแจ้งเตือนให้เจ้าของร้าน (Owner)
    if v_owner_id is not null then
      insert into public.notifications (user_id, title, message, type, related_booking_id, is_read)
      values (
        v_owner_id,
        'มีคิวจองใหม่เข้ามา!',
        'มีลูกค้านัดหมายจองคิวใหม่ วันที่ ' || v_date_str || ' เวลา ' || v_time_str || ' น. กรุณาตรวจสอบและกดยืนยันคิว',
        'BOOKING_UPDATE',
        NEW.id,
        false
      );
    end if;

  -- กรณี 2: มีการอัปเดตสถานะการจอง (UPDATE OF status)
  elsif (TG_OP = 'UPDATE') and (OLD.status is distinct from NEW.status) then
    
    if NEW.customer_id is not null then
      if NEW.status = 'CONFIRMED' then
        insert into public.notifications (user_id, title, message, type, related_booking_id, is_read)
        values (
          NEW.customer_id,
          'ร้านค้ายืนยันคิวแล้ว',
          'คิวบริการล้างรถที่ ' || v_shop_name || ' ในวันที่ ' || v_date_str || ' เวลา ' || v_time_str || ' น. ได้รับการยืนยันแล้ว',
          'BOOKING_UPDATE',
          NEW.id,
          false
        );
      elsif NEW.status = 'COMPLETED' then
        insert into public.notifications (user_id, title, message, type, related_booking_id, is_read)
        values (
          NEW.customer_id,
          'บริการล้างรถเสร็จสิ้นแล้ว',
          'บริการล้างรถที่ ' || v_shop_name || ' เสร็จเรียบร้อยแล้ว เชิญตรวจรับรถและร่วมรีวิวความประทับใจ',
          'BOOKING_UPDATE',
          NEW.id,
          false
        );
      elsif NEW.status = 'CANCELLED' then
        insert into public.notifications (user_id, title, message, type, related_booking_id, is_read)
        values (
          NEW.customer_id,
          'การจองคิวถูกยกเลิก',
          'การจองคิวที่ ' || v_shop_name || ' วันที่ ' || v_date_str || ' เวลา ' || v_time_str || ' น. ถูกยกเลิกเรียบร้อยแล้ว',
          'BOOKING_UPDATE',
          NEW.id,
          false
        );
      end if;
    end if;

  end if;

  return NEW;
end;
$$;

-- สร้าง Trigger ผูกกับตาราง bookings
drop trigger if exists on_booking_notification_trigger on public.bookings;
create trigger on_booking_notification_trigger
  after insert or update of status on public.bookings
  for each row
  execute function public.handle_booking_notification();
