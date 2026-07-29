import re
data=open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
# find printable name strings near start (characterNames[6][10])
for m in re.finditer(rb'[A-Z][a-z]{3,9}\x00', data[:0x900]):
    print('%#06x: %s'%(m.start(), m.group().rstrip(b'\x00').decode()))
