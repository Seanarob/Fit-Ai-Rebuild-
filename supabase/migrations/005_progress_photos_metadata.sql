alter table progress_photos
add column if not exists date date,
add column if not exists type text,
add column if not exists category text;
