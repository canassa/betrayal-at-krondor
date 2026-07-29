import struct
data = open('/home/canassa/src/github.com/canassa/bak2/viewer/data/STARTUP.GAM','rb').read()
print('filesize', len(data), hex(len(data)))
ACTOR_BASE = 0x90e7
INNER_BASE = 0x312e5
STRIDE_A = 0x5f
STRIDE_I = 0x16
N = 1730
SKILL=["Health","Stamina","Speed","Strength","Defense","Xbow","Melee","Cast","Assess","Armor","Weapon","Barding","Haggle","Lock","Scout","Stealth"]
# count non-empty actors: check if any stats[].max nonzero
live=0
first_live=[]
for i in range(N):
    off = ACTOR_BASE + i*STRIDE_A
    rec = data[off:off+STRIDE_A]
    # stats start at 0x08, 16 * 5 bytes
    stats = rec[0x08:0x08+80]
    anymax = any(stats[j*5+0] for j in range(16))
    if anymax:
        live+=1
        if len(first_live)<3:
            first_live.append((i,off,rec))
print('live actors (some stat.max>0):', live)
# also count inner records with class_id != 0
livei=0
for i in range(N):
    off = INNER_BASE + i*STRIDE_I
    rec = data[off:off+STRIDE_I]
    class_id = struct.unpack_from('<h', rec, 0x02)[0]
    if class_id != 0:
        livei+=1
print('inner records class_id!=0:', livei)
# dump first few live
for i,off,rec in first_live:
    print('--- actor',i,'@',hex(off))
    name = struct.unpack_from('<H', rec,0)[0]
    spells = struct.unpack_from('<3H', rec, 2)
    print('  name_ptr=%04x spells=%s cParty=%d' % (name, spells, rec[0x58]))
    stats = rec[0x08:0x08+80]
    for j in range(16):
        mx,ba,ca,fr,pm = stats[j*5:j*5+5]
        if mx or ba:
            print('   %-8s max=%3d base=%3d cached=%3d frac=%3d perm=%d'%(SKILL[j],mx,ba,ca,fr,struct.unpack('b',bytes([pm]))[0]))
    inoff = INNER_BASE + i*STRIDE_I
    irec = data[inoff:inoff+STRIDE_I]
    cid = struct.unpack_from('<h', irec, 2)[0]
    print('   inner: target=%04x class_id=%d gx=%d gy=%d flags=%02x'%(struct.unpack_from('<H',irec,0)[0], cid, irec[4], irec[5], irec[8]))
