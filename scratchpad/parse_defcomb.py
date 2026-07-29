import struct
data = open('DEF_COMB.DAT','rb').read()
print('filesize', len(data))
off = 0
total = 0
files = 0
per = []
REC = 0x5f + 0x16  # 117
while files < 700 and off + 2 <= len(data):
    count = struct.unpack_from('<H', data, off)[0]
    off += 2
    if count > 200:
        print('BAD count', count, 'at file', files, 'off', off-2); break
    total += count
    per.append(count)
    off += count * REC
    files += 1
print('files parsed', files, 'total combatants', total, 'final off', off, 'match', off==len(data))
print('nonzero files', sum(1 for c in per if c>0))
print('max count', max(per) if per else 0)
