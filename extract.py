ip = []
with open ('danted_config.txt', 'r') as f:
    for line in f:
        ip.append(line.split(':')[0])
with open ('interfaces', 'a') as f: 
    for i in ip:
        f.write(f'up ip addr add {i}/27 dev eno1\n')
     