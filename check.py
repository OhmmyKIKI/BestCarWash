import os

folders = ['auth', 'customer', 'info', 'owner']
for folder in folders:
    if not os.path.exists(folder): continue
    for f in os.listdir(folder):
        if f.endswith('.html'):
            path = os.path.join(folder, f)
            with open(path, 'r', encoding='utf-8', errors='ignore') as file:
                content = file.read()
                doctype_count = content.count('<!DOCTYPE html>')
                print(f"{path}: {len(content)} bytes, {doctype_count} doctypes")
