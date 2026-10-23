-- =========================================================================
-- แก้ไข Trigger Function: handle_booking_notification()
-- แก้ Bug syntax error: 22007 invalid input syntax for type time: "-"
-- แปลง booking_time เป็น text ก่อน coalesce อย่างปลอดภัย
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

  -- แปลงวันที่และเวลาอย่างปลอดภัย (ป้องกัน type mismatch error)
  v_date_str := coalesce(to_char(NEW.booking_date, 'DD/MM/YYYY'), '-');
  v_time_str := coalesce(substring(NEW.booking_time::text from 1 for 5), '-');

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

-- สร้าง Trigger ผูกกับตาราง bookings ใหม่
drop trigger if exists on_booking_notification_trigger on public.bookings;
create trigger on_booking_notification_trigger
  after insert or update of status on public.bookings
  for each row
  execute function public.handle_booking_notification();
