import sys
sys.path.insert(0,'cli/src')
from bakbuild import omf
from capstone import CS_ARCH_X86, CS_MODE_16, Cs
obj = omf.parse('work/ref/CBENC.OBJ')
seg = [s for s in omf.extract_code_segments(obj)][0]
data=seg.data
pubs = sorted([(p.offset,p.name) for p in obj.publics if obj.segments[p.segment_idx-1].name==seg.name])
fx={}
for f in seg.fixups:
    fx[f.offset_in_segment]=getattr(f,'target_name',None) or ''
start=int(sys.argv[1],16); end=int(sys.argv[2],16)
md=Cs(CS_ARCH_X86,CS_MODE_16)
pos=start
name={o:n for o,n in pubs}
while pos<end:
    got=None
    for insn in md.disasm(data[pos:pos+16],pos):
        got=insn; break
    if got is None:
        print('%04x: %02x  db'%(pos,data[pos])); pos+=1; continue
    fxs=''
    for k in range(pos,pos+len(got.bytes)):
        if k in fx: fxs=' ; -> '+fx[k]
    tag='  <<< '+name[pos] if pos in name else ''
    print('%04x: %-18s %s%s%s'%(pos,' '.join('%02x'%b for b in got.bytes),got.mnemonic+' '+got.op_str,fxs,tag))
    pos+=len(got.bytes)
